# Forgejo (and Gitea) Actions: the same syntax as GitHub's, read from
# .forgejo/workflows. Not enabled: rendered and checked so that moving
# there is enabling it, with its runners labelled like GitHub's.
{ ciGithubRender, ... }:
{
  ci.hosts.forgejo = {
    enable = false;
    dir = ".forgejo/workflows";
    render = ciGithubRender;
  };
}
