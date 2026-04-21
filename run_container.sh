#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

IMAGE_NAME="${1:-gpu-bootc-host:latest}"

echo "=== Dropping into ${IMAGE_NAME} as root ==="
echo "    (ephemeral shell — no systemd, no SSH, no services)"
echo ""
podman run --rm -it --entrypoint /bin/bash "${IMAGE_NAME}"
