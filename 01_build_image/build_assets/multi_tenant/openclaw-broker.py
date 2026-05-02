#!/usr/bin/env python3
# openclaw-broker - host credential broker daemon for the OpenClaw multi-tenant platform.
# Concept: docs/concepts/credential_broker.md
# Reference: docs/reference/platformctl.md, docs/reference/systemd_units.md
#
# Phase 2 design:
#   - Encrypted credential store at /var/lib/openclaw-platform/broker/store.json
#     (Fernet: AES-128-CBC + HMAC-SHA256). Master key at broker/key.bin (0600 root).
#   - Grant table at broker/grants.json: tenant -> agent -> credential_id -> scope.
#   - Append-only audit log at broker/audit.log.
#   - Admin UNIX socket at /run/openclaw-broker/admin.sock (peer-UID 0 only).
#   - Per-tenant UNIX socket at /run/openclaw-broker/tenants/<tenant>.sock,
#     chowned to tenant_<tenant>:tenant_<tenant>, mode 0600. The credential-proxy
#     sidecar in each tenant pod mounts this file.
#   - JSONL wire protocol: each request is one JSON object terminated by '\n',
#     each response is one JSON object terminated by '\n'.
#
# Out of scope (planned):
#   - Sealed / HSM-backed master key
#   - Rotation policies, scheduled rotation
#   - OAuth / login-URL flow
#   - Replication

import json
import os
import pathlib
import pwd
import select
import signal
import socket
import struct
import sys
import threading
import time
from datetime import datetime, timezone

try:
    from cryptography.fernet import Fernet, InvalidToken
except ImportError:
    sys.stderr.write("openclaw-broker: error: python3-cryptography is required\n")
    sys.exit(1)

PLATFORM_ROOT = pathlib.Path(os.environ.get("OPENCLAW_PLATFORM_ROOT", "/var/lib/openclaw-platform"))
BROKER_DIR = PLATFORM_ROOT / "broker"
TENANTS_DIR = PLATFORM_ROOT / "tenants"
RUNTIME_DIR = pathlib.Path(os.environ.get("OPENCLAW_BROKER_RUNTIME_DIR", "/run/openclaw-broker"))
ADMIN_SOCK = RUNTIME_DIR / "admin.sock"
TENANT_SOCK_DIR = RUNTIME_DIR / "tenants"
KEY_FILE = BROKER_DIR / "key.bin"
STORE_FILE = BROKER_DIR / "store.json"
GRANTS_FILE = BROKER_DIR / "grants.json"
AUDIT_FILE = BROKER_DIR / "audit.log"
STATE_FILE = BROKER_DIR / "STATE"

SO_PEERCRED = getattr(socket, "SO_PEERCRED", 17)


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg):
    sys.stdout.write(f"openclaw-broker: {msg}\n")
    sys.stdout.flush()


def err(msg):
    sys.stderr.write(f"openclaw-broker: error: {msg}\n")
    sys.stderr.flush()


def ensure_dirs():
    BROKER_DIR.mkdir(parents=True, exist_ok=True, mode=0o750)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True, mode=0o755)
    TENANT_SOCK_DIR.mkdir(parents=True, exist_ok=True, mode=0o755)
    TENANTS_DIR.mkdir(parents=True, exist_ok=True, mode=0o755)


def load_or_create_key():
    if KEY_FILE.exists():
        return Fernet(KEY_FILE.read_bytes())
    key = Fernet.generate_key()
    KEY_FILE.write_bytes(key)
    KEY_FILE.chmod(0o600)
    return Fernet(key)


def load_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def save_json_atomic(path, data, mode=0o600):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True))
    tmp.chmod(mode)
    tmp.replace(path)


class Broker:
    def __init__(self):
        self.fernet = load_or_create_key()
        # store: {credential_id: {"tenant": str, "ciphertext": str, "created": iso, "updated": iso}}
        self.store = load_json(STORE_FILE, {})
        # grants: {tenant: {agent: {credential_id: scope}}}
        self.grants = load_json(GRANTS_FILE, {})
        self.lock = threading.RLock()

    # ---- audit ----

    def audit(self, **fields):
        fields["ts"] = now_iso()
        line = json.dumps(fields, sort_keys=True) + "\n"
        with AUDIT_FILE.open("a") as f:
            f.write(line)

    # ---- crypto ----

    def encrypt(self, plaintext):
        return self.fernet.encrypt(plaintext.encode("utf-8")).decode("ascii")

    def decrypt(self, ct):
        try:
            return self.fernet.decrypt(ct.encode("ascii")).decode("utf-8")
        except InvalidToken as e:
            raise RuntimeError("ciphertext failed integrity check") from e

    # ---- credential ops ----

    def credential_add(self, tenant, cred_id, value):
        if not cred_id.startswith(f"{tenant}/"):
            raise ValueError(f"credential id {cred_id!r} must start with {tenant!r}/")
        with self.lock:
            ct = self.encrypt(value)
            existing = self.store.get(cred_id)
            self.store[cred_id] = {
                "tenant": tenant,
                "ciphertext": ct,
                "created": existing["created"] if existing else now_iso(),
                "updated": now_iso(),
            }
            save_json_atomic(STORE_FILE, self.store)
            self.audit(op="credential_add", tenant=tenant, id=cred_id, replaced=bool(existing))

    def credential_get(self, tenant, cred_id):
        with self.lock:
            entry = self.store.get(cred_id)
            if not entry or entry["tenant"] != tenant:
                raise KeyError(cred_id)
            return self.decrypt(entry["ciphertext"])

    def credential_list(self, tenant=None):
        with self.lock:
            out = []
            for cid, entry in sorted(self.store.items()):
                if tenant is not None and entry["tenant"] != tenant:
                    continue
                out.append({
                    "id": cid,
                    "tenant": entry["tenant"],
                    "created": entry.get("created"),
                    "updated": entry.get("updated"),
                })
            return out

    def credential_delete(self, tenant, cred_id):
        with self.lock:
            entry = self.store.get(cred_id)
            if not entry or entry["tenant"] != tenant:
                raise KeyError(cred_id)
            del self.store[cred_id]
            save_json_atomic(STORE_FILE, self.store)
            # Also clean up any grants referencing this credential.
            removed_grants = 0
            t_grants = self.grants.get(tenant, {})
            for agent, agrants in list(t_grants.items()):
                if cred_id in agrants:
                    del agrants[cred_id]
                    removed_grants += 1
                if not agrants:
                    del t_grants[agent]
            if not t_grants and tenant in self.grants:
                del self.grants[tenant]
            save_json_atomic(GRANTS_FILE, self.grants)
            self.audit(op="credential_delete", tenant=tenant, id=cred_id, removed_grants=removed_grants)

    # ---- grant ops ----

    def grant_add(self, tenant, agent, cred_id, scope="read"):
        with self.lock:
            entry = self.store.get(cred_id)
            if not entry or entry["tenant"] != tenant:
                raise KeyError(cred_id)
            self.grants.setdefault(tenant, {}).setdefault(agent, {})[cred_id] = scope
            save_json_atomic(GRANTS_FILE, self.grants)
            self.audit(op="grant_add", tenant=tenant, agent=agent, id=cred_id, scope=scope)

    def grant_remove(self, tenant, agent, cred_id):
        with self.lock:
            t_grants = self.grants.get(tenant, {})
            agrants = t_grants.get(agent, {})
            if cred_id not in agrants:
                raise KeyError(cred_id)
            del agrants[cred_id]
            if not agrants:
                del t_grants[agent]
            if not t_grants and tenant in self.grants:
                del self.grants[tenant]
            save_json_atomic(GRANTS_FILE, self.grants)
            self.audit(op="grant_remove", tenant=tenant, agent=agent, id=cred_id)

    def grant_list(self, tenant=None):
        with self.lock:
            out = []
            for t, agents in sorted(self.grants.items()):
                if tenant is not None and t != tenant:
                    continue
                for agent, agrants in sorted(agents.items()):
                    for cid, scope in sorted(agrants.items()):
                        out.append({"tenant": t, "agent": agent, "id": cid, "scope": scope})
            return out

    def grant_check(self, tenant, agent, cred_id):
        with self.lock:
            return self.grants.get(tenant, {}).get(agent, {}).get(cred_id)

    # ---- agent-side request ----

    def credential_request(self, tenant, agent, cred_id):
        scope = self.grant_check(tenant, agent, cred_id)
        if not scope:
            self.audit(op="credential_request", tenant=tenant, agent=agent, id=cred_id, allowed=False, reason="no grant")
            raise PermissionError(f"no grant for {agent!r} on {cred_id!r}")
        value = self.credential_get(tenant, cred_id)
        self.audit(op="credential_request", tenant=tenant, agent=agent, id=cred_id, allowed=True, scope=scope)
        return value

    def agent_grants(self, tenant, agent):
        with self.lock:
            agrants = self.grants.get(tenant, {}).get(agent, {})
            return [{"id": cid, "scope": scope} for cid, scope in sorted(agrants.items())]

    # ---- audit ----

    def audit_tail(self, n=50):
        if not AUDIT_FILE.exists():
            return []
        try:
            with AUDIT_FILE.open("r") as f:
                lines = f.readlines()[-n:]
            return [json.loads(l) for l in lines if l.strip()]
        except Exception:
            return []


def get_peer_uid(conn):
    creds = conn.getsockopt(socket.SOL_SOCKET, SO_PEERCRED, struct.calcsize("3i"))
    pid, uid, gid = struct.unpack("3i", creds)
    return uid


def write_state(state):
    STATE_FILE.write_text(
        f"state={state}\n"
        f"phase=2\n"
        f"updated={now_iso()}\n"
    )
    STATE_FILE.chmod(0o640)


# ---- request handlers ----

def handle_admin_request(broker, req):
    op = req.get("op")
    if op == "credential_add":
        broker.credential_add(req["tenant"], req["id"], req["value"])
        return {"ok": True}
    if op == "credential_get":
        return {"ok": True, "value": broker.credential_get(req["tenant"], req["id"])}
    if op == "credential_list":
        return {"ok": True, "credentials": broker.credential_list(req.get("tenant"))}
    if op == "credential_delete":
        broker.credential_delete(req["tenant"], req["id"])
        return {"ok": True}
    if op == "credential_rotate":
        # Same shape as add: replace value, preserve created.
        broker.credential_add(req["tenant"], req["id"], req["value"])
        return {"ok": True}
    if op == "grant_add":
        broker.grant_add(req["tenant"], req["agent"], req["id"], req.get("scope", "read"))
        return {"ok": True}
    if op == "grant_remove":
        broker.grant_remove(req["tenant"], req["agent"], req["id"])
        return {"ok": True}
    if op == "grant_list":
        return {"ok": True, "grants": broker.grant_list(req.get("tenant"))}
    if op == "audit_tail":
        return {"ok": True, "entries": broker.audit_tail(int(req.get("n", 50)))}
    if op == "tenant_register":
        ensure_tenant_socket(req["tenant"], req["uid"], req["gid"])
        return {"ok": True}
    if op == "tenant_unregister":
        remove_tenant_socket(req["tenant"])
        return {"ok": True}
    if op == "ping":
        return {"ok": True, "phase": 2, "ts": now_iso()}
    raise ValueError(f"unknown admin op {op!r}")


def handle_agent_request(broker, tenant, req):
    op = req.get("op")
    if op == "credential_request":
        agent = req["agent"]
        cred_id = req["id"]
        return {"ok": True, "value": broker.credential_request(tenant, agent, cred_id)}
    if op == "agent_grants":
        agent = req["agent"]
        return {"ok": True, "grants": broker.agent_grants(tenant, agent)}
    if op == "ping":
        return {"ok": True, "tenant": tenant, "phase": 2, "ts": now_iso()}
    raise ValueError(f"unknown agent op {op!r}")


# ---- socket plumbing ----

class Listener:
    def __init__(self, kind, path, tenant=None):
        self.kind = kind          # "admin" or "tenant"
        self.path = pathlib.Path(path)
        self.tenant = tenant
        self.sock = None

    def open(self, owner_uid=0, owner_gid=0, mode=0o660):
        # Remove a stale socket file if any.
        if self.path.exists() or self.path.is_symlink():
            try:
                self.path.unlink()
            except FileNotFoundError:
                pass
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.setblocking(False)
        self.sock.bind(str(self.path))
        os.chown(str(self.path), owner_uid, owner_gid)
        os.chmod(str(self.path), mode)
        self.sock.listen(8)
        return self.sock

    def close(self):
        if self.sock:
            self.sock.close()
            self.sock = None
        try:
            self.path.unlink()
        except FileNotFoundError:
            pass


# Globals for tenant-socket bookkeeping (touched only by the main loop thread).
LISTENERS = {}        # path -> Listener
TENANT_BY_FD = {}     # accept-socket fd -> tenant name (None for admin)
BROKER = None         # set in main


def tenant_sock_path(tenant):
    return TENANT_SOCK_DIR / f"{tenant}.sock"


def ensure_tenant_socket(tenant, uid, gid):
    p = tenant_sock_path(tenant)
    if str(p) in LISTENERS:
        return  # already listening
    listener = Listener("tenant", p, tenant=tenant)
    listener.open(owner_uid=int(uid), owner_gid=int(gid), mode=0o600)
    LISTENERS[str(p)] = listener
    TENANT_BY_FD[listener.sock.fileno()] = tenant
    log(f"tenant socket opened: {p} (uid={uid} gid={gid})")


def remove_tenant_socket(tenant):
    p = tenant_sock_path(tenant)
    listener = LISTENERS.pop(str(p), None)
    if listener:
        TENANT_BY_FD.pop(listener.sock.fileno(), None)
        listener.close()
        log(f"tenant socket closed: {p}")


def discover_tenants():
    """Walk /var/lib/openclaw-platform/tenants/ and open a socket for each
    existing tenant_<name> account. Used at broker startup so a reboot does
    not require platformctl to re-register every tenant."""
    if not TENANTS_DIR.exists():
        return
    for child in TENANTS_DIR.iterdir():
        if not child.is_dir():
            continue
        name = child.name
        try:
            pwent = pwd.getpwnam(f"tenant_{name}")
        except KeyError:
            continue
        try:
            ensure_tenant_socket(name, pwent.pw_uid, pwent.pw_gid)
        except Exception as exc:
            err(f"could not open tenant socket for {name}: {exc}")


# ---- read / dispatch ----

def recv_line(conn, max_bytes=1 << 20):
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
        if total > max_bytes:
            raise ValueError("request too large")


def send_line(conn, obj):
    payload = json.dumps(obj).encode("utf-8") + b"\n"
    conn.sendall(payload)


def handle_connection(broker, conn, kind, tenant=None):
    try:
        line = recv_line(conn)
        if not line:
            return
        try:
            req = json.loads(line)
        except json.JSONDecodeError as e:
            send_line(conn, {"ok": False, "error": f"invalid JSON: {e}"})
            return

        if kind == "admin":
            uid = get_peer_uid(conn)
            if uid != 0:
                send_line(conn, {"ok": False, "error": f"admin socket requires UID 0 (got {uid})"})
                return
            try:
                resp = handle_admin_request(broker, req)
            except Exception as e:
                send_line(conn, {"ok": False, "error": str(e), "type": type(e).__name__})
                return
            send_line(conn, resp)
        else:
            try:
                resp = handle_agent_request(broker, tenant, req)
            except PermissionError as e:
                send_line(conn, {"ok": False, "error": str(e), "type": "PermissionError"})
                return
            except Exception as e:
                send_line(conn, {"ok": False, "error": str(e), "type": type(e).__name__})
                return
            send_line(conn, resp)
    finally:
        try:
            conn.close()
        except Exception:
            pass


def main_loop(broker):
    write_state("running")
    poller = select.poll()
    fd_to_listener = {}
    for path, listener in list(LISTENERS.items()):
        poller.register(listener.sock.fileno(), select.POLLIN)
        fd_to_listener[listener.sock.fileno()] = listener

    log(f"listening: admin={ADMIN_SOCK} tenants={[l.tenant for l in LISTENERS.values() if l.tenant]}")

    while True:
        # Re-register any newly opened tenant sockets.
        for fd, listener in list(fd_to_listener.items()):
            if str(listener.path) not in LISTENERS:
                poller.unregister(fd)
                del fd_to_listener[fd]
        for path, listener in LISTENERS.items():
            fd = listener.sock.fileno()
            if fd not in fd_to_listener:
                poller.register(fd, select.POLLIN)
                fd_to_listener[fd] = listener

        events = poller.poll(1000)
        for fd, _ev in events:
            listener = fd_to_listener.get(fd)
            if not listener:
                continue
            try:
                conn, _ = listener.sock.accept()
            except BlockingIOError:
                continue
            t = threading.Thread(
                target=handle_connection,
                args=(broker, conn, listener.kind, listener.tenant),
                daemon=True,
            )
            t.start()


def shutdown(*_):
    write_state("stopping")
    for listener in list(LISTENERS.values()):
        listener.close()
    sys.exit(0)


def main():
    ensure_dirs()
    broker = Broker()
    global BROKER
    BROKER = broker

    # Always open the admin socket.
    admin = Listener("admin", ADMIN_SOCK)
    admin.open(owner_uid=0, owner_gid=0, mode=0o660)
    LISTENERS[str(ADMIN_SOCK)] = admin
    TENANT_BY_FD[admin.sock.fileno()] = None

    discover_tenants()
    write_state("ready")

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    try:
        main_loop(broker)
    except KeyboardInterrupt:
        shutdown()


if __name__ == "__main__":
    main()
