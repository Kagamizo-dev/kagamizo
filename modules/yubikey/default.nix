# The hardware key as the primary second factor, SMS retired. Which key you
# hold, and for each account whether its second factor is FIDO2, OATH-TOTP
# or PIV on that key — or still legacy SMS, which is admitted only with a
# stated reason so it is never kept silently and shows up as work to do.
#
#   yubikey.keys.<name> = { serial; model; formFactor; }
#   yubikey.factors.<account> = { method; key; since; reason; }
#       method  fido2 (a security key for login), totp (OATH on the key,
#               replacing a phone authenticator), piv (smart-card / SSH /
#               age-plugin-yubikey), or sms (legacy, needs a reason)
#
#   nix run .#yubikey -- status [--json]   the 2FA map: account -> method/key
#   nix run .#yubikey -- legacy            the accounts still on SMS to move
#   nix run .#yubikey -- enroll <account>  the owner's steps (a tap on the key)
#
# Enrolling is `operations.humanSteps.enroll-security-key` (a tap, the
# owner's). checks.yubikey-lean (./_lean/Yubikey.lean) proves every
# key-based factor names a declared key and every SMS factor carries a
# reason. ykman drives the key itself on the owner's machine, not here.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.yubikey;
  q = builtins.toJSON;
  accounts = lib.attrNames config.accounts.held;
  keyNames = lib.attrNames cfg.keys;

  key = types.submodule {
    options = {
      serial = mkOption {
        type = types.strMatching "[0-9]+";
        description = "The key's serial (ykman list), the owner reads it off the key.";
      };
      model = mkOption {
        type = types.enum [
          "5c-nfc"
          "5ci"
          "5-nfc"
          "5c-nano"
          "5c"
        ];
        description = "A 5 Series key: FIDO2, PIV and OATH. (Security Key series is FIDO2 only.)";
      };
      formFactor = mkOption {
        type = types.enum [
          "usb-c"
          "usb-a"
          "lightning"
        ];
      };
    };
  };
  factor = types.submodule {
    options = {
      method = mkOption {
        type = types.enum [
          "fido2"
          "totp"
          "piv"
          "sms"
        ];
      };
      key = mkOption {
        type = types.str;
        default = if keyNames == [ ] then "" else lib.head keyNames;
        description = "The key this factor is on; empty for sms.";
      };
      since = mkOption {
        type = types.nullOr (types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}");
        default = null;
      };
      reason = mkOption {
        type = types.str;
        default = "";
        description = "Why this account is still on sms (required for sms).";
      };
    };
  };

  problems = lib.concatLists (
    lib.mapAttrsToList (
      account: f:
      lib.optional (
        f.method != "sms" && !(lib.elem f.key keyNames)
      ) "yubikey.factors.${account}: method ${f.method} names key ${f.key}, which is not declared"
      ++ lib.optional (
        f.method == "sms" && f.reason == ""
      ) "yubikey.factors.${account}: on sms with no reason; move it to a key or state why it must stay"
    ) cfg.factors
  );

  ctor = m: ".${m}";
  lean = ''
    namespace Kagamizo.Yubikey

    def keys : List String := ${q keyNames}

    def factors : List Factor := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        account: f:
        "  { account := ${q account}, method := ${ctor f.method}, key := ${q f.key}, reason := ${q f.reason} }"
      ) cfg.factors
    )}
    ]

    theorem declared_sound : sound keys factors = true := by decide +kernel

    end Kagamizo.Yubikey
  '';

  rust = ''
    pub const KEYS: &[(&str, &str, &str, &str)] = &[${
      lib.concatStringsSep ", " (
        lib.mapAttrsToList (n: k: "(${q n}, ${q k.serial}, ${q k.model}, ${q k.formFactor})") cfg.keys
      )
    }];
    pub const FACTORS: &[(&str, &str, &str, &str, &str)] = &[${
      lib.concatStringsSep ", " (
        lib.mapAttrsToList (
          a: f: "(${q a}, ${q f.method}, ${q f.key}, ${q (toString f.since)}, ${q f.reason})"
        ) cfg.factors
      )
    }];
    pub const ACCOUNTS: &[&str] = &[${lib.concatMapStringsSep ", " q accounts}];
  '';
in
{
  options.yubikey = {
    keys = mkOption {
      type = types.attrsOf key;
      default = { };
    };
    factors = mkOption {
      type = types.attrsOf factor;
      default = { };
    };
  };

  config = {
    # Declared as the owner enrols the key; empty until then. The types and
    # the proof are in place so a factor cannot be declared wrong.
    yubikey.factors = { };

    perSystem =
      { pkgs, ... }:
      let
        facts = pkgs.writeText "yubikey-facts.rs" rust;
        bin = pkgs.rustPlatform.buildRustPackage {
          pname = "yubikey";
          version = "0.1.0";
          src = ./_src;
          cargoLock.lockFile = ./_src/Cargo.lock;
          YUBIKEY_FACTS = facts;
          meta.mainProgram = "yubikey";
        };
      in
      {
        packages.yubikey = bin;
        checks.yubikey-lean =
          assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
          pkgs.runCommand "yubikey-lean"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = lean;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Yubikey.lean} "$factsPath" > Check.lean
              lean Check.lean
              touch $out
            '';
        checks.yubikey-tests = bin.overrideAttrs (_: {
          doCheck = true;
        });
      };
  };
}
