I will now create the markdown document "20. create system btrfs backup on D:/var/" based on your Fedora bootc and Podman Quadlet strategy.

# 20. create system btrfs backup on D:/var/

This document outlines the implementation of an automated BTRFS backup system for the Fedora `bootc` workstation. Following the project's strategy, we will use `btrfs send/receive` for efficient, incremental snapshots and manage the backup process using **Podman Quadlets** integrated directly into the `bootc` image.

## 1. Overview of the Backup Strategy

*   **Source:** Specific subvolumes or directories (e.g., `/home`, `/var/lib/containers`).
*   **Destination:** A secondary storage drive mounted at `/mnt/storage` (referenced as `D:/var/` in planning).
*   **Method:** `btrfs send` and `btrfs receive`. This allows for atomic, point-in-time backups that only transfer changed blocks.
*   **Automation:** A Podman-managed container running via a Systemd Timer (Quadlet) to ensure the backup runs weekly.
*   **Persistence:** The backup snapshots remain on the secondary drive, ready for later compression and cloud upload.

---

## 2. The Backup Script (`btrfs-backup.sh`)

This script handles the creation of read-only snapshots and the incremental transfer.

```bash
#!/bin/bash
# /usr/local/bin/btrfs-backup.sh

SOURCE_SUBVOL="/host/home"
BACKUP_DEST="/backup/home-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LATEST_SNAPSHOT="$BACKUP_DEST/latest"

echo "Starting BTRFS backup to $BACKUP_DEST..."

# 1. Create a new read-only snapshot of the source
NEW_SNAPSHOT="/host/home-snapshots/snapshot-$TIMESTAMP"
mkdir -p /host/home-snapshots
btrfs subvolume snapshot -r "$SOURCE_SUBVOL" "$NEW_SNAPSHOT"

# 2. Perform incremental send if a previous snapshot exists
if [ -L "$LATEST_SNAPSHOT" ]; then
    PARENT_SNAPSHOT=$(readlink -f "$LATEST_SNAPSHOT")
    echo "Performing incremental backup from $PARENT_SNAPSHOT..."
    btrfs send -p "$PARENT_SNAPSHOT" "$NEW_SNAPSHOT" | btrfs receive "$BACKUP_DEST"
else
    echo "Performing full initial backup..."
    btrfs send "$NEW_SNAPSHOT" | btrfs receive "$BACKUP_DEST"
fi

# 3. Update the 'latest' symlink for the next run
rm -f "$LATEST_SNAPSHOT"
ln -s "$(basename "$NEW_SNAPSHOT")" "$LATEST_SNAPSHOT"

# 4. Cleanup old local snapshots (keep last 2)
ls -dt /host/home-snapshots/snapshot-* | tail -n +3 | xargs -r btrfs subvolume delete

echo "Backup completed successfully."
```

---

## 3. The Backup Containerfile

We containerize the backup logic to keep the host OS clean, as per the `bootc` philosophy.

```dockerfile
# Containerfile.backup
FROM fedora:latest

# Install btrfs-progs
RUN dnf install -y btrfs-progs && dnf clean all

COPY btrfs-backup.sh /usr/local/bin/btrfs-backup.sh
RUN chmod +x /usr/local/bin/btrfs-backup.sh

ENTRYPOINT ["/usr/local/bin/btrfs-backup.sh"]
```

---

## 4. Quadlet Configuration

We use two Quadlet files: a `.container` to define the backup execution and a `.timer` to schedule it.

### `backup-system.container`
This file defines the containerized service. It requires privileged access to perform BTRFS operations on the host's subvolumes.

```ini
[Unit]
Description=BTRFS System Backup Service
After=local-fs.target

[Container]
Image=localhost/btrfs-backup:latest
# Mount the host root to access subvolumes (RO for source, RW for snapshot creation)
Volume=/:/host:rbind
# Mount the destination drive (D:/var/ mapping)
Volume=/mnt/storage/var:/backup:rw
# Required for btrfs send/receive
Privileged=true

[Service]
# Ensure the container exits after the backup finishes
Type=oneshot

[Install]
WantedBy=multi-user.target
```

### `backup-system.timer`
This file schedules the backup to run weekly.

```ini
[Unit]
Description=Weekly BTRFS Backup Timer

[Timer]
# Run every Sunday at 3:00 AM
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

## 5. Integration into the `bootc` Containerfile

To ensure this is part of the core system build, add the following to your main `Containerfile`:

```dockerfile
# ... existing bootc build steps ...

# 1. Copy the backup script and Quadlets into the image
COPY btrfs-backup.sh /usr/local/bin/btrfs-backup.sh
COPY backup-system.container /etc/containers/systemd/
COPY backup-system.timer /etc/containers/systemd/

# 2. Build the backup image locally during the bootc build
# (Or pull it from a registry if built separately)
COPY Containerfile.backup /tmp/Containerfile.backup
RUN podman build -t localhost/btrfs-backup:latest -f /tmp/Containerfile.backup

# 3. Ensure the timer is enabled by default
RUN systemctl enable backup-system.timer
```

---

## 6. Actionable Steps to Execute

1.  **Prepare the Destination:** Ensure your secondary drive is formatted as BTRFS and mounted.
    ```bash
    mkfs.btrfs -L DATA_DRIVE /dev/sdb1
    mkdir -p /mnt/storage/var
    mount /dev/sdb1 /mnt/storage/var
    ```
2.  **Add to `/etc/fstab`:** Ensure the drive mounts on boot so the Quadlet can find it.
3.  **Build the `bootc` image:** Run your build pipeline. The Quadlet will automatically generate the systemd units on the first boot.
4.  **Verify:** After deployment, check the status of the timer:
    ```bash
    systemctl status backup-system.timer
    ```
5.  **Manual Trigger:** To test the backup immediately:
    ```bash
    systemctl start backup-system.service
    ```