# Create an agent

## Goal

Compose a new agent pod for an existing tenant by going through the host's `openclaw-provisioner.service`. After completing this procedure you will have:

- a new agent record at `/var/lib/openclaw-platform/tenants/<tenant>/agents/<agent>.json`
- four (or five, with cloudflared) Quadlet units at `/etc/containers/systemd/users/<UID>/`
- a running `<tenant>-<agent>-pod.service` under the tenant's user manager
- one `agent_create` line in the provisioner audit log

This corresponds to Phase 3 of the multi-tenant build (`concepts/agent_provisioning.md`).

## Prerequisites

- A booted host running the multi-tenant host image with both `openclaw-broker.service` and `openclaw-provisioner.service` active.
- Admin (`root` / `sudo`) on the host *or* an agent inside an existing tenant's openclaw-runtime container that can call `agentctl`.
- A tenant created via `platformctl tenant create` (`how-to/create_a_tenant.md`).
- Any credentials the new agent needs already enrolled (`how-to/enroll_a_credential.md`).
- Any tenant volumes you want to mount already created on disk under `/var/lib/openclaw-platform/tenants/<tenant>/volumes/<name>/`.

Verify both daemons are up:

```bash
sudo systemctl is-active openclaw-broker.service openclaw-provisioner.service
test -S /run/openclaw-provisioner/admin.sock && echo "admin socket OK"
```

## Steps (admin-side)

1. **Inspect the policy** that constrains the request.

    ```bash
    sudo platformctl policy show alice
    ```

    Confirm that the runtime image, environment image, requested credentials, and network profile you want are all in the allowlists. Edit `/var/lib/openclaw-platform/tenants/alice/policy/policy.yaml` (root-owned `0644`) to add or remove items, then `sudo systemctl reload openclaw-provisioner.service` is **not** required — the provisioner reads the file at every request.

2. **Create a tenant volume the agent will mount** (skip if it already exists):

    ```bash
    sudo install -d -m 0700 -o tenant_alice -g tenant_alice \
        /var/lib/openclaw-platform/tenants/alice/volumes/shared-code
    ```

3. **Make sure the credentials the agent needs already exist:**

    ```bash
    sudo platformctl credential list alice
    ```

    See `how-to/enroll_a_credential.md` to add any that are missing.

4. **Create the agent.**

    ```bash
    sudo platformctl agent create alice \
        --name rust-coder \
        --runtime    quay.io/m0ranmcharles/fedora_init:openclaw-runtime \
        --environment quay.io/m0ranmcharles/fedora_init:dev-env \
        --credential codex \
        --credential github \
        --storage    shared-code \
        --network    restricted-internet
    ```

    On success the provisioner returns the rendered agent record and the list of Quadlet files it generated.

5. **Verify the agent is running.**

    ```bash
    sudo platformctl agent list alice
    sudo platformctl agent inspect alice rust-coder
    UID_=$(id -u tenant_alice)
    sudo machinectl shell tenant_alice@ /usr/bin/systemctl --user list-units --type=service \
        | grep alice-rust-coder
    ```

## Steps (agent-side)

The agent itself, running inside an existing openclaw-runtime container in the tenant's onboarding pod, asks for a new agent of its own:

```bash
# inside the container
agentctl policy-show

agentctl create-agent \
    --name research-bot \
    --runtime    quay.io/m0ranmcharles/fedora_init:openclaw-runtime \
    --environment quay.io/m0ranmcharles/fedora_init:dev-env \
    --credential gemini \
    --network    api-only

agentctl list-agents
agentctl inspect-agent research-bot
```

The transport is the bind-mounted `/run/agentctl/agentctl.sock`. The agent has no `podman`, no `systemctl`, no `mount`, no `cloudflared` — those verbs do not exist in `agentctl` and are not reachable from the runtime container.

## Verify

The provisioner audit log records each allow / deny:

```bash
sudo platformctl audit tail 20
# (this prints the *broker* audit log; the provisioner has its own)
sudo tail -n 20 /var/lib/openclaw-platform/provisioner/audit.log
```

A single boolean smoke check after agent creation:

```bash
sudo platformctl agent list alice | grep -q '"id": "rust-coder"' \
    && sudo platformctl agent inspect alice rust-coder | grep -q '"status": "running"' \
    && echo "agent: PASS" || echo "agent: FAIL"
```

## Common failures and what they mean

- **`runtime image 'X' not in allowed_images.openclaw_runtime`** — image is not allowlisted in the tenant's policy. Edit `policy.yaml` to add it (admin operation), or pick one that is already allowed.
- **`credential 'X' not in allowed_credentials`** — short-name not allowlisted. Edit `policy.yaml`.
- **`credential 'X' not present in broker store`** — the credential id has not been enrolled yet. Run `platformctl credential add` (`how-to/enroll_a_credential.md`).
- **`volume 'X' does not exist under tenant 'alice'`** — the directory is missing under the tenant's `volumes/`. Pre-create it with the right ownership.
- **`max_agents=N reached`** / **`max_running_agents=N reached`** — quota hit. Stop or delete an existing agent, or increase the limit in `policy.yaml`.
- **`policy forbids privileged=true on agent requests`** — the request set a forbidden flag. The agent CLI never sets these; if you see this, the calling client is sending unsupported fields.
- **`provisioner socket not present at /run/agentctl/agentctl.sock`** — the openclaw-runtime container started before the host provisioner registered the tenant's socket, or the socket file disappeared. `sudo systemctl restart openclaw-provisioner.service` reopens all per-tenant sockets via `discover_tenants()` at startup.
- **agent record exists but `status: failed`** — the Quadlets rendered but `systemctl start` failed. The record's `last_error` field contains the systemd output. The most common cause on first boot is the runtime / environment image not yet pulled into the tenant's rootless Podman storage — `sudo machinectl shell tenant_alice@ /usr/bin/podman pull <image>` then `platformctl agent start alice <name>`.

## Stopping and removing

```bash
sudo platformctl agent stop   alice rust-coder
sudo platformctl agent start  alice rust-coder
sudo platformctl agent delete alice rust-coder
```

`delete` stops the pod, removes the four (or five) Quadlet files for that agent, drops the JSON record, and runs `daemon-reload` under the tenant's user manager. The tenant's own onboarding pod and any other agents are untouched.

## See also

- `concepts/agent_provisioning.md`
- `concepts/multi_tenant_architecture.md`
- `reference/platformctl.md`
- `reference/agentctl.md`
- `reference/tenant_quadlets.md`
- `how-to/create_a_tenant.md`
- `how-to/enroll_a_credential.md`
- `how-to/verify_tenant_isolation.md`
