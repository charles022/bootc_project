# Build and run a VM

## Goal
Convert the host image into a bootable qcow2 disk, install it into the libvirt storage pool, boot it under KVM, and connect via SSH using a pre-configured alias.

## Prerequisites
- **Host image**: Built locally and available in your local container storage (see `how-to/build_images.md`).
- **Virtualization**: libvirt, KVM, and `virt-install` installed. Your user must have `sudo` privileges for libvirt operations.
- **SSH Key**: A public key at `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub` for automatic detection. To use a different key, set `SSH_PUB_KEY_FILE=/path/to/key.pub` before running the scripts.
- **Image Builder**: The `bootc-image-builder` tool, accessible via `sudo podman pull quay.io/centos-bootc/bootc-image-builder:latest`.

## Steps

### 1. Build the qcow2 disk
Run the build script from the repository root:

```bash
./02_build_vm/build_vm.sh
```

This script performs the following:
- Detects your SSH public key and generates a temporary `config.toml` to inject it into the VM's root account.
- Invokes `bootc-image-builder` to convert the `quay.io/m0ranmcharles/fedora_init:latest` image (or a specified image name) into a qcow2 file.
- Copies the resulting disk to `/var/lib/libvirt/images/${VM_NAME}.qcow2` (default `VM_NAME=gpu-bootc-test`).
- Sets the file ownership to `qemu:qemu` so the virtualization service can access it.

The Quay tag is the default so the installed VM tracks a real registry source in `bootc status`. To test an unpushed local build instead, pass the local tag explicitly:

```bash
./02_build_vm/build_vm.sh gpu-bootc-host:latest
```

### 2. Boot the VM and configure SSH
Start the VM and set up the local SSH alias:

```bash
./02_build_vm/run_vm.sh
```

This script performs the following:
- Reuses an existing VM with the same name, or starts a new VM with 16 GB RAM, 8 vCPUs, UEFI boot, and a virtio network interface.
- Polls `virsh domifaddr --source lease` until the VM receives an IP address from the default libvirt network.
- Updates your `~/.ssh/config` file with a `# BEGIN fedora-init` block, enabling you to connect using a simple alias.

Set `RECREATE_VM=1` to destroy and recreate an existing VM. If libvirt reports an IP after the script times out, rerun the script with `VM_IP=<ip>` to write the SSH alias without hunting through `~/.ssh/config` by hand:

```bash
SSH_PUB_KEY_FILE="${HOME}/.ssh/id_ed25519_7510.pub" VM_IP=192.168.122.248 ./02_build_vm/run_vm.sh
```

### 3. Connect
Once the script completes, connect to the running VM:

```bash
ssh fedora-init
```

## Verify
- **Access**: `ssh fedora-init` should land you in a root shell on the VM without a password prompt.
- **Services**: Run `systemctl is-active sshd cloud-init.target nvidia-cdi-refresh.service`. All should report `active`. Note that `cloud-init.target` may take a moment to reach this state on the first boot.
- **Deployment**: Run `bootc status` to verify the VM is running the expected image version and is tracking the correct registry.

## Troubleshooting
- **IP not detected**: If the script times out waiting for an IP, run `sudo virsh domifaddr gpu-bootc-test`. If it reports an IPv4 address, rerun `run_vm.sh` with `VM_IP=<ip>` to write the `fedora-init` alias. If no address appears, attach to the console with `sudo virsh console gpu-bootc-test` (detach with `Ctrl+]`) to inspect the boot logs.
- **Disk not found**: Ensure you ran `build_vm.sh` before `run_vm.sh`. If you customized `VM_NAME`, ensure it was exported consistently for both scripts.
- **Permission errors**: Confirm your user is in the `libvirt` group or has appropriate `sudo` access. Verify the libvirt daemon is active with `systemctl status libvirtd`.
