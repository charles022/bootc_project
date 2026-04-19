# 12. build Containerfile (simple git install) (add to image build, test as container + vm)

This document outlines the transition from traditional shell-script-based setup (`fedora_init`) to the **bootc** methodology. We will create a Containerfile that ensures `git` is baked into the core system image, satisfying the "setup goes directly into the bootc image Containerfile" mandate from the whitepaper.

## 1. Overview of the Strategy
In our previous workflow, we ran scripts post-install to add tools like Git. In the `bootc` workflow:
1.  **Containerfile**: Defines the desired state of the OS (Git installed).
2.  **Image Build**: Podman builds a bootable container image.
3.  **Validation**: 
    *   **Container Test**: Immediate verification of the binary.
    *   **VM Test**: Verification of the bootable artifact (ISO/QCOW2) to ensure system integrity.

---

## 2. The Containerfile (`Containerfile.git`)

Create a file named `Containerfile.git`. We use the official Fedora bootc image as our base.

```dockerfile
# Use the official Fedora bootc base image
FROM quay.io/fedora/fedora-bootc:latest

# Metadata
LABEL maintainer="DevOps Team"
LABEL description="Fedora Bootc image with Git pre-installed"

# Install Git
# We use dnf clean all to keep the image size optimized
RUN dnf install -y git && \
    dnf clean all

# Ensure the system stays updated according to the whitepaper strategy
# (The weekly pipeline will trigger this build, pulling latest packages)
RUN dnf versionlock clear || true
```

---

## 3. Building the Bootc Image

Execute the build using Podman. This creates a container image that represents your entire OS filesystem.

```bash
# Build the image locally
podman build -t localhost/fedora-bootc-git:v1 -f Containerfile.git .
```

---

## 4. Test Phase A: Running as a Container
Before committing to a long VM build process, we verify the package installation by running the image as a standard container.

```bash
# Verify git version within the container
podman run --rm -it localhost/fedora-bootc-git:v1 git --version

# Expected Output:
# git version 2.x.x
```

---

## 5. Test Phase B: Building and Testing as a VM
To verify that the image boots correctly with the new changes, we use `bootc-image-builder`. 

### Step 1: Generate a Bootable ISO or Disk Image
Using the strategy from `04_build_bootc_image_as_iso.md`, we convert the container image into a bootable format.

```bash
mkdir -p ./output

podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    -v $(pwd)/output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    localhost/fedora-bootc-git:v1
```

### Step 2: Run in a Virtual Machine
Boot the resulting `qcow2` image using QEMU/KVM (as outlined in `05_run_bootc_image_as_vm.md`) to ensure the system is functional.

```bash
virt-install \
    --name bootc-test-git \
    --memory 2048 \
    --vcpus 2 \
    --disk path=./output/qcow2/disk.qcow2,format=qcow2 \
    --import \
    --os-variant fedora-rawhide \
    --graphics none
```

Once logged in, run:
```bash
which git
# Output: /usr/bin/git
```

---

## 6. Integration with Whitepaper Strategy
*   **Weekly Pipeline**: This `Containerfile.git` should be merged into your primary system `Containerfile`. When the weekly pipeline runs (as described in the whitepaper), it will pull the latest version of `git` and the base `fedora-bootc` image.
*   **Separation of Concerns**: Git is a "setup" tool and stays in the Containerfile. Any git-based automation (like a cron job to sync configs) would be handled via **Podman Quadlets** in a separate layer.
*   **BTRFS Snapshots**: Once this image is deployed to the hardware, your work within directories handled by Git can be snapshotted using the BTRFS strategy mentioned in the whitepaper, ensuring that while the OS is immutable/rebuildable, your data remains persistent and backed up.