I will begin by reading the existing documentation files to understand the progress made and ensure the v1.0 image implementation is consistent with previous steps.
I will read the content of files `07` and `08` to understand the current bootc image configuration and the backup strategy implemented so far.
I have gathered enough information to define the v1.0 image, which will serve as the core system OS. This image will include the base Fedora bootc, system configurations like root password and SSH keys, the auto-update service, and several Quadlets for cloud backups, local BTRFS snapshots, and a workstation environment. I'll now review `01_build_bootc_image_no_enhancements.md` to confirm the original base image and root setup details.
I've established the components for the v1.0 image, which will include the Fedora bootc base, authentication via root password and SSH keys, and system configurations like the hostname and essential services. Key features will be the auto-update service and various Quadlets for cloud backups, local BTRFS snapshots, and a persistent workstation environment. I'll also include a local snapshot script and define the workstation Quadlet. My final document, "9. build v1.0 image, push to quay," will cover the core Containerfile, supporting units and scripts, build and push instructions, and deployment and verification steps. I'm now ready to draft the content.
# 9. build v1.0 image, push to quay

This document details the process for building and deploying the v1.0 Fedora bootc image. This image serves as the core system OS, consolidating all fundamental configurations, automated update mechanisms, and Podman Quadlet integrations defined in previous phases (Steps 01-08) into a single, cohesive deployment.

## 1. Architectural Overview

In accordance with the project's strategy, the v1.0 image strictly adheres to the following principles:
- **Core OS Immutability**: The bootc image manages the fundamental system state and required packages.
- **Service Isolation**: All operational tasks (e.g., cloud backups, local snapshots, workstation environments) are isolated within Podman containers and managed via systemd Quadlets.
- **Automated Lifecycle**: The image includes services to autonomously pull updates from Quay.io on reboot, and perform automated backups.
- **Clean Workspace**: BTRFS snapshots and persistent containers preserve necessary state while keeping the base filesystem clean.

## 2. Preparing the Build Context

Create a dedicated directory for building the v1.0 image and populate it with the required configuration files.

### A. The Core Containerfile

This `Containerfile` defines the v1.0 image. It uses the official Fedora bootc base and injects our configurations, authentication, and Quadlets.

```dockerfile
# Containerfile.v1
FROM quay.io/fedora/fedora-bootc:40

# 1. System Authentication and Basic Config
RUN echo "root:fedora" | chpasswd
RUN echo "bootc-v1" > /etc/hostname

# Install essential system tools
RUN dnf -y install \
    NetworkManager \
    openssh-server \
    btrfs-progs \
    && dnf clean all

RUN systemctl enable sshd

# Inject SSH Keys (Replace with your actual public key)
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    echo "ssh-ed25519 AAAAC3Nza...your_key_here... user@host" > /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys

# 2. Automated Update Service (from Step 07)
COPY bootc-upgrade-on-boot.service /usr/lib/systemd/system/
RUN systemctl enable bootc-upgrade-on-boot.service

# 3. Inject Quadlets and Supporting Scripts
# Ensure the directory exists
RUN mkdir -p /etc/containers/systemd/

# Copy Quadlets for backups and workstation
COPY quadlets/backup-gdrive.container /etc/containers/systemd/
COPY quadlets/backup-gdrive.timer /etc/containers/systemd/
COPY quadlets/workstation.container /etc/containers/systemd/
COPY quadlets/local-snapshot.service /etc/containers/systemd/
COPY quadlets/local-snapshot.timer /etc/containers/systemd/

# Copy local snapshot script
COPY scripts/local-snapshot.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/local-snapshot.sh
```

### B. The Workstation Quadlet

The workstation container acts as the primary environment for day-to-day development and tasks, keeping installed software persistent but separate from the core OS.

**File: `quadlets/workstation.container`**
```ini
[Unit]
Description=Persistent Workstation Container
After=network-online.target

[Container]
Image=registry.fedoraproject.org/fedora:40
# Run persistently in the background
RunInit=true
# Mount the host user's home directory into the container
Volume=/home/chuck:/home/chuck:Z
# Retain state across reboots
AddDevice=/dev/dri
Network=host

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
```

### C. Local BTRFS Snapshot Automation

This script creates automated snapshots of the working directories before they are picked up by the GDrive backup worker (Step 08).

**File: `scripts/local-snapshot.sh`**
```bash
#!/bin/bash
set -e

SOURCE="/home/chuck"
SNAPSHOT_DIR="/mnt/data/snapshots"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "${SNAPSHOT_DIR}"
btrfs subvolume snapshot -r "${SOURCE}" "${SNAPSHOT_DIR}/home_${TIMESTAMP}"

# Optional: keep only the last 5 snapshots
ls -1t "${SNAPSHOT_DIR}"/home_* | tail -n +6 | xargs -r btrfs subvolume delete
```

**File: `quadlets/local-snapshot.service`**
```ini
[Unit]
Description=Create Local BTRFS Snapshot

[Service]
Type=oneshot
ExecStart=/usr/local/bin/local-snapshot.sh
```

**File: `quadlets/local-snapshot.timer`**
```ini
[Unit]
Description=Run Local BTRFS Snapshot Daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

### D. Cloud Backup Quadlets (From Step 08)

Ensure the `backup-gdrive.container` and `backup-gdrive.timer` files are present in the `quadlets/` directory as defined in Step 08.

## 3. Building the v1.0 Image

With the context prepared, build the comprehensive v1.0 image. Ensure you are logged into Quay.io.

```bash
# Build the bootc image, tagging it as v1.0 and latest
podman build -t quay.io/youruser/fedora-bootc-core:v1.0 -t quay.io/youruser/fedora-bootc-core:latest -f Containerfile.v1 .
```

## 4. Pushing to Quay.io

Push the newly built image to your registry. This action triggers the `bootc-upgrade-on-boot.service` on any currently running systems tracking the `latest` tag during their next reboot.

```bash
# Push the specific version tag
podman push quay.io/youruser/fedora-bootc-core:v1.0

# Push the latest tag to trigger updates
podman push quay.io/youruser/fedora-bootc-core:latest
```

## 5. Deployment and Verification

### New Installation
For a new machine, generate an ISO using the `bootc-image-builder` (as seen in Step 01) targeting the `v1.0` tag.

### Existing System Updates
For a system already running a previous iteration of your bootc image, simply reboot the machine.

1.  **Reboot the system**: The system will start up and run the `bootc-upgrade-on-boot.service`.
2.  **Verify Staging**: Run `bootc status`. You should see the `v1.0` image listed as **Staged**.
3.  **Apply**: Reboot a second time to switch into the new v1.0 environment.

### Verifying Services
Once booted into v1.0, verify that all Quadlet-managed services are active and timers are scheduled:

```bash
# Verify the workstation container is running
podman ps -a | grep workstation

# Verify timers are active for snapshots and cloud backups
systemctl list-timers | grep -E 'local-snapshot|backup-gdrive'
```

## Summary

The v1.0 image represents the fully realized initial architecture. The core OS is immutable and self-updating, development tasks are containerized within the persistent workstation, and data is automatically snapshotted locally and backed up securely to the cloud. All future OS-level enhancements will now occur via updates to this central `Containerfile.v1` and its associated Quadlets.