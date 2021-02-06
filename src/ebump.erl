%%-------------------------------------------------------------------------------------------
%% Copyright (c) 2020 Xaptum, Inc
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% @author Venkatakumar Srinivasan
%% @since February 12, 2020
%%
%%-------------------------------------------------------------------------------------------
-module(ebump).

%% API exports
-export([main/1]).

-define(APP_NAME, ?MODULE).
-define(VSN, "1.0.3").
-define(CONFIG_FILE, "ebump.config").

%% commands
-define(CMD_VERSION, "version").
-define(CMD_HELP, "help").
-define(CMD_RESET, "reset").
-define(CMD_CURRENT, "current").
-define(CMD_MAJOR, "major").
-define(CMD_MINOR, "minor").
-define(CMD_PATCH, "patch").
-define(CMD_PRE, "pre").

%% options
-define(OPT_CONFIG, 'config').

-define(SEMVER_REGEX, "^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$").
%% git commands
-define(GIT_COMMIT_HASH, "git rev-parse --short HEAD").
-define(GIT_COMMIT_COUNT, "git log --oneline | wc -l | tr -d ' '").

%%====================================================================
%% API functions
%%====================================================================
main(Args) ->
  {ok,_} = application:ensure_all_started(?APP_NAME),
  OptSpecList = option_spec_list(),
  Cmd = getopt:parse(OptSpecList, Args),
  exec(Cmd).

%%====================================================================
%% Internal functions
%%====================================================================
exec({ok, {[], []}}) ->
  help();

exec({ok, {_Options, [?CMD_VERSION]}}) ->
  version();

exec({ok, {_Options, [?CMD_HELP]}}) ->
  help();

exec({ok, {Options, [Command]}}) ->
  try
    execute_command(Command, maps:from_list(Options))
  catch
    _ : Reason ->
      io:format("ERROR: ~p~n", [Reason]),
      erlang:halt(1)
  end;

exec({ok, {_, _}}) ->
  help();

exec({error, {Reason, Data}}) ->
  io:format("~s ~p~n", [Reason, Data]),
  help(),
  erlang:halt(1).

execute_command(?CMD_RESET, Options) ->
  File = maps:get(?OPT_CONFIG, Options, ?CONFIG_FILE),
  write_config_file(File, #{major => 0, minor => 0, patch => 1});

execute_command(?CMD_PRE, Options) ->
  File = maps:get(?OPT_CONFIG, Options, ?CONFIG_FILE),
  VersionMap = consult_config_file(File),
  NextVersionMap = bump_pre(VersionMap),
  write_config_file(File, NextVersionMap),
  print_version(NextVersionMap);

execute_command(?CMD_MAJOR, Options) ->
  File = maps:get(?OPT_CONFIG, Options, ?CONFIG_FILE),
  #{major := M} = consult_config_file(File),
  NextVersionMap = #{major => M + 1, minor => 0, patch => 0},
  write_config_file(File, NextVersionMap),
  print_version(NextVersionMap);

execute_command(?CMD_MINOR, Options) ->
  File = maps:get(?OPT_CONFIG, Options, ?CONFIG_FILE),
  VersionMap = consult_config_file(File),
  #{major := Maj, minor := Min} = VersionMap,
  NextVersionMap = #{major => Maj, minor => Min + 1, patch => 0},
  write_config_file(File, NextVersionMap),
  print_version(NextVersionMap);

execute_command(?CMD_PATCH, Options) ->
  File = maps:get(?OPT_CONFIG, Options, ?CONFIG_FILE),
  VersionMap = consult_config_file(File),
  #{major := Maj, minor := Min, patch := P} = VersionMap,
  NextVersionMap = #{major => Maj, minor => Min, patch => P + 1},
  write_config_file(File, NextVersionMap),
  print_version(NextVersionMap);


execute_command(?CMD_CURRENT, Options) ->
  VersionMap = consult_config_file(Options),
  print_version(VersionMap);

execute_command(_, _) ->
  help().

option_spec_list() ->
  [
   {?OPT_CONFIG, $c, atom_to_list(?OPT_CONFIG), string, "/path/to/config/file"}
  ].

help() ->
  %% Print version
  version(),

  %% Print usage
  OptSpecList = option_spec_list(),
  getopt:usage(OptSpecList, atom_to_list(?APP_NAME), "reset|current|major|minor|patch|pre", []).

version() ->
  io:format("Version: ~s\n", [?VSN]).

bump_pre(#{pre := alpha} = Map) ->
  Map#{pre => beta};

bump_pre(#{pre := beta} = Map) ->
  Map#{pre => rc};

bump_pre(#{pre := rc} = Map) ->
  maps:remove(pre, Map);

bump_pre(Map) ->
  Map#{pre => alpha}.

print_version(VersionMap) ->
  SemVer = sem_ver(VersionMap),
  io:format("~s",[SemVer]).

sem_ver(#{major := X, minor := Y, patch := Z} = VersionMap) ->
  Hash = git_hash(),
  Count = git_count(),
  case maps:get(pre, VersionMap, nil) of
    nil ->
      io_lib:format("~p.~p.~p-~p.~s", [X, Y, Z, Count, Hash]);
    Pre ->
      io_lib:format("~p.~p.~p-~s.~p.~s", [X, Y, Z, Pre, Count, Hash])
    end.

write_config_file(File, VersionMap) ->
  Version = io_lib:format("~tp.~n", [VersionMap]),
  ok = file:write_file(File, Version).

git_hash() ->
  case os_cmd(?GIT_COMMIT_HASH, [no_halt]) of
    [] ->
      "0000000";
    Hash ->
      Hash
  end.

git_count() ->
  list_to_integer(os_cmd(?GIT_COMMIT_COUNT)).

consult_config_file(#{} = Options) ->
  File = maps:get(?OPT_CONFIG, Options, ?CONFIG_FILE),
  consult_config_file(File);

consult_config_file(FileName) ->
  case file:consult(FileName) of
    {ok, [#{} = VersionMap]} ->
      VersionMap;

    {ok, _} ->
      io:format("FILE_ERROR:~s: Invalid entries in config file! Use `reset` command to fix config file~n", [FileName]),
      erlang:halt(1);

    {error, Reason} ->
      ErrorStr = file:format_error(Reason),
      io:format("FILE_ERROR:~s: ~s~n", [FileName, ErrorStr]),
      erlang:halt(1)
  end.

os_cmd(Command) ->
  os_cmd(Command, []).

os_cmd(Command, Options) ->
  Port = open_port({spawn, Command}, [stream, in, eof, hide, exit_status]),
  Output = capture_cmd_output(Port, []),
  parse_cmd_output(Output, Options).

parse_cmd_output({0, Out}, _) ->
  %% Command completed successfully
  case lists:reverse(Out) of
    [$\n|Rest] ->
      lists:reverse(Rest);

    _ ->
      Out
  end;

parse_cmd_output({_ExitCode, _}, [no_halt]) ->
  %% Command failed with ExitCode
  "";

parse_cmd_output({ExitCode, _}, _) ->
  %% Command failed with ExitCode
  erlang:halt(ExitCode).


capture_cmd_output(Port, Sofar) ->
  receive
    {Port, {data, Bytes}} ->
      capture_cmd_output(Port, [Sofar|Bytes]);

    {Port, eof} ->
      Port ! {self(), close},
      receive
        {Port, closed} ->
          true
      end,
      receive
        {'EXIT',  Port,  _} ->
          ok
      after 1 ->              % force context switch
          ok
      end,
      ExitCode =
        receive
          {Port, {exit_status, Code}} ->
            Code
        end,
      {ExitCode, lists:flatten(Sofar)}
  end.
