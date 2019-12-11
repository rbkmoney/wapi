-module(wapi_auth).

-export([authorize_api_key/3]).
-export([authorize_operation/3]).
-export([issue_access_token/2]).
-export([issue_access_token/3]).

-export([get_subject_id/1]).
-export([get_claims/1]).
-export([get_claim/2]).
-export([get_claim/3]).
-export([get_consumer/1]).

-export([get_resource_hierarchy/0]).

-define(DEFAULT_ACCESS_TOKEN_LIFETIME, 259200).

-define(SIGNEE, wapi).

-type context () :: wapi_authorizer_jwt:t().
-type claims  () :: wapi_authorizer_jwt:claims().
-type consumer() :: client | merchant | provider.
-type timestamp() :: {calendar:datetime(), 0..999999}. % machinery:timestamp()

-export_type([context /0]).
-export_type([claims  /0]).
-export_type([consumer/0]).

-type operation_id() :: wapi_handler:operation_id().

-type api_key() ::
    %% swag_wallet_server:api_key() |
    swag_server_payres:api_key() |
    swag_server_privdoc:api_key().

-type handler_opts() :: wapi_handler:opts().

-spec authorize_api_key(operation_id(), api_key(), handler_opts()) ->
    {true, context()}. %% | false.

authorize_api_key(OperationID, ApiKey, _Opts) ->
    case parse_api_key(ApiKey) of
        {ok, {Type, Credentials}} ->
            case do_authorize_api_key(OperationID, Type, Credentials) of
                {ok, Context} ->
                    {true, Context};
                {error, Error} ->
                    _ = log_auth_error(OperationID, Error),
                    false
            end;
        {error, Error} ->
            _ = log_auth_error(OperationID, Error),
            false
    end.

log_auth_error(OperationID, Error) ->
    logger:info("API Key authorization failed for ~p due to ~p", [OperationID, Error]).

-spec parse_api_key(ApiKey :: api_key()) ->
    {ok, {bearer, Credentials :: binary()}} | {error, Reason :: atom()}.

parse_api_key(ApiKey) ->
    case ApiKey of
        <<"Bearer ", Credentials/binary>> ->
            {ok, {bearer, Credentials}};
        _ ->
            {error, unsupported_auth_scheme}
    end.

-spec do_authorize_api_key(
    OperationID :: operation_id(),
    Type :: atom(),
    Credentials :: binary()
) ->
    {ok, Context :: context()} | {error, Reason :: atom()}.

do_authorize_api_key(_OperationID, bearer, Token) ->
    % NOTE
    % We are knowingly delegating actual request authorization to the logic handler
    % so we could gather more data to perform fine-grained access control.
    wapi_authorizer_jwt:verify(Token).

%%

% TODO
% We need shared type here, exported somewhere in swagger app
-type request_data() :: #{atom() | binary() => term()}.

-spec authorize_operation(
    OperationID :: operation_id(),
    Req :: request_data(),
    Auth :: wapi_authorizer_jwt:t()
) ->
    ok | {error, unauthorized}.

%% TODO
authorize_operation(_OperationID, _Req, _) ->
    ok.
%% authorize_operation(OperationID, Req, {{_SubjectID, ACL}, _}) ->
    %% Access = get_operation_access(OperationID, Req),
    %% _ = case lists:all(
    %%     fun ({Scope, Permission}) ->
    %%         lists:member(Permission, wapi_acl:match(Scope, ACL))
    %%     end,
    %%     Access
    %% ) of
    %%     true ->
    %%         ok;
    %%     false ->
    %%         {error, unauthorized}
    %% end.

%%

-type token_spec() ::
    {destinations, DestinationID :: binary()}.

-spec issue_access_token(wapi_handler_utils:party_id(), token_spec()) ->
    wapi_authorizer_jwt:token().
issue_access_token(PartyID, TokenSpec) ->
    issue_access_token(PartyID, TokenSpec, #{}).

-type expiration() ::
    {deadline, timestamp() | pos_integer()} |
    {lifetime, Seconds :: pos_integer()}              |
    unlimited                                         .

-spec issue_access_token(wapi_handler_utils:party_id(), token_spec(), expiration()) ->
    uac_authorizer_jwt:token().
issue_access_token(PartyID, TokenSpec, ExtraProperties) ->
    {Claims0, DomainRoles, LifeTime} = resolve_token_spec(TokenSpec),
    Claims = maps:merge(ExtraProperties, Claims0),
    wapi_utils:unwrap(uac_authorizer_jwt:issue(
        wapi_utils:get_unique_id(),
        LifeTime,
        PartyID,
        DomainRoles,
        Claims,
        ?SIGNEE
    )).

-spec resolve_token_spec(token_spec()) ->
    {claims(), uac_authorizer_jwt:domains(), uac_authorizer_jwt:expiration()}.
resolve_token_spec({destinations, DestinationId}) ->
    Claims = #{},
    DomainRoles = #{
        <<"wallet-api">> => uac_acl:from_list([
            {[party, {destinations, DestinationId}], read},
            {[party, {destinations, DestinationId}], write}
        ])
    },
    Expiration = {lifetime, ?DEFAULT_ACCESS_TOKEN_LIFETIME},
    {Claims, DomainRoles, Expiration}.

-spec get_subject_id(context()) -> binary().

get_subject_id({{SubjectID, _ACL}, _}) ->
    SubjectID.

-spec get_claims(context()) -> claims().

get_claims({_Subject, Claims}) ->
    Claims.

-spec get_claim(binary(), context()) -> term().

get_claim(ClaimName, {_Subject, Claims}) ->
    maps:get(ClaimName, Claims).

-spec get_claim(binary(), context(), term()) -> term().

get_claim(ClaimName, {_Subject, Claims}, Default) ->
    maps:get(ClaimName, Claims, Default).

%%

%% TODO update for the wallet swag
%% -spec get_operation_access(operation_id(), request_data()) ->
%%     [{wapi_acl:scope(), wapi_acl:permission()}].

%% get_operation_access('StoreBankCard'     , _) ->
%%     [{[payment_resources], write}].

-spec get_resource_hierarchy() -> #{atom() => map()}.

%% TODO add some sence in here
get_resource_hierarchy() ->
    #{
        party => #{
            wallets      => #{},
            destinations => #{}
        }
    }.

-spec get_consumer(claims()) ->
    consumer().
get_consumer(Claims) ->
    case maps:get(<<"cons">>, Claims, <<"merchant">>) of
        <<"merchant">> -> merchant;
        <<"client"  >> -> client;
        <<"provider">> -> provider
    end.
