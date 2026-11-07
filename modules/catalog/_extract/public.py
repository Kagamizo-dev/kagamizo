"""Every public command, its arguments and options, from the CLI's own click tree.

Typer builds on click, so the app is walked directly instead of its drawn help:

  {"commands": {"order search": {"args": [...], "options": {
     "status": {"type": "string", "required": false, "multiple": false, "oneOf": [...]},
     ...}}}, "global": {...}}

usage: python -I public.py <out>   (with publicdotcom_cli importable)
"""

import json
import sys

import click
import typer.main
from publicdotcom_cli.cli import app


def kind(p):
    if isinstance(p, click.Option) and p.is_flag:
        return "boolean"
    t = p.type
    if isinstance(t, (click.types.IntParamType, click.types.FloatParamType, click.IntRange, click.FloatRange)):
        return "number"
    return "string"


def params(cmd):
    args, opts = [], {}
    for p in cmd.params:
        if isinstance(p, click.Argument):
            args.append({"name": p.name.replace("_", "-"), "required": p.required, "variadic": p.nargs == -1, "type": kind(p)})
        elif isinstance(p, click.Option):
            long = next((o for o in p.opts if o.startswith("--")), None)
            if long is None or p.hidden or long in ("--help", "--install-completion", "--show-completion"):
                continue
            o = {"type": kind(p), "required": p.required, "multiple": p.multiple}
            if isinstance(p.type, click.Choice):
                o["oneOf"] = [str(c) for c in p.type.choices]
            opts[long[2:]] = o
    return args, opts


root = typer.main.get_command(app)
commands = {}


def walk(group, prefix):
    for name, cmd in sorted(group.commands.items()):
        path = f"{prefix} {name}".strip()
        if isinstance(cmd, click.Group):
            walk(cmd, path)
        else:
            args, opts = params(cmd)
            commands[path] = {"args": args, "options": opts}


walk(root, "")
_, root_opts = params(root)
with open(sys.argv[1], "w") as f:
    json.dump({"commands": commands, "global": root_opts}, f, indent=1, sort_keys=True)
    f.write("\n")
