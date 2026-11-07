# design: the status page as a settings app

Read CLAUDE.md first. Kind: page.

The owner's reading of the status page: it is closest to an operating system's settings. Reorganise it on that pattern, the shape shared by SteamOS, GNOME Settings and a console's system menu.
- A left list of sections:
  - System: hosts and deployment targets;
  - Accounts;
  - Teams;
  - Pipelines;
  - Money;
  - Legal;
  - Research;
  - Twin.
- Each section has a detail pane, and a search bar at the top.
- Running work is a Task Manager-style list of processes:
  - dsh jobs;
  - host services;
  - CI runs.

Take the layout from an open-licensed settings app mapped with REA (GNOME Settings is GPL-2: study only, never vendored). Every value stays generated from declarations, and no section is hand-written. Pass the page check.
