# 14. test GPU passthrough w/ standard vm

This document outlines the procedure for enabling and testing GPU passthrough on a Fedora bootc host. Following the strategy defined in the whitepaper, we will bake the necessary drivers and configuration into the core bootc image and use a script-based approach for VM deployment to verify functionality.

## 1. Overview
GPU Passthrough (VFIO) allows a virtual machine to take direct control of a physical PCI Graphics Processing Unit, providing near-native performance. In a bootc-managed system, we ensure the host OS is prepared to "isolate" the GPU from the start.

### Prerequisites
- A CPU supporting IOMMU (Intel VT-d or AMD-Vi).
- A secondary GPU (recommended) or a headless host setup to avoid losing the primary display.
- IOMMU enabled in the system BIOS/UEFI.

---

## 2. Host Configuration (bootc Containerfile)

We need to install the virtualization stack and configure the host to load `vfio-pci` drivers.

```dockerfile
# Add to your core bootc Containerfile
FROM quay.io/fedora/fedora-bootc:40

# 1. Install Virtualization Stack
RUN dnf -y install \
    libvirt-daemon-kvm \
    libvirt-client \
    virt-install \
    qemu-kvm \
    pciutils \
    && dnf clean all

# 2. Enable Libvirt Service
RUN systemctl enable libvirtd

# 3. Create VFIO configuration
# Note: You will need to replace VENDOR:DEVICE IDs with your specific GPU IDs
COPY vfio-pci.conf /etc/modprobe.d/vfio-pci.conf
COPY kvm-frag.conf /usr/lib/bootc/kargs.d/kvm-frag.conf
```

### Supporting Files

#### `vfio-pci.conf`
This file tells the kernel to bind the `vfio-pci` driver to your specific hardware IDs instead of the standard graphics driver (e.g., nouveau or nvidia).

```text
# Example: replace 10de:1b80 and 10de:10f0 with your GPU and Audio IDs
options vfio-pci ids=10de:1b80,10de:10f0
```

#### `kvm-frag.conf` (Kernel Arguments)
Bootc allows managing kernel arguments via fragments in `/usr/lib/bootc/kargs.d/`.

```text
# For Intel
intel_iommu=on iommu=pt rd.driver.pre=vfio-pci

# For AMD (uncomment below and comment out Intel)
# amd_iommu=on iommu=pt rd.driver.pre=vfio-pci
```

---

## 3. Identifying Your GPU IDs

Before building the image, identify your GPU's PCI IDs on the current system:

```bash
# Locate the GPU and its associated Audio controller
lspci -nn | grep -i nvidia
# Example Output:
# 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
# 01:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
```
In this example, the IDs are `10de:1b80` and `10de:10f0`. Use these in your `vfio-pci.conf`.

---

## 4. Testing with a Standard VM (`virt-install`)

Once the bootc image is deployed and the system is rebooted with the new kernel arguments, verify isolation:

```bash
# Check if vfio-pci is in use for the GPU
lspci -nnk -d 10de:
# You should see: "Kernel driver in use: vfio-pci"
```

### VM Creation Script
Create a script to launch a test VM (using a Fedora ISO or a previously built bootc ISO) with the GPU passed through.

```bash
#!/bin/bash
# test_gpu_vm.sh

VM_NAME="gpu_test_vm"
GPU_PCI="pci_0000_01_00_0"  # Format: pci_DOMAIN_BUS_SLOT_FUNCTION
AUDIO_PCI="pci_0000_01_00_1"

virt-install \
  --name $VM_NAME \
  --memory 8192 \
  --vcpus 4 \
  --disk size=20,format=qcow2 \
  --os-variant fedora-unknown \
  --cdrom /var/lib/libvirt/images/fedora-workstation.iso \
  --host-device $GPU_PCI \
  --host-device $AUDIO_PCI \
  --graphics none \
  --boot uefi
```

---

## 5. Automation Strategy Alignment

- **Bootc Image:** All hardware-specific drivers (`vfio-pci`), kernel arguments (`iommu=on`), and the virtualization stack (`libvirt`) are defined in the `Containerfile`. This ensures that every time the system is rebuilt, the GPU passthrough environment is consistent.
- **Quadlets:** While the VM management here uses `libvirt`, you can containerize the management tools. However, for "standard VM" testing, host-level `libvirt` provides the most direct path for PCI orchestration.
- **Persistence:** Use the BTRFS snapshot strategy described in the whitepaper to back up your VM disk images (`/var/lib/libvirt/images`) to the separate backup drive before a weekly system refresh.

## 6. Verification Steps
1. **Host Side:** Run `dmesg | grep -i -e iommu -e vfio` to confirm IOMMU groups are created and `vfio-pci` is bound.
2. **Guest Side:** Once the VM is running, run `lspci` inside the VM. The GPU should appear as a local PCI device.
3. **Performance:** Install the appropriate drivers inside the VM (e.g., NVIDIA proprietary drivers) and run `nvidia-smi` or `glxinfo` to confirm hardware acceleration is active.