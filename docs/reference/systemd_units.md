# Systemd units

This document catalogs the systemd units authored for this project and the native host services enabled in the host image.

## Project-specific units

### bootc-host-test.service
- **Path**: `/usr/lib/systemd/system/bootc-host-test.service`
- **Type**: oneshot service
- **Purpose**: Runs a suite of health checks to verify host networking, GPU availability, and Quadlet state.
- **Triggers**: Starts automatically during normal boot.
- **Implements**: `/opt/project/bootc_host_test.sh`
- **Enabled at build time?**: Yes
- **Notes**: Runs after `sshd.service` and `nvidia-cdi-refresh.service`.

### bootc-update.timer
- **Path**: `/usr/lib/systemd/system/bootc-update.timer`
- **Type**: timer
- **Purpose**: Triggers a weekly rebuild and staging of the host image.
- **Triggers**: Fires every Sunday at 03:00; uses `Persistent=true` to catch up if the host was powered off.
- **Implements**: `bootc-update.service`
- **Enabled at build time?**: Yes

### bootc-update.service
- **Path**: `/usr/lib/systemd/system/bootc-update.service`
- **Type**: oneshot service
- **Purpose**: Rebuilds the host image in an ephemeral container and stages it to the local OSTree repository.
- **Triggers**: Activated by `bootc-update.timer`.
- **Implements**: `/usr/local/bin/bootc-update.sh`
- **Enabled at build time?**: No (triggered by timer)

### bootc-firstboot-push.service
- **Path**: `/usr/lib/systemd/system/bootc-firstboot-push.service`
- **Type**: oneshot service
- **Purpose**: Conditionally pushes a freshly-booted image to Quay to verify its health before distribution.
- **Triggers**: Runs only on the first boot of a new deployment (`ConditionFirstBoot=yes`).
- **Implements**: `/usr/local/bin/bootc-firstboot-push.sh`
- **Enabled at build time?**: Yes

### nvidia-cdi-refresh.path
- **Path**: `/usr/lib/systemd/system/nvidia-cdi-refresh.path`
- **Type**: path watcher
- **Purpose**: Monitors for the presence of NVIDIA device nodes to trigger CDI generation.
- **Triggers**: Fires when `/dev/nvidiactl` exists.
- **Implements**: `nvidia-cdi-refresh.service`
- **Enabled at build time?**: Yes

### nvidia-cdi-refresh.service
- **Path**: `/usr/lib/systemd/system/nvidia-cdi-refresh.service`
- **Type**: oneshot service
- **Purpose**: Generates the Container Device Interface (CDI) specification for NVIDIA GPUs.
- **Triggers**: Activated by `nvidia-cdi-refresh.path` or starts at boot.
- **Implements**: `nvidia-ctk cdi generate`
- **Enabled at build time?**: Yes

### getty@tty1.service drop-in
- **Path**: `/etc/systemd/system/getty@tty1.service.d/override.conf`
- **Type**: drop-in configuration
- **Purpose**: Enables automatic login for the root user on the physical or virtual console.
- **Triggers**: Starts when `getty@tty1.service` is activated.
- **Implements**: `/sbin/agetty` flags
- **Enabled at build time?**: Yes (active by default for tty1)
- **Notes**: Intended for recovery and VM console access; does not affect SSH or network security.

### openclaw-provisioner.service
- **Path**: `/usr/lib/systemd/system/openclaw-provisioner.service`
- **Type**: simple long-running daemon
- **Purpose**: The host agent-provisioning daemon (`concepts/agent_provisioning.md`). Reads per-tenant `policy.yaml`, validates `agent_create` requests, renders agent Quadlets, drives the tenant's user-mode systemd to start the new pod, appends to `/var/lib/openclaw-platform/provisioner/audit.log`.
- **Triggers**: Starts at boot via `WantedBy=multi-user.target`. `Restart=on-failure` with `RestartSec=5s`. Sets `RuntimeDirectory=openclaw-provisioner` and `StateDirectory=openclaw-platform/provisioner`. `After=openclaw-broker.service` and `Wants=openclaw-broker.service` so the broker is up first for credential cross-checks.
- **Implements**: `/usr/local/bin/openclaw-provisioner` (Python daemon).
- **Enabled at build time?**: Yes
- **Notes**: Admin socket enforces peer-UID 0. Per-tenant sockets are chowned to `tenant_<tenant>` so the rootless `openclaw-runtime` container can mount them.

### openclaw-broker.service
- **Path**: `/usr/lib/systemd/system/openclaw-broker.service`
- **Type**: simple long-running daemon
- **Purpose**: The host credential broker (`concepts/credential_broker.md`). Owns the encrypted credential store, the grant table, the audit log, and the admin / per-tenant UNIX sockets that tenant pods' `credential-proxy` sidecars connect through.
- **Triggers**: Starts at boot via `WantedBy=multi-user.target`. `Restart=on-failure` with `RestartSec=5s`. Sets `RuntimeDirectory=openclaw-broker` and `StateDirectory=openclaw-platform/broker` so systemd creates `/run/openclaw-broker/` and `/var/lib/openclaw-platform/broker/` with the right modes.
- **Implements**: `/usr/local/bin/openclaw-broker` (Python daemon).
- **Enabled at build time?**: Yes
- **Notes**: Requires `python3-cryptography`. Logs to the journal. The admin socket enforces peer-UID 0 via `SO_PEERCRED`; per-tenant sockets are chowned to `tenant_<tenant>` so the rootless tenant pod can mount them.

## Native host services

These services are part of the base Fedora Bootc image or installed via `dnf` and are explicitly enabled during the build.

### sshd
- **Purpose**: Provides remote shell access.
- **Enabled at build time?**: Yes

### cloud-init.target
- **Purpose**: Orchestrates the four stages of cloud-init (generator, local, network, config) for first-boot provisioning.
- **Enabled at build time?**: Yes

## Quadlet-generated units

Quadlet files located in `/usr/share/containers/systemd/` are processed by `systemd-quadlet-generator` at boot time. This project includes `devpod.kube`, which results in a `devpod.service` unit. See `reference/quadlets.md` for the field-by-field breakdown and `concepts/ownership_model.md` for the role Quadlet plays in the architecture.

### Per-tenant Quadlet-generated user units

When `platformctl tenant create <tenant>` runs, it renders Quadlet templates into `/etc/containers/systemd/users/<UID>/`. Podman's user-mode generator processes them under the tenant's user manager and produces:

- `<tenant>-onboard-pod.service` (from `<tenant>-onboard.pod`)
- `<tenant>-cloudflared.service` (from `<tenant>-cloudflared.container`)
- `<tenant>-onboard-env.service` (from `<tenant>-onboard-env.container`)
- `<tenant>-openclaw-runtime.service` (from `<tenant>-openclaw-runtime.container`)
- `<tenant>-credential-proxy.service` (from `<tenant>-credential-proxy.container`)

These run **as the tenant service account**, not as root. Inspect them with `systemctl --user --machine=tenant_<tenant>@ list-units`. See `reference/tenant_quadlets.md`.

## Boot order

On a typical first boot of a new deployment, units activate in this approximate sequence:

1. **`cloud-init.target`**: Processes any provided user data or SSH keys.
2. **`nvidia-cdi-refresh.service`**: Generates the CDI spec once drivers and device nodes are ready.
3. **`devpod.service`**: (Generated from Quadlet) Starts the dev pod once Podman and CDI are available.
4. **`sshd.service`**: Enables remote access.
5. **`openclaw-broker.service`**: Opens the admin socket and per-tenant sockets so tenant pods' credential-proxy sidecars can reach it.
6. **`openclaw-provisioner.service`**: Opens its own admin and per-tenant sockets (after the broker) so tenant pods' openclaw-runtime containers can call `agentctl`.
7. **`bootc-host-test.service`**: Validates the health of the entire stack.
8. **`bootc-firstboot-push.service`**: Pushes the verified image to Quay if requested by configuration.
