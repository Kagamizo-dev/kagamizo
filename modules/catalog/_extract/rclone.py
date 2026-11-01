"""rclone's backends -> catalog/_json/rclone.json, from the pinned rclone's own
`rclone config providers` (every backend and each of its options, typed).

    rclone.py RCLONE OUT
"""

import json
import os
import subprocess
import sys
import tempfile

binary, out = sys.argv[1:3]
home = tempfile.mkdtemp()
raw = subprocess.run(
    [binary, "config", "providers"],
    capture_output=True,
    text=True,
    check=True,
    env={"HOME": home, "PATH": "/var/empty"},
).stdout
backends = {}
for b in json.loads(raw):
    backends[b["Name"]] = {
        "description": b["Description"],
        "options": {
            o["Name"]: {
                "type": o["Type"],
                "required": bool(o["Required"]),
                "advanced": bool(o["Advanced"]),
                "sensitive": bool(o.get("Sensitive") or o.get("IsPassword")),
                "examples": sorted({e["Value"] for e in (o.get("Examples") or []) if e.get("Value")})
                if o.get("Exclusive")
                else [],
            }
            for o in b["Options"]
        },
    }
with open(out, "w") as f:
    json.dump({"backends": backends}, f, indent=1, sort_keys=True)
    f.write("\n")
