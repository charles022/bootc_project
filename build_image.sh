#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

# Navigate to the script directory to ensure relative paths work.
cd "$(dirname "$0")"

# Path to build assets
ASSETS_DIR="01_build_image/build_assets"
REPO="quay.io/m0ranmcharles/fedora_init"

echo "=== Starting Build Process ==="

# 1. Build the dev container image
echo "Building dev-container..."
podman build -t "${REPO}:dev-container" -f "${ASSETS_DIR}/dev-container.Containerfile" "${ASSETS_DIR}"

# 2. Build the backup sidecar image
echo "Building backup-container..."
podman build -t "${REPO}:backup-container" -f "${ASSETS_DIR}/backup-container.Containerfile" "${ASSETS_DIR}"

# 3. Build the bootc host image
echo "Building bootc host image..."
# Note: Tagged locally as gpu-bootc-host and also for Quay.
podman build -t gpu-bootc-host:latest -t "${REPO}:latest" -f "${ASSETS_DIR}/Containerfile" "${ASSETS_DIR}"

echo "=== Build Complete ==="
echo "Images created:"
echo "  - ${REPO}:dev-container"
echo "  - ${REPO}:backup-container"
echo "  - ${REPO}:latest (Host Image)"

# Optional: Push to Quay
# echo "Pushing images to Quay..."
# podman push "${REPO}:dev-container"
# podman push "${REPO}:backup-container"
