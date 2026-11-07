# upkeep: Steam on the Yoga and a perf target for the shell's web build

Read CLAUDE.md and modules/shell/_lean/Paper.lean (its gaps). Gamepad
input, the installable web app and the Pi as a target are done. Left, one
change per commit, each with the paper updated:

1. Steam as a declared native app on the Yoga once the owner enables the
   unfree `gamedev.steam` (their decision): programs.steam in the image,
   so checks.shell finds its command on the PATH.
2. A perf target for the web build (modules/perf): transfer size and
   first frame in CI's Chromium, so the number can only fall.

Ask design to review every screen at 390 and 1280 pixels before merge.
