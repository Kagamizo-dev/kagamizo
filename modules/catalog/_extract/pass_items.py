"""Proton Pass's item types -> catalog/_json/pass-items.json, from the pinned
pass-cli's own templates (`pass-cli item create login --get-template`, and so on
for each type).

    pass_items.py PASS_CLI VERSION OUT

Templates need a signed-in session, so this runs with the caller's
environment (`nix run .#pass-items-update`), not in a build sandbox; the
output carries the pass-cli version it came from, and checks.catalog-pass-items
fails when the pinned pass-cli moves past it.

Each type's fields as the template names them. A custom item's fields are
sections of typed fields (text, hidden, totp, timestamp); the field types
are the ones the custom template lists. The Proton Pass apps also offer
templates of their own for custom items (an "API credential", say) that
pass-cli does not print; those are recorded by `observed`, below, each from
a real item's shape (names and value types only).
"""

import json
import os
import subprocess
import sys

binary, version, out = sys.argv[1:4]
env = dict(os.environ, PROTON_PASS_KEY_PROVIDER="fs")

TYPES = ["login", "note", "credit-card", "identity", "wifi", "custom"]

# App templates for custom items, as a real item stores them: its
# `extra_fields`, each a name and a typed value.
observed = {
    "api-credential": {
        "source": "Mirazo-Root/Public, an API credential made in the Proton Pass app (2026-10-31)",
        "fields": {
            "API key": "hidden",
            "Secret": "hidden",
            "Expiry date": "timestamp",
            "Permissions": "text",
        },
    },
}


def template(kind):
    r = subprocess.run(
        [binary, "item", "create", kind, "--get-template"],
        capture_output=True,
        text=True,
        env=env,
    )
    if r.returncode != 0:
        sys.exit(f"pass_items.py: {kind} --get-template failed: {r.stderr.strip()}")
    return json.loads(r.stdout)


types = {}
field_kinds = set()
for kind in TYPES:
    t = template(kind)
    fields = sorted(k for k in t if k != "sections")
    entry = {"fields": fields}
    if "sections" in t:
        kinds = sorted(
            {f["field_type"] for section in t["sections"] for f in section.get("fields", [])}
        )
        entry["customFieldKinds"] = kinds
        field_kinds |= set(kinds)
    types[kind] = entry

for name, tpl in observed.items():
    unknown = set(tpl["fields"].values()) - field_kinds
    if unknown:
        sys.exit(f"pass_items.py: {name} uses field kinds pass-cli does not list: {sorted(unknown)}")

with open(out, "w") as f:
    json.dump(
        {
            "passCli": version,
            "types": types,
            "customFieldKinds": sorted(field_kinds),
            "appTemplates": observed,
        },
        f,
        indent=1,
        sort_keys=True,
    )
    f.write("\n")
