# Every card is a declared, bounded resource: one virtual Mercury card per
# vendor, with a spend limit per interval. A vendor's module declares its own
# card (mercury.cards.<vendor>), so the limit sits next to what it pays for.
#
#   cards plan              declared cards against the live ones
#   cards spend [YYYY-MM]   each card's spend this month against its limit
#   cards funds             the balances the cards draw from
#   cards apply [--prune]   issue missing cards, correct limits; --prune
#                           cancels kagamizo/ cards no longer declared (final)
#   cards freeze <name>     stop a card at once; `unfreeze` restores it
#   cards unfreeze <name>
#
# Every command runs on the OAuth session from `mercury-session login`
# (./session.nix), which the CLI refreshes and the wrapper stores back. A card
# made by hand in Mercury with a declared nickname (kagamizo/<vendor>) is
# simply adopted.
#
# A card Mercury lets reveal (agentic cards) goes straight from `mercury
# cards reveal` into a Proton Pass credit card item, card-<name> in the
# owner's vault, so a vendor's billing form fills from Proton Pass and the
# number is never printed. Entering it on the vendor's site is a Gap.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.mercury;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  catalog = (lib.importJSON ../catalog/_json/mercury.json).commands;

  card = types.submodule {
    options = {
      limitUsd = mkOption {
        type = types.ints.positive;
        description = "Most the card may spend per interval, in dollars.";
      };
      interval = mkOption {
        # The values Mercury's API documents for spendLimit.interval.
        type = types.enum [
          "daily"
          "weekly"
          "monthly"
          "yearly"
        ];
        default = "monthly";
      };
      kind = mkOption {
        type = types.enum catalog."cards create".options.kind.oneOf;
        default = "debit";
      };
      why = mkOption { type = types.str; };
    };
  };
  cards = lib.mapAttrs (name: c: c // { nickname = "kagamizo/${name}"; }) cfg.cards;
in
{
  options.mercury = {
    account = mkOption {
      type = types.enum (lib.attrNames config.accounts.held);
      default = "mercury";
    };
    fundingAccount = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name of the Mercury account cards draw from; null takes the only checking account.";
    };
    cardholder = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Email of the Mercury user cards are issued to; null takes the only user.";
    };
    cards = mkOption {
      type = types.attrsOf card;
      default = { };
    };
  };

  config.accounts.demands = lib.optionals (cfg.cards != { }) [
    {
      inherit (cfg) account;
      capability = "oauthSessions";
      need = true;
      why = "cards and mercury-session run on an OAuth session, not dashboard tokens";
    }
    {
      inherit (cfg) account;
      capability = "virtualCards";
      need = true;
      why = "mercury.cards (${lib.concatStringsSep ", " (lib.attrNames cfg.cards)})";
    }
    {
      inherit (cfg) account;
      capability = "cardSpendLimits";
      need = true;
      why = "mercury.cards.*.limitUsd";
    }
  ];

  config.perSystem =
    { pkgs, config, ... }:
    let
      spec = config.packages.secretspec-toml;
      vault = top.identity.checked.entities.${top.accounts.held.${cfg.account}.owner}.vault;

      run = pkgs.writeShellApplication {
        name = "cards-run";
        runtimeInputs = [
          config.packages.mercury
          config.packages.pass-cli
          config.packages.secretspec
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          # shellcheck source=/dev/null
          . ${config.packages.mercury-with-session}
          creds=$XDG_CONFIG_HOME/mercury/credentials.json
          [ -s "$creds" ] || { echo "cards: no Mercury session; run mercury-session login" >&2; exit 1; }
          cards=${lib.escapeShellArg (builtins.toJSON cards)}
          vault=${lib.escapeShellArg vault}
          usage="usage: cards <plan|spend [YYYY-MM]|funds|apply [--prune]|freeze <name>|unfreeze <name>>"

          # Each line of jsonl output is a card, or a page holding cards.
          live() {
            ${
              cli.mercury "cards list" {
                type = [ "virtual" ];
                format = "jsonl";
              }
            } | jq -s '[.[] | if has("cards") then .cards[] else . end
              | select((.nickname // "") | startswith("kagamizo/"))
              | select(.status != "cancelled")]'
          }
          one() { # jq filter over a list -> a single id, or fail naming what
            local out
            out=$(jq -r "$1" <<<"$2")
            if [ "$(wc -l <<<"$out")" != 1 ] || [ -z "$out" ] || [ "$out" = null ]; then
              echo "cards: expected exactly one $3, found: $(tr '\n' ' ' <<<"$out")" >&2
              exit 1
            fi
            printf %s "$out"
          }
          funding() {
            one ${
              lib.escapeShellArg (
                if cfg.fundingAccount == null then
                  ''[.[] | if has("accounts") then .accounts[] else . end | select(.kind == "checking" and .status == "active") | .id] | .[]''
                else
                  ''[.[] | if has("accounts") then .accounts[] else . end | select(.name == ${builtins.toJSON cfg.fundingAccount} or .nickname == ${builtins.toJSON cfg.fundingAccount}) | .id] | .[]''
              )
            } "$(${cli.mercury "accounts list" { format = "jsonl"; }} | jq -s .)" "funding account"
          }
          holder() {
            one ${
              lib.escapeShellArg (
                if cfg.cardholder == null then
                  ''[.[] | if has("users") then .users[] else . end | .userId] | .[]''
                else
                  ''[.[] | if has("users") then .users[] else . end | select(.email == ${builtins.toJSON cfg.cardholder}) | .userId] | .[]''
              )
            } "$(${cli.mercury "users list" { format = "jsonl"; }} | jq -s .)" "cardholder"
          }
          # Into Proton Pass, never onto the screen: only for cards Mercury
          # lets reveal (agentic cards).
          store() { # name card-json
            if [ "$(jq -r '.isAgentCard // false' <<<"$2")" != true ]; then
              echo "  card-$1: Mercury does not reveal this card (not agentic); not stored" >&2
              return 0
            fi
            ${
              cli.mercury "cards reveal" {
                card-id.shell = "$(jq -r .id <<<\"$2\")";
                format = "json";
              }
            } |
              jq --arg t "card-$1" --arg n "$(jq -r '.nameOnCard // empty' <<<"$2")" \
                '{title: $t, cardholder_name: $n, card_type: null, number: .cardNumber, cvv: .cvc,
                  expiration_date: "\(.expiration.year)-\(.expiration.month | tostring | if length == 1 then "0" + . else . end)",
                  pin: null, note: "Mercury virtual card, declared in modules/ (mercury.cards)"}' |
              ${
                cli.passCli "item create credit-card" {
                  vault-name.shell = "$vault";
                  from-template = "-";
                }
              } >/dev/null
            echo "  card-$1 stored in $vault"
          }
          byName() { jq -c --arg n "kagamizo/$1" 'map(select(.nickname == $n))[0] // empty' <<<"$(live)"; }

          case "''${1:-}" in
            plan | apply)
              l=$(live)
              for name in $(jq -r 'keys[]' <<<"$cards"); do
                c=$(jq -c --arg n "$name" '.[$n]' <<<"$cards")
                have=$(jq -c --arg n "$(jq -r .nickname <<<"$c")" 'map(select(.nickname == $n))[0] // empty' <<<"$l")
                cents=$(jq '.limitUsd * 100' <<<"$c")
                interval=$(jq -r .interval <<<"$c")
                if [ -z "$have" ]; then
                  echo "+ issue   $name: \$$(jq -r .limitUsd <<<"$c")/$interval ($(jq -r .why <<<"$c"))"
                  [ "$1" = apply ] || continue
                  new=$(${
                    cli.mercury "cards create" {
                      kind.shell = "$(jq -r .kind <<<\"$c\")";
                      type = "virtual";
                      user-id.shell = "$(holder)";
                      account-id.shell = "$(funding)";
                      nickname.shell = "$(jq -r .nickname <<<\"$c\")";
                      "spend-limit.amount-cents".shell = "$cents";
                      "spend-limit.interval".shell = "$interval";
                      format = "json";
                    }
                  })
                  store "$name" "$new"
                elif [ "$(jq '.spendLimit.amountCents' <<<"$have")" != "$cents" ] ||
                  [ "$(jq -r '.spendLimit.interval' <<<"$have")" != "$interval" ]; then
                  echo "~ limit   $name: \$$(jq '.spendLimit.amountCents / 100' <<<"$have")/$(jq -r .spendLimit.interval <<<"$have") -> \$$(jq -r .limitUsd <<<"$c")/$interval"
                  [ "$1" = apply ] || continue
                  ${
                    cli.mercury "cards update" {
                      card-id.shell = "$(jq -r .id <<<\"$have\")";
                      nickname.shell = "$(jq -r .nickname <<<\"$have\")";
                      "spend-limit.amount-cents".shell = "$cents";
                      "spend-limit.interval".shell = "$interval";
                    }
                  } >/dev/null
                else
                  echo "  ok      $name: \$$(jq -r .limitUsd <<<"$c")/$interval, $(jq -r .status <<<"$have"), ••$(jq -r .lastFour <<<"$have")"
                fi
              done
              jq -r --argjson c "$cards" '.[] | select(.nickname as $n | [$c[].nickname] | index($n) | not) | "\(.id) \(.nickname)"' <<<"$l" |
                while read -r id nick; do
                  if [ "$1" = apply ] && [ "''${2:-}" = --prune ]; then
                    ${
                      cli.mercury "cards cancel" {
                        card-id.shell = "$id";
                        yes = true;
                      }
                    } >/dev/null
                    echo "- cancelled $nick"
                  else
                    echo "- cancel  $nick (no longer declared; \`cards apply --prune\`)"
                  fi
                done
              ;;
            spend)
              # One month of card spend against each card's limit (monthly
              # limits only compare like for like).
              month=''${2:-$(date -u +%Y-%m)}
              start="$month-01"
              end=$(date -u -d "$start +1 month" +%Y-%m-%d)
              l=$(live)
              for name in $(jq -r 'keys[]' <<<"$cards"); do
                c=$(jq -c --arg n "$name" '.[$n]' <<<"$cards")
                id=$(jq -r --arg n "$(jq -r .nickname <<<"$c")" 'map(select(.nickname == $n))[0].id // empty' <<<"$l")
                if [ -z "$id" ]; then
                  echo "  $name: no live card"
                  continue
                fi
                spent=$(${
                  cli.mercury "transactions list" {
                    card-id = [ { shell = "$id"; } ];
                    start.shell = "$start";
                    end.shell = "$end";
                    format = "jsonl";
                  }
                } | jq -s '[.[] | if has("transactions") then .transactions[] else . end
                    | select(.status != "failed" and .status != "cancelled") | .amount] | map(-.) | add // 0')
                echo "  $name: \$$spent of \$$(jq -r .limitUsd <<<"$c")/$(jq -r .interval <<<"$c") in $month"
              done
              ;;
            funds)
              ${cli.mercury "accounts list" { format = "jsonl"; }} |
                jq -rs '.[] | if has("accounts") then .accounts[] else . end
                  | "  \(.name // .nickname): $\(.availableBalance) available (\(.kind), \(.status))"'
              ;;
            freeze | unfreeze)
              name=''${2:?$usage}
              have=$(byName "$name")
              [ -n "$have" ] || { echo "cards: no live card kagamizo/$name" >&2; exit 1; }
              if [ "$1" = freeze ]; then
                ${
                  cli.mercury "cards freeze" {
                    card-id.shell = "$(jq -r .id <<<\"$have\")";
                    yes = true;
                  }
                } >/dev/null
              else
                ${
                  cli.mercury "cards unfreeze" {
                    card-id.shell = "$(jq -r .id <<<\"$have\")";
                    yes = true;
                  }
                } >/dev/null
              fi
              echo "$1 kagamizo/$name"
              ;;
            *)
              echo "$usage" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      packages.cards = pkgs.writeShellApplication {
        name = "cards";
        runtimeInputs = [
          config.packages.secretspec
          config.packages.pass-cli
          config.packages.governance-authorize
        ];
        # Builds only while the declared plans cover what the repo needs.
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          case "''${1:-}" in
            apply) if [ "''${2:-}" = --prune ]; then action=cards-prune; else action=cards-apply; fi ;;
            plan | spend | funds | freeze | unfreeze) action=cards-$1 ;;
            *) action= ;;
          esac
          if [ -n "$action" ]; then
            governance-authorize "mercury:$action" ${cfg.account}
          fi
          exec secretspec run --file ${spec} --profile mercury-session \
            --reason "cards $*" -- ${run}/bin/cards-run "$@"
        '';
      };
    };
}
