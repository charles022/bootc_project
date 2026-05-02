#!/usr/bin/env python3
# openclaw-provisioner - host agent-provisioning daemon for the OpenClaw multi-tenant platform.
# Concept: docs/concepts/agent_provisioning.md
# Reference: docs/reference/platformctl.md, docs/reference/agentctl.md
#
# Phase 3 design:
#   - Per-tenant policy at /var/lib/openclaw-platform/tenants/<tenant>/policy/policy.yaml
#     constrains every request: allowed_images, allowed_credentials, allowed_networks,
#     limits (max_agents, max_running_agents, ...), forbidden flags.
#   - Admin UNIX socket at /run/openclaw-provisioner/admin.sock (peer-UID 0).
#   - Per-tenant UNIX socket at /run/openclaw-provisioner/tenants/<tenant>.sock
#     (chowned to tenant_<tenant>:tenant_<tenant>, mode 0600). The
#     openclaw-runtime container in each tenant pod mounts it so its agentctl
#     CLI can call us.
#   - Renders agent Quadlets from /var/lib/openclaw-platform/templates/agent_quadlet/
#     into /etc/containers/systemd/users/<UID>/, runs daemon-reload, then
#     systemctl --user --machine=tenant_<tenant>@ start <agent>-pod.service.
#   - Records each agent at tenants/<tenant>/agents/<agent>.json per the §15.4 object model.
#   - JSONL wire protocol, same shape as the broker.
#
# Out of scope (still planned, called out in docs):
#   - agentctl create-env (build new env images on demand)
#   - per-agent CPU / memory cgroup enforcement (recorded but not enforced)
#   - messaging-driven creation

import errno
import grp
import json
import os
import pathlib
import pwd
import re
import select
import shlex
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

PLATFORM_ROOT = pathlib.Path(os.environ.get("OPENCLAW_PLATFORM_ROOT", "/var/lib/openclaw-platform"))
TENANTS_DIR = PLATFORM_ROOT / "tenants"
PROV_DIR = PLATFORM_ROOT / "provisioner"
TEMPLATE_DIR = pathlib.Path(os.environ.get("OPENCLAW_AGENT_TEMPLATE_DIR", str(PLATFORM_ROOT / "templates" / "agent_quadlet")))
QUADLET_DIR = pathlib.Path(os.environ.get("OPENCLAW_QUADLET_DIR", "/etc/containers/systemd/users"))
RUNTIME_DIR = pathlib.Path(os.environ.get("OPENCLAW_PROVISIONER_RUNTIME_DIR", "/run/openclaw-provisioner"))
ADMIN_SOCK = RUNTIME_DIR / "admin.sock"
TENANT_SOCK_DIR = RUNTIME_DIR / "tenants"
BROKER_ADMIN_SOCK = pathlib.Path(os.environ.get("OPENCLAW_BROKER_ADMIN_SOCK", "/run/openclaw-broker/admin.sock"))
AUDIT_FILE = PROV_DIR / "audit.log"
STATE_FILE = PROV_DIR / "STATE"

SO_PEERCRED = getattr(socket, "SO_PEERCRED", 17)
NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")
ALLOWED_NETWORKS_DEFAULT = ["none", "messaging-only", "api-only", "restricted-internet"]


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg):
    sys.stdout.write(f"openclaw-provisioner: {msg}\n")
    sys.stdout.flush()


def err(msg):
    sys.stderr.write(f"openclaw-provisioner: error: {msg}\n")
    sys.stderr.flush()


def ensure_dirs():
    PROV_DIR.mkdir(parents=True, exist_ok=True, mode=0o750)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True, mode=0o755)
    TENANT_SOCK_DIR.mkdir(parents=True, exist_ok=True, mode=0o755)
    TENANTS_DIR.mkdir(parents=True, exist_ok=True, mode=0o755)


def write_state(state):
    STATE_FILE.write_text(
        f"state={state}\n"
        f"phase=3\n"
        f"updated={now_iso()}\n"
    )
    STATE_FILE.chmod(0o640)


def get_peer_uid(conn):
    creds = conn.getsockopt(socket.SOL_SOCKET, SO_PEERCRED, struct.calcsize("3i"))
    pid, uid, gid = struct.unpack("3i", creds)
    return uid


# ---- minimal YAML loader ----
# We avoid PyYAML so the host image does not gain another dependency. The
# policy schema is small and flat-ish; this loader handles the subset we use:
# scalars (str/int/bool), nested mappings, and "- item" sequences. It is a
# small parser, not a full YAML implementation; the policy file is host-owned
# (root-only writable) and changes go through admin review, so this is OK.

def parse_yaml(text):
    lines = []
    for raw in text.splitlines():
        # strip inline comments after a space
        s = raw.rstrip("\n")
        # detect comment-only line
        stripped = s.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        # remove trailing ' # ...' comments (best-effort)
        i = 0
        in_quote = False
        while i < len(s):
            c = s[i]
            if c in ("'", '"'):
                in_quote = not in_quote
            if c == "#" and not in_quote and i > 0 and s[i - 1].isspace():
                s = s[:i].rstrip()
                break
            i += 1
        lines.append(s)
    pos = [0]

    def indent_of(line):
        return len(line) - len(line.lstrip(" "))

    def cast_scalar(v):
        v = v.strip()
        if v == "":
            return None
        if v.lower() in ("true", "yes"):
            return True
        if v.lower() in ("false", "no"):
            return False
        if v.lower() in ("null", "~"):
            return None
        # quoted strings
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            return v[1:-1]
        # int
        try:
            return int(v)
        except ValueError:
            pass
        return v

    def parse_block(min_indent):
        # Decide if this block is a sequence (lines start with "- ") or a mapping.
        if pos[0] >= len(lines):
            return None
        first = lines[pos[0]]
        if indent_of(first) < min_indent:
            return None
        if first.lstrip().startswith("- "):
            return parse_sequence(min_indent)
        return parse_mapping(min_indent)

    def parse_mapping(min_indent):
        result = {}
        while pos[0] < len(lines):
            line = lines[pos[0]]
            if indent_of(line) < min_indent:
                break
            if indent_of(line) > min_indent:
                # malformed: extra indent without preceding key. Skip safely.
                pos[0] += 1
                continue
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                pos[0] += 1
                continue
            if ":" not in stripped:
                pos[0] += 1
                continue
            key, _, rest = stripped.partition(":")
            key = key.strip()
            rest = rest.strip()
            pos[0] += 1
            if rest != "":
                result[key] = cast_scalar(rest)
            else:
                # nested block follows; find its indent
                nested_indent = None
                # peek
                if pos[0] < len(lines):
                    nested = lines[pos[0]]
                    if indent_of(nested) > min_indent:
                        nested_indent = indent_of(nested)
                if nested_indent is None:
                    result[key] = None
                else:
                    result[key] = parse_block(nested_indent)
        return result

    def parse_sequence(min_indent):
        items = []
        while pos[0] < len(lines):
            line = lines[pos[0]]
            if indent_of(line) < min_indent:
                break
            stripped = line.strip()
            if not stripped.startswith("- "):
                break
            value = stripped[2:].strip()
            pos[0] += 1
            items.append(cast_scalar(value))
        return items

    return parse_block(0) or {}


# ---- policy ----

DEFAULT_POLICY = {
    "limits": {
        "max_agents": 10,
        "max_running_agents": 5,
    },
    "allowed_images": {
        "openclaw_runtime": [
            "quay.io/m0ranmcharles/fedora_init:openclaw-runtime",
        ],
        "environments": [
            "quay.io/m0ranmcharles/fedora_init:onboarding-env",
        ],
    },
    "allowed_credentials": [
        "codex", "gemini", "claude", "email", "signal", "github",
    ],
    "allowed_networks": list(ALLOWED_NETWORKS_DEFAULT),
    "default_network": "restricted-internet",
    "forbidden": {
        "privileged": True,
        "host_network": True,
        "host_pid": True,
        "host_ipc": True,
        "host_podman_socket": True,
        "arbitrary_host_mounts": True,
    },
}


def load_policy(tenant):
    p = TENANTS_DIR / tenant / "policy" / "policy.yaml"
    if not p.exists():
        return dict(DEFAULT_POLICY)
    try:
        data = parse_yaml(p.read_text())
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    # Merge defaults underneath whatever the file contains.
    out = json.loads(json.dumps(DEFAULT_POLICY))
    for k, v in data.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k].update(v)
        else:
            out[k] = v
    return out


# ---- agent records (object model §15.4) ----

def agents_dir(tenant):
    return TENANTS_DIR / tenant / "agents"


def agent_record_path(tenant, name):
    return agents_dir(tenant) / f"{name}.json"


def list_agents(tenant):
    d = agents_dir(tenant)
    if not d.exists():
        return []
    out = []
    for f in sorted(d.glob("*.json")):
        try:
            out.append(json.loads(f.read_text()))
        except Exception:
            pass
    return out


def write_agent(record):
    d = agents_dir(record["tenant"])
    d.mkdir(parents=True, exist_ok=True, mode=0o755)
    path = agent_record_path(record["tenant"], record["id"])
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(record, indent=2, sort_keys=True))
    tmp.chmod(0o640)
    tmp.replace(path)


def remove_agent_record(tenant, name):
    p = agent_record_path(tenant, name)
    try:
        p.unlink()
    except FileNotFoundError:
        pass


# ---- broker integration ----

def broker_call(req, timeout=5):
    if not BROKER_ADMIN_SOCK.exists():
        return None
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(str(BROKER_ADMIN_SOCK))
        s.sendall(json.dumps(req).encode("utf-8") + b"\n")
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        line = buf.split(b"\n", 1)[0].decode("utf-8", errors="replace")
        return json.loads(line) if line else None
    except Exception:
        return None
    finally:
        s.close()


def credential_known_to_broker(tenant, cred_id):
    reply = broker_call({"op": "credential_list", "tenant": tenant})
    if not reply or not reply.get("ok"):
        return False
    for entry in reply.get("credentials", []):
        if entry.get("id") == cred_id:
            return True
    return False


# ---- audit ----

def audit(**fields):
    fields["ts"] = now_iso()
    line = json.dumps(fields, sort_keys=True) + "\n"
    PROV_DIR.mkdir(parents=True, exist_ok=True, mode=0o750)
    with AUDIT_FILE.open("a") as f:
        f.write(line)


def audit_tail(n=50):
    if not AUDIT_FILE.exists():
        return []
    try:
        with AUDIT_FILE.open("r") as f:
            lines = f.readlines()[-n:]
        return [json.loads(l) for l in lines if l.strip()]
    except Exception:
        return []


# ---- Quadlet rendering ----

def envsubst(text, vars_):
    """Replace ${KEY} occurrences from vars_ (a dict). Keys not in vars_ are
    left as-is. We do not support default values or transformations -- this
    is a deliberately tiny, auditable substituter."""
    def repl(m):
        key = m.group(1)
        if key in vars_:
            return str(vars_[key])
        return m.group(0)
    return re.sub(r"\$\{([A-Z_][A-Z0-9_]*)\}", repl, text)


def render_agent_quadlets(tenant, name, runtime_image, env_image, network,
                          ingress, volumes, tenant_uid, tenant_gid):
    if not TEMPLATE_DIR.exists():
        raise RuntimeError(f"agent template dir not found: {TEMPLATE_DIR}")
    target = QUADLET_DIR / str(tenant_uid)
    target.mkdir(parents=True, exist_ok=True, mode=0o755)

    tenant_paths = TENANTS_DIR / tenant
    vol_lines = []
    for v in volumes:
        host_path = tenant_paths / "volumes" / v
        vol_lines.append(f"Volume={host_path}:/workspace/{v}:Z")

    env_vars = {
        "TENANT": tenant,
        "AGENT": name,
        "TENANT_UID": str(tenant_uid),
        "TENANT_GID": str(tenant_gid),
        "TENANT_HOME": str(tenant_paths / "runtime"),
        "TENANT_VOLUMES": str(tenant_paths / "volumes"),
        "TENANT_CLOUDFLARED": str(tenant_paths / "cloudflared"),
        "PLATFORM_ROOT": str(PLATFORM_ROOT),
        "RUNTIME_IMAGE": runtime_image,
        "ENV_IMAGE": env_image,
        "NETWORK": network,
        "AGENT_VOLUMES_BLOCK": "\n".join(vol_lines),
    }

    rendered = []
    for tmpl in sorted(TEMPLATE_DIR.glob("*.tmpl")):
        # Skip the cloudflared template unless ingress is requested.
        if tmpl.name == "agent-cloudflared.container.tmpl" and not ingress:
            continue
        out_name = f"{tenant}-{name}-{tmpl.name[len('agent-'):-len('.tmpl')]}"
        if tmpl.name == "agent.pod.tmpl":
            out_name = f"{tenant}-{name}.pod"
        out_path = target / out_name
        text = envsubst(tmpl.read_text(), env_vars)
        out_path.write_text(text)
        out_path.chmod(0o644)
        rendered.append(str(out_path))
    return rendered


def remove_agent_quadlets(tenant, name, tenant_uid):
    target = QUADLET_DIR / str(tenant_uid)
    if not target.exists():
        return []
    removed = []
    prefix = f"{tenant}-{name}"
    for f in list(target.iterdir()):
        if f.name == f"{prefix}.pod" or f.name.startswith(f"{prefix}-"):
            try:
                f.unlink()
                removed.append(str(f))
            except FileNotFoundError:
                pass
    return removed


# ---- systemd integration ----

def systemctl_user(tenant, *args, check=True):
    user = f"tenant_{tenant}"
    cmd = ["systemctl", "--user", f"--machine={user}@", *args]
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def systemctl_daemon_reload_user(tenant):
    try:
        systemctl_user(tenant, "daemon-reload")
    except subprocess.CalledProcessError:
        # The user manager may need a moment after enable-linger; retry briefly.
        for _ in range(5):
            time.sleep(1)
            try:
                systemctl_user(tenant, "daemon-reload")
                return
            except subprocess.CalledProcessError:
                continue
        raise


def start_agent_pod(tenant, name):
    systemctl_daemon_reload_user(tenant)
    systemctl_user(tenant, "start", f"{tenant}-{name}-pod.service")


def stop_agent_pod(tenant, name):
    try:
        systemctl_user(tenant, "stop", f"{tenant}-{name}-pod.service", check=False)
    except Exception:
        pass


# ---- per-tenant socket bookkeeping ----

LISTENERS = {}        # path -> (sock, kind, tenant)
TENANT_BY_FD = {}     # fd -> tenant or None for admin


def tenant_sock_path(tenant):
    return TENANT_SOCK_DIR / f"{tenant}.sock"


def open_listener(path, owner_uid=0, owner_gid=0, mode=0o660, tenant=None, kind="admin"):
    if path.exists() or path.is_symlink():
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.setblocking(False)
    s.bind(str(path))
    os.chown(str(path), owner_uid, owner_gid)
    os.chmod(str(path), mode)
    s.listen(8)
    LISTENERS[str(path)] = (s, kind, tenant)
    TENANT_BY_FD[s.fileno()] = tenant
    log(f"{kind} socket opened: {path} (tenant={tenant} uid={owner_uid} gid={owner_gid})")
    return s


def close_listener(path):
    entry = LISTENERS.pop(str(path), None)
    if not entry:
        return
    s, _, _ = entry
    TENANT_BY_FD.pop(s.fileno(), None)
    try:
        s.close()
    except Exception:
        pass
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def ensure_tenant_socket(tenant, uid, gid):
    p = tenant_sock_path(tenant)
    if str(p) in LISTENERS:
        return
    open_listener(p, owner_uid=int(uid), owner_gid=int(gid), mode=0o600,
                  tenant=tenant, kind="tenant")


def remove_tenant_socket(tenant):
    close_listener(tenant_sock_path(tenant))


def discover_tenants():
    if not TENANTS_DIR.exists():
        return
    for child in sorted(TENANTS_DIR.iterdir()):
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


# ---- request handlers ----

def validate_create_request(tenant, req, policy):
    if "name" not in req or not isinstance(req["name"], str) or not NAME_RE.match(req["name"]):
        raise ValueError("agent name must match [a-z][a-z0-9-]*")
    if "runtime" not in req or "environment" not in req:
        raise ValueError("missing runtime or environment image")

    runtime_image = req["runtime"]
    env_image = req["environment"]
    allowed_runtimes = (policy.get("allowed_images", {}) or {}).get("openclaw_runtime", []) or []
    allowed_envs = (policy.get("allowed_images", {}) or {}).get("environments", []) or []
    if runtime_image not in allowed_runtimes:
        raise PermissionError(f"runtime image {runtime_image!r} not in allowed_images.openclaw_runtime")
    if env_image not in allowed_envs:
        raise PermissionError(f"environment image {env_image!r} not in allowed_images.environments")

    network = req.get("network") or policy.get("default_network", "restricted-internet")
    allowed_networks = policy.get("allowed_networks", ALLOWED_NETWORKS_DEFAULT) or ALLOWED_NETWORKS_DEFAULT
    if network not in allowed_networks:
        raise PermissionError(f"network profile {network!r} not in allowed_networks")

    credentials = list(req.get("credentials") or [])
    allowed_credentials = policy.get("allowed_credentials", []) or []
    resolved_creds = []
    for c in credentials:
        if "/" in c:
            full = c
            short = c.split("/", 2)[1] if c.count("/") >= 2 else c
            if not full.startswith(f"{tenant}/"):
                raise PermissionError(f"credential {c!r} not in tenant namespace {tenant!r}/")
        else:
            short = c
            full = f"{tenant}/{c}/main"
        if short not in allowed_credentials:
            raise PermissionError(f"credential {short!r} not in allowed_credentials")
        if not credential_known_to_broker(tenant, full):
            raise PermissionError(f"credential {full!r} not present in broker store")
        resolved_creds.append(full)

    volumes = list(req.get("volumes") or req.get("storage") or [])
    bad_chars = re.compile(r"[^a-zA-Z0-9_.-]")
    for v in volumes:
        if bad_chars.search(v) or v in ("..", ".") or v.startswith("/"):
            raise ValueError(f"volume name {v!r} has disallowed characters")
        path = TENANTS_DIR / tenant / "volumes" / v
        if not path.exists():
            raise PermissionError(f"volume {v!r} does not exist under tenant {tenant!r}")

    forbidden = policy.get("forbidden", {}) or {}
    for k, v in forbidden.items():
        if v and req.get(k):
            raise PermissionError(f"policy forbids {k}=true on agent requests")

    # Quotas
    limits = policy.get("limits", {}) or {}
    existing = list_agents(tenant)
    if any(a.get("id") == req["name"] for a in existing):
        raise FileExistsError(f"agent {req['name']!r} already exists for tenant {tenant!r}")
    max_agents = limits.get("max_agents")
    if isinstance(max_agents, int) and len(existing) >= max_agents:
        raise PermissionError(f"max_agents={max_agents} reached for tenant {tenant!r}")
    max_running = limits.get("max_running_agents")
    if isinstance(max_running, int):
        running = sum(1 for a in existing if a.get("status") == "running")
        if running >= max_running:
            raise PermissionError(f"max_running_agents={max_running} reached for tenant {tenant!r}")

    return {
        "name": req["name"],
        "runtime": runtime_image,
        "environment": env_image,
        "network": network,
        "credentials": resolved_creds,
        "volumes": volumes,
        "ingress": list(req.get("ingress") or []),
    }


def cmd_agent_create(tenant, req):
    policy = load_policy(tenant)
    plan = validate_create_request(tenant, req, policy)

    pwent = pwd.getpwnam(f"tenant_{tenant}")
    rendered = render_agent_quadlets(
        tenant=tenant,
        name=plan["name"],
        runtime_image=plan["runtime"],
        env_image=plan["environment"],
        network=plan["network"],
        ingress=bool(plan["ingress"]),
        volumes=plan["volumes"],
        tenant_uid=pwent.pw_uid,
        tenant_gid=pwent.pw_gid,
    )

    record = {
        "id": plan["name"],
        "tenant": tenant,
        "runtime_image": plan["runtime"],
        "environment_image": plan["environment"],
        "credentials": plan["credentials"],
        "volumes": plan["volumes"],
        "ingress": plan["ingress"],
        "network_profile": plan["network"],
        "status": "starting",
        "created": now_iso(),
        "updated": now_iso(),
    }
    write_agent(record)

    try:
        start_agent_pod(tenant, plan["name"])
        record["status"] = "running"
        record["updated"] = now_iso()
        write_agent(record)
        audit(op="agent_create", tenant=tenant, agent=plan["name"], allowed=True,
              network=plan["network"], runtime=plan["runtime"], environment=plan["environment"])
    except subprocess.CalledProcessError as e:
        record["status"] = "failed"
        record["updated"] = now_iso()
        record["last_error"] = (e.stderr or e.stdout or str(e)).strip()
        write_agent(record)
        audit(op="agent_create", tenant=tenant, agent=plan["name"], allowed=True,
              start_failed=True, error=record["last_error"])
        raise

    return {"ok": True, "agent": record, "rendered": rendered}


def cmd_agent_list(tenant):
    return {"ok": True, "agents": list_agents(tenant)}


def cmd_agent_inspect(tenant, name):
    p = agent_record_path(tenant, name)
    if not p.exists():
        raise KeyError(name)
    return {"ok": True, "agent": json.loads(p.read_text())}


def cmd_agent_stop(tenant, name):
    if not agent_record_path(tenant, name).exists():
        raise KeyError(name)
    stop_agent_pod(tenant, name)
    rec = json.loads(agent_record_path(tenant, name).read_text())
    rec["status"] = "stopped"
    rec["updated"] = now_iso()
    write_agent(rec)
    audit(op="agent_stop", tenant=tenant, agent=name)
    return {"ok": True}


def cmd_agent_start(tenant, name):
    if not agent_record_path(tenant, name).exists():
        raise KeyError(name)
    start_agent_pod(tenant, name)
    rec = json.loads(agent_record_path(tenant, name).read_text())
    rec["status"] = "running"
    rec["updated"] = now_iso()
    write_agent(rec)
    audit(op="agent_start", tenant=tenant, agent=name)
    return {"ok": True}


def cmd_agent_delete(tenant, name):
    if not agent_record_path(tenant, name).exists():
        raise KeyError(name)
    pwent = pwd.getpwnam(f"tenant_{tenant}")
    stop_agent_pod(tenant, name)
    removed = remove_agent_quadlets(tenant, name, pwent.pw_uid)
    remove_agent_record(tenant, name)
    try:
        systemctl_daemon_reload_user(tenant)
    except subprocess.CalledProcessError:
        pass
    audit(op="agent_delete", tenant=tenant, agent=name, removed=removed)
    return {"ok": True, "removed": removed}


def cmd_policy_show(tenant):
    return {"ok": True, "policy": load_policy(tenant)}


def handle_admin(req):
    op = req.get("op")
    if op == "ping":
        return {"ok": True, "phase": 3, "ts": now_iso()}
    if op == "tenant_register":
        ensure_tenant_socket(req["tenant"], req["uid"], req["gid"])
        return {"ok": True}
    if op == "tenant_unregister":
        remove_tenant_socket(req["tenant"])
        return {"ok": True}
    if op == "audit_tail":
        return {"ok": True, "entries": audit_tail(int(req.get("n", 50)))}
    if op == "policy_show":
        return cmd_policy_show(req["tenant"])
    if op == "agent_create":
        tenant = req["tenant"]
        return cmd_agent_create(tenant, req)
    if op == "agent_list":
        return cmd_agent_list(req["tenant"])
    if op == "agent_inspect":
        return cmd_agent_inspect(req["tenant"], req["name"])
    if op == "agent_stop":
        return cmd_agent_stop(req["tenant"], req["name"])
    if op == "agent_start":
        return cmd_agent_start(req["tenant"], req["name"])
    if op == "agent_delete":
        return cmd_agent_delete(req["tenant"], req["name"])
    raise ValueError(f"unknown admin op {op!r}")


def handle_tenant(tenant, req):
    op = req.get("op")
    if op == "ping":
        return {"ok": True, "tenant": tenant, "phase": 3, "ts": now_iso()}
    if op == "policy_show":
        return cmd_policy_show(tenant)
    if op == "agent_create":
        return cmd_agent_create(tenant, req)
    if op == "agent_list":
        return cmd_agent_list(tenant)
    if op == "agent_inspect":
        return cmd_agent_inspect(tenant, req["name"])
    if op == "agent_stop":
        return cmd_agent_stop(tenant, req["name"])
    if op == "agent_start":
        return cmd_agent_start(tenant, req["name"])
    if op == "agent_delete":
        return cmd_agent_delete(tenant, req["name"])
    raise ValueError(f"unknown tenant op {op!r}")


# ---- connection handling ----

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
    conn.sendall((json.dumps(obj) + "\n").encode("utf-8"))


def handle_connection(conn, kind, tenant=None):
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
                resp = handle_admin(req)
            except Exception as e:
                send_line(conn, {"ok": False, "error": str(e), "type": type(e).__name__})
                return
            send_line(conn, resp)
        else:
            try:
                resp = handle_tenant(tenant, req)
            except Exception as e:
                send_line(conn, {"ok": False, "error": str(e), "type": type(e).__name__})
                return
            send_line(conn, resp)
    finally:
        try:
            conn.close()
        except Exception:
            pass


def main_loop():
    write_state("running")
    poller = select.poll()
    fd_to_listener = {}
    for path, (s, kind, tenant) in list(LISTENERS.items()):
        poller.register(s.fileno(), select.POLLIN)
        fd_to_listener[s.fileno()] = (s, kind, tenant)

    log(f"listening: admin={ADMIN_SOCK} tenants={[t for (_, _, t) in LISTENERS.values() if t]}")

    while True:
        # Re-register newly opened tenant sockets.
        current_fds = set()
        for path, (s, kind, tenant) in LISTENERS.items():
            fd = s.fileno()
            current_fds.add(fd)
            if fd not in fd_to_listener:
                poller.register(fd, select.POLLIN)
                fd_to_listener[fd] = (s, kind, tenant)
        # Drop fds for closed sockets.
        for fd in list(fd_to_listener.keys()):
            if fd not in current_fds:
                try:
                    poller.unregister(fd)
                except Exception:
                    pass
                del fd_to_listener[fd]

        events = poller.poll(1000)
        for fd, _ev in events:
            entry = fd_to_listener.get(fd)
            if not entry:
                continue
            sock, kind, tenant = entry
            try:
                conn, _ = sock.accept()
            except BlockingIOError:
                continue
            t = threading.Thread(target=handle_connection, args=(conn, kind, tenant), daemon=True)
            t.start()


def shutdown(*_):
    write_state("stopping")
    for path in list(LISTENERS.keys()):
        close_listener(pathlib.Path(path))
    sys.exit(0)


def main():
    ensure_dirs()
    open_listener(ADMIN_SOCK, owner_uid=0, owner_gid=0, mode=0o660, tenant=None, kind="admin")
    discover_tenants()
    write_state("ready")
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    try:
        main_loop()
    except KeyboardInterrupt:
        shutdown()


if __name__ == "__main__":
    main()
