# Every card is a declared, bounded resource: one virtual Mercury card per
# vendor, with a spend limit per interval. A vendor's module declares its own
# card (mercury.cards.<vendor>), so the limit sits next to what it pays for.
#
#   cards [--account A] <command>, on mercury.account unless named; each
#   command touches only the cards declared on that account
#   (mercury.cards.<vendor>.account, mercury.account by default):
#
#   cards plan              declared cards against the live ones
#   cards spend [YYYY-MM]   each card's spend this month against its limit
#   cards funds             the balances the cards draw from
#   cards apply [--prune]   refused: the owner mints and cancels cards
#                           (2026-10-24); plan reports what differs
#   cards vault <name>|--all  put a card the owner minted into their vault
#                           as a Proton Pass credit card item, card-<name>,
#                           straight from Mercury: never printed, never on
#                           disk (agentic cards only, Mercury's rule)
#   cards freeze <name>     stop a card at once; `unfreeze` restores it
#   cards unfreeze <name>
#
# Every command runs on the named account's OAuth session from
# `mercury-session login` (./session.nix), which the CLI refreshes and the
# wrapper stores back. The reads work on any held Mercury account; issuing
# or unfreezing a card only on mercury.account, the one the cards draw on. A card
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
  mercuryAccounts = lib.filterAttrs (_: a: a.provider == "mercury") config.accounts.held;
  # Each account the declared cards are issued on, and the vault its
  # revealed cards go to (its owner's).
  cardAccounts = lib.unique (map (c: c.account) (lib.attrValues cfg.cards));
  vaults = lib.genAttrs cardAccounts (
    a: config.identity.checked.entities.${config.accounts.held.${a}.owner}.vault
  );

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
      merchantLock = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The merchant the owner locked the card to in Mercury (merchantLock.name), checked by `cards plan`.";
      };
      between = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              for = mkOption {
                type = types.enum (lib.attrNames config.identity.entities);
                description = "The entity the card pays for, other than the one it is issued on.";
              };
              as = mkOption {
                type = types.enum [
                  "owed"
                  "contribution"
                  "draw"
                ];
                description = ''
                  owed: the other entity repays it (a receivable); contribution:
                  a capital contribution to it; draw: the business pays its
                  owner's own cost, an owner's draw.
                '';
              };
            };
          }
        );
        default = null;
        description = "When the card pays another entity's account: how it is booked between them.";
      };
      nickname = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The card's nickname in Mercury, as the owner minted it; null is kagamizo/<vendor>.";
      };
      account = mkOption {
        type = types.enum (lib.attrNames mercuryAccounts);
        default = config.mercury.account;
        defaultText = "mercury.account";
        description = "The held Mercury account the card is issued on and draws from.";
      };
    };
  };
  cards = lib.mapAttrs (
    name: c: c // { nickname = if c.nickname == null then "kagamizo/${name}" else c.nickname; }
  ) cfg.cards;
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

  config.accounts.demands = lib.concatMap (
    account:
    let
      on = lib.attrNames (lib.filterAttrs (_: c: c.account == account) cfg.cards);
    in
    [
      {
        inherit account;
        capability = "virtualCards";
        need = true;
        why = "mercury.cards (${lib.concatStringsSep ", " on})";
      }
      {
        inherit account;
        capability = "cardSpendLimits";
        need = true;
        why = "mercury.cards.{${lib.concatStringsSep "," on}}.limitUsd";
      }
    ]
  ) cardAccounts;

  config.perSystem =
    { pkgs, config, ... }:
    let
      spec = config.packages.secretspec-toml;

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
          [ -s "$creds" ] || { echo "cards: no Mercury session; run mercury-session --account <account> login" >&2; exit 1; }
          # Only the cards declared on the account this runs for.
          account=''${CARDS_ACCOUNT:?}
          cards=$(jq -c --arg a "$account" 'with_entries(select(.value.account == $a))' <<<${lib.escapeShellArg (builtins.toJSON cards)})
          vault=$(jq -r --arg a "$account" '.[$a] // empty' <<<${lib.escapeShellArg (builtins.toJSON vaults)})
          usage="usage: cards <plan|spend [YYYY-MM]|funds|vault <name>|--all|apply [--prune]|freeze <name>|unfreeze <name>>"

          # Each line of jsonl output is a card, or a page holding cards.
          declared=$cards
          live() {
            ${
              cli.mercury "cards list" {
                type = [ "virtual" ];
                format = "jsonl";
              }
            } | jq -s --argjson declared "$declared" '[.[] | if has("cards") then .cards[] else . end
              | select((.nickname // "") as $n | $n | startswith("kagamizo/") or ([$declared[].nickname] | index($n)))
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
              echo "  card-$1: Mercury reveals agentic cards only; mint it as an agentic card, or its details go into Proton Pass by hand (a Gap)" >&2
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
                  echo "+ to mint $name (the owner): \$$(jq -r .limitUsd <<<"$c")/$interval ($(jq -r .why <<<"$c"))"
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
                elif [ "$(jq -r '.merchantLock // empty' <<<"$c")" != "$(jq -r '.merchantLock.name // empty' <<<"$have")" ]; then
                  echo "~ lock    $name: Mercury says $(jq -r '.merchantLock.name // "no lock"' <<<"$have"), declared $(jq -r '.merchantLock // "no lock"' <<<"$c") (the owner sets it in Mercury)"
                else
                  echo "  ok      $name: \$$(jq -r .limitUsd <<<"$c")/$interval, $(jq -r .status <<<"$have"), ••$(jq -r .lastFour <<<"$have")$(jq -r 'if .merchantLock.name then ", locked to \(.merchantLock.name)" else "" end' <<<"$have")$(jq -r 'if .isAgentCard then ", agentic" else "" end' <<<"$have")"
                fi
              done
              # Discovery: every live virtual card on the account, whatever
              # its name, so a card the owner minted is never invisible.
              ${
                cli.mercury "cards list" {
                  type = [ "virtual" ];
                  format = "jsonl";
                }
              } | jq -s -r --argjson c "$cards" '[.[] | if has("cards") then .cards[] else . end | select(.status != "cancelled")]
                | .[] | select((.nickname // "") as $n | [$c[].nickname] | index($n) | not)
                | "? undeclared \(.nickname // "(no nickname)"): ••\(.lastFour), $\(.spendLimit.amountCents / 100)/\(.spendLimit.interval)\(if .merchantLock.name then ", locked to \(.merchantLock.name)" else "" end), \(.status); declare it in mercury.cards"'
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
            vault)
              # The card's number moves from Mercury's reveal into Proton
              # Pass through pipes only: TLS to Mercury, jq in memory,
              # pass-cli's stdin, Proton's end-to-end encryption; nothing is
              # printed, nothing touches the disk.
              [ -n "$vault" ] || { echo "cards: no owner vault for $account" >&2; exit 1; }
              l=$(live)
              if [ "''${2:-}" = --all ]; then
                names=$(jq -r 'keys[]' <<<"$cards")
              else
                names=''${2:?$usage}
                jq -e --arg n "$names" 'has($n)' <<<"$cards" >/dev/null ||
                  { echo "cards: $names is not declared on $account (mercury.cards)" >&2; exit 1; }
              fi
              for name in $names; do
                nick=$(jq -r --arg n "$name" '.[$n].nickname' <<<"$cards")
                have=$(jq -c --arg n "$nick" 'map(select(.nickname == $n))[0] // empty' <<<"$l")
                if [ -z "$have" ]; then
                  echo "  card-$name: not minted yet ($nick); the owner mints it in Mercury" >&2
                  continue
                fi
                if ${
                  cli.passCli "item list" {
                    vault-name.shell = "$vault";
                    filter-type = "credit-card";
                    output = "json";
                  }
                } | jq -e --arg t "card-$name" '(.items // .) | any(.title == $t)' >/dev/null; then
                  echo "  card-$name: already in $vault"
                  continue
                fi
                store "$name" "$have"
              done
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
          pkgs.jq
        ];
        # Builds only while the declared plans cover what the repo needs.
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          if [ "''${1:-}" != --account ]; then set -- --account ${cfg.account} "$@"; fi
          account= # set by the sourced picker
          # shellcheck source=/dev/null
          . ${config.packages.mercury-pick-account}
          # The owner mints and cancels cards (2026-10-24); the repo declares
          # them and checks them.
          if [ "''${1:-}" = apply ]; then
            echo "cards: apply is refused: the owner mints and cancels cards (2026-10-24); cards plan checks them" >&2
            exit 3
          fi
          case "''${1:-}" in
            apply | unfreeze)
              card_accounts=(${lib.concatStringsSep " " cardAccounts})
              [[ " ''${card_accounts[*]} " == *" $account "* ]] || {
                echo "cards: no card is declared on $account (declared on: ''${card_accounts[*]})" >&2
                exit 1
              }
              ;;
          esac
          export CARDS_ACCOUNT=$account
          # Never a call the session is not known to be allowed
          # (./authorization.nix).
          case "''${1:-}" in
            apply) needs=("cards create" "cards update") ;;
            freeze) needs=("cards freeze") ;;
            unfreeze) needs=("cards unfreeze") ;;
            vault) needs=("cards reveal") ;;
            *) needs=() ;;
          esac
          [ "''${1:-}" != apply ] || [ "''${2:-}" != --prune ] || needs+=("cards cancel")
          for c in "''${needs[@]}"; do
            why=$(jq -r --arg c "$c" '.[$c] // empty' ${pkgs.writeText "mercury-blocked.json" (builtins.toJSON top.mercury.blocked)})
            if [ -n "$why" ]; then
              echo "cards: $1 needs mercury $c, refused: $why" >&2
              exit 3
            fi
          done
          case "''${1:-}" in
            apply) if [ "''${2:-}" = --prune ]; then action=cards-prune; else action=cards-apply; fi ;;
            plan | spend | funds | vault | freeze | unfreeze) action=cards-$1 ;;
            *) action= ;;
          esac
          if [ -n "$action" ]; then
            governance-authorize "mercury:$action" "$account"
          fi
          exec secretspec run --file ${spec} --profile "$MERCURY_PROFILE" \
            --reason "cards $* ($account)" -- ${run}/bin/cards-run "$@"
        '';
      };
    };
}
