# Images

This document is a factual catalog of the container images built and used by this project. All images are built from definitions in `01_build_image/build_assets/`.

## Host image

The primary bootable container image containing the kernel, drivers, and system services.

- **Path**: `01_build_image/build_assets/Containerfile`
- **Purpose**: Provides the immutable host operating system for bare metal or virtual machines.
- **Base image**: `quay.io/fedora/fedora-bootc:42`
- **Key adds**:
    - **NVIDIA Stack**: `nvidia-open` (open kernel modules), `nvidia-container-toolkit`.
    - **Container Tools**: `podman`, `skopeo`.
    - **Management**: `cloud-init` (first-boot configuration), `openssh-server`.
    - **Update Pipeline**: `bootc-update.*` (systemd units and scripts for weekly rebuilds).
    - **Orchestration**: Quadlet definitions (`devpod.kube`, `devpod.yaml`) at `/usr/share/containers/systemd/`.
- **Tags**:
    - Local: `gpu-bootc-host:latest`
    - Quay: `quay.io/m0ranmcharles/fedora_init:latest`
- **Baked-in vs. pulled at runtime**: Baked-in as the system image.
- **Notes**: The host image is keyless; SSH keys and user credentials must be injected at deployment time (e.g., via `cloud-init`).

## Dev container

The GPU-accelerated development environment where workloads run.

- **Path**: `01_build_image/build_assets/dev-container.Containerfile`
- **Purpose**: Provides a decoupled workstation environment with a full PyTorch and CUDA stack.
- **Base image**: `nvcr.io/nvidia/pytorch:26.03-py3`
- **Key adds**: `bash`, `procps`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:dev-container`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman on the host.
- **Notes**: Orchestrated by the host's Quadlet as part of the `devpod` pod.

## Backup sidecar

A placeholder service for managing persistent data backups.

- **Path**: `01_build_image/build_assets/backup-container.Containerfile`
- **Purpose**: Designed to run alongside the dev container to handle state persistence and cloud sync (planned).
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `bash`, `coreutils`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:backup-container`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman on the host.

## OS builder

An ephemeral environment used for automated host image rebuilds.

- **Path**: `01_build_image/build_assets/os-builder.Containerfile`
- **Purpose**: Clones the project repository and builds fresh versions of all images during the scheduled update cycle.
- **Base image**: `quay.io/fedora/fedora:42`
- **Key adds**: `podman`, `buildah`, `skopeo`, `git`, `ca-certificates`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:os-builder`
- **Baked-in vs. pulled at runtime**: Pulled and run as an ephemeral container by the host's `bootc-update.service`.

## Common properties

### Build context
The build context for all images is the `01_build_image/build_assets/` directory. Any files copied via `COPY` instructions must reside within this folder.

### Registry
All images are published to the `quay.io/m0ranmcharles/fedora_init` namespace. See `reference/registry.md` for details on tagging and push procedures.

### Security
All images are "keyless" by design. They do not contain embedded SSH keys, API credentials, or private configuration. This allows the images to be shared publicly on Quay while maintaining security through deployment-time identity injection.

### Source of truth
The Containerfiles in the repository are the authoritative definitions for these images. Code excerpts in this documentation are for illustrative purposes only.
