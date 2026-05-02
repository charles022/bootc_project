#!/usr/bin/env python3
# messaging-bridge-signal - per-pod Signal transport for Phase 4.
# Concept: docs/concepts/messaging_interface.md
#
# Wire model:
#   - Fetches the tenant's `signal/main` credential via the per-tenant
#     broker socket (bind-mounted at /run/credential-proxy/broker.sock).
#   - Credential payload is JSON:
#       {
#         "username": "+15551234567",
#         "data_archive": "<base64 tar.gz of signal-cli local state>",
#         "allow_senders": ["+15557654321", ...]
#       }
#     The data_archive is unpacked into ~/.local/share/signal-cli at startup
#     so signal-cli can authenticate as the linked device.
#   - Drives `signal-cli jsonRpc` (line-delimited JSON-RPC over stdio) for
#     inbound and outbound. For each `receive` notification from an
#     allow-listed sender, opens a short-lived connection to
#     /run/messaging-bridge/inbound.sock and pushes one envelope.
#   - Listens on /run/messaging-bridge/outbound-signal.sock for
#     {"op":"reply", "to":"+15557654321", "body":"..."} envelopes posted by
#     the runtime; sends them via the JSON-RPC daemon's `send` method.
#
# Environment:
#   OPENCLAW_TENANT             tenant name (required)
#   OPENCLAW_AGENT              agent name (required)
#   OPENCLAW_BROKER_SOCKET      default /run/credential-proxy/broker.sock
#   OPENCLAW_MSGBUS_INBOUND     default /run/messaging-bridge/inbound.sock
#   OPENCLAW_MSGBUS_OUTBOUND    default /run/messaging-bridge/outbound-signal.sock
#   OPENCLAW_SIGNAL_CREDENTIAL  short id, default "signal"

import base64
import io
import json
import os
import pathlib
import socket
import subprocess
import sys
import tarfile
import threading
import time
from datetime import datetime, timezone

TENANT = os.environ.get("OPENCLAW_TENANT", "")
AGENT = os.environ.get("OPENCLAW_AGENT", "")
BROKER_SOCK = pathlib.Path(os.environ.get("OPENCLAW_BROKER_SOCKET", "/run/credential-proxy/broker.sock"))
INBOUND_SOCK = pathlib.Path(os.environ.get("OPENCLAW_MSGBUS_INBOUND", "/run/messaging-bridge/inbound.sock"))
OUTBOUND_SOCK = pathlib.Path(os.environ.get("OPENCLAW_MSGBUS_OUTBOUND", "/run/messaging-bridge/outbound-signal.sock"))
CRED_ID = os.environ.get("OPENCLAW_SIGNAL_CREDENTIAL", "signal")
SIGNAL_HOME = pathlib.Path.home() / ".local" / "share" / "signal-cli"


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg):
    sys.stdout.write(f"messaging-bridge-signal: {msg}\n")
    sys.stdout.flush()


def err(msg):
    sys.stderr.write(f"messaging-bridge-signal: error: {msg}\n")
    sys.stderr.flush()


def fetch_credential():
    full_id = CRED_ID if "/" in CRED_ID else f"{TENANT}/{CRED_ID}/main"
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    try:
        s.connect(str(BROKER_SOCK))
        req = {"op": "credential_request", "agent": AGENT, "id": full_id}
        s.sendall((json.dumps(req) + "\n").encode("utf-8"))
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        line = buf.split(b"\n", 1)[0].decode("utf-8")
    finally:
        s.close()
    reply = json.loads(line)
    if not reply.get("ok"):
        raise RuntimeError(f"broker denied {full_id}: {reply.get('error')}")
    return json.loads(reply["value"])


def install_signal_state(cred):
    SIGNAL_HOME.mkdir(parents=True, exist_ok=True)
    archive = base64.b64decode(cred["data_archive"])
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tar:
        tar.extractall(SIGNAL_HOME)
    log(f"installed signal-cli state at {SIGNAL_HOME}")


def emit_event(envelope):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(str(INBOUND_SOCK))
        s.sendall((json.dumps(envelope) + "\n").encode("utf-8"))
        s.close()
    except Exception as exc:
        err(f"emit failed: {exc}")


class SignalDaemon:
    """Spawns signal-cli in JSON-RPC mode and provides send/receive
    primitives over its stdio. signal-cli writes one JSON object per line
    in this mode."""

    def __init__(self, username):
        self.username = username
        self.proc = None
        self.next_id = 1
        self.lock = threading.Lock()
        self.pending = {}

    def start(self):
        cmd = [
            "signal-cli",
            "-u", self.username,
            "--config", str(SIGNAL_HOME),
            "jsonRpc",
        ]
        log(f"spawning: {' '.join(cmd)}")
        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._stderr_drain, daemon=True).start()

    def _reader(self):
        for line in self.proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if "id" in obj and obj.get("id") in self.pending:
                self.pending.pop(obj["id"]).append(obj)
                continue
            # otherwise: notification (e.g. inbound message)
            self._on_notification(obj)
        log("signal-cli stdout closed")

    def _stderr_drain(self):
        for line in self.proc.stderr:
            line = line.rstrip()
            if line:
                err(f"signal-cli: {line}")

    def _on_notification(self, obj):
        # signal-cli emits {"jsonrpc":"2.0","method":"receive","params":{...}}
        if obj.get("method") != "receive":
            return
        params = obj.get("params") or {}
        envelope = params.get("envelope") or {}
        sender = envelope.get("sourceNumber") or envelope.get("source") or ""
        msg = envelope.get("dataMessage") or {}
        body = msg.get("message")
        if body is None:
            return
        ts = envelope.get("timestamp")
        ENV.append({
            "from": sender,
            "body": body,
            "ts_signal": ts,
        })

    def call(self, method, params):
        with self.lock:
            req_id = self.next_id
            self.next_id += 1
            req = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
            mailbox = []
            self.pending[req_id] = mailbox
            self.proc.stdin.write(json.dumps(req) + "\n")
            self.proc.stdin.flush()
        for _ in range(50):
            time.sleep(0.1)
            if mailbox:
                return mailbox[0]
        return {"error": "timeout waiting for signal-cli reply"}


# Inbound notifications dropped here by SignalDaemon._on_notification, drained
# by inbound_loop and dispatched to the pod-local message bus.
ENV = []


def inbound_loop(allow_senders):
    allow = {a for a in (allow_senders or [])}
    while True:
        if not ENV:
            time.sleep(0.5)
            continue
        item = ENV.pop(0)
        sender = item["from"]
        if allow and sender not in allow:
            log(f"AUDIT messaging_inbound_dropped sender={sender!r}")
            continue
        envelope = {
            "event": "message",
            "transport": "signal",
            "bridge": "signal",
            "from": sender,
            "subject": "",
            "body": item["body"],
            "ts": now_iso(),
        }
        log(f"inbound from={sender}")
        emit_event(envelope)


def outbound_listener(daemon):
    if OUTBOUND_SOCK.exists() or OUTBOUND_SOCK.is_symlink():
        try:
            OUTBOUND_SOCK.unlink()
        except FileNotFoundError:
            pass
    OUTBOUND_SOCK.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(str(OUTBOUND_SOCK))
    os.chmod(str(OUTBOUND_SOCK), 0o660)
    s.listen(8)
    log(f"listening for replies on {OUTBOUND_SOCK}")
    while True:
        conn, _ = s.accept()
        threading.Thread(target=handle_outbound_conn, args=(conn, daemon), daemon=True).start()


def handle_outbound_conn(conn, daemon):
    try:
        buf = b""
        while b"\n" not in buf:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buf += chunk
        if not buf:
            return
        line = buf.split(b"\n", 1)[0].decode("utf-8", errors="replace")
        op = json.loads(line)
        if op.get("op") != "reply":
            conn.sendall(b'{"ok":false,"error":"unknown op"}\n')
            return
        to = op.get("to")
        body = op.get("body", "")
        if not to:
            conn.sendall(b'{"ok":false,"error":"missing to"}\n')
            return
        result = daemon.call("send", {"recipient": [to], "message": body})
        log(f"AUDIT messaging_outbound to={to!r}")
        conn.sendall((json.dumps({"ok": "error" not in result, "result": result}) + "\n").encode("utf-8"))
    except Exception as exc:
        err(f"msgbus handle: {exc}")
        try:
            conn.sendall((json.dumps({"ok": False, "error": str(exc)}) + "\n").encode("utf-8"))
        except Exception:
            pass
    finally:
        try:
            conn.close()
        except Exception:
            pass


def main():
    if not TENANT or not AGENT:
        err("OPENCLAW_TENANT and OPENCLAW_AGENT are required")
        sys.exit(1)
    log(f"starting tenant={TENANT} agent={AGENT}")
    for _ in range(30):
        if BROKER_SOCK.exists():
            break
        time.sleep(1)
    cred = fetch_credential()
    install_signal_state(cred)
    daemon = SignalDaemon(cred["username"])
    daemon.start()
    threading.Thread(target=inbound_loop, args=(cred.get("allow_senders") or [],), daemon=True).start()
    outbound_listener(daemon)


if __name__ == "__main__":
    main()
