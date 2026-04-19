I will read the contents of `19_wsenv_map_persistent_memory_location_etc.md` and `20_create_system_btrfs_backup_on_dvar.md` to understand the current configuration of the workstation environment and the BTRFS backup strategy.
# 21. automate backup: ws-env -> sys-btrfs

This document details the automation of backups for the Workstation Environment (`ws-env`) persistent data to the system's primary BTRFS backup storage (`sys-btrfs`). This implementation leverages BTRFS snapshots and the `send/receive` protocol, managed via Podman Quadlets and Systemd Timers, consistent with the project's `bootc` architectural strategy.

## 1. Objective and Architecture

The goal is to ensure that all persistent state associated with the `ws-env` container is backed up weekly to a separate physical drive (or partition) formatted with BTRFS.

*   **Source Subvolumes:** Located under `/var/lib/ws-env/` (e.g., `/var/lib/ws-env/etc`, `/var/lib/ws-env/home`).
*   **Destination (sys-btrfs):** A mounted BTRFS filesystem, typically at `/mnt/storage/backups/ws-env`.
*   **Automation:** A Systemd Timer triggers a `oneshot` service that runs a containerized backup script.
*   **Strategy:** Atomic read-only snapshots combined with incremental `btrfs send`.

---

## 2. The Backup Logic (`backup-wsenv.sh`)

This script iterates through the subvolumes assigned to `ws-env` and performs the backup.

```bash
#!/bin/bash
# /usr/local/bin/backup-wsenv.sh

# Configuration
SOURCE_ROOT="/host/var/lib/ws-env"
BACKUP_ROOT="/backup/ws-env"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SUBVOLUMES=("etc" "home") # List of subvolumes to backup

echo "Starting ws-env backup to $BACKUP_ROOT..."

for SUB in "${SUBVOLUMES[@]}"; do
    SOURCE_PATH="$SOURCE_ROOT/$SUB"
    DEST_PATH="$BACKUP_ROOT/$SUB"
    SNAPSHOT_DIR="$SOURCE_ROOT/.snapshots/$SUB"
    LATEST_LINK="$DEST_PATH/latest"
    
    mkdir -p "$SNAPSHOT_DIR"
    mkdir -p "$DEST_PATH"

    NEW_SNAPSHOT="$SNAPSHOT_DIR/snap-$TIMESTAMP"
    
    echo "Creating snapshot for $SUB..."
    btrfs subvolume snapshot -r "$SOURCE_PATH" "$NEW_SNAPSHOT"

    # Incremental Send/Receive
    if [ -L "$LATEST_LINK" ]; then
        PARENT_SNAP=$(readlink -f "$LATEST_LINK")
        echo "Sending incremental update for $SUB..."
        btrfs send -p "$PARENT_SNAP" "$NEW_SNAPSHOT" | btrfs receive "$DEST_PATH"
    else
        echo "Sending initial full backup for $SUB..."
        btrfs send "$NEW_SNAPSHOT" | btrfs receive "$DEST_PATH"
    fi

    # Update latest symlink for next incremental run
    rm -f "$LATEST_LINK"
    ln -s "$(basename "$NEW_SNAPSHOT")" "$LATEST_LINK"

    # Cleanup: Keep only the last 2 snapshots on the source for incrementals
    ls -dt "$SNAPSHOT_DIR"/snap-* | tail -n +3 | xargs -r btrfs subvolume delete
done

echo "ws-env backup sequence completed."
```

---

## 3. Quadlet Configuration

We define the backup as a containerized task using Quadlet files. This keeps the host's runtime environment clean and ensures the backup tools (like `btrfs-progs`) are available regardless of the host's minimal `bootc` package set.

### `ws-env-backup.container`
This file defines the execution environment.

```ini
[Unit]
Description=Automated ws-env BTRFS Backup
After=local-fs.target ws-env.service

[Container]
Image=localhost/btrfs-backup:latest
# Mount the host /var to access ws-env subvolumes
Volume=/var:/host/var:rbind
# Mount the sys-btrfs backup location
Volume=/mnt/storage/backups:/backup:rw
# Required for btrfs send/receive and snapshotting
Privileged=true

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-wsenv.sh

[Install]
WantedBy=multi-user.target
```

### `ws-env-backup.timer`
This schedules the backup to run weekly, specifically on Saturday nights to precede the Sunday system-wide backup.

```ini
[Unit]
Description=Weekly ws-env Backup Timer

[Timer]
# Run every Saturday at 11:00 PM
OnCalendar=Sat *-*-* 23:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

## 4. Integration into the `bootc` Image

To automate this setup, the backup script and Quadlets must be baked into the system image via the `Containerfile`.

### System `Containerfile` Snippet

```dockerfile
# ... (Base Fedora bootc setup) ...

# 1. Ensure backup destination mount point exists
RUN mkdir -p /mnt/storage/backups

# 2. Deploy the backup script
COPY backup-wsenv.sh /usr/local/bin/backup-wsenv.sh
RUN chmod +x /usr/local/bin/backup-wsenv.sh

# 3. Deploy Quadlet files
COPY ws-env-backup.container /etc/containers/systemd/
COPY ws-env-backup.timer /etc/containers/systemd/

# 4. Build or Pull the backup tool container
# Assuming 'btrfs-backup' image was built in Task 20
# If not, ensure btrfs-progs are in the host or a local build step:
RUN podman build -t localhost/btrfs-backup:latest - <<EOF
FROM fedora:latest
RUN dnf install -y btrfs-progs && dnf clean all
EOF

# 5. Enable the timer
RUN systemctl enable ws-env-backup.timer
```

---

## 5. Summary of Workflow

1.  **Weekly Saturday 23:00:** The `ws-env-backup.timer` triggers.
2.  **Snapshotting:** The script creates read-only BTRFS snapshots of `/var/lib/ws-env/etc` and `/home`.
3.  **Transfer:** `btrfs send` pipes the snapshots to the `sys-btrfs` drive at `/mnt/storage/backups/ws-env/`.
4.  **Incrementality:** After the first run, only changed blocks are transferred, keeping the process fast and efficient.
5.  **Retention:** The script automatically prunes old snapshots on the host while keeping the full history on the backup drive.

This approach ensures that even if the `bootc` image is wiped and the system reinstalled, the workstation's configuration and user data are safely preserved on a separate physical medium, ready to be restored or referenced.