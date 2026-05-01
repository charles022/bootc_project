# Create a tenant

## Goal

Create a new tenant on a running multi-tenant host. After completing this procedure you will have:

- a non-login service account `tenant_<name>` with subuid/subgid allocated
- the tenant storage tree at `/var/lib/openclaw-platform/tenants/<name>/`
- per-tenant Quadlet units rendered into `/etc/containers/systemd/users/<UID>/`
- the tenant's onboarding pod started under that tenant's rootless Podman runtime

This corresponds to Phase 0 of the multi-tenant architecture (`concepts/multi_tenant_architecture.md` § "What is built today vs. planned").

## Prerequisites

- A booted host running the multi-tenant host image (host image with `platformctl` installed; check with `command -v platformctl`).
- Admin (`root` / `sudo`) on the host.
- The tenant name must match `[a-z][a-z0-9-]*` and must not already exist.

## Steps

1. **Pick a tenant name and verify it is free.**

    ```bash
    sudo getent passwd tenant_alice && echo "already exists" || echo "available"
    ```

2. **Create the tenant.**

    ```bash
    sudo platformctl tenant create alice
    ```

    On success this prints the allocated UID and the rendered Quadlet paths.

3. **Verify the service account.**

    ```bash
    getent passwd tenant_alice
    sudo grep '^tenant_alice:' /etc/subuid /etc/subgid
    ```

    The shell field must be `/usr/sbin/nologin`. The home field must be `/var/lib/openclaw-platform/tenants/alice/runtime`.

4. **Verify the storage tree.**

    ```bash
    sudo ls -la /var/lib/openclaw-platform/tenants/alice/
    ```

    Expect `runtime/` and `volumes/` owned by `tenant_alice`; `quadlet/`, `cloudflared/`, `credentials/`, `policy/`, `logs/`, `backups/` owned by `root`.

5. **Verify the Quadlets.**

    ```bash
    UID_=$(id -u tenant_alice)
    sudo ls -la /etc/containers/systemd/users/${UID_}/
    ```

    Expect five files: `alice-onboard.pod`, `alice-cloudflared.container`, `alice-onboard-env.container`, `alice-openclaw-runtime.container`, `alice-credential-proxy.container`.

6. **Verify the pod is up.**

    ```bash
    sudo machinectl shell tenant_alice@ /usr/bin/systemctl --user list-units --type=service \
        | grep alice
    ```

    Expect `alice-onboard-pod.service` and the four container services listed as `active running` (the cloudflared sidecar will be `activating (auto-restart)` until you drop a real tunnel token into `/var/lib/openclaw-platform/tenants/alice/cloudflared/` — that is expected Phase-0 behavior).

## Verify

The smoke check that the rest of the platform agrees the tenant exists:

```bash
sudo platformctl tenant list
```

Expect `alice` listed as `active`.

The smoke check that the tenant boundary is intact:

```bash
# tenant cannot log in
sudo -u tenant_alice -i 2>&1 | head -1
# expect: "This account is currently not available."

# tenant cannot read another tenant's runtime
sudo -u tenant_alice ls /var/lib/openclaw-platform/tenants/bob/runtime 2>&1 | head -1
# expect: permission denied (when tenant bob exists)
```

## Troubleshooting

- **`platformctl: command not found`** — the host image is older than the multi-tenant layer. Update via `bootc update` and reboot.
- **`tenant_alice already exists`** — pick another name, or delete the existing tenant first with `sudo platformctl tenant delete alice`. Note: `tenant delete` is destructive (`reference/platformctl.md`).
- **`useradd` fails with "subuid range exhausted"** — `/etc/subuid` and `/etc/subgid` ran out of room; increase `SUB_UID_MAX` / `SUB_GID_MAX` in `/etc/login.defs` or remove an unused tenant. This is uncommon on a fresh host.
- **Pod service stays in `activating` state** — `sudo machinectl shell tenant_alice@ /usr/bin/journalctl --user -xeu alice-onboard-pod.service` to see the error. Most often the cloudflared image has not been pulled yet on this host (no network at boot); a network-online retry usually resolves it.
- **Cloudflared sidecar restart-loops** — expected Phase-0 behavior until a real tunnel token is provisioned into the tenant's `cloudflared/` directory; the cloudflared automation is planned (see `concepts/multi_tenant_architecture.md`).

## See also

- `reference/platformctl.md`
- `reference/tenant_quadlets.md`
- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `concepts/tenant_storage_layout.md`
