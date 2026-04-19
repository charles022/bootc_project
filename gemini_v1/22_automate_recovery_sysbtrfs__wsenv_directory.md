# 22. automate recovery: sys-btrfs -> ws-env directory

This document outlines the automation strategy for recovering the Workstation Environment (`ws-env`) from BTRFS snapshots stored in the system backup location (`sys-btrfs`). 

In our Fedora bootc architecture, the system OS is immutable and ephemeral, but the workstation environment is persistent. By leveraging BTRFS `send/receive`, we can restore the exact state of our workstation subvolume from the backups located on our secondary storage (e.g., `/var/mnt/dvar`).

## 1. Architectural Approach

- **Subvolume Recovery**: We treat `ws-env` as a BTRFS subvolume. Recovery involves deleting the current (potentially corrupted) subvolume and "receiving" a fresh copy from the latest snapshot in `sys-btrfs`.
- **Systemd Integration**: A recovery script is baked into the bootc image. A systemd service (Quadlet-compatible) provides a standard interface to trigger the recovery.
- **Persistence**: The recovery process ensures that permissions and SELinux contexts are preserved so the Podman Workstation container can immediately mount the restored data.

## 2. The Recovery Script

This script handles the logic of identifying the latest backup, stopping dependencies, and performing the BTRFS receive operation.

**File:** `/usr/local/bin/ws-restore`

```bash
#!/bin/bash
# ws-restore: Restore the workstation environment from BTRFS snapshots

BACKUP_ROOT="/var/mnt/dvar/sys-btrfs"
WS_ENV_PATH="/var/home/chuck/ws-env"
WS_CONTAINER_SERVICE="container-workstation.service"

set -e

echo "Starting recovery of $WS_ENV_PATH..."

# 1. Identify the latest snapshot
LATEST_SNAPSHOT=$(ls -dt ${BACKUP_ROOT}/ws-env-backup-* | head -n 1)

if [ -z "$LATEST_SNAPSHOT" ]; then
    echo "Error: No snapshots found in $BACKUP_ROOT"
    exit 1
fi

echo "Latest snapshot identified: $LATEST_SNAPSHOT"

# 2. Stop the workstation container to release file handles
echo "Stopping workstation container..."
systemctl stop $WS_CONTAINER_SERVICE || true

# 3. Remove the current subvolume
if [ -d "$WS_ENV_PATH" ]; then
    echo "Removing existing subvolume at $WS_ENV_PATH..."
    # If it's a subvolume, use btrfs tool; otherwise standard rm
    if btrfs subvolume show "$WS_ENV_PATH" >/dev/null 2>&1; then
        btrfs subvolume delete "$WS_ENV_PATH"
    else
        rm -rf "$WS_ENV_PATH"
    fi
fi

# 4. Receive the snapshot
echo "Receiving BTRFS snapshot..."
# Note: This assumes the backup was created using 'btrfs send'
# We pipe the snapshot into 'btrfs receive' targeting the parent directory
PARENT_DIR=$(dirname "$WS_ENV_PATH")
mkdir -p "$PARENT_DIR"

# btrfs receive creates a subvolume named after the snapshot; we then rename it
TEMP_NAME=$(basename "$LATEST_SNAPSHOT")
btrfs receive "$PARENT_DIR" < "$LATEST_SNAPSHOT"
mv "${PARENT_DIR}/${TEMP_NAME}" "$WS_ENV_PATH"

# 5. Fix permissions and SELinux labels
echo "Restoring SELinux contexts and permissions..."
chown -R chuck:chuck "$WS_ENV_PATH"
restorecon -R "$WS_ENV_PATH"

# 6. Restart the workstation
echo "Restarting workstation container..."
systemctl start $WS_CONTAINER_SERVICE

echo "Recovery complete."
```

## 3. The Recovery Service (Systemd Unit)

Instead of a Quadlet `.container`, we use a standard Systemd `.service` unit for recovery because it is an administrative action on the host filesystem, not a long-running containerized process.

**File:** `/usr/local/lib/systemd/system/ws-restore.service`

```ini
[Unit]
Description=Automated Recovery of Workstation Environment from BTRFS
After=var-mnt-dvar.mount
Requires=var-mnt-dvar.mount

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ws-restore
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

## 4. Bootc Image Integration

To include this automation in the system, add the following instructions to the core bootc `Containerfile`. This ensures every instance of the OS has the recovery tools ready.

**File:** `Containerfile` (fragment)

```dockerfile
# ... existing bootc instructions ...

# Install the recovery script
COPY scripts/ws-restore /usr/local/bin/ws-restore
RUN chmod +x /usr/local/bin/ws-restore

# Install the systemd recovery unit
COPY units/ws-restore.service /usr/lib/systemd/system/ws-restore.service

# Note: We do not enable this service by default. 
# It is triggered manually when recovery is needed.
```

## 5. Usage and Execution

Once the bootc image is deployed, the recovery process is fully automated but requires a manual trigger for safety (to prevent accidental rollbacks).

### Manual Trigger
To restore the workstation environment to the latest backup state:
```bash
sudo systemctl start ws-restore.service
```

### Verification
Monitor the logs to ensure the BTRFS receive completed successfully:
```bash
journalctl -u ws-restore.service -f
```

### Automation via Quadlet "Health" (Advanced)
If you wish to automate recovery upon a specific failure (e.g., the workstation container fails to start 3 times), you can add a `StartLimitAction` to your Workstation Quadlet file:

```ini
# workstation.container (fragment)
[Unit]
StartLimitIntervalSec=300
StartLimitBurst=3
StartLimitAction=reboot-force # Or trigger the service if logic permits
```

However, for data integrity, the recommended approach is the manual `systemctl start ws-restore` to ensure the user is aware the state is being reverted.