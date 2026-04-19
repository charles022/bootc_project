# 4. build bootc image as iso

This document outlines the process for converting a Fedora `bootc` container image into a bootable ISO. This transitions our workflow from the legacy "manual USB install + post-install scripts" to a modern "image-based deployment" where the ISO contains the fully configured system, including Quadlets and system configurations.

## Overview

The transformation follows this pipeline:
1.  **Define:** Create a `Containerfile` that includes the OS base and our Quadlets.
2.  **Build & Push:** Build the container image and push it to a registry (e.g., Quay.io).
3.  **Generate ISO:** Use the `bootc-image-builder` tool to pull the image and wrap it in an Anaconda-based installer ISO.

---

## 1. The Containerfile (The "Source of Truth")

As per our strategy, setup logic resides in the `Containerfile`. This example includes a placeholder for a Quadlet service.

```dockerfile
# Use the official Fedora Bootc base
FROM quay.io/fedora/fedora-bootc:40

# 1. Install core system software
RUN dnf -y install \
    git \
    vim \
    btrfs-progs \
    && dnf clean all

# 2. Integrate Quadlets
# We place Quadlet files in the standard system directory
COPY ./quadlets/workstation.container /usr/share/containers/systemd/
COPY ./quadlets/backup-timer.timer /usr/share/containers/systemd/
COPY ./quadlets/backup-timer.service /usr/share/containers/systemd/

# 3. Pre-configure system settings (e.g., SSH, sudoers)
# Note: Most user config should be handled via the ISO builder config
# or via Ignition, but global system defaults go here.
```

---

## 2. Building and Pushing to Quay

The `bootc-image-builder` works best when pulling from a remote registry to ensure the ISO points to a valid update source for `bootc upgrade` later.

```bash
# Define variables
IMAGE_NAME="quay.io/youruser/fedora-bootc-custom"
TAG="latest"

# Build the image locally
podman build -t "${IMAGE_NAME}:${TAG}" .

# Push to the registry
podman push "${IMAGE_NAME}:${TAG}"
```

---

## 3. Configuration for the ISO Builder (`config.json`)

The `bootc-image-builder` requires a configuration file to define the initial user, SSH keys, and how the installer should behave.

Create a file named `config.json`:

```json
{
  "blueprint": {
    "customizations": {
      "user": [
        {
          "name": "admin",
          "description": "System Administrator",
          "groups": ["wheel"],
          "key": "ssh-ed25519 AAAAC3Nza...your_public_key..."
        }
      ]
    }
  }
}
```

---

## 4. Generating the ISO

We use the `bootc-image-builder` container. This tool leverages `osbuild` to create a bootable installer.

### Execution Command

Run this command from the directory containing your `config.json`:

```bash
mkdir -p ./output

sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v $(pwd)/config.json:/config.json:ro \
    -v $(pwd)/output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --config /config.json \
    --type iso \
    quay.io/youruser/fedora-bootc-custom:latest
```

### Parameter Breakdown:
- `--privileged`: Required for disk image manipulation and loopback mounting.
- `-v /var/lib/containers/storage...`: Shares the local podman storage to speed up image access.
- `--type iso`: Specifies the output format.
- `quay.io/...`: The source image that the ISO will install to the target drive.

---

## 5. Deployment

Once the build completes, the ISO will be located in `./output/bootiso/install.iso`.

### Flash to USB
Use `dd` or `bootctl` to prepare your installation media:

```bash
sudo dd if=./output/bootiso/install.iso of=/dev/sdX bs=4M status=progress oflag=direct
```

### Installation Behavior
1.  Boot the target system from the USB.
2.  The installer will automatically partition the drive and deploy the `bootc` image.
3.  Upon reboot, the system will be running the immutable Fedora Bootc OS.
4.  The system will automatically be configured to track `quay.io/youruser/fedora-bootc-custom:latest` for weekly updates.

---

## Alignment with Whitepaper Goals

- **Clean Workspace:** Every time we boot this ISO, we get a fresh, standardized environment.
- **Quadlet Integration:** Our workstation container and backup timers are baked into the image at `/usr/share/containers/systemd/`.
- **Btrfs Ready:** The `btrfs-progs` are included in the base image, allowing our scheduled cron/timer jobs to perform `btrfs send` operations immediately after the first boot.
- **Automation:** This entire document can be scripted into the weekly pipeline to ensure the "recovery" or "reinstall" media is always as up-to-date as the running system.