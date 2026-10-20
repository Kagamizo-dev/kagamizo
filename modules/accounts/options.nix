# Accounts and their plans, typed. Nothing the repo relies on about an
# account (how many custom domains it may have, whether it has Bridge, whether
# Pass access tokens exist on it) is assumed: each is a capability of the plan
# the account is declared on, with the page that states it and when it was
# read.
#
#   accounts.capabilities.<provider>  the provider's closed capability set
#   accounts.plans.<provider>.<plan>  what a plan includes
#   accounts.held.<name>              the accounts that exist or are planned,
#                                     each on one declared plan
#
# This module only types and checks them: each provider's module (proton,
# cloudflare, github, hetzner, openrouter, ...) declares its own.
#   accounts.checked                  the held accounts with their plans'
#                                     capabilities, after every demand the rest
#                                     of the repo makes is checked against them
#
# Each provider has its own closed capability set, so a plan can neither omit
# one nor invent one (checked below); a limit is a count or "unlimited".
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.accounts;

  # A capability: its value and the evidence for it.
  cap =
    valueType:
    types.submodule {
      options = {
        value = mkOption { type = valueType; };
        source = mkOption {
          type = types.strMatching "https://.+";
          description = "The page that states it.";
        };
      };
    };
  # A limit is a count or "unlimited"; a flag is true or false.
  Value = types.oneOf [
    types.ints.unsigned
    (types.enum [ "unlimited" ])
    types.bool
  ];
  fits = kind: v: if kind == "flag" then builtins.isBool v else builtins.isInt v || v == "unlimited";
  providers = lib.attrNames cfg.capabilities;

  plan = types.submodule {
    options = {
      checked = mkOption {
        type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
        description = "When the sources were last read.";
      };
      capabilities = mkOption { type = types.attrsOf (cap Value); };
    };
  };

  # Every plan states exactly its provider's capabilities, each of its kind.
  planProblems = lib.concatLists (
    lib.mapAttrsToList (
      provider: plans:
      let
        kinds = cfg.capabilities.${provider} or null;
      in
      if kinds == null then
        [ "accounts.plans.${provider}: no provider declares accounts.capabilities.${provider}" ]
      else
        lib.concatLists (
          lib.mapAttrsToList (
            name: p:
            let
              at = "accounts.plans.${provider}.${name}";
              have = lib.attrNames p.capabilities;
              want = lib.attrNames kinds;
            in
            map (c: "${at}: missing capability `${c}`") (lib.subtractLists have want)
            ++ map (c: "${at}: ${provider} has no capability `${c}`") (lib.subtractLists want have)
            ++ lib.concatMap (
              c:
              lib.optional (
                kinds ? ${c} && !(fits kinds.${c} p.capabilities.${c}.value)
              ) "${at}.capabilities.${c}: a ${kinds.${c}} cannot be ${builtins.toJSON p.capabilities.${c}.value}"
            ) have
          ) plans
        )
    ) cfg.plans
  );

  held = types.submodule (
    { config, ... }:
    {
      options = {
        provider = mkOption { type = types.enum providers; };
        plan = mkOption {
          type = types.enum (lib.attrNames cfg.plans.${config.provider});
          description = "One of the provider's declared plans.";
        };
        owner = mkOption {
          type = types.enum (lib.attrNames config'.identity.entities);
          description = "The entity the account belongs to.";
        };
        status = mkOption {
          type = types.enum [
            "active"
            "planned"
          ];
        };
        signup = mkOption {
          type = types.nullOr signup;
          default = null;
          description = "How the account is created, for `signup`.";
        };
      };
    }
  );

  # A web signup, prepared by `signup prepare` and done once by hand: the one
  # step most providers offer no API for.
  signup = types.submodule {
    options = {
      url = mkOption {
        type = types.strMatching "https://.+";
        description = "The page the signup starts on.";
      };
      handle = mkOption {
        type = types.strMatching "[A-Za-z0-9][A-Za-z0-9-]*";
        description = "The account or organization name to claim.";
      };
      email = mkOption {
        type = types.enum addresses;
        description = "A declared mailbox (identity.domains.*.mailboxes).";
      };
      credential = mkOption {
        type = types.enum [
          "password"
          "parent"
        ];
        description = ''
          password: a login of its own, with a generated password and its 2FA
          seed in the vault item. parent: created from another account's
          session (a GitHub organization under its owner's user account).
        '';
      };
      parent = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "For credential = parent: the account it is created from, by its login.";
      };
      findings = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              fact = mkOption { type = types.str; };
              source = mkOption { type = types.str; };
              checked = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
            };
          }
        );
        default = [ ];
        description = "What was learned about the provider before signing up, with where from.";
      };
    };
  };
  addresses = lib.concatLists (
    lib.mapAttrsToList (
      domain: d: map (m: "${m}@${domain}") d.mailboxes
    ) config.identity.checked.domains
  );
  config' = config;

  # Every demand the repo makes of an account: { account; capability; need; why; }.
  # `need` is a count (the limit must cover it) or true (the flag must be set).
  covers =
    limit: need:
    if builtins.isBool need then limit == true || !need else limit == "unlimited" || need <= limit;
  signupProblems = lib.concatLists (
    lib.mapAttrsToList (
      name: a:
      lib.optionals (a.signup != null) (
        lib.optional (
          (a.signup.credential == "parent") != (a.signup.parent != null)
        ) "accounts.held.${name}.signup: `parent` is set exactly when credential = \"parent\""
      )
    ) cfg.held
  );
  problems =
    planProblems
    ++ signupProblems
    ++ lib.concatMap (
      d:
      let
        a = cfg.held.${d.account} or null;
        c = if a == null then null else cfg.plans.${a.provider}.${a.plan}.capabilities.${d.capability};
      in
      if a == null then
        [ "${d.why}: no account `${d.account}` is declared" ]
      else if !(cfg.capabilities.${a.provider} ? ${d.capability}) then
        [
          "${d.why}: ${a.provider} plans have no capability `${d.capability}`; known: ${
            lib.concatStringsSep ", " (lib.attrNames cfg.capabilities.${a.provider})
          }"
        ]
      else if covers c.value d.need then
        [ ]
      else
        [
          "${d.why}: needs ${d.capability} = ${builtins.toJSON d.need}, but ${d.account} is on ${a.provider} ${a.plan} with ${builtins.toJSON c.value} (${c.source})"
        ]
    ) cfg.demands;
in
{
  options.accounts = {
    capabilities = mkOption {
      type = types.attrsOf (
        types.attrsOf (
          types.enum [
            "limit"
            "flag"
          ]
        )
      );
      default = { };
      description = "Per provider, its closed set of capabilities; declared by the provider's module.";
    };
    plans = mkOption {
      type = types.attrsOf (types.attrsOf plan);
      default = { };
      description = "Per provider, what each plan includes, as the provider states it.";
    };
    held = mkOption {
      type = types.attrsOf held;
      default = { };
    };
    demands = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            account = mkOption { type = types.str; };
            capability = mkOption { type = types.str; };
            need = mkOption { type = types.either types.ints.unsigned types.bool; };
            why = mkOption { type = types.str; };
          };
        }
      );
      default = [ ];
      description = "What the rest of the repo needs from each account; checked against its plan.";
    };
    checked = mkOption {
      type = types.raw;
      readOnly = true;
    };
  };

  config.accounts.checked =
    if problems == [ ] then
      lib.mapAttrs (
        _: a:
        a // { capabilities = lib.mapAttrs (_: c: c.value) cfg.plans.${a.provider}.${a.plan}.capabilities; }
      ) cfg.held
    else
      throw "accounts: the declared plans do not cover what the repo needs:\n${
        lib.concatMapStrings (p: "  - ${p}\n") problems
      }";
}
