# Tenant identity model

## What

A **tenant** is a platform identity backed by a non-login Linux service account on the host. The account exists only as an isolation principal: it owns a rootless Podman runtime, a storage namespace, and a set of systemd-managed Quadlet units. It cannot log in, cannot `sudo`, has no SSH keys, and has no shell. Human guests reach the tenant's containers through cloudflared sidecars, never through the host.

This concept underpins the wider architecture in `concepts/multi_tenant_architecture.md`.

## Why

Two cheaper alternatives are tempting and both fail:

- **One real Linux user per human.** Gives every guest a real shell and home on the host. Every package install, agent crash, or compromised credential becomes a host-level concern. Violates "the host is not a workstation for guests."
- **One shared Linux user for all tenants.** Removes the boundary entirely; rootless Podman's user namespace cannot distinguish tenants if they all share the host UID.

Rootless Podman maps container users into the invoking host user's subordinate UID/GID range. By giving each tenant its own host UID and its own subuid/subgid block, container UIDs from tenant A and tenant B map into disjoint host UID ranges — so a file written by "root in tenant A's container" is owned by a UID the kernel recognizes as completely separate from "root in tenant B's container." That is the cheapest robust isolation we can get without virtualization.

## Implications

### Host accounts

Two kinds of accounts only:

| Kind | Example | Purpose |
|---|---|---|
| Real admin | `admin` (or `root` in the bootstrap image) | the only human host login; sudo, SSH, recovery |
| Tenant service account | `tenant_alice`, `tenant_bob`, ... | non-login isolation principal |

Tenant accounts have:

- **locked password** (`passwd -l`)
- **shell** `/usr/sbin/nologin`
- **no `~/.ssh/authorized_keys`**
- **not in `wheel`**, no `sudo` rights
- a **subuid/subgid range** allocated in `/etc/subuid` and `/etc/subgid`
- a **home / state directory** at `/var/lib/openclaw-platform/tenants/<tenant>/runtime` rather than `/home/<user>`
- **lingering enabled** (`loginctl enable-linger`) so user services run without an interactive login

`platformctl tenant create <name>` performs all of this in one step. See `reference/platformctl.md`.

### Container identities

Inside a tenant's containers, the user model is independent of the host:

- The dev-env container has its own user (e.g. `alice` with sudo inside the container).
- The openclaw-runtime container runs as a service user inside the container, ideally without sudo.
- Sidecars (cloudflared, credential-proxy) run as their own narrow service users.

That a container user can `sudo` inside the container is fine, because the user namespace ensures container-root ≠ host-root. The dangerous coupling — host Podman socket, host systemd socket, broad host mounts — is forbidden by policy and by the Quadlet templates the host generates (see `reference/tenant_quadlets.md`).

### Rootless Podman per tenant

Each tenant service account owns its own Podman state:

```text
/var/lib/openclaw-platform/tenants/alice/runtime/.local/share/containers/storage/
/var/lib/openclaw-platform/tenants/bob/runtime/.local/share/containers/storage/
```

Tenants do not share images, containers, networks, secrets, volumes, or systemd user units. Pulls happen per tenant. This trades disk space for isolation; it is the right trade for a small workstation.

### Pod boundary

A Podman pod shares network and IPC namespaces between its containers. Therefore:

- **Containers in the same pod must trust each other.** Co-locate only platform sidecars (cloudflared, credential-proxy) and a tenant's own workload containers (dev-env, openclaw-runtime).
- **Never co-locate two different tenants' containers in one pod.** Tenant separation is enforced one level up — at the host service account / rootless Podman boundary — not inside a pod.

### subuid / subgid allocation

`useradd` on Fedora normally allocates subuid/subgid automatically (see `/etc/login.defs`'s `SUB_UID_*` settings). `platformctl tenant create` relies on this default and verifies the range is present after user creation. If `useradd` did **not** auto-allocate (some distros / configurations disable it), `platformctl` falls back to a small allocator that:

1. reads `/etc/subuid` (or `/etc/subgid`),
2. finds the highest end-of-range across all existing entries,
3. allocates a new 65536-ID block starting just past that highest end (clamped to a configurable base, default `200000`).

This guarantees the new block does **not** overlap any existing entry — so two tenants created back-to-back never collide, even when the kernel-level auto-allocation is disabled. (Phase 0 used a hardcoded fallback range, which would cause collisions for any second tenant going through the fallback path; Phase 1 fixed this. See `roadmap.md`.)

Each tenant gets a contiguous block (typically 65536 IDs) so container-internal UIDs 0..65535 all map into that block. That block does not overlap any other tenant's, so a path owned by container-UID 0 in `tenant_alice` cannot be read by `tenant_bob`'s containers.

Operators can verify all tenants pairwise at any time with `sudo platformctl tenant verify-isolation` — it walks `/etc/subuid` and `/etc/subgid` and flags any overlap, in addition to the cross-tenant filesystem-read tests. See `how-to/verify_tenant_isolation.md`.

### Recovery

If the host is reinstalled from the host image, tenant accounts must be recreated and tenant volumes restored from backup (see `concepts/multi_tenant_architecture.md` § "Planned"). Tenant UIDs should be remapped consistently — the platform records the assigned UID in the tenant's policy file so backups can be restored with their original ownership.

## Non-negotiables

These follow from the rules in `concepts/multi_tenant_architecture.md` and are enforced by `platformctl`:

1. Tenant accounts are created with `--shell /usr/sbin/nologin` and locked passwords.
2. Tenant accounts have no `~/.ssh/authorized_keys` populated by the platform.
3. Tenant accounts are never added to `wheel`, `sudo`, or any privileged group.
4. Tenant accounts get their own subuid/subgid range, never sharing with another tenant.
5. Tenant Quadlets are placed under `/etc/containers/systemd/users/<UID>/`, owned `root:root`, mode `0644` — the tenant cannot edit them.
6. Tenant runtime state lives under `/var/lib/openclaw-platform/tenants/<tenant>/runtime/`, owned by the tenant service account. Policy and credential subdirectories remain root-owned. See `concepts/tenant_storage_layout.md`.

## See also

- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_storage_layout.md`
- `concepts/credential_broker.md`
- `concepts/access_model.md`
- `reference/platformctl.md`
- `reference/tenant_quadlets.md`
- `how-to/create_a_tenant.md`
- `how-to/verify_tenant_isolation.md`
