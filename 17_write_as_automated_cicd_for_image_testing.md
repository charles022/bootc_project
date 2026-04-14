# 17. write as automated CI/CD for image testing

This document outlines the implementation of an automated CI/CD pipeline for testing Fedora `bootc` images. Following the strategy of maintaining a clean, reproducible core system while delegating services to Podman Quadlets, this pipeline ensures that every image build is functional before it is deployed to production or pushed to a registry.

## Overview of the CI/CD Strategy

The pipeline follows these phases:
1.  **Build:** Create the `bootc` container image from the `Containerfile`.
2.  **Lint & Validate:** Check the `Containerfile` and Quadlet files for syntax and best practices.
3.  **Local Container Test:** Run the image as a standard container to verify basic service startup and Quadlet placement.
4.  **Boot Simulation (Virtualization):** Use `bootc-image-builder` to create a bootable disk image (QCOW2) and boot it via `qemu` to verify the kernel, OSTree deployment, and systemd units.
5.  **Integration Test:** Execute a test suite against the running VM.
6.  **Promote:** Push the verified image to Quay.io.

---

## 1. The Test Environment Setup

We use a shell script to orchestrate the testing process. This script can be triggered by a CRON job, a Git hook, or a CI runner (like GitHub Actions or GitLab Runner).

### `ci_test_image.sh`
```bash
#!/bin/bash
set -euo pipefail

IMAGE_NAME="quay.io/${USER}/fedora-bootc-system"
TAG="test-$(date +%Y%m%d%H%M)"
BUILD_DIR="./build"
mkdir -p "${BUILD_DIR}"

echo "--- Phase 1: Linting ---"
# Check Quadlets and Containerfiles
hadolint Containerfile
ls quadlets/*.container | xargs -I {} podman-tkn lint {}

echo "--- Phase 2: Building Image ---"
podman build -t "${IMAGE_NAME}:${TAG}" .

echo "--- Phase 3: Basic Container Validation ---"
# Verify Quadlets are in the correct directory within the image
podman run --rm "${IMAGE_NAME}:${TAG}" ls /usr/share/containers/systemd/

echo "--- Phase 4: Bootable Disk Generation & Boot Test ---"
# Use bootc-image-builder to create a QCOW2 image
# This requires root/sudo or a privileged container
podman run --rm -it --privileged \
  -v "$(pwd)/${BUILD_DIR}:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --local \
  "${IMAGE_NAME}:${TAG}"

echo "--- Phase 5: Automated VM Testing ---"
# Use a helper script to launch the VM and run tests via SSH
./scripts/run_vm_tests.sh "${BUILD_DIR}/qcow2/disk.qcow2"

echo "--- Phase 6: Promotion ---"
podman tag "${IMAGE_NAME}:${TAG}" "${IMAGE_NAME}:latest"
podman push "${IMAGE_NAME}:latest"
```

---

## 2. Automated VM Integration Testing

Testing a `bootc` image requires verifying that it actually boots and that `systemd` successfully starts the Quadlet-managed services.

### `scripts/run_vm_tests.sh`
This script uses `qemu` to boot the generated image and executes a series of probes.

```bash
#!/bin/bash
DISK_IMAGE=$1
SSH_PORT=2222

# Start VM in background
qemu-system-x86_64 -m 2048 -snapshot \
  -drive file="${DISK_IMAGE}",if=virtio \
  -net nic -net user,hostfwd=tcp::${SSH_PORT}-:22 \
  -nographic -display none &
VM_PID=$!

# Wait for SSH to become available
echo "Waiting for VM to boot..."
until nc -z localhost ${SSH_PORT}; do sleep 5; done

# Execute Tests
echo "Running Integration Tests..."
ssh -p ${SSH_PORT} -o StrictHostKeyChecking=no root@localhost << 'EOF'
  echo "Checking OS Version..."
  cat /etc/os-release | grep "fedora"
  
  echo "Checking bootc status..."
  bootc status
  
  echo "Verifying Quadlet Services..."
  systemctl is-active --quiet workstation-env.service
  
  echo "Verifying Btrfs mount points..."
  mount | grep "type btrfs"
EOF

TEST_RESULT=$?

# Cleanup
kill $VM_PID
exit $TEST_RESULT
```

---

## 3. Quadlet Integrity Check

As per the whitepaper strategy, system actions are moved to Quadlets. We must ensure these files are correctly formatted before they are baked into the image.

### `quadlets/test-integrity.sh`
This script is included in the CI pipeline to validate that Quadlets will generate valid systemd units.

```bash
#!/bin/bash
# Mock the systemd generator environment to test Quadlets
export QUADLET_UNIT_DIRS="./quadlets"
/usr/lib/systemd/system-generators/podman-system-generator --dry-run
```

---

## 4. GitHub Actions Workflow (CI Example)

If hosting on GitHub, the following workflow automates the entire process weekly.

```yaml
name: Weekly Bootc Image Rebuild & Test
on:
  schedule:
    - cron: '0 0 * * 0' # Weekly on Sunday
  push:
    branches: [ main ]

jobs:
  test-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: sudo apt-get install -y qemu-system-x86_64 podman

      - name: Build Bootc Image
        run: podman build -t bootc-test:local .

      - name: Generate Bootable Disk
        run: |
          sudo podman run --privileged -v ./output:/output \
            -v /var/lib/containers/storage:/var/lib/containers/storage \
            quay.io/centos-bootc/bootc-image-builder:latest \
            --type qcow2 --local bootc-test:local

      - name: Run Integration Tests
        run: ./scripts/run_vm_tests.sh ./output/qcow2/disk.qcow2

      - name: Login to Quay.io
        if: success()
        run: podman login -u ${{ secrets.QUAY_USER }} -p ${{ secrets.QUAY_TOKEN }} quay.io

      - name: Push Image
        if: success()
        run: |
          podman tag bootc-test:local quay.io/${{ secrets.QUAY_USER }}/fedora-bootc:latest
          podman push quay.io/${{ secrets.QUAY_USER }}/fedora-bootc:latest
```

## Summary of Alignment
- **Bootc Centric:** Testing focuses on the `ostree` deployment and `bootc status`.
- **Quadlet Validation:** Explicit steps verify that systemd services (via Quadlets) are functional and active upon boot.
- **Automation:** The pipeline replaces the manual `fedora_init` process with a "Build -> Test -> Deploy" cycle that ensures system stability.