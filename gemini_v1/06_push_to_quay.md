# 6. Push to Quay

This document outlines the process of pushing our custom Fedora bootc image to Quay.io. This is a critical step in the "build-push-update" pipeline described in the whitepaper, as it provides a centralized registry that serves as the source of truth for our system updates.

## Overview

By hosting our bootc image on Quay.io, we enable:
1. **Automated Updates**: The running system can track the registry and pull new versions as they are built.
2. **Version Control**: Tagging images allows for easy rollbacks if a weekly build introduces regressions.
3. **Deployment Consistency**: Any machine (physical or VM) can be initialized or switched to our specific system configuration using a single registry URL.

## Prerequisites

1. **Quay.io Account**: A registered account on [Quay.io](https://quay.io).
2. **Repository**: A repository created on Quay (e.g., `quay.io/youruser/fedora-bootc`).
3. **Robot Account**: For automation (the weekly pipeline), create a Robot Account in Quay with `Write` permissions to the repository.

## 1. Authentication

Before pushing, authenticate your local Podman environment with Quay. Using a Robot Account is recommended for security and automation.

```bash
# Log in using your Robot Account credentials
podman login quay.io -u "youruser+robotname" -p "token_here"
```

## 2. Tagging and Pushing

Once the bootc image is built locally (as seen in Step 01), it must be tagged with the destination registry path and pushed.

### Tagging the Image
We follow a tagging strategy that includes both a `latest` tag for the current production state and a datestamped tag for versioning.

```bash
# Define variables
REGISTRY="quay.io"
USERNAME="youruser"
REPO="fedora-bootc"
IMAGE_NAME="fedora-bootc-custom"
DATE_TAG=$(date +%Y%m%d)

# Tag as latest
podman tag ${IMAGE_NAME}:latest ${REGISTRY}/${USERNAME}/${REPO}:latest

# Tag with date for history
podman tag ${IMAGE_NAME}:latest ${REGISTRY}/${USERNAME}/${REPO}:${DATE_TAG}
```

### Pushing the Image
Push both tags to the registry.

```bash
# Push the latest image
podman push ${REGISTRY}/${USERNAME}/${REPO}:latest

# Push the dated version
podman push ${REGISTRY}/${USERNAME}/${REPO}:${DATE_TAG}
```

## 3. Configuring bootc for Updates

To ensure the running system knows to pull updates from this Quay repository, the system must be "switched" to track this source or initially installed using this URL.

### Switching an Existing System
If you are already running a bootc system but want to change its update source to your Quay repository:

```bash
# This command re-points the bootc runner to the new registry
sudo bootc switch quay.io/youruser/fedora-bootc:latest
```

### Automated Update Check
The system will now track the `latest` tag on Quay. To manually trigger a check and pull for updates:

```bash
# Check for updates and pull them into the staged deployment
sudo bootc update

# To see the status of the staged update
bootc status
```

The update will be applied upon the next reboot.

## 4. The Weekly Pipeline Script (`push_to_quay.sh`)

This script encapsulates the build-and-push logic for the weekly automation described in the whitepaper.

```bash
#!/bin/bash
# push_to_quay.sh - Build and Push custom bootc image

set -e

REGISTRY="quay.io"
USERNAME="youruser"
REPO="fedora-bootc"
IMAGE_TAG="latest"
DATE_TAG=$(date +%Y%m%d)
FULL_IMAGE_PATH="${REGISTRY}/${USERNAME}/${REPO}"

echo "--- Starting Weekly Build ---"

# 1. Pull latest base image to ensure we have the newest security patches
podman pull quay.io/fedora/fedora-bootc:40

# 2. Build the custom image (assumes Containerfile is in current directory)
podman build -t fedora-bootc-custom .

# 3. Tag images
echo "--- Tagging Image ---"
podman tag fedora-bootc-custom:latest ${FULL_IMAGE_PATH}:${IMAGE_TAG}
podman tag fedora-bootc-custom:latest ${FULL_IMAGE_PATH}:${DATE_TAG}

# 4. Push to Quay
echo "--- Pushing to Quay ---"
podman push ${FULL_IMAGE_PATH}:${IMAGE_TAG}
podman push ${FULL_IMAGE_PATH}:${DATE_TAG}

echo "--- Build and Push Complete ---"
```

## Summary of Workflow

1. **Build**: The local `podman build` incorporates the latest Quadlets and software.
2. **Push**: The image is uploaded to Quay.io with `latest` and `YYYYMMDD` tags.
3. **Notify/Update**: The target system runs `bootc update` (via a systemd timer or manual command).
4. **Reboot**: The system reboots into the new btrfs subvolume/deployment containing the updated image.