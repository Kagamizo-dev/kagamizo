# The units of work delegated so far. Each spends its owner's key, so each
# is code the owner approves; Lean holds their caps to the owners' shares.
{
  unit.units = {
    # The no-markdown migration, a section at a time (project epic
    # markdown-migration): checkable by the project's own checks.
    handoff-open-questions = {
      owner = "pm";
      task = "draft";
      maxCents = 10;
      maxSteps = 16;
      paths = [ "modules/project/_data/decisions.json" ];
      accept = [
        "project-data"
        "project-lean"
      ];
      instruction = ''
        HANDOFF.md has a section "## Open questions for the owner". Turn
        each open question in it into one entry of
        modules/project/_data/decisions.json, alongside the entries already
        there: an id (lowercase words joined by dashes), "asked":
        "2026-11-04", "question" (one plain sentence), "options" (two to
        four lowercase-dashed choices the section names or implies),
        "answer": null and "decided": null. Change nothing else. Keep the
        file canonical: after editing, run
        `jq -S --indent 2 . f > t && mv t f` on it, and check with
        `jq -e . modules/project/_data/decisions.json`.
      '';
    };
  };
}
