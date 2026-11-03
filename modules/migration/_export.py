"""Notes and Reminders out of iCloud through the pinned pyicloud
(modules/migration/tools.nix; its surface in catalog/_json/pyicloud.json).

    _export.py notes APPLE_ID COOKIE_DIR OUT_DIR       < password
    _export.py reminders APPLE_ID COOKIE_DIR OUT_DIR   < password

The password arrives on stdin, piped from Proton Pass by the `migrate`
runner (./_src), which also restores and keeps the session; it is never
printed. `notes` exports every note (deleted ones left out) as an archival
HTML page with its attachments downloaded beside it, under its folder's
name; `reminders` writes every list (completed reminders included) as one
JSON file. The counts go to stdout as JSON, for the manifest; nothing of
the content does.
"""

import json
import os
import re
import sys

from pyicloud import PyiCloudService

mode, apple_id, cookies, out_dir = sys.argv[1:5]
password = sys.stdin.readline().rstrip("\n")
api = PyiCloudService(apple_id, password, cookie_directory=cookies)
del password
if api.requires_2fa:
    sys.exit("export: the stored session needs a new sign-in (icloud login)")


def safe(name, fallback):
    """A file name from a title: its characters that are safe in a path."""
    cleaned = re.sub(r"[^A-Za-z0-9._ -]+", "_", name or "").strip(" .")
    return cleaned[:80] or fallback


if mode == "notes":
    folders = {f.id: f.name for f in api.notes.folders()}
    notes = [n for n in api.notes.iter_all() if not n.is_deleted]
    exported, locked = 0, 0
    for n in notes:
        if n.is_locked:
            locked += 1
            continue
        folder = safe(folders.get(n.folder_id) or n.folder_name, "Notes")
        target = os.path.join(out_dir, folder, safe(n.id, "note"))
        os.makedirs(target, exist_ok=True)
        api.notes.export_note(n.id, target)
        exported += 1
    print(json.dumps({"count": len(notes), "exported": exported, "locked": locked, "folders": len(folders)}))
elif mode == "reminders":
    lists = [l for l in api.reminders.lists() if not l.deleted]
    total = 0
    for l in lists:
        result = api.reminders.list_reminders(l.id, include_completed=True, results_limit=100000)
        total += len(result.reminders)
        with open(os.path.join(out_dir, f"{safe(l.title, "list")}.{safe(l.id, "id")}.json"), "w") as f:
            json.dump({"list": l.model_dump(mode="json"), **result.model_dump(mode="json")}, f, indent=1, default=str)
    print(json.dumps({"count": total, "lists": len(lists)}))
else:
    sys.exit(f"export: unknown mode {mode}")
