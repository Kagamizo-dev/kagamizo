# The Kagamizo shell: one base OS for every target, declared. A target is a
# NixOS image (the Yoga, the Raspberry Pi) or the browser (os.jingzo.org,
# behind Access). Each runs the same Rust shell (./_shell): a home of app
# cards in one vertical column, one app in front at a time, and a settings
# app whose sections are generated from the repository's own declarations.
# On a NixOS target the shell is niri's first window, and every app opens
# full screen on its own workspace below it: niri stacks workspaces
# vertically, so moving between apps is moving up and down.
#
#   shell.targets.<t> = { kind = "nixos" | "android" | "web"; host; }
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
  # The library's shelves, in the order the home shows them.
  categories = [
    "system"
    "work"
    "chat"
    "browse"
    "build"
    "research"
    "money"
    "media"
    "play"
    "twin"
    "security"
    "reverse"
  ];

  # Every module of the repository, read as papers.nix reads them.
  dir = ../.;
  modules = lib.attrNames (
    lib.filterAttrs (n: t: t == "directory" && !lib.hasPrefix "_" n) (builtins.readDir dir)
  );

  # The base's Settings sections, in order, and the generated ones beside them.
  baseSections = [
    "system"
    "devices"
    "accounts"
    "identity"
    "governance"
    "infrastructure"
    "repository"
  ];
  sectionOrder = [
    "system"
    "devices"
    "apps"
    "accounts"
    "identity"
    "teams"
    "governance"
    "infrastructure"
    "repository"
  ];
  titleOf = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s;

  # What a program is built for, and what a target runs.
  platforms = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-windows"
    "x86_64-android"
    "aarch64-android"
    "web"
  ];

  # A translator: runs programs built for `from` on a `to` machine, installed
  # on the targets it names (as a package, or as a binfmt handler).
  runtime = types.submodule {
    options = {
      from = mkOption { type = types.enum platforms; };
      to = mkOption { type = types.enum platforms; };
      kind = mkOption {
        type = types.enum [
          "package"
          "binfmt"
        ];
        description = "package: a program on the PATH; binfmt: the kernel runs `from` binaries through qemu-user transparently.";
      };
      package = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "For package: the nixpkgs attribute.";
      };
      targets = mkOption { type = types.listOf (types.enum (lib.attrNames cfg.targets)); };
      why = mkOption { type = types.str; };
    };
  };

  target = types.submodule {
    options = {
      platform = mkOption {
        type = types.enum platforms;
        description = "What the target runs natively.";
      };
      kind = mkOption {
        type = types.enum [
          "nixos"
          "android"
          "web"
        ];
        description = "nixos: an image of ours, which runs native apps; android: a phone, which runs the web target; web: a browser.";
      };
      host = mkOption {
        type = types.str;
        description = "The nixosConfigurations name, the android device, or the web target's hostname.";
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
          "module"
        ];
        description = "native: a program in the image; web: a page behind Access; builtin: a part of the shell; module: the module's own page, generated.";
      };
      module = mkOption {
        type = types.enum modules;
        description = "The module that registers it, in its own library.nix.";
      };
      description = mkOption {
        type = types.str;
        default = "";
      };
      view = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              title = mkOption { type = types.str; };
              rows = mkOption {
                type = types.listOf (types.attrsOf types.str);
                default = [ ];
                description = "Each row a title and a detail.";
              };
            };
          }
        );
        default = [ ];
        description = "For module: sections of rows its page shows, generated by the module.";
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
      targets = mkOption {
        type = types.listOf (types.enum (lib.attrNames cfg.targets));
        default = lib.attrNames cfg.targets;
        description = "Where it shows; every target unless it says otherwise.";
      };
      platform = mkOption {
        type = types.nullOr (types.enum platforms);
        default = null;
        description = "For native: what the program is built for; null for the target's own. Another platform runs through the target's runtimes.";
      };
    };
  };

  base = types.submodule {
    options = {
      section = mkOption { type = types.enum baseSections; };
      why = mkOption { type = types.str; };
    };
  };

  nativeTargets = lib.unique (
    lib.concatMap (a: a.targets) (lib.filter (a: a.kind == "native") (lib.attrValues cfg.apps))
  );
  appModules = lib.unique (lib.mapAttrsToList (_: a: a.module) cfg.apps);

  # A module's page: its paper's title, abstract, checks, packages and
  # teams, read from modules/<m>/_lean/Paper.lean when it has one.
  paperOf =
    m:
    let
      file = dir + "/${m}/_lean/Paper.lean";
      text = if builtins.pathExists file then builtins.readFile file else "";
      first =
        re:
        let
          hit = lib.findFirst lib.isList null (builtins.split re text);
        in
        if hit == null then "" else lib.head hit;
      field = name: first "\n  ${name} := \"([^\"]*)\"";
      strings =
        name:
        let
          inner = first "\n  ${name} := [[]([^\n]*)[]]";
        in
        map lib.head (lib.filter lib.isList (builtins.split "\"([^\"]*)\"" inner));
    in
    {
      title = field "title";
      abstract = field "abstract";
      checks = strings "checks";
      packages = strings "packages";
      teams = strings "agents";
    };

  # What the settings app shows, generated: never hand-written.
  generated = {
    system = lib.mapAttrsToList (n: t: {
      title = n;
      detail = "${t.kind} target (${t.host}): ${t.why}";
    }) cfg.targets;
    # Owned first, then the proposals.
    devices = lib.sort (a: b: a.owned && !b.owned) (
      lib.mapAttrsToList (n: i: {
        inherit (i) owned;
        title = n;
        detail = "${
          if i.owned then "owned" else "proposal"
        }, ${i.slot}: ${i.device}; provides ${lib.concatStringsSep ", " i.provides}";
      }) config.kit.items
    );
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
      detail = "${a.kind} ${a.category} app from modules/${a.module}, on ${lib.concatStringsSep ", " a.targets}";
    }) cfg.apps;
  };
  baseRows =
    s:
    lib.mapAttrsToList (m: b: {
      title = "modules/${m}";
      detail = b.why;
    }) (lib.filterAttrs (_: b: b.section == s) cfg.base);
  sections = map (k: {
    key = k;
    title = titleOf k;
    rows = (generated.${k} or [ ]) ++ baseRows k;
  }) sectionOrder;
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
    runtimes = mkOption {
      type = types.attrsOf runtime;
      default = { };
    };
    runtimeModule = mkOption {
      type = types.functionTo types.raw;
      readOnly = true;
      description = "A target's runtimes as a NixOS module, for its image to import.";
      default =
        t:
        { pkgs, lib, ... }:
        let
          mine = lib.filter (r: lib.elem t r.targets) (lib.attrValues cfg.runtimes);
        in
        {
          environment.systemPackages = map (r: pkgs.${r.package}) (lib.filter (r: r.kind == "package") mine);
          boot.binfmt.emulatedSystems = map (r: r.from) (lib.filter (r: r.kind == "binfmt") mine);
        };
    };
    services = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.app = mkOption {
            type = types.enum (lib.attrNames cfg.apps);
            description = "The app the module serves inside, which shows it.";
          };
        }
      );
      default = { };
      description = "Modules that are services of another app (the bank's treasury, brokerage, tax), keyed by module.";
    };
    base = mkOption {
      type = types.attrsOf base;
      default = { };
      description = "The modules that are the base: each a section of Settings, keyed by module.";
    };
    rendered = mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
      description = "The declarations as the shell reads them.";
      default = {
        inherit (cfg) apps;
        inherit sections categories;
        pages = lib.genAttrs appModules (
          m:
          paperOf m
          // {
            view = lib.concatMap (a: a.view) (lib.filter (a: a.module == m) (lib.attrValues cfg.apps));
          }
        );
      };
    };
  };

  config = {
    shell = {
      targets = {
        yoga-c940 = {
          kind = "nixos";
          platform = "x86_64-linux";
          host = "yoga-c940";
          why = "the first device: Intel graphics, a live USB that runs from RAM";
        };
        web = {
          kind = "web";
          platform = "web";
          host = "os.jingzo.org";
          why = "the same shell in any browser, the phone's included, behind Access";
        };
        # The carried kit (../kit): the Pi is the machine in the pocket, the
        # phone its screen.
        rpi5 = {
          kind = "nixos";
          platform = "aarch64-linux";
          host = "rpi5";
          why = "the kit's machine: aarch64 in a pocket, serving the shell to the phone";
        };
        pixel-9a = {
          kind = "android";
          platform = "aarch64-android";
          host = "pixel-9a";
          why = "the kit's screen: GrapheneOS, the web target installed from the browser";
        };
        android-twin = {
          kind = "android";
          platform = "x86_64-android";
          host = "pixel-9a";
          why = "the phone's twin on jingzo-host: the agents' sandboxed Pixel, which opens the web target like the phone";
        };
      };

      # The shell is base (its own Settings row) and registers its own apps;
      # every other module registers in its own library.nix.
      # Software built for one machine, run on another: each translator
      # pinned from nixpkgs, installed on the targets it names.
      runtimes = {
        qemu-x86_64 = {
          from = "x86_64-linux";
          to = "aarch64-linux";
          kind = "binfmt";
          targets = [ "rpi5" ];
          why = "x86_64 Linux programs on the Pi, through qemu-user, whatever the kernel's page size";
        };
        qemu-aarch64 = {
          from = "aarch64-linux";
          to = "x86_64-linux";
          kind = "binfmt";
          targets = [ "yoga-c940" ];
          why = "the Pi's aarch64 programs on the Yoga, to test what the kit runs before it is carried";
        };
        wine = {
          from = "x86_64-windows";
          to = "x86_64-linux";
          kind = "package";
          package = "wine64";
          targets = [ "yoga-c940" ];
          why = "Windows programs the owner owns or licenses, on the Yoga";
        };
      };
      base.shell = {
        section = "system";
        why = "the shell itself: the library, Settings, and every target's session";
      };
      apps = {
        settings = {
          name = "Settings";
          category = "system";
          kind = "builtin";
          module = "shell";
          description = "The base: every target, device, account and team, from the repository";
        };
        browser = {
          name = "Firefox";
          category = "browse";
          kind = "native";
          module = "shell";
          command = "firefox";
          # The Pi joins once its image carries the shell's session.
          targets = [ "yoga-c940" ];
        };
        terminal = {
          name = "Terminal";
          category = "build";
          kind = "native";
          module = "shell";
          command = "foot";
          targets = [ "yoga-c940" ];
        };
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
          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.pkg-config
          ];
          buildInputs = [
            # gilrs reads gamepads through udev.
            pkgs.udev
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
        # The PATH of each image a native app ships in, to check its command
        # is there (only those: reading a PATH builds the image's packages).
        imagePaths = lib.genAttrs nativeTargets (
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
                  n: t:
                  "{ name := ${q n}, web := ${lib.boolToString (t.kind != "nixos")}, platform := ${q t.platform} }"
                ) cfg.targets
              )
            }]
            def apps : List App := [${
              lib.concatStringsSep ",\n  " (
                lib.mapAttrsToList (
                  n: a:
                  "{ id := ${q n}, kind := .${a.kind}, command := ${
                    q (if a.command == null then "" else a.command)
                  }, targets := ${q a.targets}, platform := ${q (if a.platform == null then "" else a.platform)} }"
                ) cfg.apps
              )
            }]
            def runtimes : List Runtime := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (
                  n: r: "{ name := ${q n}, src := ${q r.from}, dst := ${q r.to}, targets := ${q r.targets} }"
                ) cfg.runtimes
              )
            }]
            def images : List (String × List String) := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (t: bins: "(${q t}, ${q (lib.unique bins)})") imagePaths
              )
            }]

            set_option maxRecDepth 100000
            def modules : List String := ${q modules}
            def base : List String := ${q (lib.attrNames cfg.base ++ lib.attrNames cfg.services)}
            def appModules : List String := ${q appModules}

            theorem shell_sound : sound targets runtimes apps images = true := by decide +kernel
            theorem library_covered : covered modules base appModules = true := by decide +kernel
            end Kagamizo.Shell
          '';
        };
      };
  };
}
