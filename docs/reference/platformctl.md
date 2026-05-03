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
| `platformctl tenant inspect <name>` | built | Print a tenant's UID/GID, subuid/subgid range, storage paths, Quadlet paths, lingering status, tunnel state, and pod-service state. |
| `platformctl tenant disable <name>` | built | Stop the tenant's user services and lock the account; preserves state. |
| `platformctl tenant enable <name>` | built | Re-enable a previously disabled tenant. |
| `platformctl tenant delete <name>` | built | Stop user services, remove the user, and remove `/var/lib/openclaw-platform/tenants/<name>/`. Destructive. |
| `platformctl tenant verify-isolation [<a> <b>]` | built | Run the Phase-1 isolation checks. With no arguments, runs every per-tenant invariant and every pairwise check across all tenants. |
| `platformctl tunnel set-config <tenant> [<path>]` | built | Install a cloudflared `config.yml` for the tenant (read from `<path>` or stdin). Root-owned, mode 0640. |
| `platformctl tunnel set-credentials <tenant> <path>` | built | Install a Cloudflare tunnel credentials JSON. Root-owned, mode 0600. The filename is preserved (`<tunnel-uuid>.json`). |
| `platformctl tunnel show <tenant>` | built | Print the contents of the tenant's `cloudflared/` directory. |
| `platformctl tunnel list` | built | List all tenants with their tunnel-config / credentials presence. |
| `platformctl credential add <tenant> <id>` | built | Read plaintext from stdin, encrypt and store under the tenant's namespace. |
| `platformctl credential list [<tenant>]` | built | List credentials (no plaintext) for one tenant or all tenants. |
| `platformctl credential delete <tenant> <id>` | built | Remove a credential from the store; all grants referencing it are dropped. |
| `platformctl credential rotate <tenant> <id>` | built | Replace a credential's value (read from stdin); preserves grants. |
| `platformctl grant add <tenant> <agent> <id> [<scope>]` | built | Authorize a specific agent name to read a specific credential. |
| `platformctl grant remove <tenant> <agent> <id>` | built | Revoke a single grant. |
| `platformctl grant list [<tenant>]` | built | List grants for one tenant or all tenants. |
| `platformctl audit tail [<n>]` | built | Print the last N broker audit-log entries (default 50). |
| `platformctl signal-link <tenant>` | built | Phase-4 helper. Drives `signal-cli link` interactively to pair a Signal device, prompts for the sender allow-list, packs the resulting state and writes it to the broker as the tenant's `signal/main` credential. |
| `platformctl agent create <tenant> --name X --runtime IMG --environment IMG [--credential ID]... [--storage VOL]... [--ingress CLASS]... [--messaging TRANSPORT]... [--is-main] [--network PROFILE]` | built | Compose a new agent pod. Same code path as `agentctl create-agent`, but admin-side: identity is an explicit `<tenant>` argument rather than implicit from the per-tenant socket. `--is-main` is admin-only. `--messaging` selects which messaging-bridge sidecars are rendered. |
| `platformctl agent list <tenant>` | built | List the tenant's agents. |
| `platformctl agent inspect <tenant> <name>` | built | Print one agent's full JSON record. |
| `platformctl agent start <tenant> <name>` | built | Start a previously stopped agent. |
| `platformctl agent stop <tenant> <name>` | built | Stop an agent's pod. |
| `platformctl agent delete <tenant> <name>` | built | Stop, remove Quadlets, drop the record. |
| `platformctl agent set-main <tenant> <name>` | built | Promote `<name>` to be the tenant's main agent (clearing any previously main agent). Admin-only; the per-tenant socket refuses this op. |
| `platformctl policy show <tenant>` | built | Print the tenant's policy as parsed JSON. |
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

## What `tenant verify-isolation` checks

Phase-1's central deliverable. With no arguments, runs across every tenant on the host. With two tenant names, runs only against that pair. Always fails fast and exits with code `4` on any violation. Sections:

**Per-tenant invariants** (one block per tenant):

- shell is `/usr/sbin/nologin`
- password is locked (`passwd -S` reports `L` / `LK`)
- the account is **not** a member of `wheel` or `sudo`
- a `runtime/.ssh/authorized_keys` file is flagged as a warning if present (the platform itself never creates one)
- the Quadlet directory `/etc/containers/systemd/users/<UID>/` is owned by `root` and every file in it is owned by `root`

**Pairwise isolation** (every (a, b) pair):

- distinct UIDs
- non-overlapping `/etc/subuid` ranges
- non-overlapping `/etc/subgid` ranges
- distinct storage roots
- `runuser -u tenant_a -- ls /var/lib/openclaw-platform/tenants/b/runtime` fails with `EACCES` (and the symmetric direction)
- distinct Quadlet directories

The pairwise filesystem check uses `runuser` so it does not rely on the tenants having any login configured.

## What `credential`, `grant`, and `audit` do

These subcommands are thin wrappers over the host's `openclaw-broker` daemon. They open a UNIX socket connection to `/run/openclaw-broker/admin.sock`, send one JSONL request, and print the JSON reply (pretty-printed, sorted keys). The full wire protocol is documented in `concepts/credential_broker.md`.

`credential add` and `credential rotate` read the plaintext **from stdin** so the value never appears on the command line or in shell history. Pipe the value in:

```bash
printf '%s' 'sk-real-token' | sudo platformctl credential add alice alice/codex/main
```

`grant add` and `grant remove` operate on the broker's grant table (tenant × agent × credential × scope). The agent name is whatever string the agent will pass in its `credential_request` calls — see `concepts/agent_provisioning.md`.

`credential delete` cascades into the grant table: every grant referencing the deleted credential is removed in the same transaction.

`audit tail` reads `/var/lib/openclaw-platform/broker/audit.log` (append-only JSONL) and returns the last N entries. Each entry includes a UTC timestamp and the operation's identifying fields.

The full walkthrough is `how-to/enroll_a_credential.md`.

## What `agent` and `policy` do

These subcommands wrap the host's `openclaw-provisioner.service`. They open a UNIX socket connection to `/run/openclaw-provisioner/admin.sock`, send one JSONL request, and print the JSON reply. The provisioner reads the tenant's `policy.yaml`, validates the request against allowed images / credentials / networks / volumes / quotas / forbidden flags, cross-checks credentials with the broker, renders agent Quadlets from `/var/lib/openclaw-platform/templates/agent_quadlet/`, and starts the new pod. Full request/response shapes are in `concepts/agent_provisioning.md`.

`agent create` accepts the same flags as `agentctl create-agent` (`reference/agentctl.md`) — the admin-side path goes through the **admin** socket and takes an explicit `<tenant>` argument; the agent-side path goes through the **per-tenant** socket and infers the tenant from which socket the connection arrived on. They share validation code.

`policy show` reads `/var/lib/openclaw-platform/tenants/<tenant>/policy/policy.yaml` and prints the merged result (defaults underneath). The file itself is the editable source of truth — root edits, no daemon reload required (the provisioner loads the file on every request).

The full walkthrough is `how-to/create_an_agent.md`.

## What `tunnel` configures

The cloudflared sidecar that ships with each tenant pod uses the upstream `cloudflare/cloudflared` image. It expects a config + credentials in `/etc/cloudflared/` (mounted read-only from `/var/lib/openclaw-platform/tenants/<tenant>/cloudflared/`). `platformctl tunnel set-config` and `platformctl tunnel set-credentials` install those files with root ownership; the tenant cannot rewrite them. There is no automation for actually creating the Cloudflare tunnel itself — that involves a Cloudflare API call and is part of the planned tunnel-automation work in `design/multi_tenant_architecture.md` §20 (Phase 1/4).

After installing/changing config or credentials, restart the tenant's cloudflared sidecar:

```bash
sudo systemctl --user --machine=tenant_<tenant>@ restart <tenant>-cloudflared.service
```

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `OPENCLAW_PLATFORM_ROOT` | `/var/lib/openclaw-platform` | Override the platform state root. Useful for tests. |
| `OPENCLAW_QUADLET_DIR` | `/etc/containers/systemd/users` | Where rendered Quadlet files are placed. |
| `OPENCLAW_TEMPLATE_DIR` | `${OPENCLAW_PLATFORM_ROOT}/templates/quadlet` | Source directory for `.tmpl` Quadlet templates. |
| `OPENCLAW_SUBID_BASE` | `200000` | Base UID used by the **fallback** subuid/subgid allocator (only triggers when `useradd` did not auto-allocate). |
| `OPENCLAW_SUBID_BLOCK` | `65536` | Block size for the fallback subuid/subgid allocator. |
| `OPENCLAW_BROKER_ADMIN_SOCK` | `/run/openclaw-broker/admin.sock` | Path of the broker admin socket. Useful for tests. |
| `OPENCLAW_PROVISIONER_ADMIN_SOCK` | `/run/openclaw-provisioner/admin.sock` | Path of the provisioner admin socket. Useful for tests. |
| `OPENCLAW_DRY_RUN` | unset | If set to a non-empty value, print actions without executing. |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | usage error (bad arguments, unknown subcommand) |
| `2` | precondition failed (tenant already exists, missing template) |
| `3` | host action failed (useradd, systemctl, mkdir, etc.; broker socket missing) |
| `4` | `tenant verify-isolation` found at least one violation |
| non-zero (1) | a broker call returned `{"ok": false, ...}`; the JSON reply is still printed |

## Notes

- `platformctl` does not run as a daemon. It is a one-shot command operators or scripts invoke.
- `platformctl` manages **tenant-scoped** Quadlets under `/etc/containers/systemd/users/<UID>/`, including agent dev environments. The system-wide dev pod under `/usr/share/containers/systemd/devpod.kube` remains only as a legacy GPU fallback.
- `platformctl tenant delete` is destructive. It removes the tenant's data on the host. There is currently no backup-before-delete safeguard; back up first using your own snapshot tooling.
- The fallback subuid/subgid allocator never assigns a range that overlaps an existing entry in `/etc/subuid` or `/etc/subgid`. It walks the file, finds the highest end-of-range, and allocates the next 65536-block past it. The hardcoded `100000-165535` fallback used in Phase 0 was a known bug; Phase 1 replaces it.
- The backup subcommands still print "planned" messages and exit non-zero so scripts cannot accidentally treat them as success.

## See also

- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `concepts/tenant_storage_layout.md`
- `reference/tenant_quadlets.md`
- `reference/agentctl.md`
- `how-to/create_a_tenant.md`
- `how-to/verify_tenant_isolation.md`
- `how-to/enroll_a_credential.md`
- `how-to/create_an_agent.md`
- `concepts/credential_broker.md`
- `concepts/agent_provisioning.md`
