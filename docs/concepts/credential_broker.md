# Credential broker

## What

A host-controlled daemon responsible for receiving, encrypting, storing, and dispensing tenant credentials (LLM API tokens, GitHub tokens, OAuth refresh tokens, messaging-service credentials, etc.) without ever handing the master credential to a guest container. Tenant agents reach it through a pod-local **credential-proxy** sidecar mounted with a tenant-specific socket — the proxy itself holds no master credentials and can only relay grant-checked requests for the tenant it was bound to at pod start.

**Status: built (Phase 2).** The daemon (`openclaw-broker`) ships in the host image, runs as `openclaw-broker.service` (Type=simple, Restart=on-failure), and exposes an admin socket at `/run/openclaw-broker/admin.sock` plus per-tenant sockets at `/run/openclaw-broker/tenants/<tenant>.sock` (chowned to the tenant service account). Encryption uses Fernet (AES-128-CBC + HMAC-SHA256) with a 32-byte key at `/var/lib/openclaw-platform/broker/key.bin`. Admin operations are exposed via `platformctl credential`, `platformctl grant`, and `platformctl audit` (`reference/platformctl.md`).

The Phase 2 deliverables that landed:

- broker daemon + UNIX-socket API on the host
- encrypted credential store at `/var/lib/openclaw-platform/broker/store.json`
- master key handling (key file, root-owned `0600`)
- grant table at `/var/lib/openclaw-platform/broker/grants.json`: tenant × agent × credential × scope
- credential-proxy container image (real, not stub)
- rotation and revocation API (`credential rotate`, `credential delete`, `grant remove`)
- append-only audit log at `/var/lib/openclaw-platform/broker/audit.log`

What is **still planned** is called out where it appears below: the interactive `openclaw-onboard` flow inside the onboarding-env container, OAuth/login-URL handling, sealed/HSM-backed key custody, scheduled rotation, and replication. None of those is required to use the broker today; they are hardening / UX work for Phase 4 / Phase 5.

## Why

Storing tenant credentials anywhere a tenant container can read them collapses the trust boundary established by `concepts/tenant_identity_model.md`. If `alice/codex/main` is mounted as a file in alice's openclaw-runtime container, then the LLM running in that container, every skill it loads, every npm package, and every shell command it executes can read it.

The broker exists so that the master credential never leaves the host control plane. Tenant containers receive only short-lived, scoped, revocable derivatives — and ideally ask the broker per request rather than holding any token at all.

The alternatives we rejected:

- **Master tokens in environment variables.** Visible in `/proc/<pid>/environ`, in `podman inspect`, in any process dump.
- **Master tokens in mounted secret files.** Better than env vars, but still readable by every process inside the container, including agent skills that may be untrusted.
- **Per-container vaults.** Multiplies attack surface; every container becomes its own credential store.

## Implications

### Ownership

Credentials are tied to the **tenant**, not directly to a container. Naming convention:

```text
<tenant>/<service>/<role>
```

Examples:

```text
alice/email/main
alice/signal/main
alice/codex/main
alice/gemini/main
alice/claude/main
alice/github/main
alice/cloudflare/user-route
```

Agent instances receive **grants** that name specific credentials and a scope (read / write / specific operations).

### Components

```text
host
├── openclaw-broker (service)        owns ciphertext, key, grants, audit log
├── tenant_alice
│     └── alice-credential-proxy     local socket inside alice's pod
└── tenant_bob
      └── bob-credential-proxy       local socket inside bob's pod
```

- **broker (host service):** holds the encrypted credential store, the master key, the grant table, and the audit log. Reachable only by other host components.
- **credential-proxy (per-tenant pod sidecar):** an immutable container with a small UNIX socket / HTTP API. Forwards an agent's credential request to the broker, attaches the agent's tenant + container identity, returns only what the broker authorizes. Has no broad credential dump API.

### Injection order of preference

When a container needs a credential, prefer (in order):

1. **Credential proxy API/socket** — agent calls a local API; broker returns just-in-time scoped output (e.g. an OAuth header for one outbound request).
2. **Short-lived token** — broker issues a token valid for minutes, scoped to one operation.
3. **Podman secret mounted as a file** — for credentials that must exist as files (some SDKs require this).
4. **Environment variable** — only when unavoidable; never for master credentials.

Forbidden:

- master credentials baked into an image
- master credentials in container layers
- master credentials in command-line arguments
- master credentials in logs
- master credentials in world-readable files
- master credentials in agent-writable config

### Login URL (OAuth) flow

For services like Codex / Gemini / Claude / GitHub that issue tokens via a browser-based OAuth login:

1. Onboarding tool calls `openclaw-onboard` (planned).
2. Host broker generates or receives the login URL.
3. The URL is sent to the human user via the onboarding SSH session or an existing messaging channel.
4. The user completes the login flow externally (in a real browser).
5. The broker receives the token / refresh-token via callback or paste-back.
6. The broker stores the credential under the tenant namespace.
7. Selected agents are granted scoped derivatives.

The container never becomes the master credential vault — it sees only the runtime token / session needed for its current task.

### Cloning is forbidden for credential-bearing containers

You may not "clone an authenticated openclaw-runtime container." That copies tokens, cookies, log lines, in-memory sessions, agent memory, IPC sockets, cached credentials, working files, and stale config. Instead the platform composes a fresh agent from:

```text
base image + profile + selected grants + selected storage = new agent
```

This is encoded in `agentctl create-agent` (planned, see `reference/agentctl.md`).

### Restrictions on the credential proxy itself

To keep the proxy from becoming a leak point:

- pod-local access only (no host network)
- tenant-scoped (knows its tenant id, refuses cross-tenant requests)
- agent-scoped grants (the broker tracks which agent in which pod is calling)
- audited (every issuance and every denial is logged)
- no broad credential dump API
- no list-all-secrets for an agent
- short-lived tokens preferred over long-lived ones

### Threat-mitigation summary

| Failure | Mitigation |
|---|---|
| Agent leaks a token in chat output | tokens are short-lived; the broker can revoke; audit log records the issuance |
| Agent skill exfiltrates the credential file | there is no credential file — only socket calls — and even short-lived tokens are scoped |
| Container compromised | credential-proxy is immutable, has no master credentials, can be revoked with the tenant |
| Broker bug | small codebase, host-controlled, template-based generation, audit on every action |

## Wire protocol

JSONL over UNIX socket: one request per connection, terminated by `\n`; one reply, terminated by `\n`.

**Admin socket** `/run/openclaw-broker/admin.sock` (peer must be UID 0; enforced via `SO_PEERCRED`):

| op | required fields | reply |
|---|---|---|
| `credential_add` | `tenant`, `id`, `value` | `{"ok": true}` |
| `credential_get` | `tenant`, `id` | `{"ok": true, "value": "..."}` |
| `credential_list` | optional `tenant` | `{"ok": true, "credentials": [...]}` |
| `credential_delete` | `tenant`, `id` | `{"ok": true}` (also drops grants for that id) |
| `credential_rotate` | `tenant`, `id`, `value` | `{"ok": true}` |
| `grant_add` | `tenant`, `agent`, `id`, optional `scope` | `{"ok": true}` |
| `grant_remove` | `tenant`, `agent`, `id` | `{"ok": true}` |
| `grant_list` | optional `tenant` | `{"ok": true, "grants": [...]}` |
| `audit_tail` | optional `n` | `{"ok": true, "entries": [...]}` |
| `tenant_register` | `tenant`, `uid`, `gid` | `{"ok": true}` (opens per-tenant socket) |
| `tenant_unregister` | `tenant` | `{"ok": true}` |
| `ping` | — | `{"ok": true, "phase": 2, "ts": ...}` |

Every error reply has shape `{"ok": false, "error": "...", "type": "..."}`.

**Per-tenant socket** `/run/openclaw-broker/tenants/<tenant>.sock` (chowned to `tenant_<tenant>`, mode `0600`; the tenant identity is implicit from which socket the connection arrived on):

| op | required fields | reply |
|---|---|---|
| `credential_request` | `agent`, `id` | `{"ok": true, "value": "..."}` if a grant exists, else `{"ok": false, "error": "no grant for ...", "type": "PermissionError"}` |
| `agent_grants` | `agent` | `{"ok": true, "grants": [...]}` |
| `ping` | — | `{"ok": true, "tenant": ..., "phase": 2, "ts": ...}` |

The credential-proxy sidecar inside a tenant pod connects to its mounted broker socket and re-exposes `credential_request` / `agent_grants` / `ping` on a pod-local agent socket at `/run/credential-proxy/agent.sock`. Other ops are refused at the proxy boundary.

## Files on disk

| Path | Owner | Mode | Purpose |
|---|---|---|---|
| `/var/lib/openclaw-platform/broker/key.bin` | `root:root` | `0600` | 32-byte Fernet master key |
| `/var/lib/openclaw-platform/broker/store.json` | `root:root` | `0600` | encrypted credential store (JSON) |
| `/var/lib/openclaw-platform/broker/grants.json` | `root:root` | `0600` | grant table (JSON) |
| `/var/lib/openclaw-platform/broker/audit.log` | `root:root` | `0640` | append-only audit log (JSONL) |
| `/var/lib/openclaw-platform/broker/STATE` | `root:root` | `0640` | broker liveness marker |
| `/run/openclaw-broker/admin.sock` | `root:root` | `0660` | admin socket |
| `/run/openclaw-broker/tenants/<tenant>.sock` | `tenant_<tenant>` | `0600` | per-tenant socket |

## Threat-mitigation summary

| Failure | Mitigation |
|---|---|
| Agent leaks a token in chat output | broker can revoke (`credential delete` or `grant remove`); audit log records every issuance |
| Agent skill exfiltrates the credential file | there is no credential file — only socket calls; the proxy refuses admin verbs at the pod boundary |
| Container compromised | credential-proxy is immutable, has no master credentials, can be revoked with the tenant; broker enforces grants per-request |
| Cross-tenant access attempt | per-tenant socket is chowned to that tenant only; broker's `credential_get` checks the credential's `tenant` field; `id` namespacing requires `<tenant>/...` |
| Broker bug | small codebase, host-controlled, template-based generation, audit on every action, peer-UID 0 check on admin socket, AES-128 + HMAC for at-rest encryption |

## Still planned

The pieces below are *not* required to use the broker today; flagged so they don't get lost:

- **`openclaw-onboard` interactive CLI** inside the onboarding-env container — guides a new tenant through credential enrollment without an admin running `platformctl credential add` by hand. Phase 4.
- **OAuth / login-URL flow** for services like Codex / Gemini / Claude / GitHub. Today the admin pastes the resulting token into stdin; the planned flow has the broker generate the URL and store the token automatically. Phase 4.
- **Sealed / HSM-backed master key.** Today the master key is a plain file on disk (root-only). A TPM-sealed or HSM-backed key would survive disk theft. Phase 5 hardening.
- **Scheduled rotation** with rotation policies. Today rotation is manual via `platformctl credential rotate`. Phase 5.
- **Replication.** Out of scope for a single-host workstation.

## See also

- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `concepts/tenant_storage_layout.md`
- `reference/platformctl.md`
- `reference/agentctl.md`
- `reference/systemd_units.md` § openclaw-broker.service
- `how-to/enroll_a_credential.md`
