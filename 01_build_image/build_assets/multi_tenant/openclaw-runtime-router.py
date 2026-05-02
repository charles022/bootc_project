#!/usr/bin/env python3
# openclaw-runtime-router - Phase-4 message dispatcher.
# Concept: docs/concepts/messaging_interface.md
#
# Reads JSONL envelopes from the pod-local message bus (written by the
# messaging-bridge sidecars), matches the body against a strict verb table,
# and translates each match into a UNIX-socket call to the per-tenant
# openclaw-provisioner socket bind-mounted at /run/agentctl/agentctl.sock.
# Replies are posted back to the originating bridge via {"op":"reply",...}.
#
# This replaces the Phase-0 openclaw-runtime-stub.sh idle loop. There is no
# free-text parsing, no shell execution, no LLM. The verb table is small
# and hand-coded so an adversarial allow-listed sender cannot escalate
# beyond the verbs the host has explicitly authorized.

import json
import os
import pathlib
import shlex
import socket
import sys
import threading
import time
from datetime import datetime, timezone

TENANT = os.environ.get("OPENCLAW_TENANT", "")
AGENT = os.environ.get("OPENCLAW_AGENT", "")
MSGBUS_DIR = pathlib.Path(os.environ.get("OPENCLAW_MSGBUS_DIR", "/run/messaging-bridge"))
INBOUND_SOCK = pathlib.Path(os.environ.get("OPENCLAW_MSGBUS_INBOUND", str(MSGBUS_DIR / "inbound.sock")))
AGENTCTL = pathlib.Path(os.environ.get("OPENCLAW_AGENTCTL_SOCKET", "/run/agentctl/agentctl.sock"))
DEFAULT_RUNTIME = os.environ.get(
    "OPENCLAW_DEFAULT_RUNTIME_IMAGE",
    "quay.io/m0ranmcharles/fedora_init:openclaw-runtime",
)

HELP_TEXT = """\
Available commands (one per message):
  create-agent <name> [<environment-image>] [<credential>...]
  list-agents
  stop-agent <name>
  status [<name>]
  help

Examples:
  create-agent rust-coder quay.io/m0ranmcharles/fedora_init:onboarding-env codex
  status main
"""


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg):
    sys.stdout.write(f"openclaw-runtime-router: {msg}\n")
    sys.stdout.flush()


def err(msg):
    sys.stderr.write(f"openclaw-runtime-router: error: {msg}\n")
    sys.stderr.flush()


def call_agentctl(req, timeout=15):
    if not AGENTCTL.exists():
        return {"ok": False, "error": f"agentctl socket not present at {AGENTCTL}"}
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(str(AGENTCTL))
        s.sendall((json.dumps(req) + "\n").encode("utf-8"))
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        line = buf.split(b"\n", 1)[0].decode("utf-8", errors="replace")
    finally:
        s.close()
    try:
        return json.loads(line) if line else {"ok": False, "error": "empty reply"}
    except json.JSONDecodeError as e:
        return {"ok": False, "error": f"invalid JSON: {e}"}


def post_reply_to_bridge(envelope, body, subject="re: openclaw"):
    """Connect to the per-transport outbound socket owned by the originating
    bridge (e.g. /run/messaging-bridge/outbound-email.sock for transport
    'email'), push the reply, read the ack, close. The bridge owns the
    outbound socket because only it knows the transport-specific send call."""
    transport = envelope.get("bridge") or envelope.get("transport") or ""
    if not transport:
        err("reply: envelope missing 'bridge' / 'transport'")
        return
    sock_path = MSGBUS_DIR / f"outbound-{transport}.sock"
    op = {
        "op": "reply",
        "to": envelope.get("from", ""),
        "subject": subject,
        "body": body,
        "transport": transport,
    }
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect(str(sock_path))
        s.sendall((json.dumps(op) + "\n").encode("utf-8"))
        try:
            s.recv(4096)
        except Exception:
            pass
        s.close()
        log(f"AUDIT messaging_outbound transport={transport!r} to={op['to']!r}")
    except Exception as exc:
        err(f"reply via {sock_path}: {exc}")


def dispatch(envelope):
    """Match the message body against the verb table and return reply text."""
    body = (envelope.get("body") or "").strip()
    if not body:
        return "(empty message; send `help`)"
    try:
        argv = shlex.split(body)
    except ValueError as exc:
        return f"could not parse message: {exc}"
    verb = argv[0].lower()

    if verb == "help":
        return HELP_TEXT

    if verb == "list-agents":
        reply = call_agentctl({"op": "agent_list"})
        if not reply.get("ok"):
            return f"agentctl denied: {reply.get('error')}"
        agents = reply.get("agents", [])
        if not agents:
            return "no agents."
        lines = []
        for a in agents:
            tag = " (main)" if a.get("is_main") else ""
            lines.append(f"  {a.get('id')}{tag} status={a.get('status')}")
        return "agents:\n" + "\n".join(lines)

    if verb == "status":
        if len(argv) >= 2:
            reply = call_agentctl({"op": "agent_inspect", "name": argv[1]})
            if not reply.get("ok"):
                return f"agentctl denied: {reply.get('error')}"
            a = reply.get("agent", {})
            return (
                f"{a.get('id')}: status={a.get('status')} "
                f"is_main={a.get('is_main')} messaging={a.get('messaging')}"
            )
        # No name given -> same as list-agents.
        return dispatch({**envelope, "body": "list-agents"})

    if verb == "stop-agent":
        if len(argv) < 2:
            return "stop-agent: missing <name>"
        reply = call_agentctl({"op": "agent_stop", "name": argv[1]})
        if not reply.get("ok"):
            return f"agentctl denied: {reply.get('error')}"
        return f"stopped agent {argv[1]}"

    if verb == "create-agent":
        if len(argv) < 2:
            return "create-agent: missing <name>"
        name = argv[1]
        env_image = argv[2] if len(argv) >= 3 else None
        credentials = argv[3:] if len(argv) >= 4 else []
        if env_image is None:
            return "create-agent: missing <environment-image> (must be in policy.allowed_images.environments)"
        req = {
            "op": "agent_create",
            "name": name,
            "runtime": DEFAULT_RUNTIME,
            "environment": env_image,
            "credentials": credentials,
            "volumes": [],
            "ingress": [],
            "messaging": [],
        }
        reply = call_agentctl(req)
        if not reply.get("ok"):
            return f"agentctl denied: {reply.get('error')}"
        return f"created agent {name} (status={reply.get('agent', {}).get('status')})"

    return f"unknown command {verb!r}; send `help` for the verb list"


def handle_envelope(envelope):
    log(f"AUDIT messaging_inbound transport={envelope.get('bridge')!r} from={envelope.get('from')!r}")
    try:
        body = dispatch(envelope)
    except Exception as exc:
        err(f"dispatch failed: {exc}")
        body = f"internal error: {exc}"
    post_reply_to_bridge(envelope, body)


def inbound_listener():
    """Listen on /run/messaging-bridge/inbound.sock. Bridges connect here
    to push one envelope per connection."""
    if INBOUND_SOCK.exists() or INBOUND_SOCK.is_symlink():
        try:
            INBOUND_SOCK.unlink()
        except FileNotFoundError:
            pass
    INBOUND_SOCK.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(str(INBOUND_SOCK))
    os.chmod(str(INBOUND_SOCK), 0o660)
    s.listen(8)
    log(f"listening for inbound envelopes on {INBOUND_SOCK}")
    while True:
        conn, _ = s.accept()
        threading.Thread(target=handle_inbound_conn, args=(conn,), daemon=True).start()


def handle_inbound_conn(conn):
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
        envelope = json.loads(line)
        if envelope.get("event") != "message":
            return
        handle_envelope(envelope)
    except Exception as exc:
        err(f"inbound: {exc}")
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
    log(f"agentctl socket: {AGENTCTL}")
    log(f"inbound socket: {INBOUND_SOCK}")
    # Wait briefly for the agentctl socket to appear; the provisioner
    # creates per-tenant sockets at startup, but rendezvous is best-effort.
    for _ in range(30):
        if AGENTCTL.exists():
            break
        time.sleep(1)
    inbound_listener()


if __name__ == "__main__":
    main()
