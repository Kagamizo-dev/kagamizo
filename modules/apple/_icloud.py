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
import os
import socket
import ssl
import sys
from urllib.parse import urlparse

from pyicloud import PyiCloudService
from pyicloud.exceptions import (
    PyiCloud2FARequiredException,
    PyiCloudAPIResponseException,
    PyiCloudTrustedDevicePromptException,
)
from pyicloud.hsa2_bridge import TrustedDeviceBridgeBootstrapper, _RawWebSocketClient


class ProxiedWebSocket(_RawWebSocketClient):
    """The trusted-device bridge's websocket (Apple's push host, for the
    2FA prompt) through the host's HTTPS proxy: the pinned client dials the
    host directly, which a cloud session cannot (its proxy resolves and
    admits every host; websocket.push.apple.com must be on the allowlist).
    Only the dial changes: a CONNECT tunnel, then the same TLS and upgrade.
    """

    def _open(self) -> ssl.SSLSocket:
        proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
        if not proxy:
            return super()._open()
        parsed = urlparse(self._url)
        if parsed.scheme != "wss" or not parsed.hostname:
            raise PyiCloudTrustedDevicePromptException(f"Unsupported websocket URL: {self._url}")
        port = parsed.port or 443
        p = urlparse(proxy)
        tunnel = socket.create_connection((p.hostname, p.port or 3128), self._timeout)
        tunnel.sendall(f"CONNECT {parsed.hostname}:{port} HTTP/1.1\r\nHost: {parsed.hostname}:{port}\r\n\r\n".encode("ascii"))
        reply = b""
        while b"\r\n\r\n" not in reply:
            chunk = tunnel.recv(4096)
            if not chunk:
                raise PyiCloudTrustedDevicePromptException("The proxy closed the websocket tunnel.")
            reply += chunk
        status = reply.split(b"\r\n", 1)[0].decode("iso-8859-1")
        if " 200" not in status:
            raise PyiCloudTrustedDevicePromptException(f"The proxy refused the websocket host: {status}")
        # From here the pinned client's own handshake, on the tunnel.
        real_create = socket.create_connection
        socket.create_connection = lambda *_a, **_k: tunnel
        try:
            return super()._open()
        finally:
            socket.create_connection = real_create


def validate(api, code):
    """Check Apple's code where it was sent. The pinned pyicloud (2026.10.1)
    requests an SMS with mode "sms" (base.py:1040) but validates it with the
    phone's push mode (base.py:1432), which Apple refuses when they differ:
    an SMS code is checked here with the mode it was requested with. A code
    the owner read off a trusted device is checked at the device endpoint,
    once, if the SMS check refuses it."""
    if api.two_factor_delivery_method != "sms":
        return api.validate_2fa_code(code)
    phone = api._trusted_phone_number()
    data = {"phoneNumber": phone.as_phone_number_payload(), "securityCode": {"code": code}, "mode": "sms"}
    headers = api._get_auth_headers({"Accept": "application/json, text/plain"})
    try:
        api.session.post(f"{api._auth_endpoint}/verify/phone/securitycode", json=data, headers=headers)
    except (PyiCloudAPIResponseException, PyiCloud2FARequiredException) as error:
        if not api._is_accepted_security_code_conflict(error.response):
            try:
                api._validate_trusted_device_code(code)
            except (PyiCloudAPIResponseException, PyiCloud2FARequiredException):
                return False
    api.trust_session()
    return not api.requires_2sa


mode, apple_id, cookies = sys.argv[1:4]
password = sys.stdin.readline().rstrip("\n")
api = PyiCloudService(apple_id, password, cookie_directory=cookies, authenticate=False)
del password
api._trusted_device_bridge = TrustedDeviceBridgeBootstrapper(websocket_factory=ProxiedWebSocket)
api.authenticate()

if mode == "login":
    fifo = sys.argv[4]
    if api.requires_2fa:
        # Apple sends nothing until asked: the pinned pyicloud starts the
        # trusted-device prompt here, or falls back to an SMS to the trusted
        # number when the prompt cannot start (2026-11-01: without this call
        # no code ever arrived).
        try:
            requested = api.request_2fa_code()
        except PyiCloudTrustedDevicePromptException:
            # The device prompt's bridge subscribed but Apple's push never
            # came back (2026-11-01, through the session's proxy). pyicloud
            # falls back to SMS only when the challenge's mode is "sms"; its
            # own SMS request needs only a trusted number, so ask for that
            # (the pinned 2026.10.1's _request_sms_2fa_code, base.py:1040).
            if api._trusted_phone_number() is not None:
                requested = api._request_sms_2fa_code(notice="the device prompt did not start")
            else:
                # No trusted number: a code Apple shows on a trusted device
                # still validates through the legacy device endpoint.
                print("icloud: the device prompt did not start and no trusted number is on file", file=sys.stderr, flush=True)
                requested = True
        if not requested:
            sys.exit(f"icloud: Apple offers no code delivery here ({api.two_factor_delivery_method})")
        where = {"trusted_device": "the owner's trusted devices", "sms": "the trusted phone number by SMS"}
        notice = api.two_factor_delivery_notice
        print(
            f"icloud: Apple sent a code to {where.get(api.two_factor_delivery_method, api.two_factor_delivery_method)}"
            + (f" ({notice})" if notice else "")
            + "; waiting for it",
            file=sys.stderr,
            flush=True,
        )
        with open(fifo) as f:
            code = f.readline().strip()
        if not validate(api, code):
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
