# Attenuable agent capabilities: each agent's authority is exactly its
# governance grants (../governance), and a delegated capability can be
# narrowed as it is passed down but never widened. This module renders the
# authority and serves mint / attenuate / check; Lean proves no attenuation
# escalates (./_lean/Delegation.lean).
#
#   nix run .#delegation -- mint <agent> [--json]        its full authority
#   nix run .#delegation -- attenuate <agent> <account>:<effect>...   a subset
#   nix run .#delegation -- check <agent> <account>:<effect>          allowed?
#
# The capability here is the *policy* — the (account, effect) pairs an agent
# may exercise. Carrying it as a cryptographic, offline-attenuable bearer
# token is biscuit-auth 6.0.0 (Eclipse, Rust, Datalog): its authority block
# is these facts, and `biscuit attenuate` narrows it with a public-key check
# that only narrows. That crate is pinned and wired where crates.io is
# reachable (CI/host); static.crates.io is blocked from cloud sessions, so
# this crate stays std-only and the biscuit encoding plugs in at mint/verify.
#
# checks.delegation-lean proves minting and attenuation stay within each
# agent's grant; checks.delegation-tests runs the crate's tests.
{ lib, config, ... }:
let
  q = builtins.toJSON;
  agents = config.governance.agents;

  # Each agent's authority: one (account, effect) per grant effect. Agent
  # grant effects are read/write only (the base Cedar layer forbids the rest).
  caps = lib.concatMap (
    name:
    let
      a = agents.${name};
    in
    lib.concatMap (
      g:
      map (e: {
        inherit name;
        inherit (g) account;
        effect = e;
      }) g.effects
    ) a.grants
  ) (lib.attrNames agents);

  rust = ''
    pub const CAPS: &[(&str, &str, &str)] = &[${
      lib.concatMapStringsSep ", " (c: "(${q c.name}, ${q c.account}, ${q c.effect})") caps
    }];
    pub const AGENTS: &[&str] = &[${lib.concatMapStringsSep ", " q (lib.attrNames agents)}];
  '';

  lean = ''
    namespace Kagamizo.Delegation

    -- Every (agent, account, effect) the grants render. The escalation and
    -- transitivity theorems above hold for any authority; this pins that
    -- every declared agent capability is read or write — agents never carry
    -- spend, destroy or sign-in, so no attenuation can ever reach them.
    def declared : List Cap := [
    ${lib.concatMapStringsSep ",\n" (
      c: "      { account := ${q c.account}, effect := ${q c.effect} }"
    ) caps}
    ]

    theorem declared_read_or_write :
        declared.all (fun c => c.effect == "read" || c.effect == "write") = true := by decide +kernel

    end Kagamizo.Delegation
  '';
in
{
  perSystem =
    { pkgs, ... }:
    let
      facts = pkgs.writeText "delegation-facts.rs" rust;
      bin = pkgs.rustPlatform.buildRustPackage {
        pname = "delegation";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        DELEGATION_FACTS = facts;
        meta.mainProgram = "delegation";
      };
    in
    {
      packages.delegation = bin;
      checks.delegation-lean =
        pkgs.runCommand "delegation-lean"
          {
            nativeBuildInputs = [ pkgs.lean4 ];
            facts = lean;
            passAsFile = [ "facts" ];
          }
          ''
            cat ${./_lean/Delegation.lean} "$factsPath" > Check.lean
            lean Check.lean
            touch $out
          '';
      checks.delegation-tests = bin.overrideAttrs (_: {
        doCheck = true;
      });
    };
}
