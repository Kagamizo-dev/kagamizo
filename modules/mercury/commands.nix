# Mercury's whole official CLI, governed: every command of the pinned
# release (../catalog/_json/mercury.json) has a declared effect here, and
# evaluation fails if one is missing, unknown, or both exposed and excluded,
# so a CLI bump that adds a command cannot add an ungoverned one.
#
#   nix run .#mercury-cli -- --account A <command> [options]
#
# asks governance-authorize for `mercury:cli-<command>` on A, restores A's
# session from Proton Pass, runs the official CLI and stores the refreshed
# session back. Spending and destroying are the controller's alone (Cedar's
# base policy); Mercury itself still asks for a tap in its app to move money.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.mercury;
  catalog = lib.importJSON ../catalog/_json/mercury.json;

  # What each command does to the account.
  read = [
    "accounts get"
    "accounts list"
    "cards get"
    "cards list"
    "categories list"
    "credit list"
    "customers get"
    "customers list"
    "events get"
    "events list"
    "invoices attachments get"
    "invoices attachments list"
    "invoices download"
    "invoices get"
    "invoices list"
    "org get"
    "payments get"
    "payments list"
    "recipients attachments list"
    "recipients get"
    "recipients list"
    "recipients:invites list"
    "safes download"
    "safes get"
    "safes list"
    "statements accounts list"
    "statements download"
    "statements treasury list"
    "transactions get"
    "transactions list"
    "treasury list"
    "treasury transactions"
    "users get"
    "users list"
    "webhooks get"
    "webhooks list"
    # Checks a webhook signature against the account's secret.
    "webhooks verify"
  ];
  write = [
    "categories create"
    "categories update"
    "customers create"
    "customers update"
    "invoices create"
    "invoices update"
    # Asks someone else to pay the account; nothing leaves it.
    "payments request"
    "recipients attachments attach"
    "recipients create"
    "recipients update"
    "recipients:invites create"
    "transactions attachments attach"
    "transactions update"
    "webhooks create"
    "webhooks update"
    # Stops a card spending.
    "cards freeze"
  ];
  # Lets money leave, or hands out what spends it.
  spend = [
    "payments create"
    "payments transfer"
    "cards create"
    "cards update"
    "cards unfreeze"
    # Prints the card number and CVC.
    "cards reveal"
  ];
  destroy = [
    "cards cancel"
    "categories delete"
    "customers delete"
    "invoices cancel"
    "recipients delete"
    "recipients:invites delete"
    "webhooks delete"
  ];
  excluded = {
    login = "mercury-session login: the session lives in Proton Pass";
    logout = "mercury-session: the stored session is the account's";
    status = "mercury-session status";
    upgrade = "would replace the pinned binary; versions move with the flake input";
    "onboarding apply" = "opens a new Mercury account: a signup, declared as one";
  };
  # Global options the wrapper refuses: each would bypass the stored
  # session (another key, host or environment) or print what it carries.
  refused = [
    "api-key"
    "base-url"
    "environment"
    "debug"
  ];

  slug = c: "cli-" + lib.replaceStrings [ " " ":" ] [ "-" "-" ] c;
  effects =
    lib.genAttrs read (_: "read")
    // lib.genAttrs write (_: "write")
    // lib.genAttrs spend (_: "spend")
    // lib.genAttrs destroy (_: "destroy");
  declared = read ++ write ++ spend ++ destroy;
  known = lib.attrNames catalog.commands;
  problems =
    map (c: "${c}: declared twice") (
      lib.filter (c: lib.count (x: x == c) declared > 1) (lib.unique declared)
    )
    ++ map (c: "${c}: both exposed and excluded") (lib.filter (c: excluded ? ${c}) declared)
    ++ map (c: "${c}: not a command of the pinned CLI") (
      lib.filter (c: !(lib.elem c known)) (declared ++ lib.attrNames excluded)
    )
    ++ map (c: "${c}: a command of the pinned CLI with no effect declared") (
      lib.filter (c: !(effects ? ${c}) && !(excluded ? ${c})) known
    )
    ++ map (o: "--${o}: not a global option of the pinned CLI") (
      lib.filter (o: !(catalog.global ? ${o})) refused
    );
in
{
  options.mercury.commands = mkOption {
    type = types.attrsOf (
      types.enum [
        "read"
        "write"
        "spend"
        "destroy"
      ]
    );
    readOnly = true;
    description = "Every exposed command of the pinned Mercury CLI and what it does to the account.";
  };

  config = {
    mercury.commands =
      assert lib.assertMsg (problems == [ ]) (
        "modules/mercury/commands.nix:\n" + lib.concatStringsSep "\n" problems
      );
      effects;

    governance.actions.mercury = lib.mapAttrs' (
      c: effect:
      lib.nameValuePair (slug c) {
        inherit effect;
        description = "mercury ${c}";
        command = "mercury-cli ${c}";
      }
    ) cfg.commands;

    perSystem =
      { pkgs, config, ... }:
      let
        spec = config.packages.secretspec-toml;
        commandsJson = pkgs.writeText "mercury-commands.json" (
          builtins.toJSON (lib.mapAttrs (c: _: slug c) cfg.commands)
        );
        run = pkgs.writeShellApplication {
          name = "mercury-cli-run";
          runtimeInputs = [
            config.packages.mercury
            config.packages.secretspec
            config.packages.pass-cli
            pkgs.coreutils
          ];
          text = ''
            # shellcheck source=/dev/null
            . ${config.packages.mercury-with-session}
            # Not exec: the session is stored back when this shell exits.
            mercury "$@"
          '';
        };
        inner = pkgs.writeShellApplication {
          name = "mercury-cli";
          runtimeInputs = [
            config.packages.secretspec
            config.packages.pass-cli
            config.packages.governance-authorize
            pkgs.jq
            pkgs.coreutils
          ];
          text = builtins.seq top.accounts.checked ''
            usage="usage: mercury-cli --account A <command> [options]; commands: $(jq -r 'keys | join(", ")' ${commandsJson})"
            account= # set by the sourced picker
            # shellcheck source=/dev/null
            . ${config.packages.mercury-pick-account}
            for arg in "$@"; do
              case "$arg" in
                ${lib.concatMapStringsSep " | " (o: "--${o} | --${o}=*") refused})
                  echo "mercury-cli: $arg is refused: it would bypass or print the stored session" >&2
                  exit 2 ;;
              esac
            done
            # The longest run of leading words that is a declared command.
            words=()
            for arg in "$@"; do
              case "$arg" in -*) break ;; esac
              words+=("$arg")
            done
            action=
            for ((n = ''${#words[@]}; n > 0; n--)); do
              action=$(jq -r --arg c "''${words[*]:0:n}" '.[$c] // empty' ${commandsJson})
              [ -z "$action" ] || break
            done
            [ -n "$action" ] || { echo "mercury-cli: no declared command in: $*; $usage" >&2; exit 2; }
            governance-authorize "mercury:$action" "$account"
            exec secretspec run --file ${spec} --profile "$MERCURY_PROFILE" \
              --reason "mercury-cli $action ($account)" -- ${lib.getExe run} "$@"
          '';
        };
        frozen = import ../_lib/frozen.nix {
          inherit lib pkgs;
          inherit (top) runtime;
        };
      in
      {
        packages = {
          mercury-cli-inner = inner;
          mercury-cli = frozen {
            name = "mercury-cli";
            program = lib.getExe inner;
            packages = [ ];
          };
        };
      };
  };
}
