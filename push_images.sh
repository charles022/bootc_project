#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

REPO="quay.io/m0ranmcharles/fedora_init"

echo "=== Starting Push Process to Quay.io (using v2s2 format) ==="

# 1. Push the backup service image
echo "Pushing backup-container..."
podman push --format v2s2 "${REPO}:backup-container"

# 2. Push the dev container image (Large PyTorch layers)
echo "Pushing dev-container..."
podman push --format v2s2 "${REPO}:dev-container"

# 3. Push the os-builder image (ephemeral builder used by scheduled updates)
echo "Pushing os-builder..."
podman push --format v2s2 "${REPO}:os-builder"

# 4. Push the multi-tenant images.
echo "Pushing openclaw-runtime..."
podman push --format v2s2 "${REPO}:openclaw-runtime"
echo "Pushing credential-proxy..."
podman push --format v2s2 "${REPO}:credential-proxy"
echo "Pushing onboarding-env..."
podman push --format v2s2 "${REPO}:onboarding-env"
echo "Pushing dev-env..."
podman push --format v2s2 "${REPO}:dev-env"

# 4b. Phase-4 messaging-bridge sidecars.
echo "Pushing messaging-bridge-email..."
podman push --format v2s2 "${REPO}:messaging-bridge-email"
echo "Pushing messaging-bridge-signal..."
podman push --format v2s2 "${REPO}:messaging-bridge-signal"
echo "Pushing messaging-bridge-whatsapp..."
podman push --format v2s2 "${REPO}:messaging-bridge-whatsapp"

# 5. Push the bootc host image
echo "Pushing host image..."
# Tag the local host image for the remote repository before pushing
podman tag gpu-bootc-host:latest "${REPO}:latest"
podman push --format v2s2 "${REPO}:latest"

echo "=== Push Complete ==="
echo "Images pushed to:"
echo "  - ${REPO}:backup-container"
echo "  - ${REPO}:dev-container"
echo "  - ${REPO}:os-builder"
echo "  - ${REPO}:openclaw-runtime"
echo "  - ${REPO}:credential-proxy"
echo "  - ${REPO}:onboarding-env"
echo "  - ${REPO}:dev-env"
echo "  - ${REPO}:messaging-bridge-email"
echo "  - ${REPO}:messaging-bridge-signal"
echo "  - ${REPO}:messaging-bridge-whatsapp"
echo "  - ${REPO}:latest (Host Image)"
