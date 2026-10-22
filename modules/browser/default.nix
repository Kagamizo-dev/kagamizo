# The browser: what an account's provider offers no API for, done the way
# a person does it, as a typed flow. `browser-run` (./_src, Rust over the
# DevTools Protocol) runs one flow in a fresh Chromium profile; the flows are
# declared by each provider's module (browser.flows.<provider>.<flow>) and
# each is a governance action, so Cedar decides who may run it on which
# account, and the login rule holds as for every other wrapper.
#
#   nix run .#browser -- --account A <provider>:<flow>
#
# A flow never leaves its hosts (HTTPS only), types values from the
# account's Proton Pass login item without printing them, and stops for
# the owner's approval (a push, a link, a code) where the provider asks.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  inherit (config.identity.checked) entities;

  host = types.strMatching "([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}";
  url = types.strMatching "https://([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}(/.*)?";
  role = types.enum [
    "button"
    "link"
    "textbox"
    "combobox"
    "checkbox"
    "radio"
    "option"
    "menuitem"
    "tab"
    "heading"
  ];
  target = types.submodule {
    options = {
      by = mkOption {
        type = types.enum [
          "role"
          "css"
        ];
      };
      role = mkOption {
        type = types.nullOr role;
        default = null;
      };
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      css = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };
  value = types.submodule {
    options = {
      from = mkOption {
        type = types.enum [
          "text"
          "declared"
          "pass"
        ];
      };
      text = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      field = mkOption {
        type = types.nullOr (
          types.enum [
            "username"
            "email"
            "password"
            "totp"
          ]
        );
        default = null;
      };
    };
  };
  until = types.submodule {
    options = {
      when = mkOption {
        type = types.enum [
          "url-prefix"
          "shows"
        ];
      };
      prefix = mkOption {
        type = types.nullOr url;
        default = null;
      };
      target = mkOption {
        type = types.nullOr target;
        default = null;
      };
    };
  };
  # One step; which fields each kind takes is checked by browser-run's own
  # types (deny_unknown_fields) in `checks.browser`, against every flow.
  step = types.submodule {
    options = {
      do = mkOption {
        type = types.enum [
          "goto"
          "fill"
          "click"
          "wait-for"
          "wait-url"
          "approve"
          "code"
          "snapshot"
        ];
      };
      url = mkOption {
        type = types.nullOr url;
        default = null;
      };
      target = mkOption {
        type = types.nullOr target;
        default = null;
      };
      value = mkOption {
        type = types.nullOr value;
        default = null;
      };
      prefix = mkOption {
        type = types.nullOr url;
        default = null;
      };
      seconds = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
      };
      prompt = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      until = mkOption {
        type = types.nullOr until;
        default = null;
      };
      minutes = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
      };
    };
  };
  flow = types.submodule {
    options = {
      effect = mkOption {
        type = types.enum config.governance.effects;
        description = "What the flow does to the account, for Cedar.";
      };
      description = mkOption { type = types.str; };
      hosts = mkOption {
        type = types.nonEmptyListOf host;
        description = "The only hosts the browser may be on during the flow.";
      };
      steps = mkOption { type = types.nonEmptyListOf step; };
    };
  };

  # Nulls dropped, so the JSON is exactly what browser-run's types expect.
  clean =
    v:
    if builtins.isAttrs v then
      lib.mapAttrs (_: clean) (lib.filterAttrs (_: x: x != null) v)
    else if builtins.isList v then
      map clean v
    else
      v;
  flows = lib.concatMapAttrs (
    provider: fs:
    lib.mapAttrs' (name: f: lib.nameValuePair "${provider}:${name}" (f // { inherit provider; })) fs
  ) config.browser.flows;
  rendered = lib.mapAttrs (action: f: {
    inherit action;
    inherit (f) provider;
    flow = clean {
      inherit action;
      inherit (f) hosts steps;
    };
  }) flows;
  # Every DevTools Protocol call browser-run makes (./_src), directly or
  # through chromiumoxide, with the parameters it passes. Each must exist in
  # the pinned Chromium's own protocol (../catalog/_json/cdp.json), so a
  # Chromium bump that drops or renames one fails evaluation here.
  cdpCalls = {
    "Page.navigate" = [ "url" ];
    "DOM.getDocument" = [ "depth" ];
    "DOM.querySelector" = [
      "nodeId"
      "selector"
    ];
    "DOM.focus" = [ "backendNodeId" ];
    "DOM.scrollIntoViewIfNeeded" = [ "backendNodeId" ];
    "DOM.getBoxModel" = [ "backendNodeId" ];
    "Input.insertText" = [ "text" ];
    "Input.dispatchMouseEvent" = [
      "type"
      "x"
      "y"
      "button"
      "clickCount"
    ];
    "Accessibility.queryAXTree" = [
      "backendNodeId"
      "accessibleName"
      "role"
    ];
    "Accessibility.getFullAXTree" = [ ];
  };
  protocol = (lib.importJSON ../catalog/_json/cdp.json).domains;
  cdpProblems = lib.concatLists (
    lib.mapAttrsToList (
      call: params:
      let
        parts = lib.splitString "." call;
        command = protocol.${lib.head parts}.commands.${lib.last parts} or null;
      in
      if command == null then
        [ "${call}: not in the pinned Chromium's protocol" ]
      else
        map (p: "${call}: has no parameter ${p}") (lib.filter (p: !(command.params ? ${p})) params)
    ) cdpCalls
  );

  accounts = lib.mapAttrs (_: a: {
    inherit (a) provider;
    login = {
      inherit (entities.${a.owner}) vault;
      inherit (a.login) item email;
    };
  }) config.accounts.held;
in
{
  options.browser.flows = mkOption {
    type = types.attrsOf (types.attrsOf flow);
    default = { };
    description = "Per provider, the flows its module declares.";
  };

  # Every flow is an action like any other wrapper's.
  config.governance.actions = lib.mapAttrs (
    provider:
    lib.mapAttrs (
      name: f: {
        inherit (f) effect description;
        command = "browser ${provider}:${name}";
      }
    )
  ) config.browser.flows;

  config.perSystem =
    { pkgs, config, ... }:
    let
      flowsJson = pkgs.writeText "browser-flows.json" (builtins.toJSON rendered);
      # A declared font set: with none, Chromium dies rendering a form.
      fonts = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
      accountsJson = pkgs.writeText "browser-accounts.json" (builtins.toJSON accounts);
    in
    {
      packages.browser-run =
        assert lib.assertMsg (cdpProblems == [ ]) (
          "modules/browser: DevTools calls the pinned Chromium does not have:\n"
          + lib.concatStringsSep "\n" cdpProblems
        );
        pkgs.rustPlatform.buildRustPackage {
          pname = "browser-run";
          version = "0.1.0";
          src = ./_src;
          cargoLock.lockFile = ./_src/Cargo.lock;
          meta.mainProgram = "browser";
        };

      packages.browser = pkgs.writeShellApplication {
        name = "browser";
        runtimeInputs = [
          config.packages.browser-run
          config.packages.pass-cli
          config.packages.governance-authorize
          pkgs.jq
          pkgs.coreutils
        ];
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          usage="usage: browser --account A <provider>:<flow>; flows: $(jq -r 'keys | join(", ")' ${flowsJson})"
          [ "''${1:-}" = --account ] || { echo "$usage" >&2; exit 2; }
          account=''${2:?$usage} action=''${3:?$usage}
          flow=$(jq -c --arg f "$action" '.[$f] // empty' ${flowsJson})
          [ -n "$flow" ] || { echo "no flow $action; $usage" >&2; exit 2; }
          held=$(jq -c --arg a "$account" '.[$a] // empty' ${accountsJson})
          [ -n "$held" ] || { echo "no account $account" >&2; exit 2; }
          [ "$(jq -r .provider <<<"$held")" = "$(jq -r .provider <<<"$flow")" ] ||
            { echo "$action is not for $account's provider" >&2; exit 2; }
          governance-authorize "$action" "$account"

          dir=$(mktemp -d)
          chmod 700 "$dir"
          trap 'rm -rf "$dir"' EXIT
          jq --arg a "$account" --argjson h "$held" '.flow + {account: $a, login: $h.login}' <<<"$flow" >"$dir/flow.json"
          mkdir "$dir/profile"
          [ "$(id -u)" != 0 ] || export BROWSER_NO_SANDBOX=1
          FONTCONFIG_FILE=${fonts} BROWSER_CHROMIUM=${lib.getExe pkgs.chromium} BROWSER_PROFILE=$dir/profile \
            browser "$dir/flow.json"
        '';
      };

      # browser-run against a page of its own on the loopback: it finds by
      # role and by CSS, fills, clicks, waits for an approval and reads the
      # page back; and every declared flow passes its types.
      checks.browser =
        pkgs.runCommand "browser-check"
          {
            nativeBuildInputs = [
              config.packages.browser-run
              pkgs.python3
              pkgs.jq
            ];
          }
          ''
            export HOME=$TMPDIR FONTCONFIG_FILE=${fonts} BROWSER_NO_SANDBOX=1 BROWSER_CHROMIUM=${lib.getExe pkgs.chromium}
            # Every raw protocol call in the source is one cdpCalls declares.
            grep -oh 'method: "[A-Za-z]*\.[A-Za-z]*"' ${./_src/src}/*.rs | cut -d'"' -f2 | sort -u |
              while read -r m; do
                jq -e --arg m "$m" 'has($m)' ${pkgs.writeText "cdp-calls.json" (builtins.toJSON cdpCalls)} >/dev/null ||
                  { echo "$m is called in _src but not declared in cdpCalls" >&2; exit 1; }
              done
            cp ${./_test/page.html} page.html
            python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 &
            sed s/PORT/8765/g ${./_test/flow.json} > flow.json
            mkdir profile
            BROWSER_PROFILE=$PWD/profile browser flow.json > snapshot.txt
            grep -q 'button     "Invite member"' snapshot.txt
            ! grep -q 'finance@' snapshot.txt
            jq -c 'to_entries[] | .value.flow + {account: "check", login: {vault: "v", item: "i", email: "a@b.c"}}' ${flowsJson} |
              while read -r f; do echo "$f" > one.json; browser --check one.json; done
            cp snapshot.txt $out
          '';
    };
}
