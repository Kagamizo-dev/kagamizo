"""cf's own command metadata -> catalog/cf.json.

Every command cf has, generated from Cloudflare's API schema plus the
hand-written ones (auth, init, ...): positional arguments and options with
their types and whether they are required, and the API call behind it.
"""
import json
import re
import sys

meta, dist, out = sys.argv[1:4]


schemas = json.load(open(f"{meta}/schemas.json"))["schemas"]


def command(c):
    name = c["command"].removeprefix("cf ")
    usage = c.get("usage", "")
    options = {
        o["name"]: {"type": o["type"], "required": o.get("required", False)}
        for o in c.get("options", [])
    }
    # Commands with a request body also take each body field as --<field>.
    if "[--<field> ...]" in usage:
        for f in schemas.get(name, {}).get("requestBodyFields", []):
            options.setdefault(f["name"], {"type": f["type"], "required": False, "body": True})
    return {
        "args": [
            {
                "name": a["name"],
                "type": a["type"],
                "required": a.get("required", False),
                # <domains...>: any number of values
                "variadic": f"{a['name']}..." in usage,
            }
            for a in sorted(c.get("arguments", []), key=lambda a: a.get("position", 0))
        ],
        "options": options,
        "http": [c["httpMethod"], c["apiPath"]] if c.get("httpMethod") else None,
        "summary": c.get("summary") or c.get("description", "").split("\n")[0][:160],
    }


commands = {}
for name in ("commands.json", "hand-written-commands.json"):
    for c in json.load(open(f"{meta}/{name}"))["commands"]:
        commands[c["command"].removeprefix("cf ")] = command(c)

# The OAuth scopes cf's client is registered for, from its bundled auth layer,
# where minification leaves them as one comma-separated template literal.
source = open(dist).read()
block = next(
    s for s in re.findall(r"`([^`]*)`", source) if "account_api_tokens:create" in s.split(",")
)
scopes = sorted(set(block.split(",")))

json.dump(
    {"commands": commands, "oauthScopes": scopes},
    open(out, "w"),
    indent=1,
    sort_keys=True,
)
