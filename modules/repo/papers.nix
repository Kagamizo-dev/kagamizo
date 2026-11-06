# Every module's paper (the owner's rule, 2026-11-06): each module
# justifies its existence in a paper written as Lean, `_lean/Paper.lean`,
# the module's full account in place of a README: purpose, life cycle,
# pipeline, agents, tools, data, design, guarantees, performance, cited
# prior work and gaps (./_lean/PaperSchema.lean types them).
#
#   checks.paper-<module>   Lean: the paper is complete and cited, explains
#                           exactly the module's theorems and perf targets,
#                           and names only checks, packages and teams that
#                           exist (all rendered here from the repository)
#   checks.papers           Lean: the modules without a paper never exceed
#                           the baseline (./_json/paper-baseline.json), so
#                           the backlog only shrinks
#
# Writing one: add modules/<m>/_lean/Paper.lean with
#   open Kagamizo.Paper
#   def paper : Paper := { module := "<m>", ... }
# at the top level (no namespace, no imports: the schema is joined in
# front and the facts after), then lower the baseline by one.
{ lib, config, ... }:
let
  top = config;
  dir = ../.;
  modules = lib.attrNames (
    lib.filterAttrs (n: t: t == "directory" && !lib.hasPrefix "_" n) (builtins.readDir dir)
  );
  leanDir = m: dir + "/${m}/_lean";
  hasLean = m: builtins.pathExists (leanDir m);
  hasPaper = m: hasLean m && builtins.pathExists (leanDir m + "/Paper.lean");
  withPaper = lib.filter hasPaper modules;
  missing = lib.filter (m: !hasPaper m) modules;
  baseline = (lib.importJSON ./_json/paper-baseline.json).missing;

  # The theorems a module's Lean states, by name (the paper's own excluded).
  theoremsOf =
    m:
    if !hasLean m then
      [ ]
    else
      lib.concatMap
        (
          f:
          # A declaration starts a line: `theorem n`, optionally after an
          # attribute and `private` or `protected`; prose that says
          # "theorem" mid-line is not one.
          lib.concatMap (x: if lib.isList x then [ (lib.last x) ] else [ ]) (
            builtins.split
              "\n(@[^\n]*[[:space:]]|private[[:space:]]+|protected[[:space:]]+)?theorem[[:space:]]+([A-Za-z0-9_.']+)"
              ("\n" + builtins.readFile (leanDir m + "/${f}"))
          )
        )
        (
          lib.filter (f: lib.hasSuffix ".lean" f && f != "Paper.lean") (
            lib.attrNames (builtins.readDir (leanDir m))
          )
        );

  perfOf = m: lib.attrNames (lib.filterAttrs (_: t: t.module == m) top.perf.targets);
  teams = lib.attrNames top.agents.charters;

  q = builtins.toJSON;
  list = xs: "[${lib.concatMapStringsSep ", " q xs}]";
in
{
  perSystem =
    { config, ... }:
    let
      facts = m: ''

        namespace Kagamizo.Paper.Facts
        open Kagamizo.Paper
        def facts : Facts := {
          module := ${q m},
          teams := ${list teams},
          theorems := ${list (theoremsOf m)},
          perf := ${list (perfOf m)},
          checks := ${list (lib.attrNames config.checks)},
          packages := ${list (lib.attrNames config.packages)} }
        end Kagamizo.Paper.Facts

        -- Evaluated, not kernel-decided: the kernel's String.length over a
        -- paper's prose exhausts memory. A false result fails the build.
        #eval paper.problems Kagamizo.Paper.Facts.facts
        #guard paper.wellFormed Kagamizo.Paper.Facts.facts
      '';
      paperCheck =
        m:
        config.kagamizo.leanCheck {
          name = "paper-${m}";
          source = ./_lean/PaperSchema.lean;
          # The paper itself, then the facts and the theorem over both.
          facts = builtins.readFile (leanDir m + "/Paper.lean") + facts m;
        };
    in
    {
      checks = lib.listToAttrs (map (m: lib.nameValuePair "paper-${m}" (paperCheck m)) withPaper) // {
        papers = config.kagamizo.leanCheck {
          name = "papers";
          source = ./_lean/PaperSchema.lean;
          facts = ''

            open Kagamizo.Papers
            def missing : List String := ${list missing}
            theorem papers_within_baseline : withinBaseline missing ${toString baseline} = true := by decide
          '';
        };
      };
    };
}
