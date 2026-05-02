# Agent provisioning

## What

How agents (LLM-driven processes inside an `openclaw-runtime` container) request new agents, storage, and credentials, and how the host validates each request before generating Quadlet/systemd units.

**Status: built (Phase 3 + Phase 4 messaging additions).** The agent-facing CLI (`agentctl`, `reference/agentctl.md`) lives inside the `openclaw-runtime` container. It connects over a tenant-specific UNIX socket (bind-mounted from the host) to `openclaw-provisioner.service` on the host, which reads the tenant's `policy.yaml`, validates each request against allowed images / credentials / networks / volumes / quotas / forbidden flags / allowed messaging transports, cross-checks credentials with the broker, renders agent Quadlets from `/var/lib/openclaw-platform/templates/agent_quadlet/` (including the messaging-bridge sidecars matching the request's `--messaging` list), and starts the new pod under the tenant's user manager. Every allow / deny is appended to `/var/lib/openclaw-platform/provisioner/audit.log`.

Phase 4 added two agent-record fields: `is_main` (at most one main agent per tenant; admin-only via `platformctl agent set-main`) and `messaging` (subset of `policy.allowed_messaging`). The messaging interface itself — bridge ↔ runtime protocol, verb dispatch, status reporting — is documented in `concepts/messaging_interface.md`.

What is **still planned**: `agentctl create-env` (build new environment images on demand) and `agentctl attach-storage` / `detach-storage` (volume changes after agent creation). Per-agent CPU / memory cgroup enforcement is recorded in the agent object but not yet pushed into the Quadlet — that is Phase 5 work.

## Why

Two extremes fail:

- **Static, admin-only provisioning.** The admin creates every agent by hand. Defeats the point of having an agent platform — agents cannot self-organize subtasks, cannot create per-task scratch environments, cannot scale without human latency.
- **Open-ended provisioning.** Agents call `podman run` / `systemctl` / `mount` directly. One LLM hallucination away from a privileged container, an arbitrary host mount, or a tunnel to the wrong place.

The middle path is **declarative requests via a constrained tool**, validated against a tenant policy, materialized into Quadlets by the host, and executed by host systemd. The agent describes *what* it wants; the host decides *whether* and *how*.

## Implications

### Allowed pattern

Agents may request:

- create a new agent (a new pod composed from approved templates)
- create / clone a new environment image variant
- attach an approved storage volume
- request an approved credential grant
- start / stop their own tenant's resources

Through:

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

### Forbidden pattern

Agents may **not** execute:

```text
podman run ...
podman secret ...
systemctl ...
cloudflared tunnel ...
mount ...
sudo ... (on host)
```

The Quadlet templates already block this at the container layer (no host Podman socket, no host mounts, no host systemd). `agentctl` blocks it at the CLI layer by simply not exposing those verbs.

### Provisioning flow

```text
agent request
   │
   ▼
agentctl CLI/API
   │
   ▼
tenant identity resolved        (which tenant is this caller in?)
   │
   ▼
policy engine validates         (is this template allowed?)
   │
   ▼
quota engine validates          (max_agents, max_running_agents, max_cpu, max_memory, max_storage)
   │
   ▼
credential grants checked       (is "codex" in tenant's allowed_credentials?)
   │
   ▼
storage grants checked          (does the volume exist and belong to this tenant?)
   │
   ▼
template selected               (from /var/lib/openclaw-platform/templates/quadlet/)
   │
   ▼
Quadlet generated               (rendered into /etc/containers/systemd/users/<UID>/)
   │
   ▼
systemd daemon-reload
   │
   ▼
tenant unit started
   │
   ▼
audit log written
```

### Tenant policy example

A tenant policy lives at `/var/lib/openclaw-platform/tenants/<tenant>/policy/policy.yaml` and looks roughly like:

```yaml
tenant: alice

limits:
  max_agents: 10
  max_running_agents: 5
  max_cpu_per_agent: 4
  max_memory_per_agent: 8G
  max_storage_total: 500G

allowed_images:
  openclaw_runtime:
    - registry.local/openclaw-runtime:stable
  environments:
    - registry.local/fedora-dev:stable
    - registry.local/rust-dev:stable
    - registry.local/python-dev:stable

allowed_credentials:
  - codex
  - gemini
  - claude
  - email
  - signal
  - github

default_network: restricted-internet

forbidden:
  privileged: true
  host_network: true
  host_pid: true
  host_ipc: true
  host_podman_socket: true
  arbitrary_host_mounts: true
```

A default policy is rendered for every new tenant by `platformctl tenant create` (when the policy template lands; today the template is a placeholder file).

### Object model

The host treats tenants, credentials, environment images, agents, and pods as first-class objects. Sketch:

```yaml
tenant:
  id: alice
  service_user: tenant_alice
  uid: 2001
  storage_root: /var/lib/openclaw-platform/tenants/alice
  status: active

credential:
  id: alice/codex/main
  tenant: alice
  type: codex
  storage: broker
  status: active
  rotation_policy: manual

environment_image:
  id: fedora-rust-dev
  image: registry.local/env/fedora-rust-dev:stable
  allows_internal_sudo: true
  allowed_mount_classes: [workspace, shared, scratch]

agent:
  id: alice-rust-coding
  tenant: alice
  runtime_image: registry.local/openclaw/runtime:stable
  environment_image: registry.local/env/fedora-rust-dev:stable
  credentials: [alice/codex/main, alice/github/fedora_init]
  volumes: [alice/shared-code, alice/agent-rust-private]
  ingress: [signal-route, dev-ssh]
  messaging: [email, signal]      # Phase 4; subset of policy.allowed_messaging
  is_main: false                  # Phase 4; admin-only via platformctl agent set-main
  network_profile: restricted-internet
  status: running

pod:
  id: alice-rust-coding
  tenant: alice
  containers: [openclaw-runtime, dev-env, cloudflared, credential-proxy]
  shared_network: true
  volumes: [shared-code, private]
  secrets: [tunnel-token, credential-proxy-client-token]
```

### Failure modes

| Failure | Mitigation |
|---|---|
| Agent tries to create a privileged container | policy engine rejects; templates do not expose the option |
| Agent tries to mount a host path | mount is not a parameter `agentctl` accepts |
| Agent tries to bypass `agentctl` and call `podman` directly | container has no host Podman socket, no `podman` binary configured to talk to the host |
| Agent requests a credential it has no grant for | policy engine rejects; broker refuses |
| Agent creates 1000 pods | quota engine rejects past `max_agents` |
| Bug in the host control plane | small codebase, template-based generation, dry-run mode, audit log on every action, no shell-string interpolation from agent input |

## Wire protocol

JSONL over UNIX socket; one request per connection.

**Admin socket** `/run/openclaw-provisioner/admin.sock` (peer must be UID 0; enforced via `SO_PEERCRED`):

| op | required fields | reply |
|---|---|---|
| `policy_show` | `tenant` | `{"ok": true, "policy": {...}}` |
| `agent_create` | `tenant`, `name`, `runtime`, `environment`, optional `credentials`, `volumes`, `ingress`, `network` | `{"ok": true, "agent": {...}, "rendered": [...]}` |
| `agent_list` | `tenant` | `{"ok": true, "agents": [...]}` |
| `agent_inspect` | `tenant`, `name` | `{"ok": true, "agent": {...}}` |
| `agent_start` | `tenant`, `name` | `{"ok": true}` |
| `agent_stop` | `tenant`, `name` | `{"ok": true}` |
| `agent_delete` | `tenant`, `name` | `{"ok": true, "removed": [...]}` |
| `agent_set_main` | `tenant`, `name` | `{"ok": true, "agent": {...}, "cleared": [...]}` — admin-only; the per-tenant socket refuses this op |
| `tenant_register` | `tenant`, `uid`, `gid` | `{"ok": true}` |
| `tenant_unregister` | `tenant` | `{"ok": true}` |
| `audit_tail` | optional `n` | `{"ok": true, "entries": [...]}` |
| `ping` | — | `{"ok": true, "phase": 3, ...}` |

**Per-tenant socket** `/run/openclaw-provisioner/tenants/<tenant>.sock` (chowned to `tenant_<tenant>`, mode `0600`; tenant identity is implicit from which socket the connection arrived on; the same ops as above except no `tenant` field is required and `tenant_register` / `tenant_unregister` / `audit_tail` are not exposed).

Errors always have shape `{"ok": false, "error": "...", "type": "..."}`.

## Files on disk

| Path | Owner | Mode | Purpose |
|---|---|---|---|
| `/var/lib/openclaw-platform/tenants/<tenant>/policy/policy.yaml` | `root:root` | `0644` | tenant policy (provisioner reads, admin edits) |
| `/var/lib/openclaw-platform/tenants/<tenant>/agents/<agent>.json` | `root:root` | `0640` | per-agent record (see `design/multi_tenant_architecture.md` §15.4) |
| `/var/lib/openclaw-platform/templates/agent_quadlet/*.tmpl` | `root:root` | `0644` | agent Quadlet templates |
| `/var/lib/openclaw-platform/provisioner/audit.log` | `root:root` | `0640` | append-only JSONL audit log |
| `/var/lib/openclaw-platform/provisioner/STATE` | `root:root` | `0640` | provisioner liveness marker |
| `/run/openclaw-provisioner/admin.sock` | `root:root` | `0660` | admin socket |
| `/run/openclaw-provisioner/tenants/<tenant>.sock` | `tenant_<tenant>` | `0600` | per-tenant socket |
| `/etc/containers/systemd/users/<UID>/<tenant>-<agent>*.{pod,container}` | `root:root` | `0644` | rendered agent Quadlets |

## Still planned

- **`agentctl create-env`** — build a new environment image variant from an approved base. Today the policy lists allowed environment images; the agent picks one of them.
- **`agentctl attach-storage` / `detach-storage`** — volume changes after agent creation. Today volumes are bound at create-time only.
- **CPU / memory cgroup enforcement.** The agent record carries `network_profile`; future work pushes `MemoryMax=` / `CPUQuota=` into the Quadlet from policy `limits`.

## See also

- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `concepts/credential_broker.md`
- `reference/platformctl.md`
- `reference/agentctl.md`
- `reference/tenant_quadlets.md`
- `how-to/create_an_agent.md`
