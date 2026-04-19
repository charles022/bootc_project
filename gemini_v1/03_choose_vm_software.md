# 3. choose vm software

Based on the architecture defined in the whitepaper—utilizing Fedora `bootc` for the host and Podman Quadlets for services—the optimal virtualization software is the native Linux stack: **KVM (Kernel-based Virtual Machine)** managed via **libvirt** and **QEMU**.

### Rationale
1.  **Native Integration:** KVM is built into the Fedora kernel, ensuring perfect compatibility with `bootc` updates.
2.  **Performance:** Provides near-native execution speed for Linux and Windows guests.
3.  **Stability:** libvirt is the industry standard for Linux virtualization, offering robust CLI (`virsh`), GUI (`virt-manager`), and Web (`cockpit-machines`) interfaces.
4.  **Btrfs Synergy:** Virtual machine disk images (`.qcow2`) can be stored on Btrfs subvolumes, allowing the use of `btrfs send/receive` for the snapshot-based backup strategy mentioned in the whitepaper.

---

### Implementation Strategy

Following the directive: "Setup goes directly into the bootc image Containerfile, while actions are put into quadlets."

#### 1. Host Configuration (bootc Containerfile)
We must bake the virtualization drivers, daemons, and management tools into the core `bootc` image to ensure the kernel modules and `libvirtd` are available upon boot.

```dockerfile
# Containerfile snippet for the core bootc image
FROM quay.io/fedora/fedora-bootc:40

# Install Virtualization Group and supporting tools
RUN dnf -y groupinstall "Virtualization" && \
    dnf -y install \
    virt-install \
    virt-viewer \
    cockpit-machines \
    libvirt-dbus \
    && dnf clean all

# Enable libvirtd and Cockpit for web-based VM management
RUN systemctl enable libvirtd.service
RUN systemctl enable cockpit.socket

# Add user to libvirt group for passwordless management
# Replace 'admin' with your actual system user
RUN usermod -aG libvirt admin
```

#### 2. Networking (Systemd-networkd / NetworkManager)
For `bootc` systems, a bridge is often preferred for VMs to appear as first-class citizens on the network. This should be defined in the `bootc` image under `/etc/NetworkManager/system-connections/`.

#### 3. Storage Management (Btrfs)
To align with the whitepaper's backup strategy, create a specific Btrfs subvolume for VM images. This allows you to snapshot your VMs independently of the OS.

**Command to run on the provisioned system (or via script):**
```bash
# Create subvolume for VMs
sudo btrfs subvolume create /var/lib/libvirt/images/vms

# Disable Copy-on-Write (CoW) for the images directory 
# Highly recommended for VM performance on Btrfs
sudo chattr +C /var/lib/libvirt/images/vms
```

#### 4. Quadlet Integration: Remote Management Gateway
While `libvirtd` runs on the host, we can use a Quadlet to deploy a "Management Workstation" container that contains the specialized tools for interacting with these VMs, keeping the host `bootc` image lean.

**`virt-manager.container` (Quadlet)**
```ini
[Unit]
Description=Containerized Virtual Machine Manager
After=network-online.target

[Container]
Image=quay.io/fedora/fedora:40
# Access to host libvirt socket
Volume=/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock:Z
# X11/Wayland forwarding for the GUI
Volume=/tmp/.X11-unix:/tmp/.X11-unix:ro
Environment=DISPLAY=:0
Exec=virt-manager --connect qemu:///system --no-fork

[Install]
WantedBy=multi-user.target
```

---

### Actionable Steps to Deploy

1.  **Update your Core Image:** Add the "Virtualization" group to your main `bootc` Containerfile.
2.  **Build and Push:**
    ```bash
    podman build -t quay.io/youruser/fedora-bootc-custom:latest .
    podman push quay.io/youruser/fedora-bootc-custom:latest
    ```
3.  **Switch the System:** On your target machine, ensure you are tracking the new image:
    ```bash
    sudo bootc switch quay.io/youruser/fedora-bootc-custom:latest
    sudo reboot
    ```
4.  **Create a VM:** Use the `virt-install` command to create your first guest, pointing the storage to your Btrfs subvolume:
    ```bash
    virt-install \
      --name fedora-vm \
      --vcpus 2 \
      --memory 4096 \
      --disk path=/var/lib/libvirt/images/vms/fedora.qcow2,size=20,format=qcow2 \
      --os-variant fedora-unknown \
      --network bridge=virbr0 \
      --cdrom /path/to/fedora.iso
    ```

### Backup Strategy Alignment
Because VMs are stored in `/var/lib/libvirt/images/vms`, your weekly `btrfs send` scheduled tasks (as described in your whitepaper) will capture the state of your virtual machines alongside your workstation data, ensuring a unified recovery path.