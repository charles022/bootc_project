# 11. Flash image to USB, wipe + install to system

This document outlines the final step in transitioning from a traditional script-based setup to a **Fedora bootc** managed system. Following the strategy defined in the whitepaper, we will take the ISO image generated in Step 10 (which contains our core OS, configurations, and Quadlets) and deploy it to physical hardware.

## Overview

In the `bootc` workflow, the installation process is the bridge between the "Build" phase (Containerfile) and the "Run" phase (Bare Metal). By using an ISO built with `anaconda` support, we can perform a clean wipe of the destination system and ensure the starting state matches our immutable image exactly.

## Prerequisites

1.  **Installation Media:** The `.iso` file generated in Step 10 (e.g., `fedora-bootc-v10.iso`).
2.  **USB Drive:** A drive with at least 8GB of capacity.
3.  **Target System:** The workstation or server to be wiped and converted to `bootc`.
4.  **Hardware Backup:** Ensure all transient data from the previous "fedora_init" setup is backed up, as this process will wipe the drive.

---

## Step 1: Flash the Image to USB

On your local development machine, identify the USB drive and use `dd` to write the image.

### Identify the USB Device
```bash
lsblk
```
*Note the device path (e.g., `/dev/sdX` or `/dev/nvmeXn1`). **Ensure you select the correct device to avoid data loss on your workstation.***

### Flash the ISO
Replace `fedora-bootc-v10.iso` with your actual file path and `/dev/sdX` with your USB device.

```bash
sudo dd if=path/to/fedora-bootc-v10.iso of=/dev/sdX bs=4M status=progress oflag=direct
sync
```

---

## Step 2: Boot and Wipe the System

1.  **Insert the USB** into the target system.
2.  **Boot from USB:** Access the BIOS/UEFI boot menu (usually F12, F11, or Del) and select the USB drive.
3.  **Start Installer:** Select "Install Fedora" from the boot menu.

### Partitioning and Wiping
To align with our whitepaper strategy of keeping the system clean and using BTRFS for snapshots:

- **Installation Destination:** Select the internal system drive.
- **Storage Configuration:** Select **Custom** or **Advanced Custom (Blivet-GUI)**.
- **Wipe:** Delete all existing partitions from the previous "fedora_init" installation.
- **Filesystem Strategy:**
    - Create a standard `/boot` and `/boot/efi` partition.
    - Assign the remaining space to a **BTRFS** volume for the root partition (`/`). 
    - *Optional:* Create the specific subvolumes intended for your BTRFS snapshot/backup strategy defined in the whitepaper.

---

## Step 3: Installation via Bootc/Anaconda

The Anaconda installer will recognize the `bootc` payload. It will not install "packages" in the traditional RPM sense; instead, it will:
1.  Format the target partitions.
2.  Pull the container image layers from the ISO.
3.  Deploy the disk image directly to the target drive.
4.  Configure the bootloader to point to the `ostree` deployment managed by `bootc`.

Click **Begin Installation** and wait for the process to complete.

---

## Step 4: First Boot and Verification

Once the system reboots, it will be running the immutable `bootc` image.

### 1. Verify Bootc Status
Check that the system is correctly tracking the image and is ready for future updates via Quay.
```bash
bootc status
```

### 2. Verify Quadlets
Our strategy places actions into Quadlets. Verify that the systemd services generated from Quadlets are active:
```bash
# Check status of system-level quadlets
systemctl status
```

### 3. Check BTRFS Layout
Ensure your workstation directory is ready for the snapshot strategy:
```bash
btrfs subvolume list /
```

---

## Step 5: Post-Install Alignment

Now that the system is installed, it adheres to the "weekly rebuild" lifecycle:

- **Weekly Rebuilds:** The system is now ready to receive updates. When you push a new image to Quay (as seen in Step 09), you can simply run `sudo bootc update` and reboot to apply changes.
- **Statelessness:** Since the core OS is immutable, any "cruft" accumulated during a session that wasn't explicitly added to the `Containerfile` or a persistent BTRFS subvolume will be gone upon the next image update or fresh install.
- **Workstation Container:** You can now launch your persistent workstation container using the Quadlet configuration included in the image, keeping your development environment isolated from the host OS.

## Summary Command Reference

| Action | Command |
| :--- | :--- |
| **Flash USB** | `sudo dd if=image.iso of=/dev/sdX bs=4M` |
| **Verify Image** | `bootc status` |
| **Check Services** | `systemctl list-units --type=service | grep quadlet` |
| **Apply Updates** | `sudo bootc update && reboot` |