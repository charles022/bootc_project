# 19. ws-env: map persistent memory location /etc

## Overview

In the `bootc` and Quadlet-based architecture, the Workstation Environment (`ws-env`) container is designed to be refreshed weekly. While the container image provides the base software, certain configurations within `/etc` (such as SSH host keys, custom system-wide configurations, and service settings) must persist across container recreations and image updates.

This document outlines the strategy for mapping a persistent BTRFS-backed location on the host to the container's `/etc` directory, ensuring configuration continuity while maintaining the ability to snapshot and back up the state.

## 1. Strategy: BTRFS Subvolumes for Persistence

Following the project's strategy of using **BTRFS** for snapshots and backups, we will create a dedicated subvolume on the host to house the persistent `/etc` data for the workstation.

- **Host Path:** `/var/lib/ws-env/etc`
- **Container Path:** `/etc`
- **Mount Type:** Bind mount with SELinux labeling (`:Z`).

The use of `/var` is mandatory because in Fedora `bootc`, `/var` is the primary writable and persistent location across system updates.

## 2. Host-Side Preparation

To ensure the persistent storage is ready before the container starts, we use the `Containerfile` of the base `bootc` image to ensure the directory structure exists, and a systemd unit to manage the BTRFS subvolume if it doesn't already exist.

### Containerfile Snippet (Base bootc Image)
Add this to your core system `Containerfile` to ensure the mount point exists:

```dockerfile
# Ensure the persistence root exists on the host
RUN mkdir -p /var/lib/ws-env/etc
```

### BTRFS Subvolume Setup Script
This script (or a systemd unit) ensures that the directory is a BTRFS subvolume to enable the "btrfs send" backup strategy mentioned in the whitepaper.

```bash
#!/bin/bash
# setup-ws-persistence.sh

PERSIST_DIR="/var/lib/ws-env/etc"

if [ ! -d "$PERSIST_DIR" ]; then
    mkdir -p /var/lib/ws-env
fi

if ! btrfs subvolume show "$PERSIST_DIR" > /dev/null 2>&1; then
    echo "Creating BTRFS subvolume for ws-env /etc..."
    # If directory exists but isn't a subvolume, move it and create subvolume
    if [ -d "$PERSIST_DIR" ]; then
        mv "$PERSIST_DIR" "${PERSIST_DIR}.bak"
    fi
    btrfs subvolume create "$PERSIST_DIR"
    
    # Restore backup if it existed
    if [ -d "${PERSIST_DIR}.bak" ]; then
        cp -a "${PERSIST_DIR}.bak/." "$PERSIST_DIR/"
        rm -rf "${PERSIST_DIR}.bak"
    fi
fi
```

## 3. Quadlet Configuration: `ws-env.container`

The Quadlet file manages the lifecycle of the workstation container. We map the host subvolume to the container's `/etc`. 

**Note on Initialization:** Mapping a host directory over the container's `/etc` will hide the original contents. We use a "copy-on-empty" strategy or a specific volume management approach. In Podman Quadlets, we can use an overlay or a pre-initialization script.

```ini
[Unit]
Description=Workstation Environment Container
After=network-online.target

[Container]
Image=quay.io/your-repo/ws-env:latest
ContainerName=ws-env

# Map persistent /etc
# We use :Z to handle SELinux relabeling for the container
Volume=/var/lib/ws-env/etc:/etc:Z

# Environment and User setup
User=workstation
WorkingDir=/home/workstation

# Publish SSH for access (ref: Task 18)
PublishPort=2222:22

# Ensure we have necessary capabilities
AddCapability=CAP_NET_ADMIN CAP_SYS_ADMIN

[Service]
# Optional: Ensure subvolume is ready before starting
ExecStartPre=/usr/local/bin/setup-ws-persistence.sh

[Install]
WantedBy=multi-user.target default.target
```

## 4. Handling Initial `/etc` Population

Since bind-mounting an empty host directory over `/etc` would break the container, we have two primary options:

### Option A: The "Seed" Approach (Recommended)
Modify the `ws-env` entrypoint script to check if `/etc` is empty (or missing a marker file) and populate it from a backup location within the image.

**In the `ws-env` Containerfile:**
```dockerfile
# Save the default etc to a template location
RUN cp -a /etc /etc.template
```

**In the entrypoint script (`entrypoint.sh`):**
```bash
#!/bin/bash
if [ -z "$(ls -A /etc)" ]; then
    echo "Initializing persistent /etc from template..."
    cp -a /etc.template/. /etc/
fi
exec "$@"
```

## 5. Integration with BTRFS Backup Pipeline

As per the whitepaper, these persistent locations are subject to `btrfs send` backups.

### Snapshot Script Snippet
This logic would be incorporated into the weekly backup timer:

```bash
#!/bin/bash
# backup-ws-etc.sh
BACKUP_ROOT="/mnt/backups/ws-env"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
SNAPSHOT_PATH="/var/lib/ws-env/etc_snapshot_${TIMESTAMP}"

# Create read-only snapshot
btrfs subvolume snapshot -r /var/lib/ws-env/etc "$SNAPSHOT_PATH"

# Send to backup storage
btrfs send "$SNAPSHOT_PATH" | btrfs receive "$BACKUP_ROOT"

# Cleanup old snapshot
btrfs subvolume delete "$SNAPSHOT_PATH"
```

## 6. Actionable Implementation Steps

1.  **Update Host Image:** Add the `mkdir` command to your base `bootc` Containerfile to ensure the path exists on the host.
2.  **Deploy Setup Script:** Place the `setup-ws-persistence.sh` script on the host (via `bootc` image at `/usr/local/bin/`).
3.  **Configure ws-env Image:** 
    *   Create `/etc.template` in the workstation `Containerfile`.
    *   Add the initialization logic to the entrypoint.
4.  **Deploy Quadlet:** Place `ws-env.container` in `/etc/containers/systemd/`.
5.  **Reload Systemd:** Run `systemctl daemon-reload` and `systemctl start ws-env`.

By mapping `/etc` this way, the `ws-env` container gains "memory" of its system configurations, allowing it to behave like a persistent workstation while benefiting from the immutable, reproducible nature of the `bootc` host.