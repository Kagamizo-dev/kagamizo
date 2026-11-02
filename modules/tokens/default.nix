# The credential graph: every credential the repository mints, each derived
# from a parent credential, down to a root the owner approves. Nothing is
# declared twice: the graph is read off the declarations that mint things.
#
#   roots      the owner's sign-ins: Proton Pass (`pass-cli login`),
#              Cloudflare (`cloudflare-login`), and the sign-in behind every
#              declared OAuth session (iCloud, Mercury, ...)
#   proton     each agent token (proton.agents), scoped to its vault roles
#   cloudflare each account token (cloudflare.tokens), scoped to the OAuth
#              scopes covering its permission groups
#              (cloudflare.groupScopes), and the R2 S3 keys derived from one
#   github     each repository and environment secret, carrying an agent
#              token unchanged
#
# `_lean/Graph.lean` states the rule; `checks.tokens-graph` renders this
# graph and has Lean decide it: every parent declared and earlier, every
# child's scope within its parent's, roots by a human step, children by
# automation. `nix build .#tokens-graph` is the graph as JSON.
{ lib, config, ... }:
let
  cf = config.cloudflare;
  roles = [
    "viewer"
    "editor"
    "manager"
  ];
  # A Proton Pass grant at a role includes every role below it.
  upTo = r: lib.take (lib.lists.findFirstIndex (x: x == r) 0 roles + 1) roles;
  vaults = lib.unique (lib.attrValues config.proton.infraVaults ++ config.proton.vaults);

  node =
    id: parent: issuer: scope: extra:
    {
      inherit
        id
        parent
        issuer
        scope
        ;
    }
    // extra;

  proton = [
    (node "proton:sign-in" null "human" (lib.concatMap (
      v: map (r: "${v}:${r}") (roles ++ [ "home" ])
    ) vaults) { via = "pass-cli login (approve-sign-in)"; })
  ]
  ++ lib.mapAttrsToList (
    name: a:
    node "proton:agent:${name}" "proton:sign-in" "automation"
      ([ "${a.vault}:home" ] ++ lib.concatMap (g: map (r: "${g.vault}:${r}") (upTo g.role)) a.access)
      {
        via = "proton apply";
        inherit (a) secret;
      }
  ) config.proton.agents;

  groupScope =
    token: g:
    cf.groupScopes.${g}
      or (throw "tokens: cloudflare.tokens.${token} holds `${g}`, which cloudflare.groupScopes does not map to an OAuth scope");
  cloudflare = [
    (node "cloudflare:sign-in" null "human" cf.login.scopes {
      via = "cloudflare-login (approve-sign-in)";
    })
  ]
  ++ lib.concatLists (
    lib.mapAttrsToList (
      name: t:
      let
        scope = lib.unique (map (groupScope name) (t.zone ++ t.account));
        s3 = lib.any (p: config.secrets.profiles.${p} ? R2_SECRET_ACCESS_KEY) t.storeIn;
      in
      [
        (node "cloudflare:token:${name}" "cloudflare:sign-in" "automation" scope {
          via = "bootstrap apply";
        })
      ]
      ++ lib.optional s3 (
        node "cloudflare:r2-keys:${name}" "cloudflare:token:${name}" "automation"
          (lib.filter (lib.hasPrefix "workers-r2.") scope)
          { via = "bootstrap apply (the token's id and its value's SHA-256)"; }
      )
    ) cf.tokens
  );

  # A repository secret carries one agent token as it is.
  agentFor =
    var:
    lib.findFirst (
      n: (n.secret or null) == var
    ) (throw "tokens: a GitHub secret carries ${var}, which no Proton Pass agent declares") proton;
  github = lib.concatLists (
    lib.mapAttrsToList (
      repo: r:
      lib.mapAttrsToList (
        s: var:
        let
          a = agentFor var;
        in
        node "github:${repo}:${s}" a.id "automation" a.scope { via = "github-bootstrap"; }
      ) r.secrets
      ++ lib.concatLists (
        lib.mapAttrsToList (
          env: e:
          lib.mapAttrsToList (
            s: var:
            let
              a = agentFor var;
            in
            node "github:${repo}:${env}:${s}" a.id "automation" a.scope { via = "github-bootstrap"; }
          ) e.secrets
        ) r.environments
      )
    ) config.github.repos
  );

  # Every declared OAuth session is what a sign-in left behind.
  sessions = lib.concatLists (
    lib.mapAttrsToList (
      profile: vars:
      lib.concatLists (
        lib.mapAttrsToList (
          var: v:
          lib.optionals ((v.boundary.kind or null) == "oauth-session") [
            (node "sign-in:${profile}/${var}" null "human" [ "session" ] { via = "approve-sign-in"; })
            (node "session:${profile}/${var}" "sign-in:${profile}/${var}" "automation" [ "session" ] {
              via = v.boundary.issuer;
            })
          ]
        ) (removeAttrs vars [ "defaults" ])
      )
    ) config.secrets.profiles
  );

  graph = proton ++ cloudflare ++ github ++ sessions;

  lean = lib.concatStringsSep ",\n" (
    map (
      n:
      "  { id := ${builtins.toJSON n.id}, parent := ${
          if n.parent == null then "none" else "some ${builtins.toJSON n.parent}"
        }, issuer := .${n.issuer}, scope := [${lib.concatMapStringsSep ", " builtins.toJSON n.scope}] }"
    ) graph
  );
  facts = ''

    open Kagamizo.Tokens

    /-- Every credential the modules mint, rendered by ../default.nix. -/
    def declared : List Node := [
    ${lean}
    ]

    theorem declared_wellFormed : wellFormed declared = true := by decide
  '';
in
{
  options.tokens.graph = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    description = "The credential graph, roots first (see the header).";
  };

  config = {
    tokens.graph = graph;
    perSystem =
      { pkgs, ... }:
      {
        packages.tokens-graph = pkgs.writeText "tokens-graph.json" (builtins.toJSON graph);
        checks.tokens-graph = pkgs.runCommand "tokens-graph" { nativeBuildInputs = [ pkgs.lean4 ]; } ''
          cat ${./_lean/Graph.lean} ${pkgs.writeText "Facts.lean" facts} > Check.lean
          lean Check.lean
          touch $out
        '';
      };
  };
}
