#!/usr/bin/env bash

set -euo pipefail

# Navigate to the script directory to ensure relative paths work.
cd "$(dirname "$0")"


# podman tag fedora_init:latest quay.io/charles022/fedora_init:latest
# podman push quay.io/charles022/fedora_init:latest

# build the dev container image
podman build -t quay.io/YOURORG/dev-container:latest -f dev-container.Containerfile .

# 2. Build the backup sidecar image
echo "Building backup-container..."
podman build -t quay.io/YOURORG/backup-container:latest -f backup-container.Containerfile .

# 3. Build the bootc host image
echo "Building bootc host image..."
# Note: The host image tag is local as it is the final bootable output.
podman build -t gpu-bootc-host:latest -f Containerfile .

echo "=== Build Complete ==="
echo "Images created:"
echo "  - quay.io/YOURORG/dev-container:latest"
echo "  - quay.io/YOURORG/backup-container:latest"
echo "  - gpu-bootc-host:latest"
