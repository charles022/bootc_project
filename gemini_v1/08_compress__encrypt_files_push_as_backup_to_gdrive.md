# 8. Compress + Encrypt Files, Push as Backup to GDrive

This guide outlines the implementation of an automated, secure cloud backup pipeline for your `bootc` system. Following the strategy of keeping the core image lean and using Podman Quadlets for operational tasks, we will deploy a containerized backup worker that compresses, encrypts, and synchronizes your BTRFS snapshots to Google Drive using `rclone` and `GnuPG`.

## 1. Architectural Overview

The backup process follows these stages:
1.  **Source:** BTRFS snapshots stored on the secondary drive.
2.  **Process:** A dedicated Podman container mounts the source, performs compression, encrypts the archive, and pushes it to GDrive.
3.  **Automation:** A Systemd Timer (via Quadlet) triggers the container on a weekly or monthly schedule.
4.  **Security:** GPG encryption ensures that even if the cloud provider is compromised, your data remains private.

---

## 2. Prerequisites: Rclone Configuration

Before automating, you must configure `rclone` to access your Google Drive. Since this requires an interactive OAuth flow, perform this once on a machine with a web browser (or via `rclone config` on the CLI if you use the "headless" flow).

1.  Install rclone locally: `sudo dnf install rclone`
2.  Run `rclone config` and create a new remote named `gdrive`.
3.  Follow the prompts to authorize access to Google Drive.
4.  Locate your config file (usually at `~/.config/rclone/rclone.conf`). You will need this content for the Quadlet.

---

## 3. The Backup Script (`backup-to-gdrive.sh`)

This script will reside inside our backup container image. It handles the logic of finding the latest snapshots, archiving them, and uploading.

```bash
#!/bin/bash
set -e

# Configuration (passed via Env or hardcoded in script)
SOURCE_DIR="/mnt/backups/snapshots"
TEMP_DIR="/tmp/backup_stage"
GPG_RECIPIENT="${GPG_RECIPIENT}"
REMOTE_TARGET="gdrive:backups/$(hostname)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_${TIMESTAMP}.tar.zst.gpg"

mkdir -p "${TEMP_DIR}"

echo "Starting backup: ${BACKUP_NAME}"

# 1. Compress and Encrypt on the fly
# Using zstd for high-speed, high-ratio compression
tar -cf - -C "${SOURCE_DIR}" . | \
    zstd -10 | \
    gpg --encrypt --recipient "${GPG_RECIPIENT}" --trust-model always \
    > "${TEMP_DIR}/${BACKUP_NAME}"

echo "Upload started..."

# 2. Push to Google Drive
rclone copy "${TEMP_DIR}/${BACKUP_NAME}" "${REMOTE_TARGET}" --config /etc/rclone/rclone.conf

# 3. Cleanup
rm "${TEMP_DIR}/${BACKUP_NAME}"

echo "Backup successfully pushed to ${REMOTE_TARGET}"
```

---

## 4. The Backup Containerfile

We build a specialized image containing `rclone`, `gnupg`, and `zstd`.

```dockerfile
FROM fedora:40

# Install required tools
RUN dnf install -y rclone gnupg2 zstd tar && \
    dnf clean all

# Create directories
RUN mkdir -p /etc/rclone /root/.gnupg

# Copy the backup script
COPY backup-to-gdrive.sh /usr/local/bin/backup-to-gdrive.sh
RUN chmod +x /usr/local/bin/backup-to-gdrive.sh

ENTRYPOINT ["/usr/local/bin/backup-to-gdrive.sh"]
```

---

## 5. Quadlet Configuration

To integrate this into the `bootc` system, we use Quadlet files placed in `/etc/containers/systemd/`.

### A. The Container Quadlet (`backup-gdrive.container`)
This defines the execution environment. Note the mounting of the rclone config and the GPG keyring.

```ini
[Unit]
Description=Compress, Encrypt, and Push Backups to GDrive
After=network-online.target

[Container]
Image=quay.io/youruser/backup-worker:latest
Environment=GPG_RECIPIENT=your-email@example.com
# Mount the rclone config created in step 2
Volume=/etc/rclone/rclone.conf:/etc/rclone/rclone.conf:Z
# Mount the host GPG directory to access public keys
Volume=/root/.gnupg:/root/.gnupg:Z
# Mount the source snapshots from the large drive
Volume=/mnt/data/snapshots:/mnt/backups/snapshots:ro
# Run as host network if needed for rclone
Network=host

[Service]
# Restart logic for transient network failures
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
```

### B. The Timer Quadlet (`backup-gdrive.timer`)
This schedules the backup to run weekly.

```ini
[Unit]
Description=Run GDrive Backup Weekly

[Timer]
# Run every Sunday at 3:00 AM
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

## 6. Deployment Workflow

1.  **Build and Push the Image:**
    Build the `backup-worker` image and push it to your registry (e.g., Quay.io).
    ```bash
    podman build -t quay.io/youruser/backup-worker:latest .
    podman push quay.io/youruser/backup-worker:latest
    ```

2.  **Prepare GPG:**
    Ensure the public key for `GPG_RECIPIENT` is imported on the host:
    ```bash
    gpg --import my_public_key.asc
    ```

3.  **Apply to Bootc Image:**
    In your main `bootc` Containerfile, ensure the Quadlet files are included:
    ```dockerfile
    COPY backup-gdrive.container /etc/containers/systemd/
    COPY backup-gdrive.timer /etc/containers/systemd/
    ```

4.  **Verify:**
    After the system reboots into the new image, verify the timer is active:
    ```bash
    systemctl list-timers backup-gdrive.timer
    ```
    To test the backup immediately:
    ```bash
    systemctl start backup-gdrive.service
    ```

## 7. Recovery Strategy

To restore, you would:
1.  Download the encrypted file from GDrive: `rclone copy gdrive:backups/hostname/file.gpg .`
2.  Decrypt and decompress:
    ```bash
    gpg --decrypt file.gpg | zstd -d | tar -xf -
    ```