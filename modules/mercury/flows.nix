# Mercury's browser flows (modules/browser): what its API cannot do, the
# login's email and inviting a company's own user, start from its web app.
# `survey` reads the sign-in page's controls by role and name, so the next
# flows are written against the page as it is, not guessed at. It types
# nothing and is the first step of moving a login, so it runs under the
# move-login effect: the one the login rule admits on a mismatched account.
let
  hosts = [
    "app.mercury.com"
    "mercury.com"
  ];
  email = {
    by = "role";
    role = "textbox";
    name = "Email";
  };
in
{
  browser.flows.mercury.survey = {
    effect = "move-login";
    description = "The sign-in page's controls, by role and name";
    inherit hosts;
    steps = [
      {
        do = "goto";
        url = "https://app.mercury.com/login";
      }
      {
        do = "wait-for";
        target = email;
        seconds = 30;
      }
      { do = "snapshot"; }
    ];
  };

  # Signs in with the login Proton Pass holds today (surveyed 2026-10-22:
  # Email, Password, "Log in"), then maps the signed-in pages by exploring;
  # the invite and passkey steps are written from what that shows.
  browser.flows.mercury.invite-own-user = {
    effect = "move-login";
    description = "Invite the account's own user at its declared address, and register its passkey";
    inherit hosts;
    steps = [
      {
        do = "goto";
        url = "https://app.mercury.com/login";
      }
      {
        do = "fill";
        target = email;
        # The declared address, which governance-authorize has just held
        # to the login item's; the item's username may be no address at all.
        value.from = "declared";
      }
      {
        do = "fill";
        target = {
          by = "role";
          role = "textbox";
          name = "Password";
        };
        value = {
          from = "pass";
          field = "password";
        };
      }
      {
        do = "click";
        target = {
          by = "role";
          role = "button";
          name = "Log in";
        };
      }
      {
        do = "explore";
        minutes = 30;
      }
    ];
  };
}
