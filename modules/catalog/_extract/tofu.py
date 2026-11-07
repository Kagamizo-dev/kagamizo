"""`tofu providers schema -json` -> catalog/cloudflare-provider.json.

Every resource and data source of the pinned provider, with each attribute's
type and whether it is required, optional or computed. Nested blocks are
named; their insides are left to `tofu validate`.
"""
import json
import sys

schema, out = sys.argv[1:3]
provider = next(iter(json.load(open(schema))["provider_schemas"].values()))


def attrs(block):
    return {
        name: {
            "type": a["type"] if "type" in a else "nested",
            "required": a.get("required", False),
            "optional": a.get("optional", False),
            "computed": a.get("computed", False),
        }
        for name, a in block.get("attributes", {}).items()
    } | {name: {"type": "block", "required": b.get("min_items", 0) > 0, "optional": True, "computed": False} for name, b in block.get("block_types", {}).items()}


json.dump(
    {
        "resources": {k: attrs(v["block"]) for k, v in provider["resource_schemas"].items()},
        "data": {k: attrs(v["block"]) for k, v in provider["data_source_schemas"].items()},
    },
    open(out, "w"),
    indent=1,
    sort_keys=True,
)
