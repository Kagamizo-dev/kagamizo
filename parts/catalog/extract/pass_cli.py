"""pass-cli's --help tree -> catalog/pass-cli.json.

pass-cli publishes no schema, but its help is clap's, which is regular:
walk every subcommand and record its positional arguments (required when
written <NAME>, optional when [NAME]) and its options (taking a value when
written --name <VALUE>, a flag otherwise). Runs offline: help needs no
session.
"""
import json
import re
import subprocess
import sys

binary, out = sys.argv[1:3]


def sections(text):
    current, found = None, {}
    for line in text.splitlines():
        header = re.match(r"^(Commands|Arguments|Options):\s*$", line)
        if header:
            current = header.group(1)
            found[current] = []
        elif not line.strip():
            current = None
        elif current:
            found[current].append(line)
    return found


def walk(path):
    help_text = subprocess.run([binary, *path, "--help"], capture_output=True, text=True, check=True).stdout
    s = sections(help_text)
    subs = [m.group(1) for line in s.get("Commands", []) if (m := re.match(r"^\s{2}([a-z][a-z0-9-]*)\s", line))]
    subs = [c for c in subs if c != "help"]
    entry = {
        "args": [
            {"name": m.group(2).lower().replace("_", "-"), "required": m.group(1) == "<"}
            for line in s.get("Arguments", [])
            if (m := re.match(r"^\s{2}([<\[])([A-Z0-9_]+)[>\]]", line))
        ],
        "options": {
            m.group(1): {"value": m.group(2) is not None}
            for line in s.get("Options", [])
            if (m := re.match(r"^\s+(?:-\w, )?--([a-z0-9-]+)(?: <([A-Z0-9_]+)>)?", line)) and m.group(1) != "help"
        },
    }
    catalog = {} if subs else {" ".join(path): entry}
    for sub in subs:
        catalog |= walk([*path, sub])
    return catalog


json.dump({"commands": walk([])}, open(out, "w"), indent=1, sort_keys=True)
