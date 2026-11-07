# upkeep: serve the shell at os.jingzo.org

Read CLAUDE.md and modules/shell/_lean/Paper.lean. Serve
packages.kagamizo-shell-web from jingzo-host as static files, routed
through the tunnel to os.jingzo.org behind an Access application for the
owner alone, declared in modules/cloudflare like the other hosts. The
Cloudflare change is an infrastructure apply: plan it, and the owner
approves the apply.
