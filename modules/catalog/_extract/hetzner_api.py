"""Hetzner Cloud's API surface, from its published OpenAPI spec (pinned by
hash in ../catalogs.nix).

    hetzner_api.py SPEC OUT

Writes every operation by its operationId: HTTP method, path, tag, summary,
whether it is deprecated, its parameters (where, required, type, enum), its
request body's fields and its success response's fields, each with type,
whether required, enum and description, nested objects and arrays flattened
to dotted paths (`server.public_net.ipv4.ip`, `labels.*`, `ssh_keys[]`).
Fails on a $ref it cannot resolve or an operation without an operationId.
"""

import json
import sys

METHODS = ("get", "post", "put", "delete", "patch")


def resolve(spec, node, seen=()):
    while isinstance(node, dict) and "$ref" in node:
        ref = node["$ref"]
        if ref in seen:
            return {"type": "recursive", "ref": ref}
        if not ref.startswith("#/"):
            sys.exit(f"hetzner_api.py: external $ref {ref}")
        target = spec
        for part in ref[2:].split("/"):
            if part not in target:
                sys.exit(f"hetzner_api.py: unresolved $ref {ref}")
            target = target[part]
        seen = seen + (ref,)
        node = target
    return node


def type_of(node):
    t = node.get("type")
    if isinstance(t, list):
        return "|".join(str(x) for x in t)
    if t:
        return t
    for key in ("oneOf", "anyOf", "allOf"):
        if key in node:
            return key
    return "any"


def flatten(spec, node, prefix, required, out, depth=0):
    node = resolve(spec, node)
    if depth > 12:
        return
    for key in ("allOf",):
        if key in node:
            for part in node[key]:
                flatten(spec, part, prefix, required, out, depth + 1)
            return
    for key in ("oneOf", "anyOf"):
        if key in node and "properties" not in node:
            out[prefix or "."] = {
                "type": key,
                "required": required,
                "variants": len(node[key]),
                "description": node.get("description"),
            }
            for i, part in enumerate(node[key]):
                flatten(spec, part, f"{prefix}<{i}>", required, out, depth + 1)
            return
    t = type_of(node)
    if prefix:
        out[prefix] = {
            "type": t,
            "required": required,
            "enum": node.get("enum"),
            "format": node.get("format"),
            "nullable": "null" in t.split("|"),
            "description": node.get("description"),
        }
    if "properties" in node:
        req = set(node.get("required", []))
        for name, sub in node["properties"].items():
            flatten(spec, sub, f"{prefix}.{name}" if prefix else name, name in req, out, depth + 1)
    extra = node.get("additionalProperties")
    if isinstance(extra, dict):
        flatten(spec, extra, f"{prefix}.*" if prefix else "*", False, out, depth + 1)
    if t.startswith("array") or t == "array":
        items = node.get("items")
        if isinstance(items, dict):
            flatten(spec, items, f"{prefix}[]", True, out, depth + 1)


def operations(spec):
    out = {}
    for path, item in spec["paths"].items():
        shared = item.get("parameters", [])
        for method, op in item.items():
            if method not in METHODS:
                continue
            oid = op.get("operationId")
            if not oid:
                sys.exit(f"hetzner_api.py: {method.upper()} {path} has no operationId")
            params = {}
            for p in shared + op.get("parameters", []):
                p = resolve(spec, p)
                schema = resolve(spec, p.get("schema", {}))
                params[f"{p['in']}:{p['name']}"] = {
                    "in": p["in"],
                    "required": bool(p.get("required")),
                    "type": type_of(schema),
                    "enum": schema.get("enum"),
                    "description": p.get("description"),
                }
            body = {}
            rb = resolve(spec, op.get("requestBody", {}))
            for media in rb.get("content", {}).values():
                flatten(spec, media.get("schema", {}), "", True, body)
            response, status = {}, None
            for code, resp in sorted(op.get("responses", {}).items()):
                if code.startswith("2"):
                    status = code
                    resp = resolve(spec, resp)
                    for media in resp.get("content", {}).values():
                        flatten(spec, media.get("schema", {}), "", True, response)
                    break
            out[oid] = {
                "method": method.upper(),
                "path": path,
                "tag": (op.get("tags") or [None])[0],
                "summary": op.get("summary"),
                "deprecated": bool(op.get("deprecated")),
                "params": params,
                "body": body,
                "status": status,
                "response": response,
            }
    return out


def main(spec_path, out):
    with open(spec_path) as f:
        spec = json.load(f)
    ops = operations(spec)
    declared = sum(1 for item in spec["paths"].values() for m in item if m in METHODS)
    if len(ops) != declared:
        sys.exit(f"hetzner_api.py: {len(ops)} operations read, {declared} declared (an operationId repeats)")
    with open(out, "w") as f:
        json.dump(
            {
                "api": {
                    "title": spec["info"]["title"],
                    "version": spec["info"]["version"],
                    "servers": [s["url"] for s in spec.get("servers", [])],
                    "security": spec["components"].get("securitySchemes"),
                },
                "operations": ops,
            },
            f,
            indent=1,
            sort_keys=True,
        )
        f.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
