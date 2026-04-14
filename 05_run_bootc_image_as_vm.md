# 05_run_bootc_image_as_vm.md

This document outlines the strategy for running a Fedora bootc image as a Virtual Machine (VM) using **Podman Quadlets**. Following our architectural goal of containerizing system services, we will treat the VM lifecycle as a containerized process. This allows us to manage the VM runner using the same `systemd` integration we use for our other services, while keeping the host system clean.

## 1. Objective
To execute the bootc disk image (QCOW2) generated in previous steps within a QEMU/KVM environment, managed by a Podman Quadlet. This ensures that the VM starts on boot, restarts on failure, and is decoupled from the host's manual CLI interactions.

## 2. Prerequisites
- A generated QCOW2 image (e.g., `output/qcow2/disk.qcow2`) from the `bootc-image-builder` (Task 4).
- `podman` and `systemd` installed on the host.
- Hardware virtualization (KVM) enabled on the host.

## 3. The "VM-in-a-Container" Strategy
Instead of installing `qemu` directly on the host, we use a lightweight container image that contains the QEMU binaries. We then use a Quadlet to:
1.  Map the KVM device (`/dev/kvm`) into the container.
2.  Mount the QCOW2 image into the container.
3.  Expose SSH or other ports for system management.

### Step 1: Create the VM Runner Containerfile
This image provides the execution environment for the VM.

```dockerfile
# File: vm-runner.Containerfile
FROM fedora:40

# Install QEMU and necessary utilities
RUN dnf install -y qemu-kvm qemu-img virt-viewer && \
    dnf clean all

# Entrypoint to run QEMU
# We use -nographic for headless server operation, accessible via SSH
ENTRYPOINT ["qemu-system-x86_64"]
```

Build the runner image:
```bash
podman build -t localhost/bootc-vm-runner -f vm-runner.Containerfile .
```

### Step 2: Configure the Quadlet
We define a `.container` unit for Podman Quadlet. This file should be placed in `/etc/containers/systemd/` (for system-wide) or `~/.config/containers/systemd/` (for user-level).

```ini
# File: /etc/containers/systemd/bootc-vm.container
[Unit]
Description=Fedora bootc VM Runner
After=network-online.target

[Container]
Image=localhost/bootc-vm-runner
# Mount the QCOW2 image created in Task 4
Volume=/var/lib/bootc/images/fedora-bootc.qcow2:/data/disk.qcow2:Z
# Map KVM for hardware acceleration
Device=/dev/kvm
# Forward SSH port (Host 2222 -> VM 22)
PublishPort=2222:22
# QEMU Execution Arguments
Exec=-m 2048 \
     -enable-kvm \
     -cpu host \
     -drive file=/data/disk.qcow2,format=qcow2 \
     -net nic -net user,hostfwd=tcp::22-:22 \
     -nographic \
     -snapshot

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
```

**Note on `-snapshot`:** Use this flag if you want the VM to discard changes on reboot, keeping the "clean" state of your bootc build. Remove it if you want persistent changes within the VM's disk image.

## 4. Deployment and Management

### Reload Systemd and Start
Once the Quadlet file is in place, notify systemd to generate the service:

```bash
systemctl daemon-reload
systemctl start bootc-vm.service
```

### Check Status
```bash
systemctl status bootc-vm.service
# or check podman logs
podman logs -f bootc-vm
```

### Access the VM
Since we forwarded the port in the Quadlet, you can SSH into the running bootc system from the host:

```bash
ssh -p 2222 admin@localhost
```

## 5. Alignment with Whitepaper Strategy
- **Separation of Concerns:** The host only needs Podman. The specific version of QEMU used to run the VM is contained within the `vm-runner` image.
- **Declarative Configuration:** The VM's resource allocation (RAM, CPU, Networking) is defined in the Quadlet file, making it version-controllable and repeatable.
- **Automated Lifecycle:** By integrating with `systemd` via Quadlets, the VM follows the standard system lifecycle (automatic startup, logging via `journalctl`).
- **Clean Workspace:** The use of the `-snapshot` flag (optional) ensures that we can test our bootc builds in a completely ephemeral environment before deploying to physical hardware.

## 6. Troubleshooting
- **KVM Access:** Ensure the user running the container has permissions for `/dev/kvm`. On Fedora, adding the user to the `kvm` group is standard.
- **Image Paths:** Ensure the `Volume` path in the `.container` file matches the actual location of your QCOW2 artifact.
- **SELinux:** The `:Z` flag in the `Volume` definition handles SELinux labeling to allow the container to read the disk image.