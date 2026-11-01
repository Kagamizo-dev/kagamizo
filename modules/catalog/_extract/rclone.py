"""rclone -> catalog/_json/rclone.json, from the pinned rclone itself: every
backend and each of its options, typed (`rclone config providers`); every
command with its own flags, walked through cobra's help (`rclone help`,
`rclone <command> --help`, subcommands included); and every global flag
(`rclone help flags`), which any command takes.

    rclone.py RCLONE OUT

Runs offline under an empty HOME: nothing is configured or signed in.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

binary, out = sys.argv[1:3]
home = tempfile.mkdtemp()
env = {"HOME": home, "PATH": "/var/empty"}

FLAG = re.compile(r"^\s+(?:-(\w), )?--([a-z0-9-]+)(?: (\S+))?\s{2,}(.*)$")
CHILD = re.compile(r"^\s{2}([a-z0-9][a-z0-9-]*)\s{2,}(.*)$")


def run(*words):
    r = subprocess.run([binary, *words], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        sys.exit(f"rclone.py: rclone {' '.join(words)} failed: {r.stderr.strip()}")
    return r.stdout


def sections(text):
    """cobra's help, split at its headed sections ("Flags:", "Available
    commands:", "Flags for ... (flag group X):")."""
    current, found = None, {}
    for line in text.splitlines():
        if line and not line.startswith(" ") and line.endswith(":"):
            current = line[:-1]
            found[current] = []
        elif current and line.strip():
            found[current].append(line)
    return found


def flags(lines):
    opts = {}
    for line in lines:
        m = FLAG.match(line)
        if not m:
            continue
        short, name, typ, desc = m.groups()
        entry = {"short": short, "value": typ is not None, "type": typ}
        if typ and "|" in typ:
            entry["oneOf"] = typ.split("|")
            entry["type"] = "string"
        if name != "help":
            opts[name] = entry
    return opts


def command(words):
    text = run(*words, "--help")
    found = sections(text)
    entry = {"args": [], "options": flags(found.get("Flags", []))}
    return entry, [CHILD.match(l).group(1) for l in found.get("Available commands", []) if CHILD.match(l)]


commands = {}
todo = [[c] for c in (CHILD.match(l).group(1) for l in sections(run("help")).get("Available commands", []) if CHILD.match(l))]
while todo:
    words = todo.pop(0)
    entry, children = command(words)
    commands[" ".join(words)] = entry
    todo += [words + [c] for c in children]

# Every global flag, from every group `rclone help flags` lists.
global_flags = {}
for head, lines in sections(run("help", "flags")).items():
    if "(flag group " in head or head == "Global Flags":
        global_flags.update(flags(lines))

backends = {}
for b in json.loads(run("config", "providers")):
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
for needed in ("copy", "check", "config create", "config dump", "obscure", "lsjson"):
    if needed not in commands:
        sys.exit(f"rclone.py: `rclone {needed}` not found in the help")
with open(out, "w") as f:
    json.dump({"backends": backends, "commands": commands, "global": global_flags}, f, indent=1, sort_keys=True)
    f.write("\n")
