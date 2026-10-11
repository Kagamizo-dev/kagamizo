# NixOS VM test: boots a machine with modules/tmux.nix, then
#  1. checks the generated config (prefix, documented bindings), and
#  2. attaches a real tmux client on the console, presses the prefix + ?,
#     and reads the fuzzy key finder off the screen with OCR.
{
  name = "tmux-config";
  enableOCR = true;

  nodes.machine = {
    imports = [ ../modules/tmux.nix ];
    users.users.alice.isNormalUser = true;
    services.getty.autologinUser = "alice";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("config is loaded with a Ctrl-a prefix and documented keys"):
        machine.succeed("su - alice -c 'tmux new-session -d -s probe'")
        assert "C-a" in machine.succeed("su - alice -c 'tmux show -g prefix'")
        keys = machine.succeed("su - alice -c 'tmux list-keys -N -T prefix'")
        for wanted in [
            "Search all key bindings",
            "Quick menu",
            "Split side-by-side",
            "Reload tmux config",
        ]:
            assert wanted in keys, f"missing binding: {wanted}"
        machine.succeed("su - alice -c 'tmux kill-server'")

    with subtest("prefix + ? opens the fuzzy key finder"):
        machine.wait_until_tty_matches("1", "alice@machine")
        machine.send_chars("tmux\n")
        machine.sleep(3)
        machine.send_key("ctrl-a")
        machine.send_chars("?")
        machine.wait_for_text("filter")
        machine.screenshot("key-finder")
  '';
}
