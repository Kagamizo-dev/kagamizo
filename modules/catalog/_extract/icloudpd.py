"""icloudpd's options -> catalog/_json/icloudpd.json, from the pinned
icloudpd's own --help: each option, whether it takes a value, and its
choices where it lists them.

    icloudpd.py ICLOUDPD OUT
"""

import json
import re
import subprocess
import sys

binary, out = sys.argv[1:3]
text = subprocess.run([binary, "--help"], capture_output=True, text=True, check=True).stdout
options = {}
for line in text.splitlines():
    m = re.match(r"\s{2}(?:-[a-zA-Z], )?--([a-z0-9-]+)(?:,\s*-[a-zA-Z])?(?:\s+(\{[^}]*\}|[A-Z_]+))?(?:\s|$)", line)
    if not m:
        continue
    name, arg = m.group(1), m.group(2)
    if name in options:
        continue
    entry = {"value": arg is not None}
    if arg and arg.startswith("{"):
        entry["oneOf"] = arg[1:-1].split(",")
    options[name] = entry
if "username" not in options or "directory" not in options:
    sys.exit("icloudpd.py: --username or --directory not found in --help")
with open(out, "w") as f:
    json.dump({"commands": {"icloudpd": {"args": [], "options": options}}}, f, indent=1, sort_keys=True)
    f.write("\n")
