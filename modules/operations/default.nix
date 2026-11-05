# The boundary between the owner and automation, typed and proven.
#
# The owner does only the human steps below; everything else is automation.
# Every secret the modules declare (secrets.profiles, ../_lib/secret.nix)
# says what it is, who issues it and which human steps its issuer waits on.
# ./_lean/Boundary.lean is the rule, with the theorems it guarantees for
# any secret; `checks.operations-boundary` renders every declared secret as
# Lean facts and has Lean prove each one well-formed. A step or kind named
# here that the Lean spec does not define fails to compile, so the two
# cannot drift apart.
#
#   nix build .#operations-boundary   the facts, as Lean
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  # kebab-case (Nix) to the Lean constructor (camelCase).
  camel =
    s:
    let
      parts = lib.splitString "-" s;
    in
    lib.head parts
    + lib.concatMapStrings (p: lib.toUpper (lib.substring 0 1 p) + lib.substring 1 (-1) p) (
      lib.tail parts
    );

  secrets = lib.concatLists (
    lib.mapAttrsToList (
      profile: vars:
      lib.mapAttrsToList (name: v: {
        name = "${profile}/${name}";
        boundary = v.boundary or null;
      }) (removeAttrs vars [ "defaults" ])
    ) config.secrets.profiles
  );
  unbounded = map (s: s.name) (lib.filter (s: s.boundary == null) secrets);

  issuerLean =
    issuer:
    let
      parts = lib.splitString ":" issuer;
      side = lib.head parts;
      what = lib.concatStringsSep ":" (lib.tail parts);
    in
    if side == "automation" then
      "(.automation ${builtins.toJSON what})"
    else if side == "human" then
      "(.human .${camel what})"
    else
      throw "operations: issuer ${issuer} is neither automation:<tool> nor human:<step>";

  items = lib.importJSON ../catalog/_json/pass-items.json;
  storeLean =
    name: store:
    if store.at == "note" then
      ".note"
    else
      let
        tpl =
          items.appTemplates.${store.template}
            or (throw "operations: ${name}: no Proton Pass template ${store.template} in pass-items.json");
        kind =
          tpl.fields.${store.field}
            or (throw "operations: ${name}: template ${store.template} has no field ${store.field}");
      in
      "(.field ${builtins.toJSON store.template} ${builtins.toJSON store.item} ${builtins.toJSON store.field} .${kind})";

  facts = ''
    open Kagamizo

    /-- Every secret the modules declare, rendered by ../default.nix. -/
    def declared : List Secret := [
    ${lib.concatMapStringsSep ",\n" (
      s:
      "  { name := ${builtins.toJSON s.name}, kind := .${camel s.boundary.kind}, issuer := ${issuerLean s.boundary.issuer}, needs := [${
          lib.concatMapStringsSep ", " (n: ".${camel n}") s.boundary.needs
        }], store := ${storeLean s.name s.boundary.store} }"
    ) secrets}
    ]

    /-- Every declared secret keeps the rule. -/
    theorem declared_wellFormed : declared.all wellFormed = true := by decide

    /-- Every account reached by token, rendered by ../default.nix. -/
    def credentialAccounts : List CredentialAccount := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: a:
        "  { name := ${builtins.toJSON n}, item := ${builtins.toJSON a.credential.item}, template := ${builtins.toJSON a.credential.template} }"
      ) (lib.filterAttrs (_: a: a.credential != null) config.accounts.held)
    )}
    ]

    /-- Every token account's token is declared, so it is the owner's and hidden. -/
    theorem credentials_backed : credentialAccounts.all (backed declared) = true := by decide

    /-- Every product an account has turned on by hand, with the step that did it. -/
    def enabledProducts : List (String × String × HumanStep) := [
    ${lib.concatStringsSep ",\n" (
      lib.concatLists (
        lib.mapAttrsToList (
          n: a:
          lib.mapAttrsToList (
            p: e: "  (${builtins.toJSON n}, ${builtins.toJSON p}, .${camel e.by})"
          ) a.products
        ) config.accounts.held
      )
    )}
    ]

    /-- A product is only ever turned on by the owner's enable-product step. -/
    theorem products_by_hand : enabledProducts.all (fun (_, _, s) => s == .enableProduct) = true := by decide
  '';
in
{
  options.operations = {
    humanSteps = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = "The only things the owner does by hand, and why each is theirs.";
    };
    secretKinds = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      description = "What a declared secret may be.";
    };
  };

  config = {
    operations = {
      humanSteps = {
        approve-sign-in = "a 2FA link, push or code, or a captcha: the provider asks a person";
        sign-up = "an account is opened by its holder, identity checks included (the owner's decision, 2026-10-24)";
        mint-card = "payment cards are issued by the owner (the owner's decision, 2026-10-24)";
        cancel-card = "payment cards are cancelled by the owner (the owner's decision, 2026-10-24)";
        console-credential = "a credential the provider issues only in its own console (a Gap, to be closed)";
        approve-payment = "the bank's own approval to move money, by design";
        sign-legal = "a signature or an SSN in a provider's portal";
        request-export = "asking a provider for its full data copy, where it offers one only in its own console (a Gap; by mail from the repo where accepted)";
        close-account = "closing an account at its provider, once Lean proves it emptied (modules/migration)";
        handle-device = "hands on hardware: flashing a phone, moving an eSIM, signing a phone out of iMessage";
        enroll-security-key = "registering or removing a hardware security key (a tap on the key): FIDO2, PIV or OATH on a YubiKey (modules/yubikey)";
        enable-product = "turning on a product its provider sells only in its own console, once per account (accounts.held.<a>.products; Cloudflare R2: its API answers 10042)";
      };
      secretKinds = [
        "api-token"
        "oauth-session"
        "encryption-key"
        "state"
        "passkey"
        "identifier"
      ];
    };

    perSystem =
      { pkgs, ... }:
      let
        rendered = pkgs.writeText "Facts.lean" (
          assert lib.assertMsg (unbounded == [ ]) (
            "operations: secrets without a boundary (kind, issuer): " + lib.concatStringsSep ", " unbounded
          );
          facts
        );
      in
      {
        packages.operations-boundary = rendered;
        checks.operations-boundary =
          pkgs.runCommand "operations-boundary"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
            }
            ''
              cat ${./_lean/Boundary.lean} ${rendered} > Check.lean
              lean Check.lean
              touch $out
            '';
      };
  };
}
