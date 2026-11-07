"""pass-cli's --help tree -> catalog/pass-cli.json.

pass-cli publishes no schema, but its help is clap's, which is regular:
walk every subcommand and record its positional arguments (required when
written <NAME>, optional when [NAME]) and its options (taking a value when
written --name <VALUE>, a flag otherwise) with the values an option is
limited to (clap's [possible values: ...]). Runs offline: help needs no
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


OPTION = re.compile(r"^\s+(?:-\w, )?--([a-z0-9-]+)(?: <([A-Z0-9_]+)>)?")


def options(lines):
    """Each option with its help text, which may wrap onto further lines."""
    found = {}
    for line in lines:
        m = OPTION.match(line)
        if m:
            name, text = m.group(1), [line]
            found[name] = (m.group(2) is not None, text)
        elif found:
            text.append(line)
    entries = {}
    for name, (value, text) in found.items():
        if name == "help":
            continue
        entry = {"value": value}
        choices = re.search(r"\[possible values: ([^\]]+)\]", " ".join(text))
        if choices:
            entry["oneOf"] = [c.strip() for c in choices.group(1).split(",")]
        entries[name] = entry
    return entries


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
        "options": options(s.get("Options", [])),
    }
    catalog = {} if subs else {" ".join(path): entry}
    for sub in subs:
        catalog |= walk([*path, sub])
    return catalog


json.dump({"commands": walk([])}, open(out, "w"), indent=1, sort_keys=True)
