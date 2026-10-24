# Mail as code: every domain in the identity model with mailboxes is a Proton
# custom domain, and every mailbox an address on it.
#
#   mail login          sign in to Proton (your 2FA code), save the session
#   mail plan           declared domains and addresses against Proton
#   mail apply          add missing domains, create missing addresses (with
#                       their keys), set catch-alls
#   mail apply --prune  also disable addresses no longer declared
#   mail domains        the live domains and their DNS states, as JSON
#
# A new domain's verification and DKIM values are not secret: `apply` prints
# them as identity.domains.<d>.proton, they are committed, and the infra
# workflow publishes the records. Addresses are created once Proton has
# verified the domain, so a new domain takes: apply, commit, infra apply,
# apply again.
#
# The session (UID, refresh token, key passphrase) lives in your root vault
# and is rewritten on every run, since Proton rotates the refresh token.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.protonMail;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  inherit (config.identity.checked) domains entities;
  withMail = lib.filterAttrs (_: d: d.mailboxes != [ ]) domains;

  state = {
    Domains = lib.mapAttrs (name: d: {
      Addresses = lib.genAttrs d.mailboxes (_: entities.${d.entity}.legalName);
      CatchAll = cfg.catchAll.${name} or "";
      Declared =
        if d.proton == null then
          null
        else
          {
            Verification = d.proton.verification;
            DkimID = d.proton.dkimId;
          };
    }) withMail;
  };
in
{
  options.protonMail = {
    login = {
      vault = mkOption {
        type = types.enum config.proton.vaults;
        description = "The vault holding your Proton account's login item.";
      };
      item = mkOption {
        type = types.str;
        description = "Its title; `mail login` reads its email (or username) and password fields.";
      };
    };
    catchAll = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Per domain: the mailbox that receives mail sent to undeclared addresses.";
    };
  };

  config = {
    protonMail.login = {
      vault = config.proton.infraVaults.root;
      item = "Email-ZachariahMain";
    };

    # Mail to anything@ a domain lands where automations read it.
    protonMail.catchAll = lib.mapAttrs (_: _: "automations") (
      lib.filterAttrs (_: d: builtins.elem "automations" d.mailboxes) withMail
    );

    secrets.profiles.proton-mail = {
      defaults.providers = [ "root" ];
      PROTON_MAIL_SESSION =
        import ../_lib/secret.nix "Proton Mail session for `mail`, rewritten on every run"
          "proton-mail-session"
        // {
          required = false;
        };
    };

    perSystem =
      { pkgs, config, ... }:
      {
        packages.mail = pkgs.writeShellApplication {
          name = "mail";
          runtimeInputs = [
            config.packages.proton-mail
            config.packages.pass-cli
            config.packages.secretspec
            pkgs.coreutils
          ];
          # Builds only while the declared plans cover what the repo needs.
          text = builtins.seq top.accounts.checked ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            spec=${config.packages.secretspec-toml}
            reason="mail $*"
            state=${pkgs.writeText "mail-state.json" (builtins.toJSON state)}

            # proton-mail writes the rotated session to fd 3: into a private
            # file, then into Proton Pass, then gone.
            work=$(mktemp -d)
            chmod 700 "$work"
            trap 'rm -rf "$work"' EXIT
            keep() {
              if [ -s "$work/session" ]; then
                secretspec set PROTON_MAIL_SESSION --file "$spec" --profile proton-mail \
                  --from-file "$work/session" --reason "$reason: save the session" >/dev/null
              fi
            }
            field() {
              ${cli.passCli "item view" {
                vault-name = cfg.login.vault;
                item-title = cfg.login.item;
                field.shell = "$1";
              }}
            }

            case "''${1:-}" in
              login)
                # Proton Pass logins keep the address in `email`; older ones in `username`.
                PROTON_USERNAME=$(field email 2>/dev/null || field username)
                PROTON_PASSWORD=$(field password)
                export PROTON_USERNAME PROTON_PASSWORD
                status=0
                proton-mail login 3>"$work/session" || status=$?
                unset PROTON_PASSWORD
                keep
                exit "$status"
                ;;
              plan | domains)
                PROTON_MAIL_SESSION=$(secretspec get PROTON_MAIL_SESSION --file "$spec" --profile proton-mail --reason "$reason")
                export PROTON_MAIL_SESSION
                status=0
                if [ "$1" = plan ]; then
                  proton-mail plan "$state" 3>"$work/session" || status=$?
                else
                  proton-mail domains 3>"$work/session" || status=$?
                fi
                keep
                exit "$status"
                ;;
              apply)
                PROTON_MAIL_SESSION=$(secretspec get PROTON_MAIL_SESSION --file "$spec" --profile proton-mail --reason "$reason")
                export PROTON_MAIL_SESSION
                status=0
                proton-mail apply "$state" ''${2:+"$2"} 3>"$work/session" || status=$?
                keep
                exit "$status"
                ;;
              *)
                echo "usage: mail <login|plan|apply [--prune]|domains>" >&2
                exit 2
                ;;
            esac
          '';
        };
      };
  };
}
