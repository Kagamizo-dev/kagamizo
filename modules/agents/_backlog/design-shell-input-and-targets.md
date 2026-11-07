# design: the shell's gamepad, Steam, and its next targets

Read CLAUDE.md and modules/shell/_lean/Paper.lean (its gaps). In
modules/shell, one change per commit, each with its paper updated:

1. Gamepad input: gilrs natively and the browser's Gamepad API on the web
   target, mapped onto the model's existing keys (model.rs), with tests.
2. Steam as a declared native app on the NixOS targets (programs.steam in
   the image, so checks.shell finds its command on the PATH).
3. A perf target for the web build: transfer size and first frame in
   CI's Chromium, declared in perf.targets so it can only fall.
4. The Raspberry Pi 5 as a NixOS target once its image exists.

Review every screen at 390 and 1280 pixels before asking for merge.
