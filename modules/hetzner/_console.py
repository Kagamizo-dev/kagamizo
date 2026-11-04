"""jingzo-host's console as a PNG: Hetzner's request_console (the pinned API,
catalog/_json/hetzner-api.json: POST /servers/{id}/actions/request_console,
which answers a wss_url and a VNC password), then RFB 3.8 over that
websocket (RFC 6143): VNC authentication, one full raw framebuffer.

    _console.py SERVER_NAME OUT.png        HCLOUD_TOKEN in the environment

It only looks: one shift key press to wake a blanked screen, no other input.
"""

import json
import os
import struct
import sys
import urllib.request

from Crypto.Cipher import DES
from PIL import Image
from websockets.sync.client import connect

API = "https://api.hetzner.cloud/v1"


def api(method, path, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + os.environ["HCLOUD_TOKEN"], "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


class Stream:
    """A byte stream over websocket messages."""

    def __init__(self, ws):
        self.ws, self.buf = ws, b""

    def read(self, n):
        while len(self.buf) < n:
            m = self.ws.recv(timeout=30)
            self.buf += m if isinstance(m, bytes) else m.encode("latin-1")
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, data):
        self.ws.send(data)


def vnc_response(password, challenge):
    # VNC's DES key: the password's first 8 bytes, each byte's bits reversed.
    key = bytes(int(f"{b:08b}"[::-1], 2) for b in password.encode("latin-1")[:8].ljust(8, b"\0"))
    return DES.new(key, DES.MODE_ECB).encrypt(challenge)


def main():
    name, out = sys.argv[1:3]
    servers = api("GET", f"/servers?name={name}")["servers"]
    if len(servers) != 1:
        sys.exit(f"host-console: {len(servers)} servers named {name}")
    console = api("POST", f"/servers/{servers[0]['id']}/actions/request_console")
    with connect(console["wss_url"], subprotocols=["binary"], open_timeout=30, max_size=None) as ws:
        s = Stream(ws)
        s.read(12)  # the server's version
        s.send(b"RFB 003.008\n")
        types = s.read(s.read(1)[0])
        if 2 in types:
            s.send(b"\x02")
            s.send(vnc_response(console["password"], s.read(16)))
        elif 1 in types:
            s.send(b"\x01")
        else:
            sys.exit(f"host-console: no security type it speaks: {list(types)}")
        if struct.unpack(">I", s.read(4))[0] != 0:
            sys.exit("host-console: the console refused the password")
        s.send(b"\x01")  # ClientInit: shared
        w, h = struct.unpack(">HH", s.read(4))
        s.read(16)
        s.read(struct.unpack(">I", s.read(4))[0])
        # 32 bits a pixel, true colour, little-endian, red at bit 16.
        s.send(struct.pack(">BxxxBBBBHHHBBBxxx", 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
        s.send(struct.pack(">BxHi", 2, 1, 0))  # SetEncodings: raw only
        s.send(struct.pack(">BBxxI", 4, 1, 0xFFE1) + struct.pack(">BBxxI", 4, 0, 0xFFE1))
        s.send(struct.pack(">BBHHHH", 3, 0, 0, 0, w, h))
        frame = bytearray(w * h * 4)
        while True:
            kind = s.read(1)[0]
            if kind == 0:
                (count,) = struct.unpack(">xH", s.read(3))
                for _ in range(count):
                    x, y, rw, rh, enc = struct.unpack(">HHHHi", s.read(12))
                    if enc != 0:
                        sys.exit(f"host-console: unexpected encoding {enc}")
                    data = s.read(rw * rh * 4)
                    for row in range(rh):
                        start = ((y + row) * w + x) * 4
                        frame[start : start + rw * 4] = data[row * rw * 4 : (row + 1) * rw * 4]
                break
            elif kind == 1:
                _, n = struct.unpack(">xHH", s.read(5))
                s.read(6 * n)
            elif kind == 2:
                pass
            elif kind == 3:
                s.read(3)
                s.read(struct.unpack(">I", s.read(4))[0])
            else:
                sys.exit(f"host-console: unexpected message {kind}")
    Image.frombytes("RGB", (w, h), bytes(frame), "raw", "BGRX").save(out)
    print(f"host-console: {w}x{h} written to {out}")


main()
