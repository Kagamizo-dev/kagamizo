# Mercury's browser flows (modules/browser): what its API cannot do, the
# login's email and inviting a company's own user, start from its web app.
# `survey` reads the sign-in page's controls by role and name, so the next
# flows are written against the page as it is, not guessed at.
{
  browser.flows.mercury.survey = {
    effect = "read";
    description = "The sign-in page's controls, by role and name";
    hosts = [
      "app.mercury.com"
      "mercury.com"
    ];
    steps = [
      {
        do = "goto";
        url = "https://app.mercury.com/login";
      }
      {
        do = "wait-for";
        target = {
          by = "role";
          role = "textbox";
          name = "Email";
        };
        seconds = 30;
      }
      { do = "snapshot"; }
    ];
  };
}
