# The Proton Pass items the owner fills, prepared from the record so the
# only thing left is the value: like `signup prepare`, for the legal record.
#
#   legal-prepare plan              every item the record names, and whether
#                                   it exists in the entity's vault yet
#   legal-prepare apply [<entity>]  create the missing ones, idempotent
#
# Per company: an API-credential item for the EIN (paste the nine digits
# into Secret), one for the formation (the filing number into Secret, the
# state and date into Permissions as `US-XX YYYY-MM-DD`), and a note item
# per declared document to attach the PDF to (or to paste its Proton Drive
# link into). Every other field is filled here; values are never read.
{
  lib,
  config,
  inputs,
  ...
}:
let
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  records = config.legal.checked;
  inherit (config.identity.checked) entities;

  # Every item the record names, with its vault and the custom item's
  # template (pass-cli `item create custom --from-template`), or a note.
  items = lib.concatLists (
    lib.mapAttrsToList (
      e: r:
      let
        vault = entities.${e}.vault;
        credential = title: permissions: note: {
          inherit e vault title;
          kind = "custom";
          template = {
            inherit title note;
            sections = [
              {
                section_name = "API credential";
                fields = [
                  {
                    field_name = "API key";
                    field_type = "hidden";
                    value = "";
                  }
                  {
                    field_name = "Secret";
                    field_type = "hidden";
                    value = "";
                  }
                  {
                    field_name = "Expiry date";
                    field_type = "timestamp";
                    value = "0";
                  }
                  {
                    field_name = "Permissions";
                    field_type = "text";
                    value = permissions;
                  }
                ];
              }
            ];
          };
        };
      in
      lib.optional (r.ein.item != null) (
        credential r.ein.item "EIN of ${r.legalName}"
          "Paste ${r.legalName}'s EIN into Secret as 12-3456789 (from the IRS CP 575 letter, or Northwest: get_company_ein_tool). Read by `legal-documents render` as ${
            config.legal.variables.${e}.ein
          }; declared in modules/legal/options.nix."
      )
      ++ lib.optional (r.formation.item != null) (
        credential r.formation.item "US-XX YYYY-MM-DD: the state and date of formation, replace this"
          "Paste ${r.legalName}'s state filing number into Secret, and its state and date of formation into Permissions as `US-XX YYYY-MM-DD` (from the articles, or Northwest: get_company_details_tool). Read by `legal-documents render`; declared in modules/legal/options.nix."
      )
      ++ lib.mapAttrsToList (_: d: {
        inherit e;
        inherit (d.where) vault;
        title = d.where.item;
        kind = "note";
        template = {
          title = d.where.item;
          note = "${d.title} (${d.kind}, ${r.legalName}). Attach the PDF to this item, or replace this note with its Proton Drive link. Declared in modules/legal/options.nix (legal.records.${e}.documents).";
        };
      }) r.documents
    ) records
  );
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.legal-prepare = pkgs.writeShellApplication {
        name = "legal-prepare";
        runtimeInputs = [
          pkgs.jq
          config.packages.pass-cli
        ];
        text = ''
          usage="usage: legal-prepare plan | apply [<entity>]"
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          items=${lib.escapeShellArg (builtins.toJSON items)}

          exists() { # vault title
            ${
              cli.passCli "item list" {
                vault-name.shell = "$1";
                output = "json";
              }
            } | jq -e --arg t "$2" 'any((.items // .)[]; .title == $t)' >/dev/null
          }

          cmd=''${1:?$usage}
          only=''${2:-}
          case "$cmd" in
            plan | apply) ;;
            *) echo "$usage" >&2; exit 2 ;;
          esac
          jq -c --arg only "$only" '.[] | select($only == "" or .e == $only)' <<<"$items" | while read -r it; do
            vault=$(jq -r .vault <<<"$it") title=$(jq -r .title <<<"$it") kind=$(jq -r .kind <<<"$it")
            if exists "$vault" "$title"; then
              echo "$vault/$title: ready ($kind)"
              continue
            fi
            if [ "$cmd" = plan ]; then
              echo "$vault/$title: + prepare ($kind, $(jq -r .e <<<"$it"))"
              continue
            fi
            case "$kind" in
              custom)
                jq -c .template <<<"$it" | ${
                  cli.passCli "item create custom" {
                    vault-name.shell = "$vault";
                    from-template = "-";
                  }
                } >/dev/null
                ;;
              note)
                jq -c .template <<<"$it" | ${
                  cli.passCli "item create note" {
                    vault-name.shell = "$vault";
                    from-template = "-";
                  }
                } >/dev/null
                ;;
            esac
            echo "prepared $vault/$title ($kind): fill it in Proton Pass"
          done
        '';
      };
    };
}
