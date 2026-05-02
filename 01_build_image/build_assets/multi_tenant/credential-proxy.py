#!/usr/bin/env python3
# credential-proxy - pod-local credential broker proxy for an OpenClaw tenant.
# Concept: docs/concepts/credential_broker.md
#
# Phase 2 design:
#   - Connects upstream to /run/credential-proxy/broker.sock (mounted from
#     the host: /run/openclaw-broker/tenants/<tenant>.sock).
#   - Exposes a pod-local agent socket at /run/credential-proxy/agent.sock.
#   - Tenant agents (openclaw-runtime, dev-env) connect to the agent socket
#     and call: {"op":"credential_request","agent":"...","id":"..."}.
#   - The proxy forwards the request to the broker; the broker checks the
#     grant table and either returns the plaintext value or denies.
#   - The proxy holds no master credentials. Its only privilege is to forward
#     calls on behalf of the tenant the broker socket already binds it to.
#
# Configuration (env, set by the Quadlet template):
#   OPENCLAW_TENANT             tenant name (required)
#   OPENCLAW_BROKER_SOCKET      default /run/credential-proxy/broker.sock
#   OPENCLAW_AGENT_SOCKET       default /run/credential-proxy/agent.sock

import json
import os
import pathlib
import signal
import socket
import sys
import threading
from datetime import datetime, timezone


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg):
    sys.stdout.write(f"credential-proxy: {msg}\n")
    sys.stdout.flush()


def err(msg):
    sys.stderr.write(f"credential-proxy: error: {msg}\n")
    sys.stderr.flush()


TENANT = os.environ.get("OPENCLAW_TENANT", "")
BROKER_SOCK = pathlib.Path(os.environ.get("OPENCLAW_BROKER_SOCKET", "/run/credential-proxy/broker.sock"))
AGENT_SOCK = pathlib.Path(os.environ.get("OPENCLAW_AGENT_SOCKET", "/run/credential-proxy/agent.sock"))

# Wire protocol constants
MAX_REQUEST = 1 << 20


def recv_line(conn):
    chunks = []
    total = 0
    while True:
        b = conn.recv(4096)
        if not b:
            return b"".join(chunks).decode("utf-8") if chunks else None
        chunks.append(b)
        total += len(b)
        if b"\n" in b:
            data = b"".join(chunks)
            line, _, _ = data.partition(b"\n")
            return line.decode("utf-8")
        if total > MAX_REQUEST:
            raise ValueError("request too large")


def send_line(conn, obj):
    conn.sendall((json.dumps(obj) + "\n").encode("utf-8"))


def call_broker(req):
    """Send one JSONL request to the broker upstream, return the parsed reply."""
    if not BROKER_SOCK.exists():
        return {"ok": False, "error": f"broker socket not present at {BROKER_SOCK}"}
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(str(BROKER_SOCK))
        send_line(s, req)
        line = recv_line(s)
        if not line:
            return {"ok": False, "error": "broker closed connection without reply"}
        try:
            return json.loads(line)
        except json.JSONDecodeError as e:
            return {"ok": False, "error": f"broker returned invalid JSON: {e}"}
    finally:
        s.close()


def handle_agent_connection(conn):
    try:
        line = recv_line(conn)
        if not line:
            return
        try:
            req = json.loads(line)
        except json.JSONDecodeError as e:
            send_line(conn, {"ok": False, "error": f"invalid JSON: {e}"})
            return
        op = req.get("op")
        if op not in {"credential_request", "agent_grants", "ping"}:
            send_line(conn, {"ok": False, "error": f"proxy refuses op {op!r}"})
            return
        # The proxy never relays admin verbs upstream.
        upstream = call_broker(req)
        send_line(conn, upstream)
    except Exception as e:
        try:
            send_line(conn, {"ok": False, "error": str(e), "type": type(e).__name__})
        except Exception:
            pass
    finally:
        try:
            conn.close()
        except Exception:
            pass


def open_agent_listener():
    if AGENT_SOCK.exists() or AGENT_SOCK.is_symlink():
        try:
            AGENT_SOCK.unlink()
        except FileNotFoundError:
            pass
    AGENT_SOCK.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(str(AGENT_SOCK))
    os.chmod(str(AGENT_SOCK), 0o660)
    s.listen(8)
    return s


def shutdown(*_):
    log("stopping")
    try:
        AGENT_SOCK.unlink()
    except FileNotFoundError:
        pass
    sys.exit(0)


def main():
    if not TENANT:
        err("OPENCLAW_TENANT is required")
        sys.exit(1)

    log(f"starting at {now_iso()} tenant={TENANT}")
    log(f"upstream broker socket: {BROKER_SOCK}")
    log(f"agent socket: {AGENT_SOCK}")

    # Don't fail if the broker socket isn't present yet. The container is
    # configured Restart=on-failure, but missing-broker is a recoverable state:
    # we still want the agent socket open so callers get a clear error rather
    # than ECONNREFUSED at the pod boundary.

    listener = open_agent_listener()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    while True:
        conn, _ = listener.accept()
        t = threading.Thread(target=handle_agent_connection, args=(conn,), daemon=True)
        t.start()


if __name__ == "__main__":
    main()
