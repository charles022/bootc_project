# Credential broker (planned)

## What

A host-controlled service responsible for receiving, encrypting, storing, and dispensing tenant credentials (LLM API tokens, GitHub tokens, OAuth refresh tokens, messaging-service credentials, etc.) without ever handing the master credential to a guest container.

**Status: stub.** A placeholder service unit (`openclaw-broker.service`) is enabled in the host image so the systemd dependency graph and the `/var/lib/openclaw-platform/broker/` state directory exist. The actual broker logic — encryption, scoped grant issuance, audit log, rotation — is Phase 2 of the multi-tenant build (`roadmap.md`). This document records the design we are building toward; mark sections as built-today only when the corresponding code lands.

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

## Status checklist

When implementing the broker, drop the `(planned)` markers and update `roadmap.md`:

- [ ] broker daemon + UNIX-socket API on the host
- [ ] encrypted credential store at `/var/lib/openclaw-platform/broker/store.db`
- [ ] master key handling (sealed key file, recoverable via admin)
- [ ] grant table: tenant × agent × credential × scope
- [ ] credential-proxy container image (real, not stub)
- [ ] onboarding flow to enroll first credential
- [ ] rotation and revocation API
- [ ] audit log

## See also

- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `concepts/tenant_storage_layout.md`
- `reference/platformctl.md`
- `reference/agentctl.md`
- `reference/systemd_units.md` § openclaw-broker.service
