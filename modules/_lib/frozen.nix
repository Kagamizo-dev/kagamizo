# A wrapper that runs `program` with exactly the declared environment:
#
#   frozen { name; program; packages; }
#
# starts from `env -i`, sets every variable in runtime.caller, PATH to the
# given packages only, and passes through the host variables named in
# runtime.host.passThrough (by name; an unset one stays unset). Nothing
# else the caller has reaches the program. A program that starts children
# under an environment of their own (mailbox and Bridge) reads the declared
# names from FROZEN_VARS, to hand on exactly those.
{
  lib,
  pkgs,
  runtime,
}:
{
  name,
  program,
  packages,
}:
let
  vars = runtime.caller // {
    PATH = lib.makeBinPath packages;
    FROZEN_VARS = lib.concatStringsSep " " (
      lib.attrNames runtime.caller ++ [ "PATH" ] ++ runtime.host.passThrough
    );
  };
  set = lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "${n}=${lib.escapeShellArg v}") vars);
  pass = lib.concatMapStrings (n: ''
    [ -z "''${${n}+x}" ] || through+=(${n}="''$${n}")
  '') runtime.host.passThrough;
in
pkgs.writeShellScriptBin name ''
  through=()
  ${pass}
  exec ${pkgs.coreutils}/bin/env -i ${set} "''${through[@]}" ${program} "$@"
''
