# NixOS VM test for the niri desktop: boots a machine with the same desktop,
# tmux and tools modules as the Yoga image, lets greetd auto-login into niri,
# and checks niri is running and spawned its autostart apps. This VM has no GPU
# and niri refuses software rendering, so no windows are drawn here.
{
  name = "niri-desktop";

  nodes.machine = {
    imports = [
      ../profiles/desktop-niri.nix
      ../profiles/tmux.nix
      ../profiles/tools.nix
      ../profiles/welcome.nix
      ../profiles/setup.nix
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
        machine.succeed("command -v setup")

    with subtest("greetd logs in and niri is running"):
        machine.wait_until_succeeds("pgrep -u user -x niri", timeout=180)

    with subtest("niri is alive and started the autostart apps"):
        # niri's IPC answers, and it spawned the terminal from /etc/niri/config.kdl.
        out = machine.wait_until_succeeds(
            "su - user -c 'NIRI_SOCKET=$(ls /run/user/$(id -u)/niri*.sock | head -1) niri msg version'",
            timeout=120,
        )
        assert "Compositor version" in out, f"unexpected niri msg output: {out}"
        machine.wait_until_succeeds("pgrep -u user -x foot", timeout=120)
        # Window mapping and the tmux session inside it cannot be checked here:
        # niri refuses software rendering ("software EGL renderers are skipped"),
        # and this VM has no GPU. Real-GPU behaviour is covered on hardware; the
        # tmux config itself by tests/tmux.nix; boot by scripts/boot-iso.sh.
        machine.screenshot("niri-desktop")

    # Run last: any `su - user` before the desktop session is up races with greetd
    # (the user runtime directory gets torn down and the terminal never starts).
    with subtest("welcome screen runs and shows the keys"):
        shown = machine.succeed("su - user -c welcome")
        assert "System check" in shown, shown
        assert "Quick keys" in shown, shown
        assert "Mod+D" in shown, shown
        machine.succeed("su - user -c 'pi --version'")
  '';
}
