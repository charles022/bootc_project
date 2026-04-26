# Immutable OS Deployment Pipeline
**Architecture Guide: Ephemeral Builds, RAM-Disk Handoff, and Pre-Compiled Hardware Drivers**

## 1. Executive Summary
This document defines the end-to-end architecture for a highly reproducible, immutable operating system deployment pipeline. It utilizes `bootc` and OSTree to manage host deployments while relying on a containerized, ephemeral build process to guarantee clean, deterministic OS images.

By leveraging an in-memory (tmpfs) transport layer and pre-compiling complex dependencies (like kernel modules) during the container build, this architecture completely eliminates host cache bloat, mitigates the risk of broken live updates, and provides instantaneous, natively deduplicated rollbacks.

## 2. Handling Complex Hardware Workloads
When maintaining infrastructure for intensive computational tasks—such as running TensorFlow models on RTX architecture—ensuring driver stability is paramount. The traditional live-update model (using `dnf` and DKMS) poses a severe risk of compilation failure on the host machine.

> **The Pre-Compiled Container Strategy**
> To protect the host, all kernel module compilation (e.g., NVIDIA drivers) and CUDA toolkit installations are shifted into the `Containerfile` using tools like `akmods`.
> * If an upstream driver update is incompatible with the new Linux kernel, the ephemeral container build fails.
> * The broken image is never exported or deployed.
> * The host safely continues running the previous week's stable, pre-compiled image until the upstream issue is resolved.

## 3. The Zero-Disk-Artifact Pipeline
To prevent the host machine's storage from filling up with massive, intermediate container layers, the build process utilizes a nested ephemeral builder and a RAM-disk (tmpfs) handoff.

### Step 1: Allocate the RAM Disk
A temporary file system is mounted in the host's memory to serve as the exchange directory between the ephemeral builder and the host's OSTree.
```bash
mkdir -p /tmp/os-build-ramdisk
sudo mount -t tmpfs -o size=5G tmpfs /tmp/os-build-ramdisk
```

### Step 2: Execute the Ephemeral Builder
A standardized builder container runs, pulling the latest OS configuration and securely building the image. The `--no-cache` flag ensures fresh packages and updated drivers are fetched. The final image is exported as an OCI archive directly into the RAM disk.
```bash
podman run --rm -it \
  --privileged \
  -v /tmp/os-build-ramdisk:/output \
  os-builder-image:latest \
  /bin/bash -c "git clone <repo> /work && cd /work && \
                podman build --no-cache -t temp-os . && \
                podman save --format oci-archive -o /output/update.tar temp-os"
```
*Note: Because of the `--rm` flag, the builder container and all its intermediate layers are immediately destroyed upon completion.*

### Step 3: Staging and Deduplication
The host utilizes `bootc` to read the OCI archive directly from RAM and stage it in the OSTree object repository.
```bash
bootc switch --transport oci-archive /tmp/os-build-ramdisk/update.tar
```

### Step 4: Memory Cleanup and Pivot
The RAM disk is unmounted, instantly destroying the heavy `.tar` artifact without it ever touching physical storage. The system is then rebooted into the newly staged image.
```bash
sudo umount /tmp/os-build-ramdisk
sudo reboot
```

## 4. Storage Efficiency & Deduplication
By routing the update through OSTree, the system achieves extreme disk efficiency without requiring CoW filesystems like BTRFS.

> **File-Level Hardlinking**
> OSTree stores the operating system as a content-addressed object store. During the deployment phase, OSTree hashes every file in the new image.
> 
> If a file (like `/usr/bin/bash`) has not changed since the last deployment, OSTree simply creates a new hard link to the existing object. It only writes the **byte-for-byte delta** of the modified files (e.g., the updated NVIDIA kernel module) to the physical disk.

## 5. Rollback Procedures
Because the image compilation happens offline and the update is atomic, the host's `/usr` partition is never subjected to live, mid-air mutations. 

If the weekly update results in degraded performance or unexpected runtime bugs, rolling back is instantaneous. The operator interrupts the GRUB boot menu during restart and selects the previous deployment. OSTree simply points the system back to the older set of file-level hard links, perfectly restoring the previous kernel, drivers, and software stack.
