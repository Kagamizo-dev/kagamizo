# NixOS VM test for the niri desktop: boots a machine with the same desktop,
# tmux and tools modules as the Yoga image, lets greetd auto-login into niri,
# and checks the tmux status bar shows up in the terminal that niri starts.
{
  name = "niri-desktop";
  enableOCR = true;

  nodes.machine = {
    imports = [
      ../modules/desktop-niri.nix
      ../modules/tmux.nix
      ../modules/tools.nix
    ];
    users.users.user.isNormalUser = true;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 2;
    # Software rendering inside the VM (no GPU).
    environment.sessionVariables.LIBGL_ALWAYS_SOFTWARE = "1";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("tools are installed"):
        machine.succeed("pass-cli --version")
        machine.succeed("firefox --version")
        machine.succeed("tmux -V")

    with subtest("greetd logs in and niri is running"):
        machine.wait_until_succeeds("pgrep -u user -x niri", timeout=180)

    with subtest("niri started a terminal with tmux"):
        machine.wait_until_succeeds("pgrep -u user -x foot", timeout=120)
        machine.wait_for_text("key finder|PREFIX|main", timeout=180)
        machine.screenshot("niri-desktop")
  '';
}
