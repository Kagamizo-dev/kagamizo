# The repository's languages (the owner's rule, 2026-11-05): the code we
# author is Rust, Lean or Nix. No bash, no Python, no JavaScript, no inline
# code of any language inside a Nix string; pinned upstream software we wrap
# (Minecraft's server, NautilusTrader, TradingAgents, dsh) is not ours and is
# wrapped by the least Nix that runs it.
#
# Today's code breaks the rule in many places, so it holds as a ratchet:
# every existing violation is a dated exception owned by a team, and the
# exceptions may only shrink.
#
#   repo.languages.code         rust, lean, nix: the code we write
#   repo.languages.data         file formats that are data, not code
#   repo.languages.exceptions   path -> { language; markers; owner; until;
#                               replacedBy }, from ./_json/language-exceptions.json
#
#   checks.languages          lang-scan over the tree: every file is code,
#                             data or an exception, and no Nix file carries
#                             more inline code than its exception records
#   checks.languages-ratchet  Lean (./_lean/Languages.lean): every exception
#                             is owned by a declared team and dated, and the
#                             exceptions and their markers never exceed the
#                             baseline (./_json/language-baseline.json)
#   lang-scan install-hook    the same binary as .git/hooks/pre-commit: the
#                             tree check, then nixfmt on the staged Nix files
#
# Closing an exception: rewrite the file in Rust (or move its inline code
# into a crate), delete its entry, and lower the baseline by what it held.
{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.repo.languages;
  static = lib.importJSON ./_json/language-policy.json;
  teams = lib.attrNames config.governance.agents;
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";

  exception = types.submodule {
    options = {
      language = mkOption {
        type = types.enum [
          "nix-inline"
          "sh"
          "py"
          "js"
          "html"
          "css"
          "typ"
          "cedar"
          "go"
          "other"
        ];
        description = "What the file is, or nix-inline for code inside a Nix file.";
      };
      markers = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = "For nix-inline: the inline-code markers the file may hold at most.";
      };
      owner = mkOption {
        type = types.enum teams;
        description = "The team that owes the rewrite.";
      };
      until = mkOption {
        type = date;
        description = "When the exception lapses.";
      };
      replacedBy = mkOption {
        type = types.str;
        description = "What replaces it: a Rust crate, a Nix builder.";
      };
    };
  };

  # The policy lang-scan is built with.
  policy = {
    code = [
      "rs"
      "lean"
      "nix"
    ];
    inherit (cfg) data;
    inherit (static) names skip markers;
    exceptions = lib.mapAttrs (_: e: { inherit (e) markers; }) cfg.exceptions;
  };

  baseline = lib.importJSON ./_json/language-baseline.json;
  markerTotal = lib.foldl' (n: e: n + (if e.markers == null then 0 else e.markers)) 0 (
    lib.attrValues cfg.exceptions
  );

  q = builtins.toJSON;
  facts = ''

    namespace Kagamizo.Languages

    def teams : List String := [${lib.concatMapStringsSep ", " q teams}]

    def exceptions : List Exception := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        path: e:
        "  { path := ${q path}, owner := ${q e.owner}, dated := ${
            lib.boolToString (e.until != "")
          }, markers := ${toString (if e.markers == null then 0 else e.markers)} }"
      ) cfg.exceptions
    )}
    ]

    def baseline : Baseline := { exceptions := ${toString baseline.exceptions}, markers := ${toString baseline.markers} }

    theorem exceptions_owned_and_dated : sound teams exceptions = true := by decide +kernel

    theorem backlog_never_grows : withinBaseline baseline exceptions = true := by decide +kernel

    end Kagamizo.Languages
  '';
in
{
  options.repo.languages = {
    code = mkOption {
      type = types.listOf (
        types.enum [
          "rust"
          "lean"
          "nix"
        ]
      );
      default = [
        "rust"
        "lean"
        "nix"
      ];
      readOnly = true;
      description = "The languages we author code in.";
    };
    data = mkOption {
      type = types.listOf (types.strMatching "[a-z0-9]+");
      default = static.data;
      description = "File extensions that are data, not code.";
    };
    exceptions = mkOption {
      type = types.attrsOf exception;
      default = { };
      description = "Each file that breaks the rule today, dated and owned.";
    };
  };

  config = {
    repo.languages.exceptions = lib.importJSON ./_json/language-exceptions.json;

    perSystem =
      { pkgs, config, ... }:
      let
        policyFile = pkgs.writeText "language-policy.json" (builtins.toJSON policy);
        lang-scan = pkgs.rustPlatform.buildRustPackage {
          pname = "lang-scan";
          version = "0.1.0";
          src = ./_languages;
          cargoLock.lockFile = ./_languages/Cargo.lock;
          LANG_SCAN_POLICY = policyFile;
          LANG_SCAN_NIXFMT = lib.getExe pkgs.nixfmt;
          doCheck = true;
          meta.mainProgram = "lang-scan";
        };
      in
      {
        packages.lang-scan = lang-scan;

        checks.languages = derivation {
          name = "languages";
          inherit (pkgs.stdenv.hostPlatform) system;
          builder = lib.getExe lang-scan;
          args = [
            "check"
            self
          ];
        };

        checks.languages-ratchet =
          assert lib.assertMsg (lib.length (lib.attrNames cfg.exceptions) <= baseline.exceptions)
            "repo.languages: ${toString (lib.length (lib.attrNames cfg.exceptions))} exceptions, the baseline allows ${toString baseline.exceptions}";
          assert lib.assertMsg (markerTotal <= baseline.markers)
            "repo.languages: ${toString markerTotal} inline markers, the baseline allows ${toString baseline.markers}";
          config.kagamizo.leanCheck {
            name = "languages-ratchet";
            source = ./_lean/Languages.lean;
            inherit facts;
          };
      };
  };
}
