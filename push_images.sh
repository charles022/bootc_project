#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

REPO="quay.io/m0ranmcharles/fedora_init"

echo "=== Starting Push Process to Quay.io (using v2s2 format) ==="

# 1. Push the backup sidecar image
echo "Pushing backup-container..."
podman push --format v2s2 "${REPO}:backup-container"

# 2. Push the dev container image (Large PyTorch layers)
echo "Pushing dev-container..."
podman push --format v2s2 "${REPO}:dev-container"

# 3. Push the bootc host image
echo "Pushing host image..."
# Tag the local host image for the remote repository before pushing
podman tag gpu-bootc-host:latest "${REPO}:latest"
podman push --format v2s2 "${REPO}:latest"

echo "=== Push Complete ==="
echo "Images pushed to:"
echo "  - ${REPO}:backup-container"
echo "  - ${REPO}:dev-container"
echo "  - ${REPO}:latest (Host Image)"
