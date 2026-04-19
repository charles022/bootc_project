# 15. test GPU passthrough w/ bootc image

This document outlines the strategy for implementing and testing GPU passthrough within a Fedora bootc-managed system. Following the architecture defined in the whitepaper, we divide the responsibility between the **Bootc Image (Host Setup)** and **Podman Quadlets (Container Execution)**.

## Overview
GPU passthrough in this context refers to two primary scenarios:
1.  **Host-to-Container:** Making the host's GPU available to a containerized workstation or workload (using DRI or NVIDIA CDI).
2.  **Host-to-VM:** Passing the physical GPU hardware through to a Virtual Machine running on top of the bootc host (using VFIO).

This guide focuses on **Host-to-Container** passthrough as it aligns with the "workstation container" strategy, while providing the foundation for VM-based passthrough.

---

## Phase 1: The Bootc Image (Host Setup)

The Containerfile for your bootc image must include the necessary kernel modules, firmware, and drivers. 

### 1.1 Containerfile Configuration (NVIDIA Example)
If using NVIDIA, we must install the drivers and the `nvidia-container-toolkit` directly into the bootc image.

```dockerfile
FROM quay.io/fedora/fedora-bootc:40

# Install kernel headers and build tools for akmods
RUN dnf -y install \
    kernel-devel \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    nvidia-container-toolkit \
    && dnf clean all

# Generate the CDI (Container Device Interface) specification
# This allows Podman to recognize the GPU as a resource
RUN nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# For AMD/Intel (Standard DRI)
# Simply ensure firmware and mesa-dri-drivers are present
RUN dnf -y install \
    libva-utils \
    vulkan-loader \
    mesa-dri-drivers \
    && dnf clean all

# Enable lingering for the user so Quadlets run on boot
RUN loginctl enable-linger core
```

### 1.2 Kernel Arguments
To ensure the GPU is handled correctly at boot, you may need to add kernel arguments. In a bootc flow, these can be set via `rpm-ostree kargs` on the live system or defined during the build if using `bootc-image-builder`.

For **VM Passthrough (VFIO)**, add:
`intel_iommu=on iommu=pt rd.driver.pre=vfio-pci`

---

## Phase 2: The Quadlet Strategy (Action)

Once the host image supports the hardware, we use a Quadlet to pass the device into the containerized environment.

### 2.1 The Workstation Quadlet (`workstation.container`)
This Quadlet file should be placed in `/etc/containers/systemd/` (for system-wide) or `~/.config/containers/systemd/` (for user-level).

```ini
[Unit]
Description=Workstation Container with GPU Access
After=network-online.target

[Container]
Image=quay.io/youruser/workstation-image:latest
ContainerName=workstation
Environment=DISPLAY=:0
Volume=/tmp/.X11-unix:/tmp/.X11-unix:ro

# Option A: NVIDIA (Using CDI)
Annotation=run.oci.keep_original_groups=1
Device=nvidia.com/gpu=all

# Option B: AMD/Intel (Using DRI)
Device=/dev/dri/renderD128
Device=/dev/dri/card0

# Permissions for X11/Wayland
User=core
Group=video
Group=render

[Install]
WantedBy=multi-user.target default.target
```

---

## Phase 3: Validation and Testing

### 3.1 Verify Host Recognition
After booting into the new bootc image, verify that the host sees the GPU and the drivers are loaded:

```bash
# Check NVIDIA
nvidia-smi

# Check AMD/Intel
ls -l /dev/dri
```

### 3.2 Verify CDI Generation
Ensure the CDI file exists and lists your devices:
```bash
cat /etc/cdi/nvidia.yaml
```

### 3.3 Test Inside the Container
Run a test command through the Quadlet-managed container to confirm the GPU is working.

**For NVIDIA (CUDA):**
```bash
podman exec workstation nvidia-smi
```

**For Graphics/OpenGL (AMD/Intel/NVIDIA):**
```bash
podman exec workstation glxinfo | grep "OpenGL renderer"
```

---

## Phase 4: Implementation Workflow

1.  **Update Containerfile:** Add the driver and toolkit layers to your primary bootc Containerfile.
2.  **Build & Push:** 
    ```bash
    podman build -t quay.io/youruser/fedora-bootc-custom:v15 .
    podman push quay.io/youruser/fedora-bootc-custom:v15
    ```
3.  **Upgrade System:** 
    ```bash
    bootc switch quay.io/youruser/fedora-bootc-custom:v15
    reboot
    ```
4.  **Deploy Quadlet:** Place the `.container` file in `/etc/containers/systemd/`.
5.  **Reload & Start:**
    ```bash
    systemctl daemon-reload
    systemctl start workstation
    ```

## Summary of Benefit
By placing the **drivers and CDI generation** in the bootc image, we ensure that the kernel and hardware interface are always in sync. By using **Quadlets**, we keep the runtime configuration (which GPU to use, which container gets access) decoupled from the OS image, allowing for rapid iteration of the workstation environment without needing to rebuild the entire system OS.