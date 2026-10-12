# NixOS VM test for the niri desktop: boots a machine with the same desktop,
# tmux and tools modules as the Yoga image, lets greetd auto-login into niri,
# and checks, via niri and tmux themselves, that the terminal with the tmux
# session is up. (Screen OCR is not used: the VM's display does not show niri.)
{
  name = "niri-desktop";

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

    with subtest("niri started a terminal running the tmux session"):
        machine.wait_until_succeeds("pgrep -u user -x foot", timeout=120)
        machine.wait_until_succeeds("su - user -c 'tmux has-session -t main'", timeout=120)
        windows = machine.wait_until_succeeds(
            "su - user -c 'NIRI_SOCKET=$(ls /run/user/$(id -u)/niri*.sock | head -1) niri msg windows'",
            timeout=60,
        )
        assert "foot" in windows.lower(), f"no foot window in niri: {windows}"
        # Informational only: the VM's virtual display does not show niri's output.
        machine.screenshot("niri-desktop")
  '';
}
