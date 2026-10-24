"""Mercury's API surface, read from the pinned Go SDK the CLI is built on.

    mercury_api.py SDK_DIR CLI_DIR CLI_CATALOG OUT

SDK_DIR is github.com/MercuryTechnologies/mercury-go as the CLI's go.mod pins
it; CLI_DIR is the CLI's pinned source; CLI_CATALOG is ../_json/mercury.json,
whose command names the commands map uses. Writes:

  endpoints  every method api.md lists: HTTP method, path, SDK service and
             method, path parameters, the params type and where it goes
             (body or query), the response type, whether it pages
  types      every struct in the SDK: each field's JSON name, Go type,
             whether it is required, its format and its documentation
  enums      every string enum: its values
  commands   each CLI command (as the catalog names it) and the SDK methods
             its handler calls, so a command maps to its endpoints
"""

import json
import os
import re
import sys

CODE = re.compile(r'<code title="(\w+) ([^"]+)">(.*?)</code>')
SERVICE = re.compile(r"client\.((?:\w+\.)*\w+)\.<a [^>]*#(\w+)Service\.(\w+)\">")
TYPE_REF = re.compile(r"#(\w+)\">")
STRUCT = re.compile(r"^type (\w+) struct \{\n(.*?)^\}", re.M | re.S)
FIELD = re.compile(r"^\t(\w+)\s+(\S+)\s+`([^`]*)`$")
ENUM_TYPE = re.compile(r"^type (\w+) string$", re.M)
ENUM_CONST = re.compile(r"^\t\w+\s+(\w+)\s+=\s+\"([^\"]*)\"$", re.M)


def tag(tags, key):
    m = re.search(key + r':"([^"]*)"', tags)
    return m.group(1) if m else None


def endpoints(sdk):
    with open(os.path.join(sdk, "api.md")) as f:
        text = f.read()
    out = {}
    for method, path, body in CODE.findall(text):
        s = SERVICE.search(body)
        if not s:
            sys.exit(f"mercury_api.py: no SDK method for {method} {path}")
        chain, service, fn = s.groups()
        args, _, returns = body.partition(") (")
        if not returns:
            args, _, returns = body.rpartition(") ")
        params = [t for t in TYPE_REF.findall(args) if t.endswith("Params")]
        path_params = re.findall(r"\{(\w+)\}", path)
        ret = [t for t in TYPE_REF.findall(returns) if t not in ("error",)]
        paged = "pagination#" in returns
        if "http.Response" in returns:
            response = "raw"
        elif paged:
            response = ret[-1] if ret else None
        else:
            response = ret[0] if ret else None
        key = f"{chain}.{fn}".lower()
        out[key] = {
            "method": method.upper(),
            "path": path,
            "sdk": f"client.{chain}.{fn}",
            "service": service,
            "pathParams": path_params,
            "params": params[0] if params else None,
            "paramsIn": ("query" if " query " in args or "query <" in args else "body")
            if params
            else None,
            "response": response,
            "paged": paged,
        }
    return out


def go_files(sdk):
    for name in sorted(os.listdir(sdk)):
        if name.endswith(".go") and not name.endswith("_test.go"):
            yield os.path.join(sdk, name)


def types_and_enums(sdk):
    types, enums = {}, {}
    # An enum's constants may sit in another file than its type.
    consts, enum_types = [], set()
    for path in go_files(sdk):
        with open(path) as f:
            text = f.read()
        consts += ENUM_CONST.findall(text)
        enum_types |= set(ENUM_TYPE.findall(text))
    for name in enum_types:
        values = sorted({v for t, v in consts if t == name})
        if values:
            enums[name] = values
    for path in go_files(sdk):
        with open(path) as f:
            text = f.read()
        for name, body in STRUCT.findall(text):
            fields, doc = {}, []
            for line in body.split("\n"):
                stripped = line.strip()
                if stripped.startswith("//"):
                    doc.append(stripped[2:].strip())
                    continue
                m = FIELD.match(line)
                if m:
                    go, gotype, tags = m.groups()
                    jname = (tag(tags, "json") or "").split(",")[0]
                    qname = (tag(tags, "query") or "").split(",")[0]
                    wire = jname if jname not in ("", "-") else qname
                    if wire:
                        fields[wire] = {
                            "go": go,
                            "type": gotype,
                            "in": "query" if wire == qname and jname in ("", "-") else "json",
                            "required": tag(tags, "api") == "required",
                            "format": tag(tags, "format"),
                            "doc": " ".join(doc) or None,
                        }
                doc = [] if not stripped.startswith("//") else doc
            types[name] = {"file": os.path.basename(path), "fields": fields}
    return types, enums


def commands(cli, catalog):
    """Each CLI command, by the catalog's name, and the SDK methods its
    handler calls. A catalog command no handler matches is an error."""
    names = {re.sub(r"[ :]", "", k).lower(): k for k in catalog}
    cmd_dir = os.path.join(cli, "pkg", "cmd")
    out = {}
    for name in sorted(os.listdir(cmd_dir)):
        if not name.endswith(".go") or name.endswith("_test.go"):
            continue
        with open(os.path.join(cmd_dir, name)) as f:
            text = f.read()
        # var xCreate = cli.Command{ Name: "create", ... Action: handleXCreate }
        # Commands with body flags are wrapped: requestflag.WithInnerFlags(cli.Command{...
        for var, block in re.findall(
            r"var (\w+) = (?:requestflag\.WithInnerFlags\()?&?cli\.Command\{(.*?)\n\}", text, re.S
        ):
            cname = re.search(r'Name:\s*"([^"]+)"', block)
            action = re.search(r"Action:\s*(\w+)", block)
            if not (cname and action):
                continue
            fn = re.search(r"func " + re.escape(action.group(1)) + r"\(.*?\n\}", text, re.S)
            calls = sorted(set(re.findall(r"client\.((?:\w+\.)*\w+)\(", fn.group(0)))) if fn else []
            # Top-level commands (login, logout, status) are auth<Name>.
            key = names.get(var.lower()) or (
                cname.group(1) if var == "auth" + cname.group(1).title() and cname.group(1) in catalog else None
            )
            if key:
                out[key] = {"handler": action.group(1), "file": name, "calls": calls}
    unmatched = sorted(set(catalog) - set(out))
    if unmatched:
        sys.exit(f"mercury_api.py: catalog commands with no handler found: {unmatched}")
    return out


def main(sdk, cli, catalog_path, out):
    with open(catalog_path) as f:
        catalog = json.load(f)["commands"]
    eps = endpoints(sdk)
    types, enums = types_and_enums(sdk)
    with open(os.path.join(sdk, ".stats.yml")) as f:
        stats = f.read()
    declared = int(re.search(r"configured_endpoints:\s*(\d+)", stats).group(1))
    if len(eps) != declared:
        sys.exit(f"mercury_api.py: {len(eps)} endpoints in api.md, the SDK declares {declared}")
    # Every tagged field and every string constant in the SDK is read, or
    # nothing is written: a layout this does not parse fails here.
    tagged = consts = 0
    for path in go_files(sdk):
        with open(path) as f:
            text = f.read()
        tagged += len(re.findall(r'^\s+\w+\s.*`.*(?:json|query):"[^-"]', text, re.M))
        consts += len(ENUM_CONST.findall(text))
    read = sum(len(t["fields"]) for t in types.values())
    if read != tagged:
        sys.exit(f"mercury_api.py: read {read} of the SDK's {tagged} tagged fields")
    if sum(len(v) for v in enums.values()) != len(
        {(t, v) for path in go_files(sdk) for t, v in ENUM_CONST.findall(open(path).read())}
    ):
        sys.exit("mercury_api.py: an enum constant was not read")
    missing = sorted(
        {t for e in eps.values() for t in (e["params"], e["response"]) if t and t != "raw"}
        - set(types)
    )
    if missing:
        sys.exit(f"mercury_api.py: types the endpoints use but no struct defines: {missing}")
    with open(out, "w") as f:
        json.dump(
            {"endpoints": eps, "types": types, "enums": enums, "commands": commands(cli, catalog)},
            f,
            indent=1,
            sort_keys=True,
        )
        f.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
