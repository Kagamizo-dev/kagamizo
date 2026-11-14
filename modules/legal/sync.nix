# What the registered agent knows about each company, read through the
# `northwest` wrapper (governance-authorize is inside it; every tool here is
# a read) into ./_json/<entity>.json: dates, states, standing, filing and
# document titles. Nothing private: the projection keeps a closed set of
# keys and redacts anything shaped like an EIN or an SSN, and what it writes
# is committed, so the homepage can show it (../site).
#
#   legal-sync [--out DIR] [<entity>]     default DIR: modules/legal/_json
#
# Not run here against the live service: it needs a Northwest session
# (`northwest login`, a Gap in modules/cloudflare/README.md).
{ lib, config, ... }:
let
  records = config.legal.checked;
  held = config.accounts.held;
  # Each company with a registered-agent account at Northwest.
  targets = lib.filterAttrs (
    _: r: r.registeredAgent != null && held.${r.registeredAgent}.provider == "northwest"
  ) records;
  # Reads only (modules/northwest/tools.nix types them so).
  reads = [
    "get_company_details_tool"
    "get_company_state_status_tool"
    "get_filing_statuses_tool"
    "get_annual_reports_tool"
    "get_documents_tool"
  ];
  keep = [
    "name"
    "company_name"
    "legal_name"
    "title"
    "document_title"
    "type"
    "entity_type"
    "document_type"
    "filing_type"
    "state"
    "jurisdiction"
    "status"
    "state_status"
    "standing"
    "date"
    "formation_date"
    "formed"
    "filed"
    "filed_at"
    "due"
    "due_date"
    "received"
    "created_at"
    "updated_at"
    "autopay"
    "company"
    "companies"
    "documents"
    "filings"
    "annual_reports"
    "items"
    "results"
    "data"
  ];
  # A closed set of keys, then every string scrubbed of identifiers.
  project = ''
    walk(if type == "object" then with_entries(select(.key | IN(${
      lib.concatMapStringsSep ", " builtins.toJSON keep
    }))) else . end)
    | walk(if type == "string" then gsub("[0-9]{2}-[0-9]{7}|[0-9]{3}-[0-9]{2}-[0-9]{4}"; "[redacted]") else . end)
  '';
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.legal-sync = pkgs.writeShellApplication {
        name = "legal-sync";
        runtimeInputs = [
          config.packages.northwest
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          usage="usage: legal-sync [--out DIR] [<entity>]"
          out=modules/legal/_json
          if [ "''${1:-}" = --out ]; then
            out=''${2:?$usage}
            shift 2
          fi
          only=''${1:-}
          targets=${lib.escapeShellArg (builtins.toJSON (lib.mapAttrs (_: r: r.registeredAgent) targets))}
          mkdir -p "$out"
          for entity in $(jq -r 'keys[]' <<<"$targets"); do
            [ -z "$only" ] || [ "$only" = "$entity" ] || continue
            account=$(jq -r --arg e "$entity" '.[$e]' <<<"$targets")
            file=$out/$entity.json
            result=$(jq -n --arg a "$account" --arg d "$(date -u +%F)" \
              '{_source: "northwest (\($a)) read tools, \($d); projected by modules/legal/sync.nix: a closed set of keys, identifiers redacted"}')
            for tool in ${lib.concatStringsSep " " reads}; do
              if got=$(northwest --account "$account" call "$tool" '{}' 2>/dev/null); then
                result=$(jq --arg t "$tool" --argjson v "$(jq ${lib.escapeShellArg project} <<<"$got")" '.[$t] = $v' <<<"$result")
              else
                echo "legal-sync: $entity: $tool answered nothing (not signed in, or it takes arguments)" >&2
              fi
            done
            jq -S . <<<"$result" >"$file"
            echo "legal-sync: $file"
          done
        '';
      };
    };
}
