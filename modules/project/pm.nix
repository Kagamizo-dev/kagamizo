# The project's coordinator: one agent, in the shape of the teams of
# ../agents/teams.nix, that keeps the epics, decisions and gaps current
# (`project status`, `project next`) and proposes only project data. It
# spends Kagamizo's swarm key, whose three swarms take 9 of its 10 dollars.
{
  governance.agents.pm = {
    serves = "kagamizo";
    purpose = "the project team: epics, decisions and gaps kept current, the next work ordered, every open epic owned";
    personas = [
      "project-management/project-management-project-shepherd"
      "project-management/project-manager-senior"
    ];
    tools = [
      "repo"
      "matrix"
    ];
    changeClasses = [ "content" ];
    budgetUsdPerMonth = 1;
    harness = "dsh";
  };

  organization.areas.kagamizo."dev+pm" = {
    owner = "pm";
    reviewers = [ "review" ];
    changeClasses = [ "content" ];
    purpose = "the project as typed data (modules/project): what is planned, decided, open and next";
  };
}
