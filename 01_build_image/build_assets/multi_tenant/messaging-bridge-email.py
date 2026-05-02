#!/usr/bin/env python3
# messaging-bridge-email - per-pod email transport for Phase 4.
# Concept: docs/concepts/messaging_interface.md
#
# Wire model:
#   - Fetches the tenant's `email/main` credential through the pod-local
#     credential-proxy at /run/credential-proxy/agent.sock (NOT directly from
#     the broker; the credential-proxy boundary is reused so that the per-tenant
#     UID gating remains the authoritative auth boundary).
#   - The credential payload is JSON:
#       {
#         "imap_host": "imap.example.com", "imap_port": 993,
#         "smtp_host": "smtp.example.com", "smtp_port": 465,
#         "username": "alice@example.com",
#         "password": "...",
#         "from_addr": "alice@example.com",
#         "allow_senders": ["a@example.com", "b@example.com"]
#       }
#   - On each new INBOX message from an allow-listed sender, opens a
#     short-lived connection to /run/messaging-bridge/inbound.sock (the
#     runtime listens on this) and writes one JSONL envelope:
#       {"event":"message","transport":"email","bridge":"email",
#        "from":"...","subject":"...","body":"...","ts":"..."}
#   - Listens on /run/messaging-bridge/outbound-email.sock for
#     {"op":"reply","to":"...","subject":"...","body":"..."} envelopes
#     posted by the runtime, and sends them via SMTP.
#
# Environment (set by the Quadlet template):
#   OPENCLAW_TENANT               tenant name (required)
#   OPENCLAW_AGENT                agent name (required)
#   OPENCLAW_BROKER_SOCKET        default /run/credential-proxy/broker.sock
#   OPENCLAW_MSGBUS_INBOUND       default /run/messaging-bridge/inbound.sock
#   OPENCLAW_MSGBUS_OUTBOUND      default /run/messaging-bridge/outbound-email.sock
#   OPENCLAW_EMAIL_CREDENTIAL     short id, default "email"
#   OPENCLAW_EMAIL_POLL_SECONDS   default 30

import email
import email.message
import imaplib
import json
import os
import pathlib
import smtplib
import socket
import ssl
import sys
import threading
import time
from datetime import datetime, timezone

TENANT = os.environ.get("OPENCLAW_TENANT", "")
AGENT = os.environ.get("OPENCLAW_AGENT", "")
BROKER_SOCK = pathlib.Path(os.environ.get("OPENCLAW_BROKER_SOCKET", "/run/credential-proxy/broker.sock"))
INBOUND_SOCK = pathlib.Path(os.environ.get("OPENCLAW_MSGBUS_INBOUND", "/run/messaging-bridge/inbound.sock"))
OUTBOUND_SOCK = pathlib.Path(os.environ.get("OPENCLAW_MSGBUS_OUTBOUND", "/run/messaging-bridge/outbound-email.sock"))
CRED_ID = os.environ.get("OPENCLAW_EMAIL_CREDENTIAL", "email")
POLL_SECONDS = int(os.environ.get("OPENCLAW_EMAIL_POLL_SECONDS", "30"))


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg):
    sys.stdout.write(f"messaging-bridge-email: {msg}\n")
    sys.stdout.flush()


def err(msg):
    sys.stderr.write(f"messaging-bridge-email: error: {msg}\n")
    sys.stderr.flush()


def fetch_credential():
    """Resolve the tenant's email credential through the per-tenant broker
    socket. Returns the parsed JSON credential value, or raises."""
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
    raw = reply.get("value", "")
    return json.loads(raw)


def emit_event(envelope):
    """Best-effort push to the runtime's inbound socket. Drops on connect
    failure so a transient runtime restart does not crash the bridge."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(str(INBOUND_SOCK))
        s.sendall((json.dumps(envelope) + "\n").encode("utf-8"))
        s.close()
    except Exception as exc:
        err(f"emit failed: {exc}")


def imap_loop(cred):
    seen = set()
    allow = set(cred.get("allow_senders", []) or [])
    while True:
        try:
            ctx = ssl.create_default_context()
            with imaplib.IMAP4_SSL(cred["imap_host"], int(cred.get("imap_port", 993)), ssl_context=ctx) as M:
                M.login(cred["username"], cred["password"])
                M.select("INBOX", readonly=False)
                typ, data = M.search(None, "UNSEEN")
                if typ != "OK":
                    log(f"imap search returned {typ}; sleeping")
                else:
                    for num in data[0].split():
                        if num in seen:
                            continue
                        seen.add(num)
                        typ, msg_data = M.fetch(num, "(RFC822)")
                        if typ != "OK" or not msg_data or not msg_data[0]:
                            continue
                        msg = email.message_from_bytes(msg_data[0][1])
                        sender_addr = email.utils.parseaddr(msg.get("From", ""))[1].lower()
                        if allow and sender_addr not in {a.lower() for a in allow}:
                            log(f"rejecting message from non-allow-listed sender {sender_addr!r}")
                            audit_drop(sender_addr, msg.get("Subject", ""))
                            continue
                        body = extract_text_body(msg)
                        envelope = {
                            "event": "message",
                            "transport": "email",
                            "bridge": "email",
                            "from": sender_addr,
                            "subject": msg.get("Subject", ""),
                            "body": body,
                            "ts": now_iso(),
                        }
                        log(f"inbound from={sender_addr} subject={envelope['subject']!r}")
                        emit_event(envelope)
        except Exception as exc:
            err(f"imap loop: {exc}")
        time.sleep(POLL_SECONDS)


def extract_text_body(msg):
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                payload = part.get_payload(decode=True) or b""
                charset = part.get_content_charset() or "utf-8"
                try:
                    return payload.decode(charset, errors="replace")
                except Exception:
                    return payload.decode("utf-8", errors="replace")
        return ""
    payload = msg.get_payload(decode=True) or b""
    charset = msg.get_content_charset() or "utf-8"
    try:
        return payload.decode(charset, errors="replace")
    except Exception:
        return payload.decode("utf-8", errors="replace")


def audit_drop(sender, subject):
    log(f'AUDIT messaging_inbound_dropped sender={sender!r} subject={subject!r}')


def send_reply(cred, op):
    to = op.get("to")
    if not to:
        err("reply missing 'to'")
        return
    msg = email.message.EmailMessage()
    msg["From"] = cred.get("from_addr", cred["username"])
    msg["To"] = to
    msg["Subject"] = op.get("subject", "openclaw reply")
    msg.set_content(op.get("body", ""))
    ctx = ssl.create_default_context()
    smtp_port = int(cred.get("smtp_port", 465))
    if smtp_port == 465:
        with smtplib.SMTP_SSL(cred["smtp_host"], smtp_port, context=ctx) as S:
            S.login(cred["username"], cred["password"])
            S.send_message(msg)
    else:
        with smtplib.SMTP(cred["smtp_host"], smtp_port) as S:
            S.starttls(context=ctx)
            S.login(cred["username"], cred["password"])
            S.send_message(msg)
    log(f"AUDIT messaging_outbound to={to!r} subject={op.get('subject', '')!r}")


def outbound_listener(cred):
    """Open the per-transport outbound socket and accept reply envelopes
    from the runtime. One JSONL op per connection."""
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
        threading.Thread(target=handle_outbound_conn, args=(conn, cred), daemon=True).start()


def handle_outbound_conn(conn, cred):
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
        if op.get("op") == "reply":
            try:
                send_reply(cred, op)
                conn.sendall(b'{"ok":true}\n')
            except Exception as exc:
                err(f"send_reply: {exc}")
                conn.sendall((json.dumps({"ok": False, "error": str(exc)}) + "\n").encode("utf-8"))
        else:
            conn.sendall(b'{"ok":false,"error":"unknown op"}\n')
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
    # Wait briefly for the broker socket to come up; the pod's container
    # start order is best-effort, not strict.
    for _ in range(30):
        if BROKER_SOCK.exists():
            break
        time.sleep(1)
    cred = fetch_credential()
    log(f"resolved credential id={CRED_ID} for {cred.get('username')}")
    threading.Thread(target=imap_loop, args=(cred,), daemon=True).start()
    outbound_listener(cred)


if __name__ == "__main__":
    main()
