# Build images

## Goal
Build the host image, dev container, backup service, and os-builder images on a local workstation.

## Prerequisites
- Podman installed and rootless builds functional (run `podman info` to confirm).
- Sufficient disk space (approximately 30 GB); the dev container is the largest layer due to the PyTorch base image.
- Network access to pull base images from:
  - `quay.io/fedora/fedora-bootc:42`
  - `nvcr.io/nvidia/pytorch:26.03-py3`
  - `registry.fedoraproject.org/fedora:42`
  - `quay.io/fedora/fedora:42`
- The repository cloned locally.

## Steps
1. Navigate to the repository root.
2. Execute the build script:
   ```bash
   ./build_image.sh
   ```
3. Wait for the process to complete. The first run takes significant time as it pulls the large NVIDIA PyTorch base layer.

The `build_image.sh` script orchestrates four `podman build` invocations sequentially. It tags the host image both locally (`gpu-bootc-host:latest`) and for the remote registry (`quay.io/m0ranmcharles/fedora_init:latest`).

## Verify
Confirm the images exist in local storage:
```bash
podman images | grep -E 'fedora_init|gpu-bootc-host'
```
The output should list four distinct image entries: the host image, the dev container, the backup service, and the os-builder.

## Troubleshooting
- **Network unreachable pulling NVIDIA base**: The NVIDIA Container Registry (`nvcr.io`) may occasionally rate-limit requests. Retry the build, or run `podman login nvcr.io` if you have specific credentials.
- **No space left on device**: Building these images, especially the dev container, is resource-intensive. Clean your local image cache with `podman system prune -a` and ensure `/var/lib/containers` or your rootless storage path has enough headroom.
- **Permission denied**: Ensure you are running the script as a user with permission to execute Podman commands. Rootless Podman is recommended.
