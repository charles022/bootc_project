#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

# The container image to convert and run (e.g., gpu-bootc-host:latest)
IMAGE_NAME="${1:-gpu-bootc-host:latest}"

echo "=== Converting $IMAGE_NAME to qcow2 ==="

# Ensure a fresh output directory
mkdir -p ./output
sudo rm -rf ./output/*

# 1. Convert the Bootable Container to a Disk Image
sudo podman run \
  --rm \
  --privileged \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --local "localhost/$IMAGE_NAME"

echo "=== Starting VM with virt-install ==="

# 2. Boot the VM with virt-install
sudo virt-install \
  --name gpu-bootc-test \
  --memory 16384 \
  --vcpus 8 \
  --disk path=./output/qcow2/disk.qcow2,format=qcow2,bus=virtio \
  --import \
  --os-variant fedora-unknown \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --boot uefi
