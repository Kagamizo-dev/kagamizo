"""Every mercury command and its options, read from the CLI's pinned Go source.

The help output is a drawn TUI, but pkg/cmd declares each command as a
cli.Command literal and each option as a requestflag.Flag[T] / InnerFlag[T]
(or a plain cli flag), so the source is the exact catalog. Output:

  {"commands": {"cards create": {"args": [], "options": {
     "kind": {"type": "string", "required": true, "oneOf": ["debit", "credit"]},
     "spend-limit": {"type": "json", "required": false}, ...}}},
   "global": {...}}

usage: mercury.py <source dir> <out>
"""

import json
import pathlib
import re
import sys

src, out = pathlib.Path(sys.argv[1]), sys.argv[2]
cmd_dir = src / "pkg" / "cmd"


def block(text, start):
    """The text of the {...} block whose opening brace is at `start`."""
    depth = 0
    in_str = None
    i = start
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\" and in_str == '"':
                i += 2
                continue
            if c == in_str:
                in_str = None
        elif c in "\"`":
            in_str = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
        i += 1
    raise ValueError("unbalanced braces")


def field(body, name):
    m = re.search(rf'\b{name}:\s*("(?:[^"\\]|\\.)*"|`[^`]*`|true|false)', body)
    if not m:
        return None
    v = m.group(1)
    if v in ("true", "false"):
        return v == "true"
    return json.loads(v) if v.startswith('"') else v[1:-1]


def go_type(t):
    """A Go type parameter as a catalog type; maps and `any` take JSON."""
    t = t.lstrip("*")
    if t in ("int64", "float64", "int"):
        return "number"
    if t == "bool":
        return "boolean"
    if t == "[]string":
        return "list"
    if t == "string":
        return "string"
    return "json"

PLAIN = {"StringFlag": "string", "IntFlag": "number", "Int64Flag": "number", "BoolFlag": "boolean", "StringSliceFlag": "list"}


def flags(body):
    """The options of a command (or the root) literal, and its inner options."""
    opts = {}
    m = re.search(r"\bFlags:\s*\[\]cli\.Flag\{", body)
    if not m:
        return opts
    fl = block(body, m.end() - 1)
    inner = re.search(r"\nInner: ", body)
    if inner:
        fl += body[inner.end() :]
    for f in re.finditer(r"&(?:requestflag\.(?:Inner)?Flag\[([^\n{]*?)\]|cli\.(\w+))\{", fl):
        fb = block(fl, f.end() - 1)
        name = field(fb, "Name")
        if not name:
            continue
        t = go_type(f.group(1)) if f.group(1) else PLAIN.get(f.group(2), "string")
        o = {"type": t, "required": bool(field(fb, "Required"))}
        allowed = re.search(r"Allowed values: ((?:\"[^\"]*\"(?:, )?)+)", field(fb, "Usage") or "")
        if allowed:
            o["oneOf"] = re.findall(r'"([^"]*)"', allowed.group(1))
        opts[name] = o
    return opts


# Every `var x = cli.Command{...}` across the package.
commands = {}
for path in sorted(cmd_dir.glob("*.go")):
    if path.name.endswith("_test.go"):
        continue
    text = path.read_text()
    for m in re.finditer(r"\bvar (\w+) = (requestflag\.WithInnerFlags\()?cli\.Command\{", text):
        body = block(text, m.end() - 1)
        if m.group(2):
            # WithInnerFlags(cmd, map[string][]requestflag.HasOuterFlag{...}):
            # the nested options (spend-limit.amount-cents, ...) are in the map.
            rest = text[m.end() - 1 + len(body) :]
            inner = re.match(r"\s*,\s*map\[string\]\[\]requestflag\.HasOuterFlag\{", rest)
            if inner:
                body += "\nInner: " + block(rest, inner.end() - 1)
        commands[m.group(1)] = body

root_text = (cmd_dir / "cmd.go").read_text()
root = block(root_text, re.search(r"cli\.Command\{", root_text).end() - 1)

catalog = {}


def walk(body, prefix):
    """Resources nest: {Name: "x", Commands: []*cli.Command{&leaf, {Name: ...}}}."""
    m = re.search(r"\bCommands:\s*\[\]\*cli\.Command\{", body)
    if not m:
        return
    lst = block(body, m.end() - 1)[1:-1]
    i = 0
    while i < len(lst):
        c = lst[i]
        if c == "&":
            ref = re.match(r"&(\w+)", lst[i:]).group(1)
            leaf = commands.get(ref)
            if leaf is not None:
                name = field(leaf, "Name")
                path = f"{prefix} {name}".strip()
                if re.search(r"\bCommands:\s*\[\]\*cli\.Command\{", leaf):
                    walk(leaf, path)
                else:
                    catalog[path] = {"args": [], "options": flags(leaf)}
            i += len(ref) + 1
        elif c == "{":
            sub = block(lst, i)
            name = field(sub, "Name")
            walk(sub, f"{prefix} {name}".strip())
            i += len(sub)
        else:
            i += 1


walk(root, "")
pathlib.Path(out).write_text(
    json.dumps({"commands": dict(sorted(catalog.items())), "global": flags(root)}, indent=1, sort_keys=True) + "\n"
)
