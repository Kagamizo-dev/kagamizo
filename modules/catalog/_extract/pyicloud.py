"""pyicloud's surface -> catalog/_json/pyicloud.json, asked of the pinned
library itself: every service PyiCloudService exposes (a property on it
whose class lives in pyicloud.services), and each service's public methods
and properties with their parameters, from their signatures.

    pyicloud.py OUT

Run with the pinned pyicloud on the path (modules/migration/tools.nix). What
the migration's exporter (modules/migration/_src, _export.py) calls on it is
held to this by checks.catalog-coverage; a pyicloud bump that drops or
renames a method arrives as a diff here.
"""

import importlib
import inspect
import json
import pkgutil
import sys

import pyicloud
import pyicloud.services
from pyicloud import PyiCloudService

(out,) = sys.argv[1:2]

# Every class in pyicloud.services, by name, so a service's helpers (an
# album, a note, a reminder list) are typed too.
classes = {}
for m in pkgutil.walk_packages(pyicloud.services.__path__, "pyicloud.services."):
    mod = importlib.import_module(m.name)
    for name, cls in inspect.getmembers(mod, inspect.isclass):
        if cls.__module__ == m.name:
            classes[name] = cls


def params(fn):
    try:
        sig = inspect.signature(fn)
    except (TypeError, ValueError):
        return []
    found = []
    for p in sig.parameters.values():
        if p.name in ("self", "cls"):
            continue
        entry = {"name": p.name, "required": p.default is inspect.Parameter.empty and p.kind not in (p.VAR_POSITIONAL, p.VAR_KEYWORD)}
        if p.annotation is not inspect.Parameter.empty:
            entry["type"] = p.annotation if isinstance(p.annotation, str) else getattr(p.annotation, "__name__", str(p.annotation))
        if p.kind in (p.VAR_POSITIONAL, p.VAR_KEYWORD):
            entry["variadic"] = True
        found.append(entry)
    return found


def surface(cls):
    methods, properties = {}, []
    for name, member in inspect.getmembers(cls):
        if name.startswith("_"):
            continue
        if isinstance(member, property):
            properties.append(name)
        elif inspect.isfunction(member) or inspect.ismethod(member):
            methods[name] = {"params": params(member)}
    return {"methods": methods, "properties": sorted(properties)}


# The services: PyiCloudService's properties that return a service class
# (read off their annotations, so no account is signed in).
services = {}
for name, member in inspect.getmembers(PyiCloudService):
    if name.startswith("_") or not isinstance(member, property) or member.fget is None:
        continue
    ret = inspect.signature(member.fget).return_annotation
    ret_name = ret if isinstance(ret, str) else getattr(ret, "__name__", None)
    if ret_name in classes:
        services[name] = ret_name

catalog = {
    "pyicloud": pyicloud.__version__ if hasattr(pyicloud, "__version__") else "",
    "service": {"methods": surface(PyiCloudService)["methods"], "properties": surface(PyiCloudService)["properties"], "init": params(PyiCloudService.__init__)},
    "services": services,
    "classes": {name: surface(cls) for name, cls in sorted(classes.items())},
}
with open(out, "w") as f:
    json.dump(catalog, f, indent=1, sort_keys=True)
    f.write("\n")
