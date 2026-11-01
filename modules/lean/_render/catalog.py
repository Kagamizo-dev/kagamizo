"""One pinned catalog (catalog/_json/<name>.json) -> Lean, in the model of
../_lean/Api.lean.

    catalog.py NAME VERSION CATALOG.json OUT.lean [OUT.json]

OUT.json, when given, is the same model as JSON: what the Rust checker
(../_src, `api-check`) reads, so Lean and Rust check one thing.

Each catalog's own shape (a CLI's commands and options, an HTTP API's
operations and body fields, a provider's resources) is read into
operations with typed inputs. A type the catalog states that this does not
know fails the render, naming it, so a tool bump that brings a new kind of
input stops here until the model has it.
"""

import json
import re
import sys

name, version, path, out = sys.argv[1:5]
out_json = sys.argv[5] if len(sys.argv) > 5 else None
catalog = json.load(open(path))


class Unknown(Exception):
    pass


def lean_str(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
    return f'"{s}"'


def ty_lean(t):
    if isinstance(t, str):
        return "." + t
    tag, arg = t
    if tag == "list":
        return f"(.list {ty_lean(arg)})"
    if tag == "oneOf":
        return "(.oneOf [" + ", ".join(lean_str(v) for v in arg) + "])"
    if tag == "named":
        return f"(.named {lean_str(arg)})"
    raise Unknown(f"ty {t}")


def inp(n, t, required=False, positional=False):
    return {"name": n, "ty": t, "required": bool(required), "positional": positional}


def fail(what):
    sys.exit(f"lean/_render/catalog.py: {name}: {what}: not in the model (../_lean/Api.lean)")


# --- command-line tools -------------------------------------------------

SIMPLE = {
    "string": "string",
    "boolean": "flag",
    "bool": "flag",
    "number": "number",
    "int": "int",
    "json": "json",
    "duration": "duration",
    "ip": "ip",
    "ipNet": "cidr",
    "stringToString": "pairs",
}


def cli_ty(o):
    """An option or argument of a command-line tool."""
    if o.get("oneOf"):
        return ("oneOf", list(o["oneOf"]))
    t = o.get("type")
    if t is None:
        # A flag-or-value option as cobra and clap record it.
        return "string" if o.get("value", True) else "flag"
    if t in ("list", "stringArray", "strings"):
        return ("list", "string")
    if t == "ipSlice":
        return ("list", "ip")
    if t in SIMPLE:
        return SIMPLE[t]
    fail(f"option type {t!r}")


def cli_ops(commands, globals_):
    """Each command's positional arguments, in order, then its options; the
    tool's global options are every command's too, as ../../_lib/cli.nix
    takes them."""
    ops = []
    for words, c in commands.items():
        inputs = []
        for a in c.get("args") or []:
            t = cli_ty(a)
            if a.get("variadic"):
                t = ("list", t)
            inputs.append(inp(a["name"], t, a.get("required"), positional=True))
        options = dict(globals_)
        options.update(c.get("options") or {})
        for o, spec in options.items():
            t = cli_ty(spec)
            if spec.get("multiple"):
                t = ("list", t)
            inputs.append(inp(o, t, spec.get("required")))
        ops.append({"name": words, "inputs": inputs})
    return ops


# --- HTTP APIs ----------------------------------------------------------

OPENAPI = {"string": "string", "integer": "int", "number": "number", "boolean": "bool", "object": "json", "oneOf": "json"}


def openapi_ty(spec, items=None):
    if spec.get("enum"):
        return ("oneOf", [str(v) for v in spec["enum"] if v is not None])
    t = (spec.get("type") or "").replace("|null", "")
    if t == "array":
        return ("list", openapi_ty(items) if items else "json")
    if t in OPENAPI:
        return OPENAPI[t]
    fail(f"OpenAPI type {spec.get('type')!r}")


def hetzner_ops(operations):
    ops = []
    for op, o in operations.items():
        inputs = []
        for p, spec in (o.get("params") or {}).items():
            inputs.append(inp(p, openapi_ty(spec), spec.get("required")))
        body = o.get("body") or {}
        for field, spec in body.items():
            if "." in field or "[" in field:
                continue  # nested: carried by its top-level field's json
            inputs.append(inp(field, openapi_ty(spec, body.get(field + "[]")), spec.get("required")))
        ops.append({"name": op, "inputs": inputs})
    return ops


GO = {"string": "string", "time.Time": "string", "io.Reader": "string", "float64": "number", "int64": "int", "bool": "bool", "any": "json"}


def go_ty(t):
    m = re.fullmatch(r"param\.Opt\[(.+)\]", t)
    if m:
        return go_ty(m.group(1))
    if t.startswith("[]"):
        return ("list", go_ty(t[2:]))
    if t in GO:
        return GO[t]
    if re.fullmatch(r"[A-Z][A-Za-z0-9]*", t):
        return ("named", t)
    fail(f"Go type {t!r}")


def mercury_api(c):
    types = [
        {"name": n, "fields": [inp(f, go_ty(s["type"]), s.get("required")) for f, s in d["fields"].items()]}
        for n, d in c["types"].items()
    ]
    enums = [(n, list(vs)) for n, vs in c["enums"].items()]
    ops = []
    for e, d in c["endpoints"].items():
        inputs = [inp(p, "string", True) for p in d.get("pathParams") or []]
        if d.get("params"):
            inputs += next(t["fields"] for t in types if t["name"] == d["params"])
        ops.append({"name": e, "inputs": inputs})
    return ops, types, enums


# Chrome DevTools Protocol: a domain's commands, typed by its own objects and
# enums; a reference to a plain alias (DOM.NodeId is an integer) is json,
# since the catalog keeps objects and enums only.
CDP = {"string": "string", "integer": "int", "number": "number", "boolean": "bool", "object": "json", "any": "json", "binary": "string"}


def cdp(c):
    domains = c["domains"]
    declared = {f"{d}.{n}" for d, v in domains.items() for k in ("objects", "enums") for n in v.get(k) or {}}

    def ty(t, here):
        m = re.fullmatch(r"array<(.+)>", t)
        if m:
            return ("list", ty(m.group(1), here))
        if t in CDP:
            return CDP[t]
        ref = t if "." in t else f"{here}.{t}"
        return ("named", ref) if ref in declared else "json"

    ops, types, enums = [], [], []
    for d, v in domains.items():
        for cmd, spec in (v.get("commands") or {}).items():
            ins = [inp(p, ty(s["type"], d), not s.get("optional")) for p, s in (spec.get("params") or {}).items()]
            ops.append({"name": f"{d}.{cmd}", "inputs": ins})
        for n, vs in (v.get("enums") or {}).items():
            enums.append((f"{d}.{n}", list(vs)))
        for n, fields in (v.get("objects") or {}).items():
            fs = [inp(f, ty(s["type"], d), not s.get("optional")) for f, s in (fields or {}).items()]
            types.append({"name": f"{d}.{n}", "fields": fs})
    return ops, types, enums


# --- OpenTofu providers ---------------------------------------------------

TOFU = {"string": "string", "number": "number", "bool": "bool", "nested": "json", "block": "json", "dynamic": "json"}


def tofu_ty(t):
    if isinstance(t, str):
        if t in TOFU:
            return TOFU[t]
        fail(f"provider type {t!r}")
    kind, of = t[0], t[1]
    if kind in ("list", "set"):
        return ("list", tofu_ty(of))
    if kind in ("map", "object"):
        return "json"
    fail(f"provider type {t!r}")


def tofu(c):
    ops = []
    for kind in ("resources", "data"):
        for r, attrs in c[kind].items():
            ins = [
                inp(a, tofu_ty(s["type"]), s.get("required"))
                for a, s in attrs.items()
                if s.get("required") or s.get("optional")
            ]
            ops.append({"name": f"{'resource' if kind == 'resources' else 'data'}.{r}", "inputs": ins})
    return ops


# --- read ------------------------------------------------------------------

def pass_items(c):
    """Proton Pass's items as record types: each item type by its fields
    (string-valued), each custom-item field kind a type of its own, and each
    app template by its fields, typed by kind."""
    types = [{"name": f"field.{k}", "fields": []} for k in c["customFieldKinds"]]
    for t, d in c["types"].items():
        types.append({"name": f"item.{t}", "fields": [inp(f, "string") for f in d["fields"]]})
    for t, d in c["appTemplates"].items():
        fields = [inp(f, ("named", f"field.{k}"), True) for f, k in d["fields"].items()]
        types.append({"name": f"template.{t}", "fields": fields})
    return types


RCLONE = {
    "string": "string",
    "bool": "bool",
    "int": "int",
    "float64": "number",
    "Duration": "duration",
    "SizeSuffix": "string",
    "Encoding": "string",
    "Tristate": ("oneOf", ["true", "false", "unset"]),
    "Bits": "string",
    "Time": "string",
    "CommaSepList": ("list", "string"),
    "SpaceSepList": ("list", "string"),
    "stringArray": ("list", "string"),
}


def rclone_ty(o):
    if o["examples"]:
        return ("oneOf", o["examples"])
    t = o["type"]
    if t in RCLONE:
        return RCLONE[t]
    if "|" in t:
        return ("oneOf", t.split("|"))
    fail(f"rclone option type {t!r}")


types, enums = [], []
if "backends" in catalog:
    # Each backend's configuration, as `rclone config create NAME BACKEND key=value`.
    ops = [
        {"name": f"backend.{b}", "inputs": [inp(k, rclone_ty(o), o["required"]) for k, o in d["options"].items()]}
        for b, d in catalog["backends"].items()
    ]
elif "appTemplates" in catalog:
    ops, types = [], pass_items(catalog)
elif "endpoints" in catalog:
    ops, types, enums = mercury_api(catalog)
elif "operations" in catalog:
    ops = hetzner_ops(catalog["operations"])
elif "domains" in catalog:
    ops, types, enums = cdp(catalog)
elif "resources" in catalog:
    ops = tofu(catalog)
elif "runtime_catalog" in catalog:
    # REA: its MCP tools and its CLI's commands; it publishes no input schemas.
    ops = [{"name": f"tool.{t}", "inputs": []} for f in catalog["tools"]["families"] for t in f["tools"]]
    ops += [{"name": f"cli.{t}", "inputs": []} for t in catalog["cli"]["commands"]]
elif "commands" in catalog:
    g = catalog.get("global") or {}
    ops = cli_ops(catalog["commands"], g if isinstance(g, dict) else {})
else:
    fail("catalog shape")

# --- write -----------------------------------------------------------------

ident = re.sub(r"[^A-Za-z0-9]", "", name.title())


def input_lean(i):
    return "{ name := %s, ty := %s, required := %s%s }" % (
        lean_str(i["name"]),
        ty_lean(i["ty"]),
        "true" if i["required"] else "false",
        ", positional := true" if i.get("positional") else "",
    )


def ty_json(t):
    if isinstance(t, str):
        return t
    tag, arg = t
    if tag == "list":
        return {"list": ty_json(arg)}
    return {tag: arg}


def chunks(xs, n=100):
    return [xs[i : i + n] for i in range(0, len(xs), n)] or [[]]


lines = [f"namespace Kagamizo.Api.{ident}", "open Kagamizo.Api", ""]
op_chunks = chunks(ops)
for k, chunk in enumerate(op_chunks):
    lines.append(f"def ops{k} : List Operation := [")
    lines.append(
        ",\n".join(
            "  { name := %s, inputs := [%s] }" % (lean_str(o["name"]), ", ".join(map(input_lean, o["inputs"])))
            for o in chunk
        )
    )
    lines.append("]\n")
type_chunks = chunks(types)
for k, chunk in enumerate(type_chunks):
    lines.append(f"def types{k} : List TypeDecl := [")
    lines.append(
        ",\n".join(
            "  { name := %s, fields := [%s] }" % (lean_str(t["name"]), ", ".join(map(input_lean, t["fields"])))
            for t in chunk
        )
    )
    lines.append("]\n")
lines.append("def enums : List (String × List String) := [")
lines.append(",\n".join("  (%s, [%s])" % (lean_str(n), ", ".join(map(lean_str, vs))) for n, vs in enums))
lines.append("]\n")
lines.append(f"/-- {name}, as its pinned version states it. -/")
lines.append("def api : Api := {")
lines.append(f"  name := {lean_str(name)}, version := {lean_str(version)},")
lines.append("  ops := " + " ++ ".join(f"ops{k}" for k in range(len(op_chunks))) + ",")
lines.append("  types := " + " ++ ".join(f"types{k}" for k in range(len(type_chunks))) + ",")
lines.append("  enums := enums }")
lines.append("")
if types or enums:
    lines.append("/-- Every type it refers to by name, it declares. -/")
    lines.append("theorem closed : api.closed = true := by decide +kernel")
    lines.append("")
lines.append(f"end Kagamizo.Api.{ident}")
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
if out_json:
    with open(out_json, "w") as f:
        json.dump(
            {
                "name": name,
                "version": version,
                "ops": [
                    {"name": o["name"], "inputs": [dict(i, ty=ty_json(i["ty"])) for i in o["inputs"]]} for o in ops
                ],
            },
            f,
            sort_keys=True,
        )
print(f"{name}: {len(ops)} operations, {len(types)} types, {len(enums)} enums", file=sys.stderr)
