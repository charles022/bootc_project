#!/usr/bin/env python3
# agentctl - tenant-side CLI for self-provisioning, runs inside the
# openclaw-runtime container. Talks JSONL over the per-tenant provisioner
# socket bind-mounted from the host at /run/agentctl/agentctl.sock.
#
# Concept: docs/concepts/agent_provisioning.md
# Reference: docs/reference/agentctl.md
#
# The CLI deliberately does NOT expose `podman / systemctl / mount / sudo /
# cloudflared` verbs; those are forbidden by design (§22 of the proposal).

import argparse
import json
import os
import socket
import sys

SOCK = os.environ.get("OPENCLAW_AGENTCTL_SOCKET", "/run/agentctl/agentctl.sock")
TIMEOUT = float(os.environ.get("OPENCLAW_AGENTCTL_TIMEOUT", "10"))


def err(msg):
    sys.stderr.write(f"agentctl: error: {msg}\n")


def call(req):
    if not os.path.exists(SOCK):
        err(f"provisioner socket not present at {SOCK}")
        sys.exit(3)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(TIMEOUT)
    try:
        s.connect(SOCK)
        s.sendall(json.dumps(req).encode("utf-8") + b"\n")
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        line = buf.split(b"\n", 1)[0].decode("utf-8", errors="replace")
    finally:
        s.close()
    if not line:
        err("provisioner closed connection without reply")
        sys.exit(3)
    try:
        return json.loads(line)
    except json.JSONDecodeError as e:
        err(f"provisioner returned invalid JSON: {e}")
        sys.exit(3)


def emit(obj):
    print(json.dumps(obj, indent=2, sort_keys=True))


def cmd_ping(args):
    emit(call({"op": "ping"}))


def cmd_policy_show(args):
    reply = call({"op": "policy_show"})
    emit(reply)
    sys.exit(0 if reply.get("ok") else 1)


def cmd_create_agent(args):
    req = {
        "op": "agent_create",
        "name": args.name,
        "runtime": args.runtime,
        "environment": args.environment,
        "credentials": args.credential or [],
        "volumes": args.storage or [],
        "ingress": args.ingress or [],
        "messaging": args.messaging or [],
    }
    if args.network:
        req["network"] = args.network
    reply = call(req)
    emit(reply)
    sys.exit(0 if reply.get("ok") else 1)


def cmd_list_agents(args):
    reply = call({"op": "agent_list"})
    emit(reply)
    sys.exit(0 if reply.get("ok") else 1)


def cmd_inspect_agent(args):
    reply = call({"op": "agent_inspect", "name": args.name})
    emit(reply)
    sys.exit(0 if reply.get("ok") else 1)


def cmd_stop_agent(args):
    reply = call({"op": "agent_stop", "name": args.name})
    emit(reply)
    sys.exit(0 if reply.get("ok") else 1)


def cmd_start_agent(args):
    reply = call({"op": "agent_start", "name": args.name})
    emit(reply)
    sys.exit(0 if reply.get("ok") else 1)


def cmd_delete_agent(args):
    reply = call({"op": "agent_delete", "name": args.name})
    emit(reply)
    sys.exit(0 if reply.get("ok") else 1)


def build_parser():
    p = argparse.ArgumentParser(prog="agentctl",
                                description="Tenant-side CLI for OpenClaw agent self-provisioning.")
    sub = p.add_subparsers(dest="cmd")

    sp = sub.add_parser("ping", help="check connectivity to the provisioner")
    sp.set_defaults(func=cmd_ping)

    sp = sub.add_parser("policy-show", help="print the calling tenant's policy")
    sp.set_defaults(func=cmd_policy_show)

    sp = sub.add_parser("create-agent", help="compose a new agent pod from approved templates")
    sp.add_argument("--name", required=True)
    sp.add_argument("--runtime", required=True,
                    help="OpenClaw runtime image; must appear in policy.allowed_images.openclaw_runtime")
    sp.add_argument("--environment", required=True,
                    help="dev environment image; must appear in policy.allowed_images.environments")
    sp.add_argument("--credential", action="append",
                    help="short name (e.g. codex) or full id (e.g. <tenant>/codex/main); repeatable")
    sp.add_argument("--storage", action="append",
                    help="tenant volume name to attach at /workspace/<name>; repeatable")
    sp.add_argument("--ingress", action="append",
                    help="ingress class label, e.g. dev-ssh; repeatable; opt-in cloudflared sidecar")
    sp.add_argument("--messaging", action="append",
                    help="messaging transport (email, signal, whatsapp); repeatable; "
                         "must appear in policy.allowed_messaging; renders the matching "
                         "messaging-bridge sidecar in the agent pod")
    sp.add_argument("--network",
                    help="network profile (must appear in policy.allowed_networks)")
    sp.set_defaults(func=cmd_create_agent)

    sp = sub.add_parser("list-agents", help="list this tenant's agents")
    sp.set_defaults(func=cmd_list_agents)

    sp = sub.add_parser("inspect-agent", help="show one agent's full record")
    sp.add_argument("name")
    sp.set_defaults(func=cmd_inspect_agent)

    sp = sub.add_parser("stop-agent", help="stop an agent's pod")
    sp.add_argument("name")
    sp.set_defaults(func=cmd_stop_agent)

    sp = sub.add_parser("start-agent", help="start a previously stopped agent's pod")
    sp.add_argument("name")
    sp.set_defaults(func=cmd_start_agent)

    sp = sub.add_parser("delete-agent", help="stop and remove an agent and its Quadlets")
    sp.add_argument("name")
    sp.set_defaults(func=cmd_delete_agent)

    return p


def main():
    p = build_parser()
    args = p.parse_args()
    if not getattr(args, "func", None):
        p.print_help()
        sys.exit(1)
    args.func(args)


if __name__ == "__main__":
    main()
