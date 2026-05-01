# platformctl

The admin-side CLI for the multi-tenant layer. Runs on the host as `root` (or via `sudo`). Manages tenant lifecycle, renders Quadlet templates, and reloads systemd.

- **Path**: `/usr/local/bin/platformctl` (source: `01_build_image/build_assets/multi_tenant/platformctl.sh`)
- **Concept**: `concepts/multi_tenant_architecture.md`, `concepts/tenant_identity_model.md`
- **Templates**: `/var/lib/openclaw-platform/templates/quadlet/` (source: `01_build_image/build_assets/multi_tenant/*.tmpl`)

## Subcommand summary

| Subcommand | Status | Purpose |
|---|---|---|
| `platformctl tenant create <name>` | built | Create a non-login service account, allocate storage, render the onboarding-pod Quadlets, enable lingering, reload systemd. |
| `platformctl tenant list` | built | List tenants known to the platform. |
| `platformctl tenant disable <name>` | built | Stop the tenant's user services and lock the account; preserves state. |
| `platformctl tenant enable <name>` | built | Re-enable a previously disabled tenant. |
| `platformctl tenant delete <name>` | built | Stop user services, remove the user, and remove `/var/lib/openclaw-platform/tenants/<name>/`. Destructive. |
| `platformctl agent list <tenant>` | planned | List agent pods for a tenant. |
| `platformctl agent create <tenant> ...` | planned | Wraps `agentctl` for admin-driven agent creation. |
| `platformctl credential list <tenant>` | planned | List credentials in the tenant's namespace. |
| `platformctl credential rotate <tenant> <id>` | planned | Trigger a rotation. |
| `platformctl tunnel list <tenant>` | planned | List the tenant's cloudflared tunnels / routes. |
| `platformctl backup run <tenant>` | planned | Snapshot tenant volumes, policy, credential metadata. |
| `platformctl backup restore <tenant> --snapshot <id>` | planned | Restore from a snapshot. |

Subcommands marked **planned** print a stub message identifying the implementation phase.

## What `tenant create` does

`platformctl tenant create alice` performs, in order:

1. Validates `<name>` is a lowercase alphanumeric string.
2. Refuses if `tenant_alice` already exists.
3. Creates a non-login service account:
   - `useradd --system --create-home --home-dir /var/lib/openclaw-platform/tenants/alice/runtime --shell /usr/sbin/nologin tenant_alice`
   - locks the password (`passwd -l`).
   - verifies subuid/subgid allocation; falls back to explicit `usermod -v / -w` if not auto-allocated.
4. Creates the tenant storage subtree (see `concepts/tenant_storage_layout.md`):
   - `runtime/`, `volumes/` — `tenant_alice:tenant_alice`, mode `0700`.
   - `quadlet/`, `cloudflared/`, `credentials/`, `policy/`, `logs/`, `backups/` — `root:root`, mode `0750`.
5. Writes a placeholder tenant policy file at `policy/policy.yaml` (the policy engine itself is planned).
6. Renders the onboarding-pod Quadlets from `/var/lib/openclaw-platform/templates/quadlet/*.tmpl` into `/etc/containers/systemd/users/<UID>/<tenant>-*.{pod,container}`. See `reference/tenant_quadlets.md`.
7. Enables systemd lingering for the tenant service account (`loginctl enable-linger tenant_alice`) so the user manager runs without an interactive login.
8. Runs `systemctl daemon-reload` so Podman's user-mode Quadlet generator picks up the new units.
9. Starts the tenant's onboarding pod via `systemctl --user --machine=tenant_alice@ start <tenant>-onboard.service`.

The command is idempotent for steps that are already in the desired state, but refuses to overwrite an existing tenant's account or storage.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `OPENCLAW_PLATFORM_ROOT` | `/var/lib/openclaw-platform` | Override the platform state root. Useful for tests. |
| `OPENCLAW_QUADLET_DIR` | `/etc/containers/systemd/users` | Where rendered Quadlet files are placed. |
| `OPENCLAW_TEMPLATE_DIR` | `${OPENCLAW_PLATFORM_ROOT}/templates/quadlet` | Source directory for `.tmpl` Quadlet templates. |
| `OPENCLAW_DRY_RUN` | unset | If set to a non-empty value, print actions without executing. |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | usage error (bad arguments, unknown subcommand) |
| `2` | precondition failed (tenant already exists, missing template) |
| `3` | host action failed (useradd, systemctl, mkdir, etc.) |

## Notes

- `platformctl` does not run as a daemon. It is a one-shot command operators or scripts invoke.
- `platformctl` only manages **tenant-scoped** Quadlets under `/etc/containers/systemd/users/<UID>/`. The system-wide dev pod under `/usr/share/containers/systemd/devpod.kube` is unrelated and unchanged.
- `platformctl tenant delete` is destructive. It removes the tenant's data on the host. There is currently no backup-before-delete safeguard; back up first using your own snapshot tooling.
- The agent / credential / tunnel / backup subcommands print clear "planned" messages and exit non-zero so scripts cannot accidentally treat them as success.

## See also

- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `concepts/tenant_storage_layout.md`
- `reference/tenant_quadlets.md`
- `reference/agentctl.md`
- `how-to/create_a_tenant.md`
