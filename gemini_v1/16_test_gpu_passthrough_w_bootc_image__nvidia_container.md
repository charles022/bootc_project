# 16. test GPU passthrough w/ bootc image + nvidia container

This document outlines the strategy for enabling NVIDIA GPU passthrough within a Fedora `bootc` environment. Following the project's core philosophy, we split the responsibility: the **Bootc Image** handles the hardware drivers and container runtime configuration, while a **Podman Quadlet** manages the execution of the GPU-accelerated workload.

## 1. Architectural Approach

*   **Bootc Containerfile**: Responsible for installing the NVIDIA kernel modules (via akmods), CUDA libraries, and the NVIDIA Container Toolkit. It also configures the Container Device Interface (CDI) so Podman can recognize the GPU.
*   **Kernel Arguments**: The image will be configured to blacklist the open-source `nouveau` driver and enable NVIDIA modesetting.
*   **Quadlet**: A `.container` unit that requests GPU access using the `--device` or `--gpus` flags, targeting a specialized workstation or testing image.

---

## 2. The Bootc Containerfile

This file builds the base OS image. It leverages RPM Fusion to provide the proprietary drivers.

```dockerfile
# Containerfile.bootc-gpu
FROM quay.io/fedora/fedora-bootc:40

# 1. Install RPM Fusion Repositories
RUN dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 2. Install NVIDIA Drivers and Kernel Headers
# Note: kernel-devel is required for akmods to build the module for the bootc kernel
RUN dnf install -y \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    kernel-devel \
    nvidia-container-toolkit

# 3. Configure NVIDIA Container Toolkit for CDI
# This allows Podman to use --device nvidia.com/gpu=all
RUN nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# 4. Set Kernel Arguments for NVIDIA
# We use bootc-style kargs to ensure nouveau is disabled
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    echo "rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1" > /usr/lib/bootc/kargs.d/nvidia.conf

# 5. Clean up to reduce image size
RUN dnf clean all
```

---

## 3. The Test Quadlet

Once the system is booted into the image above, we use a Quadlet to run a test container. This ensures the GPU is visible from within a containerized environment.

```ini
# /etc/containers/systemd/gpu-test.container
[Unit]
Description=NVIDIA GPU Passthrough Test
After=network-online.target

[Container]
# Use a standard CUDA image for verification
Image=docker.io/nvidia/cuda:12.4.1-base-fedora39
ContainerName=nvidia-smi-test

# Request all NVIDIA GPUs via CDI
Annotation=run.oci.keep_original_groups=1
Device=nvidia.com/gpu=all

# Run nvidia-smi and then sleep to keep the container alive for inspection
Exec=sh -c "nvidia-smi && sleep infinity"

[Service]
Restart=on-failure

[Install]
WantedBy=multi-user.target default.target
```

---

## 4. Implementation Steps

### Step 1: Build the Bootc Image
Build the image locally or in your CI pipeline.
```bash
podman build -t quay.io/youruser/fedora-bootc-nvidia:v1 -f Containerfile.bootc-gpu .
```

### Step 2: Push and Deploy
Push the image to your registry (Quay.io as per the whitepaper) and switch your system to it.
```bash
podman push quay.io/youruser/fedora-bootc-nvidia:v1
# On the target system:
sudo bootc switch quay.io/youruser/fedora-bootc-nvidia:v1
sudo reboot
```

### Step 3: Verify Driver Installation
After rebooting, verify the host sees the GPU.
```bash
lsmod | grep nvidia
nvidia-smi
```

### Step 4: Run the Quadlet
Deploy the Quadlet file to `/etc/containers/systemd/` and reload systemd.
```bash
sudo systemctl daemon-reload
sudo systemctl start gpu-test.service
```

### Step 5: Verify Passthrough
Check the logs of the systemd service to see the output of `nvidia-smi` from *inside* the container.
```bash
journalctl -u gpu-test.service
```

---

## 5. Integration with Workstation Strategy

As noted in the whitepaper, your "Workstation Image" should be a separate layer or container that also utilizes these GPU capabilities.

1.  **Development Environment**: In your workstation `.container` Quadlet, include the `Device=nvidia.com/gpu=all` line.
2.  **Persistence**: Ensure your BTRFS mount points are defined in the Quadlet to keep your development work persistent while the GPU-enabled container remains ephemeral or easily replaceable.

```ini
# Example snippet for the workstation quadlet
[Container]
Image=quay.io/youruser/workstation-image:latest
Device=nvidia.com/gpu=all
Volume=/home/user/work:/home/user/work:z
```