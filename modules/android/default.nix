# The digital twin of the owner's phone (a Pixel 9a): an emulated Android
# device, declared whole, that the agents use as a sandboxed tool. Its
# state is its base image plus its declared settings plus its declared
# apps and nothing else: the emulator boots without snapshots, and the
# wrapper applies the declaration on every start.
#
#   android.devices.<name>.base      what it boots: the SDK's AOSP emulator
#                                    image now (kind "aosp", pinned by the
#                                    hash nixpkgs' SDK repository states);
#                                    kind "grapheneos" is typed but refused
#                                    until a build job provides an image
#   android.devices.<name>.profile   the hardware profile: device id, screen
#   android.devices.<name>.ram       memory, in MB
#   android.devices.<name>.settings  <key> = { namespace; value; }, applied
#                                    with `adb shell settings put`
#   android.devices.<name>.apps      APKs pinned by sha256, installed on boot
#   android.twin                     the device the host runs (./_host.nix)
#
#   nix run .#android-twin           create the AVD if missing, boot headless,
#                                    wait for boot, apply settings, install
#                                    apps, print one status line, stay up
#   nix run .#android-twin-screen [path.png]
#                                    a screenshot of the running twin
#
# checks.android-twin has Lean prove (./_lean/Twin.lean) that a device's
# state is a function of (base, settings, apps), that changing a setting or
# adding an app never changes the base, and decide that every app's hash
# is 64 hex and every setting's namespace one of the three; and it reads
# the AVD config the module renders. No emulator runs in the sandbox.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.android;
  q = builtins.toJSON;

  # nixpkgs' pinned view of Google's SDK repository: the image archives and
  # their hashes (sha1, as Google publishes them).
  repo = lib.importJSON "${inputs.nixpkgs}/pkgs/development/mobile/androidenv/repo.json";
  namespaces = [
    "global"
    "system"
    "secure"
  ];
  imageTypes = [
    "google_apis"
    "default"
  ];
  # The SDK's device profiles nearest the owner's phone, newest first; the
  # wrapper uses the declared one when its avdmanager lists it, else the
  # declared screen alone (the config it writes is the declaration's).
  profiles = [
    "pixel_9a"
    "pixel_9"
    "pixel_8a"
    "pixel_8"
  ];
  grapheneosRefused =
    n:
    throw ''
      android.devices.${n}.base.kind = "grapheneos": no GrapheneOS emulator image is pinned yet.
      GrapheneOS publishes none for every release; the future build job `android-grapheneos-image`
      (GrapheneOS's sdk_phone64_x86_64 target, built from a pinned tag) will provide one.
      Declare kind = "aosp" until then.'';

  base = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "aosp"
          "grapheneos"
        ];
        default = "aosp";
        description = "aosp: the SDK's emulator image. grapheneos: refused until a build job provides an image.";
      };
      platform = mkOption {
        type = types.enum (lib.attrNames repo.images);
        default = "36";
        description = "The API level (Android 16 is 36).";
      };
      imageType = mkOption {
        type = types.enum imageTypes;
        default = "google_apis";
      };
      abi = mkOption {
        type = types.enum [ "x86_64" ];
        default = "x86_64";
      };
      image = mkOption {
        type = types.str;
        readOnly = true;
        description = "The SDK package id, as avdmanager takes it.";
      };
      sha1 = mkOption {
        type = types.strMatching "[0-9a-f]{40}";
        readOnly = true;
        description = "The image archive's hash, as the SDK repository states it: the base.";
      };
    };
  };

  device = types.submodule (
    { name, config, ... }:
    {
      config.base =
        let
          b = config.base;
          entry =
            repo.images.${b.platform}.${b.imageType}.${b.abi}
              or (throw "android.devices.${name}.base: nixpkgs' SDK repository has no ${b.imageType} ${b.abi} image for platform ${b.platform}");
          aosp = v: if b.kind == "grapheneos" then grapheneosRefused name else v;
        in
        {
          image = aosp "system-images;android-${b.platform};${b.imageType};${b.abi}";
          sha1 = aosp (lib.head entry.archives).sha1;
        };
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          readOnly = true;
        };
        base = mkOption {
          type = base;
          default = { };
        };
        profile = {
          device = mkOption {
            type = types.enum profiles;
            default = "pixel_9a";
            description = "The SDK hardware profile (avdmanager --device), when its list has it.";
          };
          width = mkOption {
            type = types.ints.positive;
            default = 1080;
          };
          height = mkOption {
            type = types.ints.positive;
            default = 2424;
          };
          density = mkOption {
            type = types.ints.positive;
            default = 420;
            description = "Pixels per inch, as Android's density buckets name it.";
          };
        };
        ram = mkOption {
          type = types.ints.positive;
          default = 2048;
          description = "MB. The phone has 8192; the host (../hetzner) shares 8 GB with the agents.";
        };
        settings = mkOption {
          type = types.attrsOf (
            types.submodule {
              options = {
                namespace = mkOption { type = types.enum namespaces; };
                value = mkOption { type = types.str; };
              };
            }
          );
          default = { };
          description = "Android settings, <key> = { namespace; value; }: `adb shell settings put <namespace> <key> <value>`.";
        };
        apps = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                name = mkOption { type = types.strMatching "[a-z][a-z0-9-]*"; };
                url = mkOption {
                  type = types.strMatching "https://.*\\.apk";
                  description = "The APK, fetched at build and pinned by sha256.";
                };
                sha256 = mkOption { type = types.strMatching "[0-9a-f]{64}"; };
                package = mkOption {
                  type = types.nullOr (types.strMatching "[A-Za-z0-9_.]+");
                  default = null;
                  description = "The application id, so an installed app is not reinstalled; null installs (replacing) every start.";
                };
              };
            }
          );
          default = [ ];
        };
      };
    }
  );

  # The AVD's config.ini: the declaration, whole; the wrapper writes it
  # over whatever avdmanager made.
  avdConfig =
    d:
    let
      kv = {
        AvdId = d.name;
        "avd.ini.displayname" = d.name;
        "avd.ini.encoding" = "UTF-8";
        "abi.type" = d.base.abi;
        "hw.cpu.arch" = d.base.abi;
        "hw.cpu.ncore" = "2";
        "image.sysdir.1" = "${lib.replaceStrings [ ";" ] [ "/" ] d.base.image}/";
        "tag.id" = d.base.imageType;
        "tag.display" = if d.base.imageType == "google_apis" then "Google APIs" else "Default";
        "hw.device.name" = d.profile.device;
        "hw.device.manufacturer" = "Google";
        "hw.lcd.width" = toString d.profile.width;
        "hw.lcd.height" = toString d.profile.height;
        "hw.lcd.density" = toString d.profile.density;
        "skin.name" = "${toString d.profile.width}x${toString d.profile.height}";
        "skin.path" = "_no_skin";
        "hw.ramSize" = toString d.ram;
        "vm.heapSize" = "512";
        "disk.dataPartition.size" = "6G";
        "hw.gpu.enabled" = "yes";
        "hw.gpu.mode" = "swiftshader_indirect";
        "hw.keyboard" = "yes";
        "hw.mainKeys" = "no";
        "hw.audioInput" = "no";
        "hw.audioOutput" = "no";
        "hw.camera.back" = "none";
        "hw.camera.front" = "none";
        "hw.sdCard" = "no";
        "hw.sensors.orientation" = "yes";
        "PlayStore.enabled" = "false";
        "fastboot.forceColdBoot" = "yes";
        "showDeviceFrame" = "no";
      };
    in
    lib.concatStrings (lib.mapAttrsToList (k: v: "${k} = ${v}\n") kv);

  rendered = ''
    namespace Kagamizo.Twin

    /-- Every declared device, rendered by modules/android/default.nix. -/
    def devices : List Device := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (n: d: ''
        { name := ${q n},
            base := { kind := ${q d.base.kind}, image := ${q d.base.image}, sha1 := ${q d.base.sha1} },
            settings := [
        ${lib.concatStringsSep ",\n" (
          lib.mapAttrsToList (
            k: s: "      { ns := ${q s.namespace}, key := ${q k}, value := ${q s.value} }"
          ) d.settings
        )}
            ],
            apps := [
        ${lib.concatMapStringsSep ",\n" (
          a: "      { name := ${q a.name}, sha256 := ${q a.sha256} }"
        ) d.apps}
            ] }'') cfg.devices
    )}
    ]

    /-- Every base is a hash. -/
    theorem bases_pinned : devices.all (fun d => d.base.pinned) = true := by decide +kernel

    /-- Every base is of a kind the model knows. -/
    theorem bases_known : devices.all (fun d => d.base.known) = true := by decide +kernel

    /-- Every app is pinned: 64 hex characters of sha256. -/
    theorem apps_pinned : devices.all Device.appsPinned = true := by decide +kernel

    /-- Every setting names one of the three namespaces. -/
    theorem settings_typed : devices.all Device.settingsTyped = true := by decide +kernel

    theorem each_app_pinned :
        ∀ d ∈ devices, ∀ a ∈ d.apps,
          a.sha256.toList.length = 64 ∧ a.sha256.toList.all isHex = true :=
      pinned_each devices apps_pinned

    theorem each_setting_typed :
        ∀ d ∈ devices, ∀ s ∈ d.settings, ∃ n : Namespace, Namespace.parse? s.ns = some n :=
      typed_each devices settings_typed

    end Kagamizo.Twin
  '';
in
{
  options.android = {
    devices = mkOption {
      type = types.attrsOf device;
      default = { };
    };
    twin = mkOption {
      type = types.enum (lib.attrNames cfg.devices);
      default = "pixel-9a";
      description = "The device packages.android-twin runs and the host serves.";
    };
    unfreeNames = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      description = "The SDK packages' names (unfree in nixpkgs), for a host's allowUnfreePredicate.";
    };
  };

  config = {
    android = {
      devices.pixel-9a = {
        # Animations off and the screen kept on: what every automation of
        # an Android device sets, so a screenshot is the state, not a frame
        # of a transition.
        settings = {
          window_animation_scale = {
            namespace = "global";
            value = "0";
          };
          transition_animation_scale = {
            namespace = "global";
            value = "0";
          };
          animator_duration_scale = {
            namespace = "global";
            value = "0";
          };
          stay_on_while_plugged_in = {
            namespace = "global";
            value = "7";
          };
          screen_off_timeout = {
            namespace = "system";
            value = "2147483647";
          };
        };
      };
      # Each SDK component is a package and its deployment ("android-sdk-"
      # before it), both unfree; the command-line tools are "androidsdk".
      unfreeNames =
        let
          b = cfg.devices.${cfg.twin}.base;
          parts = [
            "cmdline-tools"
            "tools"
            "emulator"
            "platform-tools"
            "platforms"
            "system-image-${b.platform}-${b.imageType}-${b.abi}"
          ];
        in
        parts ++ map (p: "android-sdk-${p}") parts;
    };

    perSystem =
      { pkgs, system, ... }:
      let
        d = cfg.devices.${cfg.twin};
        # The SDK is unfree and wants its licence accepted in nixpkgs'
        # config: a nixpkgs of its own, admitting the SDK's packages by name
        # and nothing else.
        apkgs = import inputs.nixpkgs {
          inherit system;
          config = {
            android_sdk.accept_license = true;
            allowUnfreePredicate = p: lib.elem (lib.getName p) cfg.unfreeNames;
          };
        };
        composed = apkgs.androidenv.composeAndroidPackages {
          platformVersions = [ d.base.platform ];
          systemImageTypes = [ d.base.imageType ];
          abiVersions = [ d.base.abi ];
          includeEmulator = true;
          includeSystemImages = true;
          buildToolsVersions = [ ];
          includeCmake = false;
        };
        sdk = "${composed.androidsdk}/libexec/android-sdk";
        # adb, avdmanager (wrapped with its JDK) and the emulator.
        bin = "${composed.androidsdk}/bin";
        config-ini = pkgs.writeText "${d.name}-config.ini" (avdConfig d);
        apk =
          a:
          pkgs.fetchurl {
            inherit (a) url sha256;
            name = "${a.name}.apk";
          };
        env = ''
          export ANDROID_HOME=${sdk} ANDROID_SDK_ROOT=${sdk}
          export ANDROID_USER_HOME="''${ANDROID_USER_HOME:-''${XDG_STATE_HOME:-$HOME/.local/state}/android-twin}"
          export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd" ANDROID_EMULATOR_HOME="$ANDROID_USER_HOME"
          port="''${ANDROID_TWIN_PORT:-5554}"
          serial="emulator-$port"
          adb() { ${bin}/adb "$@"; }
        '';
      in
      {
        packages = {
          android-twin = pkgs.writeShellApplication {
            name = "android-twin";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gnugrep
            ];
            text = ''
              ${env}
              avd="$ANDROID_AVD_HOME/${d.name}.avd"
              mkdir -p "$ANDROID_AVD_HOME"

              if [ ! -f "$avd/config.ini" ]; then
                device=()
                if ${bin}/avdmanager list device -c 2>/dev/null | grep -qx ${q d.profile.device}; then
                  device=(--device ${q d.profile.device})
                fi
                # "no" to a custom hardware profile; the declared config follows.
                echo no | ${bin}/avdmanager create avd --force \
                  --name ${q d.name} --package ${q d.base.image} --path "$avd" "''${device[@]}" >/dev/null
              fi
              # The declaration, whole, over whatever avdmanager wrote.
              cp ${config-ini} "$avd/config.ini"

              if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
                accel=(-accel on); how=kvm
              else
                accel=(-accel off); how=software
              fi

              # No snapshot: every boot starts from the base, then the declaration.
              ${bin}/emulator -avd ${q d.name} -port "$port" \
                -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect \
                -no-snapshot -no-metrics "''${accel[@]}" &
              emu=$!
              trap 'adb -s "$serial" emu kill >/dev/null 2>&1 || kill "$emu" 2>/dev/null || true' EXIT

              adb -s "$serial" wait-for-device
              until [ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
                kill -0 "$emu" 2>/dev/null || { echo "android-twin: ${d.name} died before boot" >&2; exit 1; }
                sleep 3
              done

              ${lib.concatStrings (
                lib.mapAttrsToList (
                  k: s: "adb -s \"$serial\" shell settings put ${s.namespace} ${q k} ${q s.value}\n"
                ) d.settings
              )}
              ${lib.concatMapStrings (
                a:
                if a.package != null then
                  ''
                    adb -s "$serial" shell pm list packages | tr -d '\r' | grep -qx "package:${a.package}" \
                      || adb -s "$serial" install -r ${apk a} >/dev/null
                  ''
                else
                  ''
                    adb -s "$serial" install -r ${apk a} >/dev/null
                  ''
              ) d.apps}
              echo "android-twin: ${d.name} up on $serial (${d.base.kind} ${d.base.image}, accel $how, ${toString (lib.length (lib.attrNames d.settings))} settings, ${toString (lib.length d.apps)} apps)"
              wait "$emu"
            '';
          };

          android-twin-screen = pkgs.writeShellApplication {
            name = "android-twin-screen";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              ${env}
              out="''${1:-android-twin-$(date -u +%Y%m%dT%H%M%SZ).png}"
              adb -s "$serial" exec-out screencap -p > "$out"
              echo "$out"
            '';
          };

          android-twin-config = config-ini;
        };

        checks.android-twin =
          pkgs.runCommand "android-twin"
            {
              nativeBuildInputs = [
                pkgs.lean4
                pkgs.gnugrep
              ];
              facts = rendered;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Twin.lean} "$factsPath" > Check.lean
              lean Check.lean

              # The AVD config the wrapper writes: every line a key, and the
              # declaration in it.
              ini=${config-ini}
              if grep -vE '^[A-Za-z0-9_.]+ = .+$' "$ini"; then
                echo "android-twin: a line of the AVD config is not 'key = value'" >&2; exit 1
              fi
              for want in 'hw.lcd.width = ${toString d.profile.width}' \
                          'hw.lcd.height = ${toString d.profile.height}' \
                          'hw.lcd.density = ${toString d.profile.density}' \
                          'hw.ramSize = ${toString d.ram}' \
                          'hw.device.name = ${d.profile.device}' \
                          'image.sysdir.1 = ${lib.replaceStrings [ ";" ] [ "/" ] d.base.image}/'; do
                grep -qxF "$want" "$ini"
              done
              touch $out
            '';
      };
  };
}
