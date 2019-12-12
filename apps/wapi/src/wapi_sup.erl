%% @doc Top level supervisor.
%% @end

-module(wapi_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%%

-spec start_link() -> {ok, pid()} | {error, {already_started, pid()}}.

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.

init([]) ->
    % AuthorizerSpecs = get_authorizer_child_specs(),
    {LogicHandlers, LogicHandlerSpecs} = get_logic_handler_info(),
    HealthCheck = enable_health_logging(genlib_app:env(wapi, health_check, #{})),
    HealthRoutes = [{'_', [erl_health_handle:get_route(HealthCheck)]}],
    SwaggerSpec = wapi_swagger_server:child_spec(HealthRoutes, LogicHandlers),
    UacConf = get_uac_config(),
    ok = uac:configure(UacConf),
    {ok, {
        {one_for_all, 0, 1},
            LogicHandlerSpecs ++ [SwaggerSpec]
    }}.

-spec get_logic_handler_info() -> {Handlers :: #{atom() => module()}, [Spec :: supervisor:child_spec()] | []} .

get_logic_handler_info() ->
    {#{
        %% wallet  => wapi_wallet_handler,
        payres  => wapi_payres_handler,
        privdoc => wapi_privdoc_handler
    }, []}.

-spec enable_health_logging(erl_health:check()) ->
    erl_health:check().

enable_health_logging(Check) ->
    EvHandler = {erl_health_event_handler, []},
    maps:map(fun (_, V = {_, _, _}) -> #{runner => V, event_handler => EvHandler} end, Check).

get_uac_config() ->
    maps:merge(
        genlib_app:env(wapi, access_conf),
        #{access => wapi_auth:get_access_config()}
    ).
