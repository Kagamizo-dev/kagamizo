# Proton Pass as an OpenTofu state backend, typed, proven and served from
# the CLI. Each OpenTofu layer names a backend here; its state is kept as
# generations of note items in a declared vault (chunked under Proton Pass's
# item size), written by the protocol `_lean/Store.lean` proves never loses a
# state, and served to OpenTofu as its standard `http` backend on the
# loopback for the length of one run.
#
#   statestore-run <backend> [--read-only] -- <command>
#       serves the backend, exports OpenTofu's TF_HTTP_* addresses, runs the
#       command, stops; --read-only serves no lock (a viewer cannot create
#       the lock item), for plans
#   statestore <get|put|show> --vault V --name N [--chunk-size B]
#       the state itself, for migration and recovery (put reads stdin)
#
# pass-cli must be signed in (PROTON_PASS_KEY_PROVIDER=fs). Values pass
# between pass-cli and OpenTofu only, never through stderr.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.statestore;
  vaults = lib.attrValues config.proton.infraVaults ++ config.proton.vaults;
in
{
  options.statestore.backends = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            vault = mkOption {
              type = types.enum vaults;
              description = "A declared Proton Pass vault (proton.infraVaults, proton.vaults).";
            };
            name = mkOption {
              type = types.strMatching "[a-z][a-z0-9-]*";
              default = name;
              description = "The title every item of this state starts with (<name>@<generation>[#<chunk>]).";
            };
            chunkSize = mkOption {
              type = types.ints.between 64 16000;
              default = 8000;
              description = ''
                Largest note, in bytes. Proton Pass documents no limit; on
                2026-11-01 a state carrying a 20 KB Worker page was refused
                (InvalidValue) where the smaller DNS-only state had been
                taken, so chunks stay well under either.
              '';
            };
          };
        }
      )
    );
    default = { };
    description = "The OpenTofu states kept in Proton Pass, one per layer.";
  };

  config.perSystem =
    { pkgs, config, ... }:
    let
      statestore = pkgs.rustPlatform.buildRustPackage {
        pname = "statestore";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        meta.mainProgram = "statestore";
      };
      backends = builtins.toJSON (
        lib.mapAttrs (_: b: { inherit (b) vault name chunkSize; }) cfg.backends
      );
    in
    {
      packages.statestore = statestore;

      packages.statestore-run = pkgs.writeShellApplication {
        name = "statestore-run";
        runtimeInputs = [
          statestore
          config.packages.pass-cli
          pkgs.jq
          pkgs.coreutils
          pkgs.python3
        ];
        text = ''
          usage="usage: statestore-run <backend> [--read-only] -- <command...>"
          backend=''${1:?$usage}
          shift
          b=$(jq -ce --arg b "$backend" '.[$b]' <<<${lib.escapeShellArg backends}) ||
            { echo "statestore-run: no backend $backend; declared: $(jq -r 'keys | join(", ")' <<<${lib.escapeShellArg backends})" >&2; exit 2; }
          ro=false
          if [ "''${1:-}" = --read-only ]; then ro=true; shift; fi
          [ "''${1:-}" = -- ] || { echo "$usage" >&2; exit 2; }
          shift
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          port=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
          fifo=$(mktemp -u)
          mkfifo "$fifo"
          statestore serve --vault "$(jq -r .vault <<<"$b")" --name "$(jq -r .name <<<"$b")" \
            --chunk-size "$(jq -r .chunkSize <<<"$b")" --port "$port" >"$fifo" &
          server=$!
          trap 'kill "$server" 2>/dev/null; rm -f "$fifo"' EXIT
          read -r ready <"$fifo" || true
          [ "$ready" = ready ] || { echo "statestore-run: the backend did not start" >&2; exit 1; }
          export TF_HTTP_ADDRESS="http://127.0.0.1:$port/state"
          if [ "$ro" = false ]; then
            export TF_HTTP_LOCK_ADDRESS="http://127.0.0.1:$port/lock"
            export TF_HTTP_UNLOCK_ADDRESS="http://127.0.0.1:$port/lock"
          fi
          status=0
          "$@" || status=$?
          exit "$status"
        '';
      };

      # The protocol's proofs, kernel-checked.
      checks.statestore-lean =
        pkgs.runCommand "statestore-lean" { nativeBuildInputs = [ pkgs.lean4 ]; }
          ''
            lean ${./_lean/Store.lean}
            touch $out
          '';
      checks.statestore-tests = statestore.overrideAttrs (_: {
        doCheck = true;
      });
    };
}
