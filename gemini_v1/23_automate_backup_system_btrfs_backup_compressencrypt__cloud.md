# 23. automate backup: system btrfs backup compress/encrypt -> cloud

This document defines the final stage of the automated backup pipeline for the Fedora `bootc` system. Building upon the local BTRFS snapshots created in Tasks 20 and 21, this process implements an offsite, encrypted "3-2-1" backup strategy. It uses containerized tools (`rclone`, `GnuPG`, `zstd`) managed by Podman Quadlets to ensure data is compressed, secured, and synchronized to cloud storage.

## 1. Objective and Strategy

The goal is to take the point-in-time BTRFS snapshots stored on the secondary backup drive and move them to a cloud provider (e.g., Google Drive, AWS S3, or Backblaze B2).

*   **Source:** Local BTRFS snapshots on the secondary drive (typically `/mnt/storage/var/backups`).
*   **Compression:** High-ratio `zstd` compression to reduce bandwidth and storage costs.
*   **Encryption:** Symmetric or asymmetric `GnuPG` encryption to ensure zero-knowledge privacy in the cloud.
*   **Transport:** `rclone` for robust, resumeable uploads to nearly any cloud provider.
*   **Automation:** A weekly Systemd Timer (Quadlet) that triggers after the local backup completion.

---

## 2. The Cloud Sync Script (`cloud-backup.sh`)

This script identifies the latest snapshots, bundles them into an encrypted archive, and uploads them.

```bash
#!/bin/bash
# /usr/local/bin/cloud-backup.sh
set -e

# Configuration
SOURCE_DIR="/mnt/local-backups"
TEMP_DIR="/tmp/cloud_stage"
GPG_RECIPIENT="${GPG_RECIPIENT}" # Email or Key ID
REMOTE_NAME="gdrive"            # Configured in rclone
REMOTE_PATH="backups/$(hostname)"
TIMESTAMP=$(date +%Y%m%d)
FILENAME="sys-backup-${TIMESTAMP}.tar.zst.gpg"

mkdir -p "${TEMP_DIR}"

echo "Starting cloud backup preparation for ${FILENAME}..."

# 1. Archive, Compress, and Encrypt in a pipeline
# We use tar -C to change directory and bundle the latest snapshots
tar -cf - -C "${SOURCE_DIR}" . | \
    zstd -10 -T0 | \
    gpg --batch --encrypt --recipient "${GPG_RECIPIENT}" --trust-model always \
    > "${TEMP_DIR}/${FILENAME}"

echo "Upload initiated to ${REMOTE_NAME}:${REMOTE_PATH}..."

# 2. Upload using rclone
rclone copy "${TEMP_DIR}/${FILENAME}" "${REMOTE_NAME}:${REMOTE_PATH}" \
    --config /etc/rclone/rclone.conf \
    --progress

# 3. Cleanup
rm "${TEMP_DIR}/${FILENAME}"

echo "Cloud backup successfully completed."
```

---

## 3. The Backup Worker Containerfile

We create a dedicated utility image to keep the core `bootc` image free of heavy backup dependencies.

```dockerfile
# Containerfile.cloud-backup
FROM fedora:latest

# Install rclone, gnupg, and compression tools
RUN dnf install -y rclone gnupg2 zstd tar && \
    dnf clean all

# Ensure script is available
COPY cloud-backup.sh /usr/local/bin/cloud-backup.sh
RUN chmod +x /usr/local/bin/cloud-backup.sh

ENTRYPOINT ["/usr/local/bin/cloud-backup.sh"]
```

---

## 4. Quadlet Configuration

These files reside in `/etc/containers/systemd/` within the `bootc` image.

### `cloud-backup.container`
This defines the execution environment, mounting the necessary host paths for the rclone config, GPG keys, and local backup source.

```ini
[Unit]
Description=Compress, Encrypt, and Push Backups to Cloud
After=network-online.target backup-system.service
Requires=network-online.target

[Container]
Image=localhost/cloud-backup-worker:latest
Environment=GPG_RECIPIENT=admin@example.com
# Mount the rclone config (managed on host or injected)
Volume=/etc/rclone/rclone.conf:/etc/rclone/rclone.conf:Z
# Mount the host GPG keyring to access the public key
Volume=/root/.gnupg:/root/.gnupg:Z
# Mount the local BTRFS snapshots from the secondary drive
Volume=/mnt/storage/var/backups:/mnt/local-backups:ro
# Run as host network for cloud API access
Network=host

[Service]
# One-shot task
Type=oneshot
# Increase timeout for large uploads
TimeoutStartSec=3600

[Install]
WantedBy=multi-user.target
```

### `cloud-backup.timer`
Schedules the cloud sync to run on Sunday mornings, two hours after the local BTRFS backup begins.

```ini
[Unit]
Description=Weekly Cloud Backup Timer

[Timer]
# Run every Sunday at 05:00 AM
OnCalendar=Sun *-*-* 05:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

## 5. Integration into the `bootc` Containerfile

Add the following to your main system `Containerfile` to bake the automation into the OS image.

```dockerfile
# ... (Base bootc setup) ...

# 1. Copy the cloud sync script and Quadlets
COPY cloud-backup.sh /usr/local/bin/cloud-backup.sh
COPY cloud-backup.container /etc/containers/systemd/
COPY cloud-backup.timer /etc/containers/systemd/

# 2. Build the worker image during the system build
COPY Containerfile.cloud-backup /tmp/Containerfile.cloud-backup
RUN podman build -t localhost/cloud-backup-worker:latest -f /tmp/Containerfile.cloud-backup

# 3. Enable the timer
RUN systemctl enable cloud-backup.timer
```

---

## 6. Implementation Steps

1.  **Configure Rclone:** 
    On the host system (or a separate workstation), run `rclone config` to set up your remote (e.g., `gdrive`). Move the resulting `rclone.conf` to `/etc/rclone/rclone.conf` on the target system.
2.  **Import GPG Key:** 
    Ensure the public key used for encryption is imported into the root user's keyring on the host:
    ```bash
    gpg --import my_public_key.asc
    ```
3.  **Deploy & Build:** 
    Build and deploy the `bootc` image as usual. The systemd units will be automatically generated by the Quadlet generator on boot.
4.  **Verification:**
    Check the timer status:
    ```bash
    systemctl list-timers cloud-backup.timer
    ```
    Manually trigger a test upload:
    ```bash
    systemctl start cloud-backup.service
    journalctl -u cloud-backup.service -f
    ```

This approach ensures that even in the event of local hardware failure or site disaster, the entire workstation state—including the workstation environment and system configurations—is safely recoverable from the cloud.