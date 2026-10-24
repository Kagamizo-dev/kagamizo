"""hcloud's command tree -> catalog/_json/hcloud.json, from the pinned binary.

    hcloud.py HCLOUD OUT

Walks cobra's help: each command's command sections are its children,
its "Flags:" its own options (taking a value when a type word follows the
name; `{a|b|c}` or "one of: a, b" in the description lists the values), and
the root's "Global Flags:" (from any leaf) the options every command takes.
Runs offline: help needs no token.
"""

import json
import os
import re
import subprocess
import sys

binary, out = sys.argv[1:3]
env = {"HOME": os.environ.get("TMPDIR", "/tmp"), "PATH": "", "HCLOUD_TOKEN": ""}

FLAG = re.compile(r"^\s+(?:-(\w), )?--([a-z0-9-]+)(?: (\S+))?\s{2,}(.*)$")
CHILD = re.compile(r"^\s{2}([a-z0-9][a-z0-9-]*)\s{2,}(.*)$")


def help_of(words):
    r = subprocess.run([binary, *words, "--help"], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        sys.exit(f"hcloud.py: hcloud {' '.join(words)} --help failed: {r.stderr.strip()}")
    return r.stdout


def sections(text):
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
        values = None
        braces = re.search(r"\{([^}]+)\}", desc)
        oneof = re.search(r"one of:?\s*([a-z0-9_, |-]+)", desc, re.I)
        if braces:
            values = re.split(r"[|,]\s*", braces.group(1))
        elif oneof:
            values = [v.strip() for v in re.split(r"[|,]", oneof.group(1)) if v.strip()]
        opts[name] = {
            "short": short,
            "value": typ is not None,
            "type": typ,
            "oneOf": values,
            "description": desc.strip(),
        }
    return opts


commands, global_flags = {}, None


def walk(words):
    global global_flags
    text = help_of(words)
    parts = sections(text)
    # hcloud groups children under headings of its own ("Resources",
    # "Additional Commands", ...): every section but these lists children.
    plain = {"Usage", "Aliases", "Examples", "Flags", "Global Flags"}
    children = [
        m.group(1)
        for name, lines in parts.items()
        if name not in plain
        for line in lines
        if (m := CHILD.match(line)) and m.group(1) not in ("help", "completion")
    ]
    if words:
        usage = (parts.get("Usage") or [""])[0].strip()
        commands[" ".join(words)] = {
            "usage": usage,
            "options": flags(parts.get("Flags", [])),
            "group": bool(children),
        }
    if "Global Flags" in parts and global_flags is None:
        global_flags = flags(parts["Global Flags"])
    for child in children:
        walk(words + [child])


walk([])
if len(commands) < 50 or "server create" not in commands:
    sys.exit(f"hcloud.py: only {len(commands)} commands read")
with open(out, "w") as f:
    json.dump({"commands": commands, "global": global_flags or {}}, f, indent=1, sort_keys=True)
    f.write("\n")
