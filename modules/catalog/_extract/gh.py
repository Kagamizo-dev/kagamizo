"""gh's reference -> catalog/gh.json.

`gh help reference` prints every command as a heading (`### gh secret set
<secret-name> [flags]`) followed by its flags in cobra's layout
(`  -b, --body string   desc`). Record each leaf command's positional
arguments (<required>, [<optional>], `...` variadic), its options (taking a
value when a type word follows the name) and the values an option is
limited to (`{a|b|c}` or `{a,b,c}` in its description). A group whose own help offers
-R/--repo passes it to every command under it. Runs offline.
"""
import json
import re
import subprocess
import sys

binary, out = sys.argv[1:3]
gh = lambda *a: subprocess.run([binary, *a], capture_output=True, text=True, check=True).stdout

HEADING = re.compile(r"^#{2,4} gh (.+)$")
FLAG = re.compile(r"^\s+(?:-\w, )?--([a-z0-9-]+)(?: (\S+))?\s{2,}(.*)$")

commands, current = {}, None
for line in gh("help", "reference").splitlines():
    m = HEADING.match(line)
    if m:
        words, args = [], []
        for token in re.findall(r"\[[^\]]*\]|<[^>]*>|\S+", m.group(1)):
            if token.startswith(("<", "[")) or token == "|":
                if token in ("[flags]", "<command>"):
                    continue
                name = re.sub(r"[\[\]<>.]", "", token).split("|")[0].strip().split(" ")[0]
                if name:
                    args.append({"name": name, "required": token.startswith("<"), "variadic": "..." in token})
            elif not args:
                words.append(token)
        current = None
        if "<command>" not in m.group(1):
            current = commands.setdefault(" ".join(words), {"args": args, "options": {}})
        continue
    f = FLAG.match(line)
    if current is not None and f and f.group(1) != "help":
        entry = {"value": f.group(2) is not None}
        if f.group(2) == "int":
            entry["type"] = "number"
        elif f.group(2) in ("strings", "stringArray"):
            entry["type"] = "list"
        choices = re.search(r"\{([A-Za-z0-9_-]+(?:[|,][A-Za-z0-9_-]+)+)\}", f.group(3))
        if choices and entry["value"]:
            entry["oneOf"] = re.split(r"[|,]", choices.group(1))
        current["options"][f.group(1)] = entry

# -R/--repo is inherited from the group, so it is missing from the reference.
for group in sorted({c.split(" ")[0] for c in commands}):
    try:
        text = gh(group, "--help")
    except subprocess.CalledProcessError:
        continue
    if re.search(r"--repo \[HOST/\]OWNER/REPO", text):
        for name, c in commands.items():
            if name.split(" ")[0] == group:
                c["options"].setdefault("repo", {"value": True})

json.dump({"commands": commands}, open(out, "w"), indent=1, sort_keys=True)
