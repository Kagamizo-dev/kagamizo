"""Proton Mail Bridge's command line, read from its pinned source.

    bridge.py SOURCE OUT

Its flags (internal/app/app.go) and the commands of its interactive CLI
(internal/frontend/cli/frontend.go, an ishell tree built with AddCmd), as
{"flags": [...], "commands": {"updates autoupdates disable": {...}}}. Every
node of the tree is listed, a group as well as its leaves, with ishell's
own `exit` and `help`.
"""

import json
import re
import sys

CMD = re.compile(r'&ishell\.Cmd\{\s*Name:\s*"([^"]+)"(.*?)\n\t*\}', re.S)


def flags(source):
    with open(f"{source}/internal/app/app.go") as f:
        text = f.read()
    names = dict(re.findall(r'\b(flag\w+|Flag\w+)\s*=\s*"([^"]+)"', text))
    used = re.findall(r"Name:\s*(flag\w+|Flag\w+)", text)
    return sorted({names[u] for u in used if u in names})


def commands(source):
    with open(f"{source}/internal/frontend/cli/frontend.go") as f:
        text = f.read()
    var = {}  # Go variable -> its command's name
    # ishell's own commands; Bridge replaces its `clear` with a group.
    out = {"exit": {"aliases": []}, "help": {"aliases": []}}

    def add(path, body):
        aliases = re.search(r"Aliases:\s*\[\]string\{([^}]*)\}", body)
        out[path] = {
            "aliases": re.findall(r'"([^"]+)"', aliases.group(1)) if aliases else [],
        }

    for m in re.finditer(r"(\w+)\s*:=\s*" + CMD.pattern, text, re.S):
        var[m.group(1)] = m.group(2)
    # Walk the AddCmd calls in order, so a group is placed before its children.
    pending = []
    for m in re.finditer(r"(\w+)\.AddCmd\((?:(\w+)\)|" + CMD.pattern + ")", text, re.S):
        owner, child_var, name, body = m.group(1), m.group(2), m.group(3), m.group(4)
        pending.append((owner, child_var, name, body))
    bodies = {m.group(1): m.group(3) for m in re.finditer(r"(\w+)\s*:=\s*" + CMD.pattern, text, re.S)}

    def path_of(v):
        if v == "fe":
            return ""
        return parent_paths[v]

    parent_paths = {}
    changed = True
    while changed:
        changed = False
        for owner, child_var, name, body in pending:
            if owner != "fe" and owner not in parent_paths:
                continue
            base = path_of(owner)
            if child_var:
                if child_var in parent_paths:
                    continue
                path = f"{base} {var[child_var]}".strip()
                parent_paths[child_var] = path
                add(path, bodies[child_var])
                changed = True
            else:
                path = f"{base} {name}".strip()
                if path not in out:
                    add(path, body)
                    changed = True
    return dict(sorted(out.items()))


def main(source, out):
    catalog = {"flags": flags(source), "commands": commands(source)}
    if len(catalog["commands"]) < 20 or "login" not in catalog["commands"]:
        sys.exit("bridge.py: the CLI tree was not found where expected")
    with open(out, "w") as f:
        json.dump(catalog, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
