# agentctl (planned)

The agent-facing CLI for self-provisioning. Runs **inside an OpenClaw runtime container**, talks to a host endpoint, and can request new agents, environments, storage attachments, and credential grants. Every request is validated against tenant identity, policy, quota, credential grants, and storage grants before the host generates a Quadlet.

**Status: planned.** No `agentctl` binary is shipped today. This page records the planned shape. The conceptual basis is `concepts/agent_provisioning.md`.

## Planned subcommands

| Subcommand | Purpose |
|---|---|
| `agentctl create-agent ...` | Compose a new tenant pod from approved runtime image + environment image + grants. |
| `agentctl create-env ...` | Build a new environment image variant from an approved base. |
| `agentctl list-agents` | List the calling tenant's agents. |
| `agentctl stop-agent <name>` | Stop a specific agent pod. |
| `agentctl request-credential <id>` | Ask the broker for a scoped credential grant. |
| `agentctl attach-storage <volume>` | Attach an approved volume to an existing agent. |
| `agentctl detach-storage <volume>` | Reverse of `attach-storage`. |

## Planned constraints

Every command is constrained by:

- the calling tenant's identity (resolved from the calling pod, not from agent input)
- the calling agent's identity within that tenant
- the tenant's policy file (`/var/lib/openclaw-platform/tenants/<tenant>/policy/policy.yaml`)
- the tenant's quota
- the agent's grant scope
- the platform's approved-templates registry

The CLI does **not** expose:

```text
agentctl podman ...
agentctl systemctl ...
agentctl mount ...
agentctl cloudflared ...
agentctl sudo ...
```

These verbs are simply not subcommands. The transport between the agent container and the host endpoint is a UNIX socket inside the pod, mounted from the credential-proxy / agentctl sidecar — not a podman socket and not the host systemd socket.

## Sketch

```bash
agentctl create-agent \
    --name alice-rust-coder \
    --runtime openclaw:stable \
    --environment fedora-rust-dev:stable \
    --storage alice-shared-code \
    --credential codex \
    --credential github:fedora_init \
    --network restricted-internet
```

If allowed by policy, the host renders Quadlets, reloads systemd, starts the pod, and returns the new agent's id. If denied, the host returns the denial reason and writes an audit-log entry.

## See also

- `concepts/agent_provisioning.md`
- `concepts/multi_tenant_architecture.md`
- `concepts/credential_broker.md`
- `reference/platformctl.md`
- `reference/tenant_quadlets.md`
