# 24. automate recovery: cloud -> sys-btrfs

This document defines the automation for the first stage of a disaster recovery scenario: pulling the encrypted, compressed system backups from cloud storage (Google Drive, S3, etc.) and restoring them to the local BTRFS backup drive (`sys-btrfs`). This completes the "3-2-1" backup loop by ensuring that offsite data can be seamlessly reintegrated into the local recovery pipeline defined in Task 22.

## 1. Objective and Architecture

The goal is to restore the local backup repository (the "sys-btrfs" storage) to its last known good state using the archives created in Task 23.

*   **Source:** Cloud Remote (e.g., `gdrive:backups/$(hostname)`).
*   **Destination:** Local BTRFS backup mount (e.g., `/mnt/storage/backups`).
*   **Process:** A containerized worker fetches the latest encrypted tarball, decrypts it using GPG, and extracts the BTRFS snapshots/streams back to the local disk.
*   **Strategy:** Manual trigger via Systemd for safety, ensuring recovery is an intentional administrative action.

---

## 2. The Cloud Recovery Script (`cloud-restore.sh`)

This script identifies the most recent backup on the cloud remote, downloads it, and performs the decryption/extraction pipeline.

```bash
#!/bin/bash
# /usr/local/bin/cloud-restore.sh
set -e

# Configuration
DEST_DIR="/mnt/local-backups"
TEMP_DIR="/tmp/restore_stage"
REMOTE_NAME="gdrive"
REMOTE_PATH="backups/$(hostname)"
# If no specific file is provided, find the latest
BACKUP_FILE="${1}" 

mkdir -p "${TEMP_DIR}"
mkdir -p "${DEST_DIR}"

# 1. Identify the latest backup if not specified
if [ -z "$BACKUP_FILE" ]; then
    echo "Querying cloud for the latest backup..."
    BACKUP_FILE=$(rclone lsf "${REMOTE_NAME}:${REMOTE_PATH}" --config /etc/rclone/rclone.conf --sort modtime --reverse | grep ".tar.zst.gpg" | head -n 1)
fi

if [ -z "$BACKUP_FILE" ]; then
    echo "Error: No backup files found in ${REMOTE_NAME}:${REMOTE_PATH}"
    exit 1
fi

echo "Downloading ${BACKUP_FILE} from cloud..."

# 2. Download from Cloud
rclone copy "${REMOTE_NAME}:${REMOTE_PATH}/${BACKUP_FILE}" "${TEMP_DIR}/" \
    --config /etc/rclone/rclone.conf \
    --progress

echo "Decrypting and extracting archive to ${DEST_DIR}..."

# 3. Decrypt, Decompress, and Extract in a pipeline
# Note: GPG will prompt for passphrase or use agent if private key is present
gpg --batch --decrypt "${TEMP_DIR}/${BACKUP_FILE}" | \
    zstd -d | \
    tar -xf - -C "${DEST_DIR}"

# 4. Cleanup
rm "${TEMP_DIR}/${BACKUP_FILE}"

echo "Restoration to sys-btrfs completed successfully."
echo "You can now run 'systemctl start ws-restore' to recover the workstation environment."
```

---

## 3. Quadlet Configuration

We use a Podman Quadlet to define the recovery container. Since recovery is a sensitive operation, we do not attach a timer; it is triggered manually.

### `cloud-restore.container`
This file resides in `/etc/containers/systemd/` within the `bootc` image.

```ini
[Unit]
Description=Restore Backups from Cloud to Local sys-btrfs
After=network-online.target local-fs.target
Requires=network-online.target

[Container]
# Reuse the backup-worker image from Task 23
Image=localhost/cloud-backup-worker:latest
# Mount the rclone config
Volume=/etc/rclone/rclone.conf:/etc/rclone/rclone.conf:Z
# Mount the GPG directory (MUST contain the private key for decryption)
Volume=/root/.gnupg:/root/.gnupg:Z
# Mount the destination BTRFS backup drive
Volume=/mnt/storage/backups:/mnt/local-backups:rw
# Run as host network for cloud API access
Network=host
# Use interactive tty if manual passphrase entry is needed
Terminal=true

[Service]
Type=oneshot
# Allows passing a specific filename via environment variable or argument
ExecStart=/usr/local/bin/cloud-restore.sh
# Increase timeout for large downloads
TimeoutStartSec=7200

[Install]
WantedBy=multi-user.target
```

---

## 4. GPG Private Key Preparation

Decryption requires the private key corresponding to the public key used in Task 23. In a "bare metal" recovery scenario, you must provide this key to the system.

### Option A: Manual Import (Recommended for Security)
Before running the restore, import your private key from a secure source (e.g., an encrypted USB drive):
```bash
gpg --import /path/to/my_private_key.gpg
```

### Option B: Pre-staged (Less Secure)
If you keep the private key on the system (e.g., in `/root/.gnupg`), the Quadlet will automatically mount it and use it for decryption.

---

## 5. Integration into the `bootc` Containerfile

Add the recovery script and Quadlet to your system image.

```dockerfile
# ... (Base bootc setup) ...

# 1. Copy the cloud restore script
COPY cloud-restore.sh /usr/local/bin/cloud-restore.sh
RUN chmod +x /usr/local/bin/cloud-restore.sh

# 2. Deploy the Quadlet container unit
COPY cloud-restore.container /etc/containers/systemd/

# 3. Ensure the backup-worker image is built (if not already handled in Task 23)
# COPY Containerfile.cloud-backup /tmp/Containerfile.cloud-backup
# RUN podman build -t localhost/cloud-backup-worker:latest -f /tmp/Containerfile.cloud-backup
```

---

## 6. Execution and Verification

### Step 1: Trigger Recovery
To restore the latest backup from the cloud to your local BTRFS drive:
```bash
sudo systemctl start cloud-restore.service
```

### Step 2: Verify Restoration
Check that the local backup directory now contains the BTRFS snapshots or stream files:
```bash
ls -la /mnt/storage/backups/
```

### Step 3: Complete the Restoration
Now that the "sys-btrfs" storage is populated, you can proceed with Task 22 to restore the actual workstation subvolumes:
```bash
sudo systemctl start ws-restore.service
```

## 7. Troubleshooting

- **GPG Passphrase:** If your GPG key is password-protected, you may need to use `gpg-agent` or run the container with `-it` (interactive) if triggered manually via `podman run`. For fully automated headless recovery, consider using a subkey with no passphrase or providing the passphrase via a file/environment variable (use with caution).
- **Rclone Config:** Ensure the `rclone.conf` contains a valid refresh token. If it has expired, you will need to re-authenticate on a machine with a browser and update the file.