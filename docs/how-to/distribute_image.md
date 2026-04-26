# Distribute the host image to a third party

## Goal
Help a downstream user pull the published `quay.io/m0ranmcharles/fedora_init:latest` image, build a qcow2 virtual disk, and inject their own SSH key via a cloud-init NoCloud seed at first boot.

## Prerequisites
- Downstream user has Podman and libvirt installed (for the VM path).
- An SSH key pair on the downstream user's machine.
- Access to the target machine for bare-metal deployment (out of scope for this how-to — see `concepts/state_and_persistence.md` for context).

## Steps

### 1. Pull the host image
The downstream user pulls the keyless host image from the public registry:
```bash
sudo podman pull quay.io/m0ranmcharles/fedora_init:latest
```

### 2. Author a NoCloud seed
Create two files, `user-data` and `meta-data`, to define the first-boot configuration.

`user-data`:
```yaml
#cloud-config
ssh_authorized_keys:
  - ssh-ed25519 AAAA... user@host
```

`meta-data`:
```yaml
instance-id: gpu-bootc-deploy-1
local-hostname: gpu-bootc
```

Bake these files into a `cidata` ISO:
```bash
genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data
```
Alternatively, use `cloud-localds seed.iso user-data meta-data` if available.

### 3. Build the qcow2
The downstream user converts the OCI image to a qcow2 disk. Note that the project's internal `02_build_vm/build_vm.sh` is optimized for local development; for distribution, use `bootc-image-builder` directly:

```bash
sudo podman run --rm --privileged \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --rootfs xfs \
  --local quay.io/m0ranmcharles/fedora_init:latest
```

### 4. Boot the qcow2 and attach the seed ISO
Attach the `seed.iso` as a CD-ROM device during the initial boot. Using `virt-install`:

```bash
sudo virt-install \
  --name gpu-bootc \
  --memory 16384 --vcpus 8 \
  --disk path=./output/qcow2/disk.qcow2,format=qcow2 \
  --disk path=./seed.iso,device=cdrom \
  --import \
  --os-variant fedora-unknown \
  --network network=default \
  --boot uefi
```

At first boot, cloud-init detects the `cidata` label, reads the seed, and writes the SSH key into `/root/.ssh/authorized_keys`.

### 5. Connect
Find the VM's IP address and connect via SSH:
```bash
sudo virsh domifaddr gpu-bootc
ssh root@<ip>
```

## Verify
- Run `bootc status` on the VM to confirm the deployed image matches the pulled OCI tag.
- Verify `/root/.ssh/authorized_keys` contains the key provided in the `user-data` file.

## Troubleshooting
- **No SSH access** — Connect via `virsh console gpu-bootc` (leveraging the emergency autologin fallback) and check the cloud-init logs with `journalctl -u cloud-init`. Ensure the seed ISO was created with the correct `cidata` volume label.
- **Image pull fails** — Confirm the registry repository is public and accessible from the downstream environment using `sudo podman pull`.
