# Tenant storage layout

## What

Where tenant-related state lives on the host filesystem, who owns it, and what may or may not be mounted from it into a tenant's containers.

## Why

Three kinds of state coexist on a multi-tenant workstation:

1. **Platform state the host owns** — policies, credential ciphertext, generated Quadlet sources. The tenant must never write to this.
2. **Tenant runtime state** — rootless Podman storage, container volumes. The tenant service account owns this.
3. **Templates and platform-shared assets** — Quadlet templates, default policies. Read-only references shared across tenants.

A flat home directory cannot represent these distinctions. A dedicated tree under `/var/lib/openclaw-platform/` makes ownership explicit, makes backup/restore tractable, and makes mount policy easy to audit.

## Implications

### Top-level layout

```text
/var/lib/openclaw-platform/
├── templates/
│   ├── quadlet/                       Quadlet template files (root:root, ro)
│   ├── policies/                      default tenant policy templates (planned)
│   └── onboarding/                    onboarding-pod assets (planned)
├── tenants/
│   ├── alice/
│   │   ├── runtime/                   tenant_alice home for rootless Podman
│   │   ├── volumes/                   tenant-owned named volumes
│   │   ├── quadlet/                   generated Quadlet sources for alice (root-owned)
│   │   ├── cloudflared/               tunnel tokens (root-owned, 0600)
│   │   ├── credentials/               credential ciphertext (root-owned, planned)
│   │   ├── policy/                    rendered tenant policy (root-owned)
│   │   ├── logs/                      audit + service logs (planned)
│   │   └── backups/                   per-tenant backup staging (planned)
│   └── bob/
│       └── ...
├── broker/                            credential broker state (root-owned, planned)
├── provisioner/                       provisioner state (root-owned, planned)
└── backups/                           platform-wide backups (planned)
```

The host image creates `/var/lib/openclaw-platform/{templates,broker,provisioner,backups}` and the empty `templates/quadlet/` directory at build time. Per-tenant subtrees are created by `platformctl tenant create` (see `reference/platformctl.md`).

### Ownership rules

| Path | Owner | Mode | Tenant writable? |
|---|---|---|---|
| `/var/lib/openclaw-platform/` | `root:root` | `0755` | no |
| `/var/lib/openclaw-platform/templates/...` | `root:root` | `0755` / `0644` | no |
| `/var/lib/openclaw-platform/tenants/<tenant>/runtime/` | `tenant_<tenant>` | `0700` | yes (it is the tenant's home) |
| `/var/lib/openclaw-platform/tenants/<tenant>/volumes/` | `tenant_<tenant>` | `0700` | yes (only via container mounts) |
| `/var/lib/openclaw-platform/tenants/<tenant>/quadlet/` | `root:root` | `0750` | no |
| `/var/lib/openclaw-platform/tenants/<tenant>/cloudflared/` | `root:root` | `0750` | no (mounted ro into cloudflared sidecar) |
| `/var/lib/openclaw-platform/tenants/<tenant>/credentials/` | `root:root` | `0750` | no (planned) |
| `/var/lib/openclaw-platform/tenants/<tenant>/policy/` | `root:root` | `0755` | no |

Generated Quadlet files for the tenant are also placed in `/etc/containers/systemd/users/<UID>/` (where the systemd user-mode generator looks). The copy under `tenants/<tenant>/quadlet/` is the source of truth that survives backup / restore; the copy under `/etc/containers/systemd/users/<UID>/` is regenerated on tenant create / update.

### Quadlet placement

Per-tenant Quadlets live at:

```text
/etc/containers/systemd/users/<UID>/
├── <tenant>-onboard.pod
├── <tenant>-cloudflared.container
├── <tenant>-onboard-env.container
├── <tenant>-openclaw-runtime.container
└── <tenant>-credential-proxy.container
```

These files are root-owned (`0644`). The tenant cannot edit them. Podman's user generator at boot reads only the `<UID>/` matching the user being started, so tenant_bob's user manager never sees alice's units. See `reference/tenant_quadlets.md` for the template-rendering details and `reference/quadlets.md` for the placement rules in general.

### Mount policy (tenant containers)

**Allowed mounts into tenant containers:**

- a tenant-owned volume → the tenant's pod
- a tenant-owned shared volume → other pods of the same tenant
- a read-only template volume → the tenant's pod
- the cloudflared tunnel-token file → cloudflared sidecar only, read-only

**Forbidden mounts into tenant containers (and refused by the Quadlet templates):**

- `/`, `/etc`, `/usr`
- `/var/lib/openclaw-platform/` (or any of its non-tenant subdirectories)
- `/var/run/podman/podman.sock`
- `/run/systemd`, host systemd socket
- another tenant's volume or token
- the host's cloudflared credentials directory as writable
- the host credential broker database

The Quadlet templates (`reference/tenant_quadlets.md`) hard-code only the mounts in the "allowed" list. Anything outside that list requires editing the template under `/var/lib/openclaw-platform/templates/quadlet/`, which is host-image / admin territory.

### Backup boundary

For backup and restore (planned):

- **back up** `tenants/<tenant>/{volumes,quadlet,credentials,policy,logs}` and `broker/` — the *data*.
- **do not back up** `tenants/<tenant>/runtime/.local/share/containers/storage/` — these are pulled images and ephemeral container state, recoverable from the registry.
- record the tenant's UID/GID in the policy file so a restored backup can be remapped onto a freshly recreated `tenant_<tenant>` account.

The detailed backup/restore plan is `concepts/multi_tenant_architecture.md` § "What is built today vs. planned" (still planned).

## See also

- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `reference/platformctl.md`
- `reference/tenant_quadlets.md`
- `reference/quadlets.md`
