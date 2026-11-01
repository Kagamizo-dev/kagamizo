"""iCloud, read through the pinned pyicloud (modules/migration/tools.nix).

    _icloud.py login APPLE_ID COOKIE_DIR CODE_FIFO   < password
    _icloud.py inventory APPLE_ID COOKIE_DIR OUT    < password

The password arrives on stdin, piped from Proton Pass by ./icloud.nix; it is
never printed or kept. `login` signs in, takes the 2FA code the owner reads
off their iPhone from CODE_FIFO (written by the session that relays it), and
trusts the session, so later runs need no code while it lasts. `inventory`
writes what the account holds to OUT as JSON (sizes, counts, and each Hide
My Email relay's label and the site it was made for, which are the logins
that must move before the account closes) and prints only the counts.
"""

import json
import sys

from pyicloud import PyiCloudService

mode, apple_id, cookies = sys.argv[1:4]
password = sys.stdin.readline().rstrip("\n")
api = PyiCloudService(apple_id, password, cookie_directory=cookies)
del password

if mode == "login":
    fifo = sys.argv[4]
    if api.requires_2fa:
        print("icloud: Apple sent a code to the owner's trusted devices; waiting for it", file=sys.stderr, flush=True)
        with open(fifo) as f:
            code = f.readline().strip()
        if not api.validate_2fa_code(code):
            sys.exit("icloud: Apple refused the code")
        if not api.is_trusted_session:
            api.trust_session()
    print("icloud: signed in", file=sys.stderr)
    sys.exit(0)

if mode != "inventory":
    sys.exit(f"icloud: unknown mode {mode}")
out = sys.argv[4]
if api.requires_2fa:
    sys.exit("icloud: the stored session needs a new sign-in (icloud login)")


def guard(name, f):
    try:
        return f()
    except Exception as e:  # one service failing must not hide the rest
        return {"error": f"{type(e).__name__}: {e}"[:300]}


storage = guard(
    "storage",
    lambda: {
        "usedBytes": api.account.storage.usage.used_storage_in_bytes,
        "totalBytes": api.account.storage.usage.total_storage_in_bytes,
        "byMedia": {k: v.usage_in_bytes for k, v in api.account.storage.usages_by_media.items()},
    },
)
hme = guard(
    "hideMyEmail",
    lambda: [
        {"label": e.get("label"), "note": e.get("note"), "address": e.get("hme"), "active": e.get("isActive")}
        for e in api.hidemyemail
    ],
)
report = {
    "storage": storage,
    "photos": guard("photos", lambda: len(api.photos.all)),
    "contacts": guard("contacts", lambda: len(api.contacts.all or [])),
    "calendars": guard("calendars", lambda: [c.get("title") for c in api.calendar.get_calendars()]),
    "notes": guard("notes", lambda: sum(1 for _ in api.notes.iter_all())),
    "reminderLists": guard("reminders", lambda: [l.title for l in api.reminders.lists()]),
    "driveTop": guard("drive", lambda: api.drive.root.dir()),
    "hideMyEmail": hme,
}
with open(out, "w") as f:
    json.dump(report, f, indent=1, default=str)
summary = {k: (len(v) if isinstance(v, list) else v) for k, v in report.items() if k not in ("storage",)}
summary["usedGB"] = round(storage["usedBytes"] / 1e9, 1) if isinstance(storage, dict) and "usedBytes" in storage else storage
print(json.dumps(summary, default=str))
