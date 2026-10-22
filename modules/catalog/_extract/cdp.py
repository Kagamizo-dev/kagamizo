"""The pinned Chromium's DevTools Protocol -> catalog/cdp.json.

Chromium serves the exact protocol it speaks at /json/protocol once it is
started with a debugging port. Start it headless on an ephemeral port, read
the port from DevToolsActivePort in its profile, fetch the protocol and keep,
per domain, every command with its parameters (type or $ref, optional,
enum) and its return values, and every type's enum values. Nothing leaves
the loopback.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

chromium, out = sys.argv[1:3]


def kind(p):
    t = p.get("$ref") or p.get("type", "any")
    if t == "array":
        item = p.get("items", {})
        t = "array<" + (item.get("$ref") or item.get("type", "any")) + ">"
    entry = {"type": t}
    if p.get("optional"):
        entry["optional"] = True
    if "enum" in p:
        entry["enum"] = p["enum"]
    return entry


def fields(ps):
    return {p["name"]: kind(p) for p in ps or []}


profile = tempfile.mkdtemp()
proc = subprocess.Popen(
    [chromium, "--headless=new", "--no-sandbox", "--disable-gpu", "--no-first-run",
     "--disable-background-networking", "--disable-component-update",
     f"--user-data-dir={profile}", "--remote-debugging-port=0", "about:blank"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    port_file = os.path.join(profile, "DevToolsActivePort")
    for _ in range(300):
        if os.path.exists(port_file) and open(port_file).read().strip():
            break
        time.sleep(0.1)
    else:
        sys.exit("chromium never opened its debugging port")
    port = open(port_file).read().split()[0]
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/protocol", timeout=30) as r:
        protocol = json.load(r)
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=30) as r:
        version = json.load(r)
finally:
    proc.terminate()
    proc.wait()

domains = {}
for d in protocol["domains"]:
    domains[d["domain"]] = {
        "commands": {
            c["name"]: {
                "params": fields(c.get("parameters")),
                "returns": fields(c.get("returns")),
                **({"experimental": True} if c.get("experimental") else {}),
                **({"deprecated": True} if c.get("deprecated") else {}),
            }
            for c in d.get("commands", [])
        },
        "enums": {t["id"]: t["enum"] for t in d.get("types", []) if "enum" in t},
    }

with open(out, "w") as f:
    json.dump({"_source": "the pinned Chromium's /json/protocol",
               "protocol": version.get("Protocol-Version"),
               "domains": domains}, f, indent=1, sort_keys=True)
    f.write("\n")
