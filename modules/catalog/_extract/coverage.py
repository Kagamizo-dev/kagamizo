"""Every call the modules make to a cataloged tool, held against its catalog.

    coverage.py MODULES_DIR CATALOG_DIR OUT

Typed calls (`cli.<tool> "<command>" { ... }`) are already checked by
../../_lib/cli.nix when the flake evaluates; they are counted here. Raw
calls in shell text (`pass-cli item view --field ...`) and in Rust
(`Command::new("pass-cli")` with its arguments as string literals) are
checked here: the command must be one the pinned tool has, and every
`--option` beside it one that command (or the tool, globally) takes.

Writes a report per module to OUT; exits 1 naming each call that does not
match, so `checks.catalog-coverage` fails on it.
"""

import json
import os
import re
import sys

TOOLS = {
    "pass-cli": ("pass-cli.json", "passCli"),
    "gh": ("gh.json", "gh"),
    "mercury": ("mercury.json", "mercury"),
    "public": ("public.json", "public"),
    "cf": ("cf.json", "cf"),
}
SOURCES = (".nix", ".sh", ".rs", ".py")
WORD = re.compile(r"[a-z][a-z0-9-]*")
# Where a shell command line ends: a pipe, a list, a redirect, a subshell.
END = re.compile(r"\s*(\|\||&&|[|;)`]|>|<|2>)")
FLAG = re.compile(r"(?<![\w-])--([a-z][a-z0-9-]*)")


def load(catalog_dir):
    tools = {}
    for tool, (file, typed) in TOOLS.items():
        with open(os.path.join(catalog_dir, file)) as f:
            c = json.load(f)
        tools[tool] = {
            "commands": c["commands"],
            "global": set((c.get("global") or {}).keys()),
            "tops": {k.split(" ")[0] for k in c["commands"]},
            "typed": typed,
        }
    return tools


def command_of(cat, words):
    """The longest catalog command the words start with, or None."""
    for n in range(len(words), 0, -1):
        name = " ".join(words[:n])
        if name in cat["commands"]:
            return name
    return None


def options_of(cat, command):
    return set(cat["commands"][command].get("options", {}).keys()) | cat["global"]


def strip_comment(path, line):
    s = line.lstrip()
    if path.endswith(".rs"):
        return "" if s.startswith("//") else line
    return "" if s.startswith("#") else line


def shell_calls(path, text, tools):
    """Raw calls on one line each: the tool, then its command words."""
    for no, line in enumerate(text.splitlines(), 1):
        line = strip_comment(path, line)
        if not line or "cli." in line:
            continue
        for tool, cat in tools.items():
            for m in re.finditer(r"(?:^|[\s(|;&`$])" + re.escape(tool) + r" ([^\n]*)", line):
                rest = m.group(1)
                rest = END.split(rest, maxsplit=1)[0]
                words = []
                for w in rest.split():
                    if WORD.fullmatch(w):
                        words.append(w)
                    else:
                        break
                # Prose ("pass-cli is not signed in") names no command.
                if not words or words[0] not in cat["tops"]:
                    continue
                command = command_of(cat, words)
                yield tool, command, FLAG.findall(rest), f"{path}:{no}", " ".join(words)


def rust_calls(path, text, tools):
    """A Rust file that runs a tool: each `Command::new("tool")` call's
    string literals up to where it runs, its command word pairs and
    options. A call whose arguments come from a helper (`.args(args)`) has
    none of its own; then the file's literals are what it is given."""
    for tool, cat in tools.items():
        marker = f'Command::new("{tool}")'
        spans = []
        for m in re.finditer(re.escape(marker), text):
            end = re.search(r"\.(output|spawn|status)\(\)", text[m.end():])
            spans.append(text[m.end(): m.end() + end.start()] if end else text[m.end():])
        if not spans:
            continue
        if all(not re.search(r'"[a-z-]', span) for span in spans):
            spans = [text]
        for span in spans:
            literals = re.findall(r'"([a-z][a-z0-9-]*)",\s*"([a-z][a-z0-9-]*)"', span)
            commands = sorted(
                {f"{a} {b}" for a, b in literals if f"{a} {b}" in cat["commands"]}
            )
            options = sorted(set(re.findall(r'"--([a-z][a-z0-9-]*)"', span)))
            if not commands:
                yield tool, None, options, path, "(no command found)"
                continue
            allowed = set().union(*(options_of(cat, c) for c in commands))
            for c in commands:
                yield tool, c, [], path, c
            for o in options:
                if o not in allowed:
                    yield tool, commands[0], [o], path, "(options of " + ", ".join(commands) + ")"


def main(modules_dir, catalog_dir, out):
    tools = load(catalog_dir)
    report = {}
    problems = []
    for root, dirs, files in os.walk(modules_dir):
        dirs[:] = [d for d in dirs if d not in ("_json", "target")]
        for name in sorted(files):
            if not name.endswith(SOURCES) or name == "coverage.py":
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, modules_dir)
            module = rel.split(os.sep)[0]
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
            entry = report.setdefault(module, {})
            for tool, cat in tools.items():
                for m in re.finditer(r"cli\." + cat["typed"] + r' "([^"]+)"', text):
                    entry.setdefault(tool, {"typed": set(), "raw": set()})["typed"].add(m.group(1))
            calls = rust_calls(rel, text, tools) if name.endswith(".rs") else shell_calls(rel, text, tools)
            for tool, command, flags, where, said in calls:
                if command is None:
                    problems.append(f"{where}: {tool} {said}: not a command of the pinned {tool}")
                    continue
                entry.setdefault(tool, {"typed": set(), "raw": set()})["raw"].add(command)
                allowed = options_of(tools[tool], command)
                for flag in flags:
                    if flag not in allowed:
                        problems.append(f"{where}: {tool} {command}: no option --{flag}")
    with open(out, "w") as f:
        for module in sorted(report):
            entry = report[module]
            if not entry:
                continue
            f.write(f"{module}\n")
            for tool in sorted(entry):
                for kind in ("typed", "raw"):
                    cmds = sorted(entry[tool][kind])
                    if cmds:
                        f.write(f"  {tool:<9} {kind:<5} {', '.join(cmds)}\n")
        f.write("\nused of each catalog:\n")
        for tool, cat in tools.items():
            used = set()
            for entry in report.values():
                if tool in entry:
                    used |= entry[tool]["typed"] | entry[tool]["raw"]
            f.write(f"  {tool:<9} {len(used)} of {len(cat['commands'])} commands\n")
        if problems:
            f.write("\nproblems:\n" + "".join(f"  {p}\n" for p in problems))
    if problems:
        print("calls the pinned tools do not have:", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main(*sys.argv[1:])
