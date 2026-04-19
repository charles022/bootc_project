# 13. build Quadlet (simple ws-env, no integration) (add to image build, test as container + vm)

This document outlines the process of creating a simple workstation environment (`ws-env`) managed by a Podman Quadlet, integrating it into the Fedora bootc image, and validating the setup in both containerized and virtualized environments.

## 1. Overview of the Strategy

Following the whitepaper's architectural principles:
- **Bootc Image:** Contains the base OS, system-level configurations, and the Quadlet definition files.
- **Quadlet:** Defines a `systemd` service that manages the lifecycle of the workstation container.
- **Workstation Container:** A separate image containing the development tools and user environment, decoupled from the host OS.

## 2. Create the Workstation Environment Image (`ws-env`)

First, we define a simple Containerfile for the workstation environment. This image will be pulled or built and then run by the Quadlet.

```dockerfile
# File: ws-env.Containerfile
FROM fedora:40

# Install basic development tools
RUN dnf install -y \
    git \
    vim \
    tmux \
    curl \
    wget \
    htop \
    && dnf clean all

# Create a default user
RUN useradd -m -s /bin/bash developer
USER developer
WORKDIR /home/developer

CMD ["/bin/bash"]
```

Build this image locally for testing:
```bash
podman build -t localhost/ws-env:latest -f ws-env.Containerfile .
```

## 3. Define the Quadlet Configuration

Quadlets are stored in `/usr/share/containers/systemd/` (for system-wide services) or `/etc/containers/systemd/`. We will place ours in `/etc/containers/systemd/` within the bootc image.

Create a file named `ws-env.container`:

```ini
# File: ws-env.container
[Unit]
Description=Workstation Environment Container
After=network-online.target

[Container]
Image=localhost/ws-env:latest
ContainerName=ws-env
Terminal=true
# Since this is "no integration", we keep it simple without volumes for now
# Internal=true or specific network settings can be added later

[Service]
# Restart the container if it crashes
Restart=always

[Install]
# Start this unit when the system boots
WantedBy=multi-user.target
```

## 4. Integrate into the Bootc Image

Now, we update the main bootc `Containerfile` to include the Quadlet definition and ensure the workstation image is available on the system.

```dockerfile
# File: Containerfile (Bootc Image)
FROM quay.io/fedora/fedora-bootc:40

# 1. Install Podman (required for Quadlets)
RUN dnf install -y podman && dnf clean all

# 2. Copy the Quadlet definition to the system path
COPY ws-env.container /etc/containers/systemd/ws-env.container

# 3. Pre-load the workstation image into the bootc image's local storage
# This ensures the container can start even without initial internet access.
# Note: In a production pipeline, this image might be pulled from a registry.
COPY --from=localhost/ws-env:latest / /tmp/ws-env-root/
# Alternatively, use 'podman save' and 'podman load' logic during build if needed,
# but for bootc, we often rely on the Quadlet pulling the image or it being 
# part of the staged content.
```

*Note: For a seamless experience, the `ws-env` image should be pushed to a registry (like Quay.io) and the `Image=` line in the Quadlet updated to point there.*

## 5. Build and Test

### Step A: Build the Bootc Image
```bash
podman build -t localhost/fedora-bootc-ws:latest .
```

### Step B: Test as a Container
To verify the Quadlet is placed correctly and the image is valid, run the bootc image as a privileged container (to simulate a booting system):

```bash
podman run -it --privileged --name test-bootc localhost/fedora-bootc-ws:latest /sbin/init
```

Inside the running bootc container, check if the Quadlet was picked up by systemd:
```bash
systemctl daemon-reload
systemctl status ws-env.service
podman ps # Should show the ws-env container running
```

### Step C: Test as a VM
Use `bootc-image-builder` to create a bootable ISO or Disk Image.

1. **Generate the ISO:**
```bash
podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    -v $(pwd)/output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    localhost/fedora-bootc-ws:latest
```

2. **Run in a VM (QEMU/KVM):**
```bash
qemu-kvm -m 2048 -drive file=output/qcow2/disk.qcow2,format=qcow2,if=virtio -net nic -net user,hostfwd=tcp::2222-:22
```

3. **Verify:**
Once the VM boots, log in and verify that `systemctl status ws-env` shows the service as active and `podman ps` shows your workstation container running.