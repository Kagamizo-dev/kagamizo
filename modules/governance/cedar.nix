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
# Entities: every legal identity, people included; a person controls their
# own. Resources: Account, every held account, a child of its owner.
#
# The base policies come first and are the same for every declaration: a
# controller may do anything to their entity's accounts; an agent never
# spends, destroys or signs in, and never reaches an account outside the
# entity it serves. Grants are the only permits an agent ever gets.
#
# Proton Pass is the authority on logins: governance-authorize reads the
# account's login item (the address it signs in with, never the password)
# into the request's context, and nothing is allowed on an account whose
# login is missing, differs from the declared one, or is not on its owner's
# domain. An agent's token opens no login items, so it is denied until an
# audit it can read exists (a Gap).
{ lib, config, ... }:
let
  cfg = config.governance;
  inherit (config.identity.checked) entities;
  ns = "Kagamizo";
  people = lib.filterAttrs (_: e: e.kind == "person") entities;
  accounts = config.accounts.held;
  # A person is a legal identity like any company, and controls their own.
  controllers = n: lib.unique (lib.optional (people ? ${n}) n ++ cfg.controllers.${n} or [ ]);
  domainsOf =
    e: lib.attrNames (lib.filterAttrs (_: d: d.entity == e) config.identity.checked.domains);
  domainOf = email: lib.last (lib.splitString "@" email);
  # What governance-authorize reads from Proton Pass for each account.
  logins = lib.mapAttrs (_: a: {
    vault = entities.${a.owner}.vault;
    inherit (a.login) item email;
  }) accounts;
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

  # A tool named after an effect would share its id with the provider's
  # group for that effect, and Cedar would read it as its own group.
  clashes = lib.filter (a: lib.elem a.tool cfg.effects) actionList;
  schema =
    assert lib.assertMsg (clashes == [ ]) (
      "modules/governance: actions named after an effect: "
      + lib.concatMapStringsSep ", " (a: a.id) clashes
    );
    ''
      namespace ${ns} {
        entity Person;
        entity Entity { kind: String, controllers: Set<Person>, domains: Set<String> };
        entity Account in [Entity] { owner: Entity, provider: String, login: String, loginDomain: String };
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
            appliesTo { principal: [Person, Agent], resource: [Account], context: { login?: String } };
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

    @id("logins-say-whose-they-are")
    forbid (principal, action, resource is ${ns}::Account)
    unless {
      resource.owner.domains.contains(resource.loginDomain) &&
      (
        (context has login && context.login == resource.login) ||
        (principal is ${ns}::Person && action in ${act "move-login"})
      )
    };

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
        controllers = map (uid "Person") (controllers n);
        domains = domainsOf n;
      };
      parents = [ ];
    }) entities
    ++ lib.mapAttrsToList (n: a: {
      uid = (uid "Account" n).__entity;
      attrs = {
        owner = uid "Entity" a.owner;
        inherit (a) provider;
        login = a.login.email;
        loginDomain = domainOf a.login.email;
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
  test = testAs (account: {
    login = accounts.${account}.login.email;
  });
  testAs = context: name: principal: action: account: decision: reason: {
    inherit name decision reason;
    num_errors = 0;
    request = {
      inherit principal;
      action = "${ns}::Action::${str action}";
      resource = ref "Account" account;
      context = context account;
    };
    entities = entityJson;
  };
  neverEffects = [
    "spend"
    "destroy"
    "session"
    "move-login"
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
        ) (controllers a.owner)
      ) withActions
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: _:
        lib.concatLists (
          lib.mapAttrsToList (
            acc: a:
            map (
              e:
              let
                x = firstOf a.provider e;
              in
              if x == null then null else agentTest name acc e x.id
            ) cfg.effects
          ) withActions
        )
      ) cfg.agents
    )
  );
  # What an agent gets for one action on one account: another entity's
  # account and the never-effects deny, a grant allows, the rest denies.
  agentTest =
    name: acc: e: id:
    let
      agent = cfg.agents.${name};
      a = accounts.${acc};
      me = ref "Agent" name;
      granted = lib.any (g: g.account == acc && lib.elem e g.effects) agent.grants;
      never = lib.optional (lib.elem e neverEffects) "agents-never-spend-destroy-or-sign-in";
      what = if id == (firstOf a.provider e).id then e else id;
    in
    if a.owner != agent.serves then
      test "${name} may not ${what} ${acc}, ${a.owner}'s" me id acc "deny" (
        [ "agents-serve-one-entity" ] ++ never
      )
    else if never != [ ] then
      test "${name} may never ${what} on ${acc}" me id acc "deny" never
    else
      test "${name} ${if granted then "may" else "may not"} ${what} ${acc}" me id acc (
        if granted then "allow" else "deny"
      ) (lib.optional granted "grant:${name}:${acc}");
  # Every action of every provider, on every account of that provider: its
  # controllers may run it, and each agent gets what its effect and grants
  # say. Browser flows are tested below, with their move-login case.
  flowIds = lib.concatLists (
    lib.mapAttrsToList (p: fs: map (f: toolId p f) (lib.attrNames fs)) config.browser.flows
  );
  actionTests = lib.concatMap (
    x:
    lib.optionals (!(lib.elem x.id flowIds)) (
      lib.concatLists (
        lib.mapAttrsToList (
          acc: a:
          map (
            person:
            test "${person} may run ${x.id} on ${acc}" (ref "Person" person) x.id acc "allow" [ "controllers" ]
          ) (controllers a.owner)
          ++ lib.mapAttrsToList (name: _: agentTest name acc x.effect x.id) cfg.agents
        ) (lib.filterAttrs (_: a: a.provider == x.provider) accounts)
      )
    )
  ) actionList;
  # Every browser flow, on every account of its provider: each controller
  # may run it, a move-login flow even while the login is still another
  # address, and each agent gets what its effect and grants say.
  flowTests = lib.concatLists (
    lib.mapAttrsToList (
      provider: flows:
      lib.concatLists (
        lib.mapAttrsToList (
          flow: f:
          let
            id = toolId provider flow;
          in
          lib.concatLists (
            lib.mapAttrsToList (
              acc: a:
              lib.concatMap (
                person:
                [
                  (test "${person} may run ${id} on ${acc}" (ref "Person" person) id acc "allow" [ "controllers" ])
                ]
                ++ lib.optional (f.effect == "move-login") (
                  testAs (_: { login = "someone@example.com"; })
                    "${person} may run ${id} on ${acc} while its login is another address"
                    (ref "Person" person)
                    id
                    acc
                    "allow"
                    [ "controllers" ]
                )
              ) (controllers a.owner)
              ++ lib.mapAttrsToList (name: _: agentTest name acc f.effect id) cfg.agents
            ) (lib.filterAttrs (_: a: a.provider == provider) accounts)
          )
        ) flows
      )
    ) config.browser.flows
  );
  # A login Proton Pass does not confirm denies even the controller.
  loginTests = lib.concatLists (
    lib.mapAttrsToList (
      acc: a:
      let
        x = lib.findFirst (x: x.provider == a.provider) null actionList;
        person = lib.head (controllers a.owner);
        deny =
          context: why:
          testAs (_: context) "${person} may not act on ${acc} ${why}" (ref "Person" person) x.id acc "deny" [
            "logins-say-whose-they-are"
          ];
        fix = firstOf a.provider "move-login";
      in
      lib.optionals (x != null) [
        (deny { } "when Proton Pass has no login for it")
        (deny { login = "someone@example.com"; } "when its login in Proton Pass is another address")
      ]
      # Moving the login onto the declared address is the one way out.
      ++ lib.optional (fix != null) (
        testAs (_: { login = "someone@example.com"; })
          "${person} may move ${acc}'s login from another address"
          (ref "Person" person)
          fix.id
          acc
          "allow"
          [ "controllers" ]
      )
    ) withActions
  );
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      loginsJson = pkgs.writeText "logins.json" (builtins.toJSON logins);
      policy = pkgs.runCommand "governance-policy" { } ''
        mkdir $out
        cp ${pkgs.writeText "schema.cedarschema" schema} $out/schema.cedarschema
        cat ${pkgs.writeText "base.cedar" base} ${pkgs.writeText "grants.cedar" grants} > $out/policies.cedar
        cp ${pkgs.writeText "entities.json" (builtins.toJSON entityJson)} $out/entities.json
        cp ${
          pkgs.writeText "tests.json" (builtins.toJSON (tests ++ loginTests ++ flowTests ++ actionTests))
        } $out/tests.json
      '';
    in
    {
      packages.governance-policy = policy;

      packages.governance-authorize = pkgs.writeShellApplication {
        name = "governance-authorize";
        runtimeInputs = [
          pkgs.cedar
          pkgs.jq
          pkgs.coreutils
          config.packages.pass-login
        ];
        text = ''
          action=''${1:?usage: governance-authorize ACTION ACCOUNT}
          account=''${2:?usage: governance-authorize ACTION ACCOUNT}
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}

          # The account's login as Proton Pass has it: its addresses only
          # (username, when it is one, and email), never the password.
          vault=$(jq -r --arg a "$account" '.[$a].vault // empty' ${loginsJson})
          item=$(jq -r --arg a "$account" '.[$a].item // empty' ${loginsJson})
          declared=$(jq -r --arg a "$account" '.[$a].email // empty' ${loginsJson})
          seen=
          [ -z "$vault" ] || seen=$(pass-login "$vault" "$item")
          context=$(mktemp)
          trap 'rm -f "$context"' EXIT
          if [ -n "$seen" ] && [ "$(wc -l <<<"$seen")" = 1 ]; then
            jq -n --arg l "$seen" '{login: $l}' >"$context"
          else
            echo '{}' >"$context"
          fi
          who=''${KAGAMIZO_PRINCIPAL:-person:${root}}
          case "$who" in
            agent:*) principal="${ns}::Agent::\"''${who#agent:}\"" ;;
            person:*) principal="${ns}::Person::\"''${who#person:}\"" ;;
            *) echo "governance: KAGAMIZO_PRINCIPAL is agent:<name> or person:<name>" >&2; exit 2 ;;
          esac
          if cedar authorize --schema ${policy}/schema.cedarschema --policies ${policy}/policies.cedar \
            --entities ${policy}/entities.json --principal "$principal" \
            --action "${ns}::Action::\"$action\"" --resource "${ns}::Account::\"$account\"" \
            --context "$context" >/dev/null; then
            exit 0
          fi
          echo "governance: $who may not $action on $account (modules/governance)" >&2
          if [ "$seen" != "$declared" ]; then
            echo "governance: its login in Proton Pass ($vault / $item) is ''${seen:-missing or unreadable}, not $declared" | tr '\n' ' ' >&2
            echo >&2
          fi
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
