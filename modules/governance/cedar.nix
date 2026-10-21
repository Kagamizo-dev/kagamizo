# The governance declarations (./options.nix) compiled to Cedar: a schema, the
# entities, the policies and tests that pin what they decide. Every wrapper
# that reaches an account asks `governance-authorize` before it acts.
#
#   nix build .#governance-policy   schema.cedarschema, policies.cedar,
#                                   entities.json, tests.json
#   governance-authorize ACTION ACCOUNT
#       allow or deny for the caller, KAGAMIZO_PRINCIPAL (`agent:<name>` as
#       set by `orca-swarm`, or `person:<name>`; unset, the root person)
#
# Principals: Person (identity entities of kind person), Agent (one per
# governance.agents entry, the identity its Proton Pass token carries).
# Resources: Account, every held account owned by an LLC or nonprofit, a
# child of that Entity. Accounts a person holds are outside this model:
# no agent can be granted them, and their wrappers do not ask.
#
# The base policies come first and are the same for every declaration: a
# controller may do anything to their entity's accounts; an agent never
# spends, destroys or signs in, and never reaches an account outside the
# entity it serves. Grants are the only permits an agent ever gets.
{ lib, config, ... }:
let
  cfg = config.governance;
  inherit (config.identity.checked) entities;
  ns = "Kagamizo";
  orgs = lib.filterAttrs (_: e: e.kind != "person") entities;
  people = lib.filterAttrs (_: e: e.kind == "person") entities;
  accounts = lib.filterAttrs (_: a: orgs ? ${a.owner}) config.accounts.held;
  root = lib.head (
    lib.attrNames (lib.filterAttrs (_: e: e.vault == config.proton.infraVaults.root) people)
  );

  str = builtins.toJSON;
  uid = type: id: {
    __entity = {
      type = "${ns}::${type}";
      inherit id;
    };
  };
  ref = type: id: "${ns}::${type}::${str id}";
  act = id: "${ns}::Action::${str id}";
  toolId = provider: tool: "${provider}:${tool}";

  # Every action, by provider and by effect.
  actionList = lib.concatLists (
    lib.mapAttrsToList (
      provider: tools:
      lib.mapAttrsToList (tool: a: {
        inherit provider tool;
        inherit (a) effect;
        id = toolId provider tool;
      }) tools
    ) cfg.actions
  );
  providers = lib.attrNames cfg.actions;
  firstOf =
    provider: effect: lib.findFirst (a: a.provider == provider && a.effect == effect) null actionList;

  schema = ''
    namespace ${ns} {
      entity Person;
      entity Entity { kind: String, controllers: Set<Person> };
      entity Account in [Entity] { owner: Entity, provider: String };
      entity Agent { serves: Entity, purpose: String };

      action ${lib.concatMapStringsSep ", " str cfg.effects};
    ${lib.concatMapStrings (
      p:
      lib.concatMapStrings (e: ''
        action ${str "${p}:${e}"} in [${str e}];
      '') cfg.effects
    ) providers}
    ${
      lib.concatMapStrings (a: ''
        action ${str a.id} in [${str "${a.provider}:${a.effect}"}]
          appliesTo { principal: [Person, Agent], resource: [Account] };
      '') actionList
    }}
  '';

  base = ''
    @id("controllers")
    permit (principal is ${ns}::Person, action, resource is ${ns}::Account)
    when { resource.owner.controllers.contains(principal) };

    @id("agents-never-spend-destroy-or-sign-in")
    forbid (
      principal is ${ns}::Agent,
      action in [${lib.concatMapStringsSep ", " act neverEffects}],
      resource
    );

    @id("agents-serve-one-entity")
    forbid (principal is ${ns}::Agent, action, resource is ${ns}::Account)
    unless { resource.owner == principal.serves };
  '';

  grants = lib.concatStrings (
    lib.mapAttrsToList (
      name: a:
      lib.concatMapStrings (
        g:
        let
          provider = config.accounts.held.${g.account}.provider;
        in
        ''

          // ${g.why}
          @id(${str "grant:${name}:${g.account}"})
          permit (
            principal == ${ref "Agent" name},
            action in [${lib.concatMapStringsSep ", " (e: act "${provider}:${e}") g.effects}],
            resource == ${ref "Account" g.account}
          );
        ''
      ) a.grants
    ) cfg.agents
  );

  entityJson =
    lib.mapAttrsToList (n: _: {
      uid = (uid "Person" n).__entity;
      attrs = { };
      parents = [ ];
    }) people
    ++ lib.mapAttrsToList (n: e: {
      uid = (uid "Entity" n).__entity;
      attrs = {
        inherit (e) kind;
        controllers = map (uid "Person") (cfg.controllers.${n} or [ ]);
      };
      parents = [ ];
    }) orgs
    ++ lib.mapAttrsToList (n: a: {
      uid = (uid "Account" n).__entity;
      attrs = {
        owner = uid "Entity" a.owner;
        inherit (a) provider;
      };
      parents = [ (uid "Entity" a.owner).__entity ];
    }) accounts
    ++ lib.mapAttrsToList (n: a: {
      uid = (uid "Agent" n).__entity;
      attrs = {
        serves = uid "Entity" a.serves;
        inherit (a) purpose;
      };
      parents = [ ];
    }) cfg.agents;

  # What the policies must decide, derived from the declarations: every
  # grant allows, and every base rule denies, for one action of each kind.
  # `reason` is the policies that decide it: a test fails if the right
  # answer comes from the wrong rule.
  test = name: principal: action: account: decision: reason: {
    inherit name decision reason;
    num_errors = 0;
    request = {
      inherit principal;
      action = "${ns}::Action::${str action}";
      resource = ref "Account" account;
      context = { };
    };
    entities = entityJson;
  };
  neverEffects = [
    "spend"
    "destroy"
    "session"
  ];
  withActions = lib.filterAttrs (_: a: cfg.actions ? ${a.provider}) accounts;
  tests = lib.filter (t: t != null) (
    lib.concatLists (
      lib.mapAttrsToList (
        acc: a:
        map (
          person:
          let
            x = lib.findFirst (x: x.provider == a.provider) null actionList;
          in
          if x == null then
            null
          else
            test "${person} controls ${acc}" (ref "Person" person) x.id acc "allow" [ "controllers" ]
        ) (cfg.controllers.${a.owner} or [ ])
      ) withActions
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: agent:
        let
          me = ref "Agent" name;
          granted = acc: e: lib.any (g: g.account == acc && lib.elem e g.effects) agent.grants;
          never = e: lib.optional (lib.elem e neverEffects) "agents-never-spend-destroy-or-sign-in";
        in
        lib.concatLists (
          lib.mapAttrsToList (
            acc: a:
            map (
              e:
              let
                x = firstOf a.provider e;
              in
              if x == null then
                null
              else if a.owner != agent.serves then
                test "${name} may not ${e} ${acc}, ${a.owner}'s" me x.id acc "deny" (
                  [ "agents-serve-one-entity" ] ++ never e
                )
              else if never e != [ ] then
                test "${name} may never ${e} on ${acc}" me x.id acc "deny" (never e)
              else
                test "${name} ${if granted acc e then "may" else "may not"} ${e} ${acc}" me x.id acc (
                  if granted acc e then "allow" else "deny"
                ) (lib.optional (granted acc e) "grant:${name}:${acc}")
            ) cfg.effects
          ) withActions
        )
      ) cfg.agents
    )
  );
in
{
  perSystem =
    { pkgs, ... }:
    let
      policy = pkgs.runCommand "governance-policy" { } ''
        mkdir $out
        cp ${pkgs.writeText "schema.cedarschema" schema} $out/schema.cedarschema
        cat ${pkgs.writeText "base.cedar" base} ${pkgs.writeText "grants.cedar" grants} > $out/policies.cedar
        cp ${pkgs.writeText "entities.json" (builtins.toJSON entityJson)} $out/entities.json
        cp ${pkgs.writeText "tests.json" (builtins.toJSON tests)} $out/tests.json
      '';
    in
    {
      packages.governance-policy = policy;

      packages.governance-authorize = pkgs.writeShellApplication {
        name = "governance-authorize";
        runtimeInputs = [ pkgs.cedar ];
        text = ''
          action=''${1:?usage: governance-authorize ACTION ACCOUNT}
          account=''${2:?usage: governance-authorize ACTION ACCOUNT}
          who=''${KAGAMIZO_PRINCIPAL:-person:${root}}
          case "$who" in
            agent:*) principal="${ns}::Agent::\"''${who#agent:}\"" ;;
            person:*) principal="${ns}::Person::\"''${who#person:}\"" ;;
            *) echo "governance: KAGAMIZO_PRINCIPAL is agent:<name> or person:<name>" >&2; exit 2 ;;
          esac
          if cedar authorize --schema ${policy}/schema.cedarschema --policies ${policy}/policies.cedar \
            --entities ${policy}/entities.json --principal "$principal" \
            --action "${ns}::Action::\"$action\"" --resource "${ns}::Account::\"$account\"" >/dev/null; then
            exit 0
          fi
          echo "governance: $who may not $action on $account (modules/governance)" >&2
          exit 1
        '';
      };

      checks.governance-cedar =
        assert lib.assertMsg (cfg.problems == [ ]) (lib.concatStringsSep "\n" cfg.problems);
        pkgs.runCommand "governance-cedar" { nativeBuildInputs = [ pkgs.cedar ]; } ''
          cedar validate --schema ${policy}/schema.cedarschema --policies ${policy}/policies.cedar
          cedar check-parse --schema ${policy}/schema.cedarschema --entities ${policy}/entities.json
          cedar run-tests --schema ${policy}/schema.cedarschema --policies ${policy}/policies.cedar \
            --tests ${policy}/tests.json
          touch $out
        '';
    };
}
