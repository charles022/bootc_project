#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

# The container image to convert and run (e.g., gpu-bootc-host:latest)
IMAGE_NAME="${1:-gpu-bootc-host:latest}"
BUILDER_IMAGE="${BUILDER_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"
OUTPUT_DIR="$(pwd)/output"
BUILDER_REF="$IMAGE_NAME"

if [[ "$IMAGE_NAME" != */* ]]; then
  BUILDER_REF="localhost/$IMAGE_NAME"
fi

echo "=== Converting $IMAGE_NAME to qcow2 ==="

# Ensure a fresh output directory
mkdir -p "$OUTPUT_DIR"
sudo rm -rf "$OUTPUT_DIR"/*

# 1. Convert the Bootable Container to a Disk Image
sudo podman run \
  --rm \
  --privileged \
  -v "$OUTPUT_DIR:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  "$BUILDER_IMAGE" \
  --type qcow2 \
  --local "$BUILDER_REF"

echo "=== Starting VM with virt-install ==="

# 2. Boot the VM with virt-install
sudo virt-install \
  --name gpu-bootc-test \
  --memory 16384 \
  --vcpus 8 \
  --disk path="$OUTPUT_DIR/qcow2/disk.qcow2",format=qcow2,bus=virtio \
  --import \
  --os-variant fedora-unknown \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --boot uefi
