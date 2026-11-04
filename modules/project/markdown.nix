# The markdown files still allowed (the owner's rule, 2026-11-04: no more
# markdown). Only ever shrinks: a file leaves this list when its content is
# a typed module (project.epics.markdown-migration); a new markdown file
# fails checks.no-markdown. CLAUDE.md stays, rendered from typed policy once
# migrated, because Claude Code reads that file.
{ lib, ... }:
{
  options.project.markdown = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.enum [
        "tool"
        "hand-written"
        "generated"
      ]
    );
    description = "Path from the repository root, and why it is still markdown.";
  };

  config.project.markdown = {
    "CLAUDE.md" = "tool"; # read by Claude Code itself
    "HANDOFF.md" = "hand-written";
    "README.md" = "hand-written";
    "modules/cloudflare/README.md" = "hand-written";
    "modules/catalog/README.md" = "generated"; # nix run .#catalog-readme
    "modules/perf/README.md" = "generated"; # nix run .#perf-readme
  };
}
