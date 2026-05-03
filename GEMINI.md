# GEMINI.md - Project Context

## Project Overview
This project, titled "Bootc System Migration," focuses on moving from a traditional manual setup (Fedora Server + scripts) to a modern **bootc (bootable container)** architecture. The goal is a reproducible, immutable core OS with persistent workstation environments managed via Podman Quadlets and Btrfs snapshots.

### Main Technologies
- **Base OS**: Fedora Bootc (`quay.io/fedora/fedora-bootc`).
- **Orchestration**: Systemd (host) and Podman Quadlets (containers/pods).
- **GPU Integration**: NVIDIA drivers (open kernel modules), NVIDIA Container Toolkit, and CDI (Container Device Interface).
- **Storage**: Btrfs for system-wide snapshots and persistent data management.
- **Registry**: Quay.io for image distribution.

### Architecture
1.  **Bootc Host Image**: Contains the kernel, NVIDIA drivers, and Quadlet definitions. It is the "metal" or VM layer.
2.  **Dev/Workstation Container**: A decoupled workload environment (e.g., PyTorch/CUDA stack) that runs on the host.
3.  **Quadlets**: Bridging mechanism between systemd and Podman, allowing containers to be managed as system services.

---

## Building and Running

### Build Flow
The build process involves three layers: the dev container, the backup service (a standalone host Quadlet, not a pod sidecar), and finally the bootc host image that integrates them.

- **Build Images**:
  ```bash
  ./build_image.sh
  ```
  *Infers paths from `01_build_image/build_assets/`.*

### Testing (VM)
The project uses `bootc-image-builder` to convert the bootable container into a virtual disk.

- **Build VM disk**:
  ```bash
  ./02_build_vm/build_vm.sh [IMAGE_NAME]
  ```
  *Defaults to `gpu-bootc-host:latest`. Converts the OCI image to qcow2 via
  `bootc-image-builder` and installs it into the libvirt storage pool.*
- **Run VM**:
  ```bash
  ./02_build_vm/run_vm.sh
  ```
  *Starts the VM with `virt-install` (UEFI boot), detects its IP, and writes
  a `fedora-init` block into `~/.ssh/config` so you can `ssh fedora-init`.*

---

## Development Conventions

### Separation of Concerns
- **Host Layer (Bootc)**: Hardware drivers, CDI generation, SSH access, and network configuration.
- **Container Layer**: Application runtimes, development tools, and user environments.
- **Quadlets**: Should be baked into the host image at `/usr/share/containers/systemd/`.

### GPU Path
- **CDI Strategy**: Use `.kube` Quadlets pointing to Kubernetes-style Pod YAMLs. This allows the use of documented `resources.limits: nvidia.com/gpu=all` selectors.
- **Generation**: A one-shot systemd service (`nvidia-cdi-refresh.service`) must run `nvidia-ctk cdi generate` at boot time to account for actual hardware.

### Persistence & Updates
- **Mutability**: `/usr` is immutable. `/etc` is mutable but subject to 3-way merges during updates. `/var` is fully mutable.
- **Updates**: Rebuild the bootc image weekly, push to Quay, and use `bootc upgrade` or reboots to pull the latest image.

---

## Key Files

### Documentation (canonical)
- `docs/README.md`: Documentation index — start here.
- `docs/overview.md`: 2-page project pitch and 3-layer model.
- `docs/contributing.md`: Format, structure, terminology, and update rules for the docs themselves — **read this before adding, editing, or removing a doc**.
- `docs/concepts/`: Why the project is built this way (`gpu_stack.md`, `ownership_model.md`, `update_pipeline.md`, etc.).
- `docs/reference/`: Code-paired catalogs of the actual artifacts (Containerfiles, systemd units, Quadlets, scripts). Update these when the corresponding files change.
- `docs/how-to/`: Procedural recipes (build, push, validate GPU, distribute, etc.).

### Code
- `01_build_image/build_assets/Containerfile`: Primary definition for the host image.
- `01_build_image/build_assets/dev-container.Containerfile`: Definition for the dev container.
- `02_build_vm/build_vm.sh` + `02_build_vm/run_vm.sh`: Local VM validation flow.

### Legacy
The `.md` files at the repo root (`process_separation_model.md`, `gpu_integration_path.md`, `ostree_notes.md`, etc.) are the original whiteboard the new docs were built from; preserved for archive but superseded by `docs/`.
