# 1. build bootc image (no enhancements)

This document outlines the initial step in transitioning from a script-based system setup to a **Fedora bootc** managed infrastructure. The goal here is to create a functional, bootable core OS image that serves as the foundation for future enhancements (Quadlets, workstation containers, etc.).

## 1. Overview
In alignment with the whitepaper, we are shifting the "core system OS" setup directly into a `Containerfile`. This "no enhancements" version focuses on:
- Utilizing the official Fedora bootc base image.
- Configuring basic authentication (root password/SSH keys).
- Ensuring the image is ready for deployment via `bootc install` or `bootc switch`.

## 2. Prerequisites
- **Podman**: Installed and functional on your build machine.
- **Quay.io Account**: Required for pushing the image (as specified in the pipeline strategy).
- **SSH Public Key**: To allow remote access to the deployed system.

## 3. The Containerfile
Create a file named `Containerfile.base`. This file defines the core operating system.

```dockerfile
# Use the official Fedora bootc base image
FROM quay.io/fedora/fedora-bootc:40

# Define a root password (recommend changing this or using SSH keys only in production)
# This example sets the password to 'fedora' for initial setup
RUN echo "root:fedora" | chpasswd

# Install basic networking and management tools if not already present
RUN dnf -y install \
    NetworkManager \
    openssh-server \
    && dnf clean all

# Ensure SSH is enabled on boot
RUN systemctl enable sshd

# Inject your SSH public key for secure access
# Replace the placeholder below with your actual public key
RUN mkdir -p /usr/etc/ssh/sshd_config.d && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh
    
# Use a RUN command to write the key to avoid local file dependency issues during build
RUN echo "ssh-ed25519 AAAAC3Nza...your_key_here... user@host" > /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys

# Set the hostname
RUN echo "bootc-core" > /etc/hostname
```

## 4. Building the Image
Run the following command to build the image locally. Replace `your-username` with your Quay.io namespace.

```bash
podman build -t quay.io/your-username/fedora-bootc-core:latest -f Containerfile.base .
```

## 5. Pushing to the Registry
As per the whitepaper's strategy, the image must be hosted in a registry to facilitate system updates.

```bash
# Log in to Quay.io
podman login quay.io

# Push the image
podman push quay.io/your-username/fedora-bootc-core:latest
```

## 6. Deployment and Installation
Once the image is in the registry, you have two primary ways to use it.

### A. Fresh Installation (via USB/ISO)
To install this on a clean drive, use the `bootc-image-builder` to create a bootable ISO or disk image:

```bash
podman run --rm -it --privileged \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v ./output:/output \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type iso \
  quay.io/your-username/fedora-bootc-core:latest
```

### B. Switching an Existing bootc System
If you are already running a Fedora bootc system and want to "rebase" to this new core image:

```bash
# On the target system
sudo bootc switch quay.io/your-username/fedora-bootc-core:latest
sudo reboot
```

## 7. Verification
After booting into the new image, verify the setup:
1. **Check Version**: `bootc status` should show your Quay image as the booted source.
2. **Persistent Storage**: Ensure `/var` is writable (standard bootc behavior).
3. **Connectivity**: Verify you can SSH into the system using the keys provided in the `Containerfile`.

## Summary of Next Steps
This "no enhancements" image provides the clean slate required by the whitepaper. The next phase will involve adding **Quadlets** to manage system services and the **workstation container** for daily operations, keeping the core image lightweight and the services modular.