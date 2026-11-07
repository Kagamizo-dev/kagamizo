# The Kagamizo shell: one base OS for every target, declared. A target is a
# NixOS image (the Yoga, the Raspberry Pi) or the browser (os.jingzo.org,
# behind Access). Each runs the same Rust shell (./_shell): a home of app
# cards in one vertical column, one app in front at a time, and a settings
# app whose sections are generated from the repository's own declarations.
# On a NixOS target the shell is niri's first window, and every app opens
# full screen on its own workspace below it: niri stacks workspaces
# vertically, so moving between apps is moving up and down.
#
#   shell.targets.<t> = { kind = "nixos" | "web"; host; }
#   shell.apps.<a>    = { name; category; kind = "native" | "web";
#                         command | url; targets; }
#
#   packages.kagamizo-shell     the shell, with the declarations it shows
#   packages.kagamizo-shell-web the same shell as WebAssembly, with its page
#   checks.shell                Lean (./_lean/Shell.lean): every app ships on
#                               a target, the web target holds only web apps,
#                               every native app's command is in its image,
#                               and ids are unique
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.shell;
  q = builtins.toJSON;
  categories = [
    "system"
    "work"
    "chat"
    "browse"
    "play"
    "build"
  ];

  target = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "nixos"
          "web"
        ];
      };
      host = mkOption {
        type = types.str;
        description = "The nixosConfigurations name, or the web target's hostname.";
      };
      why = mkOption { type = types.str; };
    };
  };

  app = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      category = mkOption { type = types.enum categories; };
      kind = mkOption {
        type = types.enum [
          "native"
          "web"
          "builtin"
        ];
        description = "native: a program in the image; web: a page behind Access; builtin: a part of the shell.";
      };
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "For native: the program's name on the image's PATH.";
      };
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      targets = mkOption { type = types.listOf (types.enum (lib.attrNames cfg.targets)); };
    };
  };

  web = n: "https://${n}.jingzo.org";
  nixosTargets = lib.attrNames (lib.filterAttrs (_: t: t.kind == "nixos") cfg.targets);
  allTargets = lib.attrNames cfg.targets;

  # What the settings app shows, generated: never hand-written.
  sections = {
    system = lib.mapAttrsToList (n: t: {
      title = n;
      detail = "${t.kind} target (${t.host}): ${t.why}";
    }) cfg.targets;
    accounts = lib.mapAttrsToList (n: a: {
      title = n;
      detail = "${a.provider or "account"}, plan ${a.plan or "undeclared"}";
    }) config.accounts.held;
    teams = lib.mapAttrsToList (n: c: {
      title = n;
      detail = c.goal;
    }) config.agents.charters;
    apps = lib.mapAttrsToList (_: a: {
      title = a.name;
      detail = "${a.kind} ${a.category} app on ${lib.concatStringsSep ", " a.targets}";
    }) cfg.apps;
  };
in
{
  options.shell = {
    targets = mkOption {
      type = types.attrsOf target;
      default = { };
    };
    apps = mkOption {
      type = types.attrsOf app;
      default = { };
    };
    rendered = mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
      description = "The declarations as the shell reads them.";
      default = {
        inherit (cfg) apps targets;
        inherit sections categories;
      };
    };
  };

  config = {
    shell.targets = {
      yoga-c940 = {
        kind = "nixos";
        host = "yoga-c940";
        why = "the first device: Intel graphics, a live USB that runs from RAM";
      };
      web = {
        kind = "web";
        host = "os.jingzo.org";
        why = "the same shell in any browser, the phone's included, behind Access";
      };
    };

    shell.apps = {
      settings = {
        name = "Settings";
        category = "system";
        kind = "builtin";
        targets = allTargets;
      };
      browser = {
        name = "Firefox";
        category = "browse";
        kind = "native";
        command = "firefox";
        targets = nixosTargets;
      };
      terminal = {
        name = "Terminal";
        category = "build";
        kind = "native";
        command = "foot";
        targets = nixosTargets;
      };
      # The status page (modules/site, at status.mirazo.org behind Access):
      # CI, the teams, the twin. Its own page; the shell is where it opens.
      status = {
        name = "Status";
        category = "system";
        kind = "web";
        url = "https://status.mirazo.org";
        targets = allTargets;
      };
      agents = {
        name = "Agents";
        category = "work";
        kind = "web";
        url = web "agents";
        targets = allTargets;
      };
      code = {
        name = "Code";
        category = "build";
        kind = "web";
        url = web "code";
        targets = allTargets;
      };
      harness = {
        name = "Harness";
        category = "work";
        kind = "web";
        url = web "harness";
        targets = allTargets;
      };
      chat = {
        name = "Chat";
        category = "chat";
        kind = "web";
        url = web "chat";
        targets = allTargets;
      };
    };

    perSystem =
      { pkgs, config, ... }:
      let
        declared = pkgs.writeText "shell.json" (builtins.toJSON cfg.rendered);
        shell = pkgs.rustPlatform.buildRustPackage {
          pname = "kagamizo-shell";
          version = "0.1.0";
          src = ./_shell;
          cargoLock.lockFile = ./_shell/Cargo.lock;
          doCheck = true;
          SHELL_DECLARED = declared;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [
            pkgs.libxkbcommon
            pkgs.wayland
            pkgs.libGL
          ];
          # egui opens its window through winit, which loads these at run time.
          postFixup = ''
            wrapProgram $out/bin/kagamizo-shell --prefix LD_LIBRARY_PATH : ${
              lib.makeLibraryPath [
                pkgs.libxkbcommon
                pkgs.wayland
                pkgs.libGL
              ]
            }
          '';
          meta.mainProgram = "kagamizo-shell";
        };
        # The web target: the library built for wasm32 by a toolchain that
        # has the target, bound by the wasm-bindgen its lockfile pins, and
        # the page shell-page writes.
        rust =
          (pkgs.extend inputs.rust-overlay.overlays.default).rust-bin.stable."1.99.1".minimal.override
            {
              targets = [ "wasm32-unknown-unknown" ];
            };
        wasmPlatform = pkgs.makeRustPlatform {
          cargo = rust;
          rustc = rust;
        };
        web = wasmPlatform.buildRustPackage {
          pname = "kagamizo-shell-web";
          version = "0.1.0";
          src = ./_shell;
          cargoLock.lockFile = ./_shell/Cargo.lock;
          SHELL_DECLARED = declared;
          nativeBuildInputs = [ pkgs.wasm-bindgen-cli_0_2_121 ];
          # Its own build: the default hook adds the host's --target as well.
          buildPhase = "cargo build --offline --release --lib --target wasm32-unknown-unknown";
          doCheck = false;
          installPhase = ''
            mkdir -p $out
            wasm-bindgen --target web --no-typescript --out-dir $out \
              target/wasm32-unknown-unknown/release/kagamizo_shell.wasm
            ${shell}/bin/shell-page $out
          '';
        };
        # Each NixOS target's PATH, to check every native app's command is there.
        imagePaths = lib.genAttrs nixosTargets (
          t:
          lib.concatMap (p: lib.attrNames (builtins.readDir "${p}/bin")) (
            lib.filter (
              p: builtins.pathExists "${p}/bin"
            ) top.flake.nixosConfigurations.${cfg.targets.${t}.host}.config.environment.systemPackages
          )
        );
      in
      {
        packages.kagamizo-shell = shell;
        packages.kagamizo-shell-web = web;
        checks.shell = config.kagamizo.leanCheck {
          name = "shell";
          source = ./_lean/Shell.lean;
          facts = ''

            namespace Kagamizo.Shell
            def targets : List Target := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (
                  n: t: "{ name := ${q n}, web := ${lib.boolToString (t.kind == "web")} }"
                ) cfg.targets
              )
            }]
            def apps : List App := [${
              lib.concatStringsSep ",\n  " (
                lib.mapAttrsToList (
                  n: a:
                  "{ id := ${q n}, kind := .${a.kind}, command := ${
                    q (if a.command == null then "" else a.command)
                  }, targets := ${q a.targets} }"
                ) cfg.apps
              )
            }]
            def images : List (String × List String) := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (t: bins: "(${q t}, ${q (lib.unique bins)})") imagePaths
              )
            }]

            set_option maxRecDepth 100000
            theorem shell_sound : sound targets apps images = true := by decide +kernel
            end Kagamizo.Shell
          '';
        };
      };
  };
}
