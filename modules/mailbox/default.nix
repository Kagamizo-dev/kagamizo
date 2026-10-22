# Confirmation mail, read by the session itself: Proton Mail Bridge (nixpkgs,
# pinned with the flake) serves the Proton account over IMAP on the
# loopback, and `mailbox` (./_src, Rust) reads from it only what a module
# declares: mail to an account's own login address, from its provider's
# sender domains, and the one link on its provider's hosts.
#
#   nix run .#mailbox -- login
#       signs Bridge in to Proton with the `proton` account's login item;
#       Proton's 2FA code (or a human verification) is the owner's step
#   nix run .#mailbox -- link --account A [--since MIN] [--wait MIN]
#       the newest declared link in A's mail, on stdout only, for a browser
#       flow to open; nothing else of the mail is printed
#
# Bridge's keychain is `pass`, here a stand-in (mailbox-keychain) that keeps
# Bridge's vault key in Proton Pass; the encrypted vault itself (Bridge's
# Proton session) is kept there too between runs, in the owner's sessions
# vault. Bridge is told not to update itself or send diagnostics.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  inherit (config.identity.checked) entities;

  domain = types.strMatching "([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}";
  sender = types.submodule {
    options = {
      from = mkOption {
        type = types.nonEmptyListOf domain;
        description = "Domains the provider's mail comes from (a subdomain of one counts).";
      };
      hosts = mkOption {
        type = types.nonEmptyListOf domain;
        description = "Hosts a link in that mail may be on to be followed.";
      };
      path = mkOption {
        type = types.nullOr (types.strMatching "/[A-Za-z0-9/_-]*");
        default = null;
        description = "The link's path starts with this; null while it is being mapped.";
      };
    };
  };

  # Everything the driver (./_src) types into Bridge's CLI and starts it
  # with: each command must be one the pinned Bridge has
  # (../catalog/_json/bridge.json), so a Bridge bump that drops or renames
  # one fails evaluation; `checks.mailbox` holds the source to this list.
  bridgeCommands = [
    "updates autoupdates disable"
    "telemetry disable"
    "login"
    "info"
    "cert export"
    "exit"
  ];
  # Answers to Bridge's own questions (yes/no, Enter after a verification).
  bridgeAnswers = [
    "yes"
    ""
  ];
  bridgeFlags = [ "cli" ];
  bridgeCatalog = lib.importJSON ../catalog/_json/bridge.json;
  bridgeProblems =
    map (c: "Bridge has no command `${c}`") (
      lib.filter (c: !(bridgeCatalog.commands ? ${c})) bridgeCommands
    )
    ++ map (f: "Bridge has no flag --${f}") (
      lib.filter (f: !(lib.elem f bridgeCatalog.flags)) bridgeFlags
    );

  proton = config.accounts.held.proton;
  profile = "proton-bridge";
  withMail = lib.filterAttrs (
    _: a: config.mailbox.senders ? ${a.provider} && a.login.email != null
  ) config.accounts.held;
  accounts = lib.mapAttrs (_: a: {
    inherit (a) provider;
    to = a.login.email;
    inherit (config.mailbox.senders.${a.provider}) from hosts path;
  }) withMail;
in
{
  options.mailbox.senders = mkOption {
    type = types.attrsOf sender;
    default = { };
    description = "Per provider, the confirmation mail its flows wait for.";
  };

  config = {
    accounts.demands = [
      {
        account = "proton";
        capability = "bridge";
        need = true;
        why = "mailbox: confirmation mail through Proton Mail Bridge";
      }
    ];

    secrets.profiles.${profile} = {
      defaults.providers = [ "${proton.owner}-sessions" ];
      BRIDGE_VAULT_KEY =
        import ../_lib/secret.nix "Proton Mail Bridge's vault key, kept by its keychain stand-in"
          "bridge-vault-key"
        // {
          required = false;
        };
      BRIDGE_VAULT =
        import ../_lib/secret.nix "Proton Mail Bridge's encrypted vault (its Proton session), base64"
          "bridge-vault"
        // {
          required = false;
        };
    };

    # Signing Bridge in is a session on the Proton account; reading one
    # account's confirmation mail is a read on that account.
    governance.actions = {
      proton.bridge = {
        effect = "session";
        description = "Sign Proton Mail Bridge in and serve the mailboxes over IMAP on the loopback";
        command = "mailbox login";
      };
    }
    // lib.mapAttrs (_: _: {
      confirmation-mail = {
        effect = "read";
        description = "The declared link in the account's confirmation mail";
        command = "mailbox link";
      };
    }) config.mailbox.senders;

    perSystem =
      { pkgs, config, ... }:
      let
        accountsJson = pkgs.writeText "mailbox-accounts.json" (builtins.toJSON accounts);
        run = pkgs.rustPlatform.buildRustPackage {
          pname = "mailbox";
          version = "0.1.0";
          src = ./_src;
          cargoLock.lockFile = ./_src/Cargo.lock;
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ pkgs.openssl ];
          meta.mainProgram = "mailbox";
        };
        # Bridge finds its keychain by the name `pass` on its PATH.
        keychain = pkgs.runCommand "mailbox-keychain" { } ''
          mkdir -p $out/bin
          ln -s ${run}/bin/mailbox-keychain $out/bin/pass
        '';
      in
      {
        packages.mailbox-run =
          assert lib.assertMsg (bridgeProblems == [ ]) (
            "modules/mailbox: calls the pinned Bridge does not have:\n"
            + lib.concatStringsSep "\n" bridgeProblems
          );
          run;

        packages.mailbox = pkgs.writeShellApplication {
          name = "mailbox";
          runtimeInputs = [
            run
            config.packages.pass-cli
            config.packages.secretspec
            config.packages.governance-authorize
            pkgs.jq
            pkgs.coreutils
          ];
          text = builtins.seq top.accounts.checked ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            usage="usage: mailbox login | link --account A [--since MIN] [--wait MIN]; accounts: $(jq -r 'keys | join(", ")' ${accountsJson})"
            governance-authorize proton:bridge proton
            args=()
            case "''${1:-}" in
              login) args=(login) ;;
              link)
                [ "''${2:-}" = --account ] || { echo "$usage" >&2; exit 2; }
                account=''${3:?$usage}
                shift 3
                held=$(jq -c --arg a "$account" '.[$a] // empty' ${accountsJson})
                [ -n "$held" ] || { echo "no declared confirmation mail for $account; $usage" >&2; exit 2; }
                governance-authorize "$(jq -r .provider <<<"$held"):confirmation-mail" "$account"
                args=(link --to "$(jq -r .to <<<"$held")")
                while read -r d; do args+=(--from "$d"); done < <(jq -r '.from[]' <<<"$held")
                while read -r h; do args+=(--host "$h"); done < <(jq -r '.hosts[]' <<<"$held")
                path=$(jq -r '.path // empty' <<<"$held")
                [ -z "$path" ] || args+=(--path "$path")
                while [ $# -gt 0 ]; do
                  case $1 in
                    --since | --wait) args+=("$1" "''${2:?$1 needs minutes}"); shift 2 ;;
                    *) echo "$usage" >&2; exit 2 ;;
                  esac
                done
                ;;
              *) echo "$usage" >&2; exit 2 ;;
            esac

            private=$(mktemp -d)
            chmod 700 "$private"
            trap 'rm -rf "$private"' EXIT
            MAILBOX_PRIVATE=$private \
              MAILBOX_BRIDGE=${lib.getExe pkgs.protonmail-bridge} \
              MAILBOX_KEYCHAIN_DIR=${keychain}/bin \
              MAILBOX_SECRETSPEC_FILE=${config.packages.secretspec-toml} \
              MAILBOX_PROFILE=${profile} \
              MAILBOX_LOGIN_VAULT=${lib.escapeShellArg entities.${proton.owner}.vault} \
              MAILBOX_LOGIN_ITEM=${lib.escapeShellArg proton.login.item} \
              MAILBOX_LOGIN=${proton.login.email} \
              mailbox "''${args[@]}"
          '';
        };

        # The keychain stand-in through every call Bridge's keychain makes,
        # with a secretspec stand-in: the vault key goes to "Proton Pass",
        # the store keeps only empty markers, and any other call is refused.
        checks.mailbox =
          pkgs.runCommand "mailbox-check"
            {
              nativeBuildInputs = [
                keychain
                pkgs.coreutils
                pkgs.findutils
                pkgs.gnugrep
                pkgs.jq
              ];
            }
            ''
              # Every command and answer the driver sends, and every flag it
              # starts Bridge with, is declared above.
              declared=${pkgs.writeText "bridge-sends.json" (builtins.toJSON (bridgeCommands ++ bridgeAnswers))}
              { grep -o 'send("[^"]*")' ${./_src/src/main.rs} | cut -d'"' -f2
                grep -o '^ *("[a-z ]*", "' ${./_src/src/main.rs} | cut -d'"' -f2
              } | sort -u | while read -r c; do
                jq -e --arg c "$c" 'index($c) != null' $declared >/dev/null ||
                  { echo "the driver sends \`$c\` to Bridge, undeclared in bridgeCommands" >&2; exit 1; }
              done
              grep -o '\.arg("--[a-z-]*")' ${./_src/src/main.rs} | cut -d'"' -f2 | sed 's/^--//' |
                while read -r f; do
                  jq -e --arg f "$f" 'index($f) != null' ${pkgs.writeText "bridge-flags.json" (builtins.toJSON bridgeFlags)} >/dev/null ||
                    { echo "the driver starts Bridge with --$f, undeclared in bridgeFlags" >&2; exit 1; }
                done
              export PASSWORD_STORE_DIR=$TMPDIR/store SECRETSPEC_STUB_DIR=$TMPDIR/pp MAILBOX_PRIVATE=$TMPDIR/private
              export MAILBOX_SECRETSPEC_FILE=/dev/null MAILBOX_PROFILE=${profile} MAILBOX_CALLER_HOME=$TMPDIR
              mkdir -p $PASSWORD_STORE_DIR $SECRETSPEC_STUB_DIR $MAILBOX_PRIVATE $TMPDIR/bin
              cp ${./_test/secretspec} $TMPDIR/bin/secretspec
              export PATH=$TMPDIR/bin:$PATH
              b64() { printf %s "$1" | base64 -w0 | tr '+/' '-_'; }
              key=docker-credential-helpers/$(b64 protonmail/bridge-v3/users/bridge-vault-key)
              check=docker-credential-helpers/$(b64 bridge/check)
              pass ls
              printf check | pass insert -f -m "$check/check"
              [ "$(pass show "$check/check")" = check ]
              pass rm -rf "$check"
              ! printf other | pass insert -f -m "$check/check"
              printf 'the-key' | pass insert -f -m "$key/bridge-vault-key"
              [ "$(cat $SECRETSPEC_STUB_DIR/BRIDGE_VAULT_KEY)" = the-key ]
              [ "$(pass show "$key/bridge-vault-key")" = the-key ]
              [ -z "$(find $PASSWORD_STORE_DIR -type f -size +0)" ]
              [ -z "$(ls -A $MAILBOX_PRIVATE)" ]
              ! printf x | pass insert -f -m docker-credential-helpers/other/user
              ! pass show docker-credential-helpers/other/user
              touch $out
            '';
      };
  };
}
