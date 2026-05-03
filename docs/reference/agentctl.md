# agentctl

The agent-facing CLI for self-provisioning. Runs **inside an OpenClaw runtime container**, talks to the host `openclaw-provisioner.service` over the per-tenant UNIX socket bind-mounted at `/run/agentctl/agentctl.sock`. Every request is validated against tenant identity, policy, quota, credential grants, and storage grants before the host generates a Quadlet.

- **Path in the container**: `/usr/local/bin/agentctl` (source: `01_build_image/build_assets/multi_tenant/agentctl.py`)
- **Concept**: `concepts/agent_provisioning.md`
- **Daemon**: `openclaw-provisioner.service` on the host (`reference/systemd_units.md`)

## Subcommand summary

| Subcommand | Status | Purpose |
|---|---|---|
| `agentctl ping` | built | Liveness check — connect to the provisioner and read its phase number. |
| `agentctl policy-show` | built | Print the calling tenant's policy as parsed JSON (read-only). |
| `agentctl create-agent --name X --runtime IMG --environment IMG [--credential ID]... [--storage VOLUME]... [--ingress CLASS]... [--messaging TRANSPORT]... [--network PROFILE]` | built | Compose a new agent pod from approved templates. The provisioner validates against policy / quota / grants before rendering Quadlets and starting the pod under the tenant's user manager. |
| `agentctl list-agents` | built | List the calling tenant's agents (no admin info; no other tenant's agents). |
| `agentctl inspect-agent <name>` | built | Print the full agent object record. |
| `agentctl start-agent <name>` | built | Start a previously stopped agent. |
| `agentctl stop-agent <name>` | built | Stop an agent's pod (record stays). |
| `agentctl delete-agent <name>` | built | Stop the agent, remove its Quadlets, drop its record. |
| `agentctl create-env ...` | planned | Build a new environment image variant from an approved base. |
| `agentctl attach-storage <agent> <volume>` | planned | Attach a tenant-owned volume after agent creation. |
| `agentctl detach-storage <agent> <volume>` | planned | Reverse of `attach-storage`. |
| `agentctl request-credential <id>` | covered by credential-proxy | Already provided by the pod-local credential-proxy socket — see `concepts/credential_broker.md`. |

## Hard constraints

The CLI deliberately does **not** expose:

```text
agentctl podman ...
agentctl systemctl ...
agentctl mount ...
agentctl cloudflared ...
agentctl sudo ...
```

These verbs are not subcommands — there is no way for an agent to ask the host to run them. The transport into the container is a single mounted UNIX socket pointing at the per-tenant provisioner socket; the openclaw-runtime image has no podman, no systemd-side socket, no mount tools.

## Validation pipeline

Every `create-agent` request goes through, in order (refer to `concepts/agent_provisioning.md` for the diagram):

1. **Tenant identity** resolved from which per-tenant socket the connection arrived on.
2. **Image allowlist** — `runtime` must be in `policy.allowed_images.openclaw_runtime`; `environment` must be in `policy.allowed_images.environments`.
3. **Network allowlist** — the chosen `network` (or the policy default) must be in `policy.allowed_networks`.
4. **Credential allowlist** — every credential short-name in the request must be in `policy.allowed_credentials`. Short names like `codex` are expanded to `<tenant>/codex/main`. Full ids must already start with `<tenant>/`.
5. **Credential exists** — the provisioner calls the broker (`credential_list` admin op) to verify each credential is in the store.
6. **Storage exists** — every requested `--storage <name>` must point at an existing directory under `/var/lib/openclaw-platform/tenants/<tenant>/volumes/`.
7. **Forbidden flags** — every key in `policy.forbidden` whose value is `true` (`privileged`, `host_network`, `host_pid`, `host_ipc`, `host_podman_socket`, `arbitrary_host_mounts`) is checked against the request.
8. **Messaging allowlist** — every `--messaging <transport>` must be in `policy.allowed_messaging`. Tenants cannot pass `is_main` over the per-tenant socket; that is admin-only via `platformctl agent set-main`.
9. **Quotas** — `max_agents` (count of existing agent records) and `max_running_agents` (count of those with `status: running`).
10. **Render Quadlets** from `/var/lib/openclaw-platform/templates/agent_quadlet/`. Messaging-bridge sidecars are rendered only for the transports listed in `--messaging`.
11. **`systemctl --user --machine=tenant_<tenant>@ daemon-reload`** then **`start <tenant>-<agent>-pod.service`**.
12. **Audit-log** entry written.

If any step fails, the provisioner returns `{"ok": false, "error": "...", "type": "PermissionError"|...}` and the audit log records the denial.

## Sketch

```bash
# Inside the openclaw-runtime container, as the agent itself:
agentctl create-agent \
    --name rust-coder \
    --runtime  quay.io/m0ranmcharles/fedora_init:openclaw-runtime \
    --environment quay.io/m0ranmcharles/fedora_init:dev-env \
    --storage shared-code \
    --credential codex \
    --credential github \
    --network restricted-internet
```

The reply, on success:

```json
{
  "ok": true,
  "agent": {
    "id": "rust-coder",
    "tenant": "alice",
    "runtime_image": "quay.io/m0ranmcharles/fedora_init:openclaw-runtime",
    "environment_image": "quay.io/m0ranmcharles/fedora_init:dev-env",
    "credentials": ["alice/codex/main", "alice/github/main"],
    "volumes": ["shared-code"],
    "ingress": [],
    "messaging": [],
    "is_main": false,
    "network_profile": "restricted-internet",
    "status": "running",
    "created": "...",
    "updated": "..."
  },
  "rendered": [
    "/etc/containers/systemd/users/2001/alice-rust-coder.pod",
    "/etc/containers/systemd/users/2001/alice-rust-coder-openclaw-runtime.container",
    "/etc/containers/systemd/users/2001/alice-rust-coder-dev-env.container",
    "/etc/containers/systemd/users/2001/alice-rust-coder-credential-proxy.container"
  ]
}
```

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `OPENCLAW_AGENTCTL_SOCKET` | `/run/agentctl/agentctl.sock` | Where the provisioner socket is mounted. |
| `OPENCLAW_AGENTCTL_TIMEOUT` | `10` | Seconds before a hung connection gives up. |

## See also

- `concepts/agent_provisioning.md`
- `concepts/multi_tenant_architecture.md`
- `concepts/credential_broker.md`
- `reference/platformctl.md`
- `reference/tenant_quadlets.md`
- `how-to/create_an_agent.md`
