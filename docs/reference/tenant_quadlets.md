# Tenant Quadlets

Quadlet templates and per-tenant placement rules for the multi-tenant layer. These are distinct from the system-wide `devpod.kube` covered by `reference/quadlets.md`.

## Where the templates live

Templates ship inside the host image and end up at:

```text
/var/lib/openclaw-platform/templates/quadlet/
├── tenant-onboard.pod.tmpl
├── tenant-cloudflared.container.tmpl
├── tenant-onboard-env.container.tmpl
├── tenant-openclaw-runtime.container.tmpl
└── tenant-credential-proxy.container.tmpl
```

Sources in the repo: `01_build_image/build_assets/multi_tenant/*.tmpl`. The host Containerfile copies them into the image at build time.

## Where the rendered units land

`platformctl tenant create <tenant>` renders the templates into a per-tenant directory:

```text
/etc/containers/systemd/users/<UID>/
├── <tenant>-onboard.pod
├── <tenant>-cloudflared.container
├── <tenant>-onboard-env.container
├── <tenant>-openclaw-runtime.container
└── <tenant>-credential-proxy.container
```

`<UID>` is the numeric UID of the `tenant_<tenant>` service account. Podman's user-mode Quadlet generator only reads the directory matching the user it is generating for, so `tenant_bob`'s manager never sees alice's units.

The rendered files are **owned by `root:root`, mode `0644`** — readable but not writable by the tenant. This matches the rule in `concepts/multi_tenant_architecture.md`: "the host controls desired config; the tenant service account owns runtime state."

## Why per-UID under /etc

Two placement strategies exist for rootless Quadlets:

- **Per-tenant user dir:** `/var/lib/openclaw-platform/tenants/<tenant>/runtime/.config/containers/systemd/`. Tenant-writable; the platform must trust the tenant not to rewrite its own units.
- **Per-UID under `/etc`:** `/etc/containers/systemd/users/<UID>/`. Root-owned; only the matching UID's user manager processes it.

This project uses the second form. It matches a host-managed control plane: the **admin** authors the desired pod definition and the kernel ensures only the right tenant's manager sees it.

## Variable substitution

Templates use a tiny set of `${VAR}` placeholders. `platformctl` renders them with `envsubst` against a fixed allowlist; arbitrary shell expansion is not performed.

| Variable | Source |
|---|---|
| `${TENANT}` | the tenant name argument (validated `[a-z][a-z0-9-]*`) |
| `${TENANT_UID}` | numeric UID of `tenant_${TENANT}` |
| `${TENANT_GID}` | numeric GID of `tenant_${TENANT}` |
| `${TENANT_HOME}` | `/var/lib/openclaw-platform/tenants/${TENANT}/runtime` |
| `${TENANT_VOLUMES}` | `/var/lib/openclaw-platform/tenants/${TENANT}/volumes` |
| `${TENANT_CLOUDFLARED}` | `/var/lib/openclaw-platform/tenants/${TENANT}/cloudflared` |
| `${PLATFORM_ROOT}` | `/var/lib/openclaw-platform` |

Templates that need any other host path must be edited in the source repo and shipped via the next host image update — by design, `platformctl` cannot generalize beyond the allowlisted variables.

## Template walkthroughs

Excerpts only. The repo files are authoritative.

### tenant-onboard.pod.tmpl

```ini
[Unit]
Description=Onboarding pod for tenant ${TENANT}
After=network-online.target
Wants=network-online.target

[Pod]
PodName=${TENANT}-onboard

[Install]
WantedBy=default.target
```

Rendered to `<tenant>-onboard.pod`. Generated systemd unit: `<tenant>-onboard-pod.service`.

### tenant-cloudflared.container.tmpl

```ini
[Unit]
Description=Cloudflared sidecar for tenant ${TENANT}
After=${TENANT}-onboard-pod.service
BindsTo=${TENANT}-onboard-pod.service

[Container]
Image=docker.io/cloudflare/cloudflared:latest
Pod=${TENANT}-onboard.pod
Volume=${TENANT_CLOUDFLARED}:/etc/cloudflared:ro,Z
Exec=tunnel --no-autoupdate run

[Install]
WantedBy=default.target
```

Notes:

- The cloudflared config / tunnel token is mounted **read-only** from a root-owned directory; the tenant cannot rewrite it.
- The container has no host network, no host mounts beyond `/etc/cloudflared`, no Podman socket.
- The unit `BindsTo` the pod — when the pod stops, cloudflared stops with it.
- The container only starts producing traffic once the operator drops a real tunnel token into `${TENANT_CLOUDFLARED}/`. Until then it logs a missing-config error and restarts; this is intentional Phase-0 behavior.

### tenant-onboard-env.container.tmpl

The tenant's onboarding shell (sshd-bearing). Used during the first-time enrollment flow described in `concepts/multi_tenant_architecture.md` § Phase 0.

```ini
[Unit]
Description=Onboarding env for tenant ${TENANT}
After=${TENANT}-onboard-pod.service
BindsTo=${TENANT}-onboard-pod.service

[Container]
Image=quay.io/m0ranmcharles/fedora_init:onboarding-env
Pod=${TENANT}-onboard.pod
Volume=${TENANT_VOLUMES}:/workspace:Z
Environment=OPENCLAW_TENANT=${TENANT}

[Install]
WantedBy=default.target
```

### tenant-openclaw-runtime.container.tmpl

The tenant's agent runtime. Phase-0 image is a stub that prints its identity and idles.

```ini
[Unit]
Description=OpenClaw runtime for tenant ${TENANT}
After=${TENANT}-onboard-pod.service
BindsTo=${TENANT}-onboard-pod.service

[Container]
Image=quay.io/m0ranmcharles/fedora_init:openclaw-runtime
Pod=${TENANT}-onboard.pod
Environment=OPENCLAW_TENANT=${TENANT}
ReadOnly=true

[Install]
WantedBy=default.target
```

`ReadOnly=true` enforces the rule that the runtime image is more locked down than the dev environment.

### tenant-credential-proxy.container.tmpl

The pod-local credential proxy. Phase-0 image is a stub; Phase-2 implements the real broker client.

```ini
[Unit]
Description=Credential proxy for tenant ${TENANT}
After=${TENANT}-onboard-pod.service
BindsTo=${TENANT}-onboard-pod.service

[Container]
Image=quay.io/m0ranmcharles/fedora_init:credential-proxy
Pod=${TENANT}-onboard.pod
Environment=OPENCLAW_TENANT=${TENANT}
ReadOnly=true

[Install]
WantedBy=default.target
```

## Lifecycle

- **Render:** `platformctl tenant create` — `envsubst` over each `*.tmpl`, write to `/etc/containers/systemd/users/<UID>/`, `systemctl daemon-reload`, then `systemctl --user --machine=tenant_<tenant>@ start <tenant>-onboard-pod.service`.
- **Re-render:** Currently `platformctl` does not re-render templates after the initial create; tenant updates are a planned `platformctl tenant update` subcommand. To force a re-render today, delete the user's `/etc/containers/systemd/users/<UID>/` and re-run `tenant create` against a renamed tenant, or edit by hand.
- **Stop:** `platformctl tenant disable` runs `systemctl --user --machine=tenant_<tenant>@ stop <tenant>-onboard-pod.service` and disables lingering. Files remain.
- **Remove:** `platformctl tenant delete` stops the pod, removes the rendered units, deletes the tenant user, and removes `/var/lib/openclaw-platform/tenants/<tenant>/`.

## Forbidden options in tenant Quadlets

The templates intentionally never include these keys; do not add them in a fork:

- `Privileged=true`
- `PodmanArgs=--privileged`
- `Network=host`
- `PidsLimit=...` set to 0 / unbounded combined with privileged
- mount of `/`, `/etc`, `/usr`, `/var/lib/openclaw-platform`, `/run/podman/podman.sock`, `/run/systemd`
- mount of another tenant's `/var/lib/openclaw-platform/tenants/<other>/`
- mount of the host cloudflared credentials directory as writable

If a future feature genuinely requires one of these, it belongs in a new template under `/var/lib/openclaw-platform/templates/quadlet/`, shipped via a host image update, not added at runtime.

## See also

- `reference/quadlets.md` — system-wide Quadlet rules and the dev pod definition.
- `reference/platformctl.md`
- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `concepts/tenant_storage_layout.md`
