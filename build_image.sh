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

# 3. Build the os-builder image
# Ephemeral builder used by the host's scheduled-update pipeline. Carries
# podman/buildah/git/skopeo so it can clone the repo into RAM, rebuild
# all four images, and emit the host image as an oci-archive on a tmpfs
# mount supplied by the host. See 01_build_image/build_assets/os-builder.sh.
echo "Building os-builder..."
podman build -t "${REPO}:os-builder" -f "${ASSETS_DIR}/os-builder.Containerfile" "${ASSETS_DIR}"

# 4. Build the multi-tenant Phase-0 stub images.
# These are referenced by the Quadlet templates that platformctl renders
# per-tenant. They are intentionally minimal Phase-0 scaffolds.
# See docs/concepts/multi_tenant_architecture.md.
MT_DIR="${ASSETS_DIR}/multi_tenant"
echo "Building openclaw-runtime (stub)..."
podman build -t "${REPO}:openclaw-runtime" -f "${MT_DIR}/openclaw-runtime.Containerfile" "${MT_DIR}"
echo "Building credential-proxy (stub)..."
podman build -t "${REPO}:credential-proxy" -f "${MT_DIR}/credential-proxy.Containerfile" "${MT_DIR}"
echo "Building onboarding-env (stub)..."
podman build -t "${REPO}:onboarding-env" -f "${MT_DIR}/onboarding-env.Containerfile" "${MT_DIR}"

# 5. Build the bootc host image
# The OCI image is shareable: no SSH keys, no passwords, no per-user identity
# is baked in. Credentials are injected at deployment time (qcow2/ISO/install)
# via bootc-image-builder --config or a cloud-init seed. See ./02_build_vm/.
echo "Building bootc host image..."
podman build -t gpu-bootc-host:latest -t "${REPO}:latest" -f "${ASSETS_DIR}/Containerfile" "${ASSETS_DIR}"

echo "=== Build Complete ==="
echo "Images created:"
echo "  - ${REPO}:dev-container"
echo "  - ${REPO}:backup-container"
echo "  - ${REPO}:os-builder"
echo "  - ${REPO}:openclaw-runtime    (multi-tenant Phase-0 stub)"
echo "  - ${REPO}:credential-proxy    (multi-tenant Phase-0 stub)"
echo "  - ${REPO}:onboarding-env      (multi-tenant Phase-0 stub)"
echo "  - ${REPO}:latest (host image, tagged locally as gpu-bootc-host:latest)"
echo ""
echo "Next steps:"
echo "  - Explore host image (shell): ./run_container.sh"
echo "  - Build VM disk:              ./02_build_vm/build_vm.sh"
echo "  - Boot VM + get SSH alias:    ./02_build_vm/run_vm.sh"
echo "  - Push to Quay:               ./push_images.sh"
