# 10. pull v1.0 image, build as ISO (w/ anaconda)

This document provides the final step for creating a "golden" installation media for our core system. We will pull the production-ready `v1.0` image from Quay.io and package it into a bootable ISO using the `bootc-image-builder`. This ISO leverages the **Anaconda** installer to automate the partitioning and deployment of our immutable OS to bare-metal hardware or virtual machines.

## 1. Overview of the ISO Build Process

The `bootc-image-builder` tool uses `osbuild` under the hood to transform a container image into a disk image. When we specify the `iso` type, it generates a Fedora-based installer (Anaconda) that:
1.  Loads the `bootc` container image from the physical media.
2.  Partitions the target disk (typically using BTRFS as per our strategy).
3.  Deploys the container contents to the disk using `bootc install`.
4.  Configures the system to track the original registry (Quay.io) for future updates.

---

## 2. Prerequisites

-   **Image Availability:** Ensure `quay.io/youruser/fedora-bootc-core:v1.0` is pushed and public (or you have credentials configured).
-   **Hardware:** A Linux system with Podman installed and at least 20GB of free space.
-   **Privileges:** The builder requires `--privileged` execution to manage loopback devices.

---

## 3. Configuration: `config.json`

The `config.json` file allows us to inject "Day 0" configurations that Anaconda will apply during the installation. This includes the initial administrative user and disk setup.

**File: `config.json`**
```json
{
  "blueprint": {
    "customizations": {
      "user": [
        {
          "name": "chuck",
          "description": "System Owner",
          "groups": ["wheel"],
          "key": "ssh-ed25519 AAAAC3Nza...your_key_here... chuck@workstation"
        }
      ],
      "kernel": {
        "append": "console=ttyS0 console=tty0"
      }
    }
  },
  "anaconda": {
    "kickstart": {
      "contents": "# Custom Kickstart commands can go here if needed\n"
    }
  }
}
```

*Note: While `bootc` handles most configurations via the image itself, the `user` defined here is essential for initial login if the image doesn't have a default password.*

---

## 4. Building the ISO

We run the builder as a container. We explicitly target the `v1.0` tag to ensure we are building the validated version of our system.

### The Build Command

```bash
# Create an output directory for the ISO
mkdir -p ./build-output

# Execute the builder
sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v $(pwd)/config.json:/config.json:ro \
    -v $(pwd)/build-output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --config /config.json \
    --type iso \
    quay.io/youruser/fedora-bootc-core:v1.0
```

### Key Parameters:
- `--type iso`: This tells the builder to create an Anaconda-based installer ISO.
- `quay.io/youruser/fedora-bootc-core:v1.0`: The source container image that will be "installed" by the ISO.
- `-v /var/lib/containers/storage...`: (Optional) Speeds up the build by sharing your local image cache.

---

## 5. Deployment and Testing

### A. Testing in a VM (Recommended)
Before flashing to a USB drive, verify the ISO boots correctly in a virtual machine.

```bash
virt-install \
    --name bootc-v1-test \
    --memory 4096 \
    --vcpus 2 \
    --disk size=20,format=qcow2 \
    --cdrom ./build-output/bootiso/install.iso \
    --os-variant fedora-unknown
```

### B. Flashing to USB
Once verified, write the ISO to your physical installation media:

```bash
# Identify your USB drive (e.g., /dev/sdX) - BE CAREFUL!
lsblk

# Flash the image
sudo dd if=./build-output/bootiso/install.iso of=/dev/sdX bs=4M status=progress oflag=direct
```

---

## 6. Strategy Alignment

-   **Rebuild Cycle:** In our weekly pipeline, this ISO build step ensures that if we ever need to "wipe and reinstall" (as per the whitepaper), we are using the exact same image that is currently running in production.
-   **Anaconda Automation:** By using the `iso` type, we leverage the battle-tested Anaconda installer, which handles complex hardware detection and disk partitioning that a simple "disk image" might struggle with.
-   **Seamless Upgrades:** Because the ISO was built from `v1.0`, the installed system will automatically have its `bootc` config pointing back to Quay. If we push `v1.1` to the `latest` tag later, the system will pull it automatically on the next reboot.
-   **Clean Workspace:** This installation process provides the "blank slate" starting point while immediately deploying all Quadlets and system-d services required for our BTRFS snapshot and backup workflows.