#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

# Navigate to the script directory to ensure relative paths work.
cd "$(dirname "$0")"

echo "=== Starting Build Process ==="

# 1. Build the dev container image
echo "Building dev-container..."
podman build -t ghcr.io/YOURORG/dev-container:latest -f dev-container.Containerfile .

# 2. Build the backup sidecar image
echo "Building backup-container..."
podman build -t ghcr.io/YOURORG/backup-container:latest -f backup-container.Containerfile .

# 3. Build the bootc host image
echo "Building bootc host image..."
# Note: The host image tag is local as it is the final bootable output.
podman build -t gpu-bootc-host:latest -f Containerfile .

echo "=== Build Complete ==="
echo "Images created:"
echo "  - ghcr.io/YOURORG/dev-container:latest"
echo "  - ghcr.io/YOURORG/backup-container:latest"
echo "  - gpu-bootc-host:latest"
