# Performance records, per module (the owner's rule, 2026-11-01): every
# target a module declares here is measured on every CI run, build time or
# runtime, and the build fails when a measurement is slower than the best
# time known by more than the record's tolerance. Beating the record moves
# it. Lean (./_lean/Perf.lean) states the rule and proves what it
# guarantees; `checks.perf` has it decide every record against the latest
# measurement. The report (./README.md, rendered) is each module's standing.
#
#   perf.targets.<name> = { module; kind; attr; tolerancePercent; method; }
#
#   nix run .#perf-measure [OUT.jsonl]   rebuild each build target from
#                                        scratch (nix build --rebuild) and
#                                        time it; run each runtime target's
#                                        benchmark; one JSON line per target
#   nix run .#perf-record -- IN.jsonl    fold measurements into the records
#                                        (./_json/records.json): a faster
#                                        time becomes the record, a slower
#                                        one is kept as the latest; prints
#                                        what moved
#   nix run .#perf-readme                render ./README.md from the records
#
# Measuring is CI's (the `cache` workflow, after the push: the runner's
# clock is the one every record is on); a container's own times are noted
# as such and never become records.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.perf;
  stored = lib.importJSON ./_json/records.json;
  inherit (stored) records;
  baseline = stored.baseline or null;
  q = builtins.toJSON;

  target = types.submodule {
    options = {
      module = mkOption {
        type = types.str;
        description = "The module the target belongs to (its directory under modules/).";
      };
      kind = mkOption {
        type = types.enum [
          "build"
          "runtime"
        ];
      };
      attr = mkOption {
        type = types.str;
        description = "The flake attribute: built (--rebuild) for `build`, run for `runtime` (prints milliseconds).";
      };
      tolerancePercent = mkOption {
        type = types.ints.between 0 100;
        default = 10;
      };
      method = mkOption {
        type = types.str;
        description = "How the number is produced and what would move it; the sources the method rests on.";
      };
    };
  };

  # Lean facts: every target with a record, against a measurement (the
  # committed latest, or CI's fresh one: perf-check).
  fact =
    n: t: measuredMs:
    "  { target := ${q n}, module := ${q t.module}, kind := ${q t.kind}, recordMs := ${toString records.${n}.recordMs}, tolerancePercent := ${toString t.tolerancePercent}, measuredMs := ${toString measuredMs} }";
  withRecords = lib.filterAttrs (n: _: records ? ${n}) cfg.targets;
  factsOf = measured: ''
    namespace Kagamizo.Perf

    def declared : List Record := [
    ${lib.concatStringsSep ",\n" (lib.mapAttrsToList (n: t: fact n t (measured n)) withRecords)}
    ]

    /-- Every record is sane and every latest measurement within tolerance. -/
    theorem declared_fine : declared.all (fun r => r.sane && r.fine) = true := by decide

    end Kagamizo.Perf
  '';
  facts = factsOf (n: records.${n}.latestMs);
  unknown = lib.subtractLists (lib.attrNames cfg.targets) (lib.attrNames records);
in
{
  options.perf.targets = mkOption {
    type = types.attrsOf target;
    default = { };
  };

  config.perSystem =
    { pkgs, ... }:
    let
      targetsJson = pkgs.writeText "perf-targets.json" (builtins.toJSON cfg.targets);
      measure = pkgs.writeShellApplication {
        name = "perf-measure";
        runtimeInputs = [
          pkgs.nix
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          out=''${1:-/dev/stdout}
          jq -r 'to_entries[] | "\(.key) \(.value.kind) \(.value.attr)"' ${targetsJson} | while read -r name kind attr; do
            case "$kind" in
              build)
                # Built once (from the cache, or here), then rebuilt alone
                # and timed: the time is the one derivation's, not its
                # dependencies'.
                nix build --no-link ".#$attr" >/dev/null
                s=$(date +%s%N)
                nix build --rebuild --no-link ".#$attr" >/dev/null
                e=$(date +%s%N)
                ms=$(( (e - s) / 1000000 ))
                ;;
              runtime)
                ms=$(nix run ".#$attr" 2>/dev/null | tail -1)
                ;;
            esac
            jq -cn --arg n "$name" --arg host "$(uname -m) $(nproc) cpus" --argjson ms "$ms" --arg at "$(date -u +%FT%TZ)" \
              '{target: $n, ms: $ms, host: $host, at: $at}' >>"$out"
            echo "perf-measure: $name $ms ms" >&2
          done
        '';
      };
      record = pkgs.writeShellApplication {
        name = "perf-record";
        runtimeInputs = [
          pkgs.jq
          pkgs.git
          pkgs.coreutils
        ];
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          in=''${1:?usage: perf-record IN.jsonl}
          f=modules/perf/_json/records.json
          jq -s --slurpfile cur "$f" '
            reduce .[] as $m ($cur[0];
              .records[$m.target] as $r
              | .records[$m.target] = (
                  if $r == null or $m.ms < $r.recordMs
                  then {recordMs: $m.ms, recordAt: $m.at, recordHost: $m.host, latestMs: $m.ms, latestAt: $m.at}
                  else $r + {latestMs: $m.ms, latestAt: $m.at}
                  end))' "$in" >"$f.new"
          jq -r --slurpfile old "$f" '
            .records | to_entries[]
            | ($old[0].records[.key].recordMs // null) as $was
            | select($was != .value.recordMs)
            | "\(.key): record \($was // "none") -> \(.value.recordMs) ms"' "$f.new"
          mv "$f.new" "$f"
          git status --short "$f"
        '';
      };
      # CI: the fresh measurements against the committed records; the
      # facts are written with the measured numbers and Lean decides them.
      check = pkgs.writeShellApplication {
        name = "perf-check";
        runtimeInputs = [
          pkgs.lean4
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          in=''${1:?usage: perf-check IN.jsonl}
          work=$(mktemp -d)
          trap 'rm -rf "$work"' EXIT
          # The template's measured numbers are replaced by the file's.
          cp ${
            pkgs.writeText "Facts.lean" (factsOf (n: "MEASURED_${lib.replaceStrings [ "-" ] [ "_" ] n}"))
          } "$work/Facts.lean"
          chmod u+w "$work/Facts.lean"
          jq -r '"\(.target) \(.ms)"' "$in" | while read -r n ms; do
            sed -i "s/MEASURED_''${n//-/_}/$ms/" "$work/Facts.lean"
          done
          if grep -q MEASURED_ "$work/Facts.lean"; then
            echo "perf-check: a target with a record was not measured:" >&2
            grep -o "MEASURED_[A-Za-z0-9_]*" "$work/Facts.lean" >&2
            exit 1
          fi
          cat ${./_lean/Perf.lean} "$work/Facts.lean" > "$work/Check.lean"
          lean "$work/Check.lean" && echo "perf-check: every measurement within its record's tolerance" >&2
        '';
      };
      readme = pkgs.writeText "README.md" ''
        # Performance records

        Per module, the best time known for each measured target and the
        latest measurement, in milliseconds (`_json/records.json`, moved by
        `perf-record` from CI's `perf-measure`). `checks.perf` has Lean
        decide that every latest measurement is within its record's
        tolerance; a slower build fails. Rendered by `nix run .#perf-readme`.

        | Module | Target | Kind | Record (ms) | Latest (ms) | Tolerance | Method |
        |---|---|---|---|---|---|---|
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            n: t:
            let
              r = records.${n} or null;
            in
            "| ${t.module} | `${n}` | ${t.kind} | ${if r == null then "none yet" else toString r.recordMs} | ${
              if r == null then "none yet" else toString r.latestMs
            } | ${toString t.tolerancePercent}% | ${t.method} |"
          ) cfg.targets
        )}
        ${lib.optionalString (baseline != null) ''

          ## Baseline

          Measured on ${baseline.host}; a first look, before CI's records exist.

          | Target | ms |
          |---|---|
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: ms: "| `${n}` | ${toString ms} |") baseline.ms)}

          ${lib.optionalString (baseline ? notes) (
            lib.concatStringsSep "\n" (lib.mapAttrsToList (n: note: "- `${n}`: ${note}") baseline.notes)
          )}

          What stands out, in order of cost: `lean-api-rclone` (one `decide`
          over 1200 operations; splitting the closedness proof per chunk,
          or `native_decide`, is the cut), `migrate-build` (the Rust
          release build; LTO off and `codegen-units` up for CI, the cache
          serving it otherwise), `catalog-coverage` (Python over every
          source file; a Rust walker, or scanning only changed files).
        ''}
      '';
    in
    {
      packages = {
        perf-measure = measure;
        perf-record = record;
        perf-check = check;
        perf-readme = pkgs.writeShellApplication {
          name = "perf-readme";
          runtimeInputs = [ pkgs.git ];
          text = ''
            cd "$(git rev-parse --show-toplevel)"
            install -m 644 ${readme} modules/perf/README.md
            git status --short modules/perf/README.md
          '';
        };
        perf-facts = pkgs.writeText "Facts.lean" facts;
      };
      checks = {
        perf =
          pkgs.runCommand "perf"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
            }
            (
              assert lib.assertMsg (unknown == [ ]) (
                "modules/perf: records for targets no longer declared: " + lib.concatStringsSep ", " unknown
              );
              ''
                cat ${./_lean/Perf.lean} ${pkgs.writeText "Facts.lean" facts} > Check.lean
                lean Check.lean
                touch $out
              ''
            );
        perf-readme = pkgs.runCommand "perf-readme-in-sync" { } ''
          cmp ${readme} ${./README.md} || { echo "modules/perf/README.md is stale: nix run .#perf-readme" >&2; exit 1; }
          touch $out
        '';
      };
    };
}
