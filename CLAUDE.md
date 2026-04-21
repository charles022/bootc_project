# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **bootc (bootable container)** project that replaces a traditional Fedora Server + setup-scripts workflow with an immutable, reproducible host OS plus Podman Quadlet-managed container workloads. The intended deployment target is a GPU workstation; NVIDIA driver/CDI integration is a first-class concern.

Most files in the repo root are long-form design/whitepaper docs (`README.md` is the master checklist, `process_separation_model.md`, `gpu_integration_path.md`, `ostree_notes.md`, etc.). Active build artifacts live under `01_build_image/build_assets/` and `02_build_vm/`.

## Commands

Build all three images (dev-container, backup-container, bootc host):
```bash
./build_image.sh
```
- Tags the host image as both `gpu-bootc-host:latest` (local) and `quay.io/m0ranmcharles/fedora_init:latest` (remote).
- **No SSH keys or credentials** are baked in — the OCI image is deliberately keyless so it's safe to push publicly. Credentials are injected at deployment (qcow2/ISO) time; see `02_build_vm/build_vm.sh` and the README "Access" section.
- Build context for all three is `01_build_image/build_assets/` — any new `COPY` source must live there.

Run the host image as an ephemeral root shell (local exploration — no systemd, no SSH, no services):
```bash
./run_container.sh [IMAGE_NAME]   # defaults to gpu-bootc-host:latest
```

Push all three images to Quay:
```bash
./push_images.sh
```
- Uses `--format v2s2` deliberately. Requires a prior `podman login quay.io` (see `quay_repository.md` for the encrypted-CLI-password flow).

Build the VM disk image (qcow2) from the host OCI image:
```bash
./02_build_vm/build_vm.sh [IMAGE_NAME]   # defaults to gpu-bootc-host:latest
```
- Auto-detects `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`; override with `SSH_PUB_KEY_FILE=`.
- Pipes the image into root's container storage (`podman save | sudo podman load`) before calling `bootc-image-builder`, because `sudo podman` uses a separate storage path from the rootless build.
- Generates `./output/config.toml` with a `[[customizations.user]]` entry injecting the SSH key, passes `--rootfs xfs --config /config.toml` to bootc-image-builder.
- Copies the produced qcow2 to `/var/lib/libvirt/images/${VM_NAME}.qcow2` (the libvirt storage pool) so QEMU's system user can read it.

Boot the VM and set up the `ssh fedora-init` alias:
```bash
./02_build_vm/run_vm.sh
```
- Tears down any existing `gpu-bootc-test` VM first — no manual `virsh destroy/undefine` needed.
- Starts the VM with `--noautoconsole` so the script continues immediately. Attach manually with `sudo virsh console gpu-bootc-test` (detach with Ctrl+]).
- After boot, polls `virsh domifaddr` for the VM IP, then writes/replaces a `Host fedora-init` block in `~/.ssh/config` with `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null` (so rebuilds don't trigger "host key changed" errors). Prints `ssh fedora-init` when done.
- Overrides: `VM_NAME=...` for a different VM name; `SSH_PUB_KEY_FILE=/path/to/key.pub` for a non-default key.

Estimate Quay push time for current local images:
```bash
./estimate_push_time.py
```

There are no tests, linters, or CI configured. Smoke validation happens at runtime: `bootc-host-test.service` runs `bootc_host_test.sh` at boot, and the dev container's CMD runs `dev_container_test.py` (imports torch, checks CUDA).

## Architecture

Three layers, built independently, integrated via Quadlet:

1. **Bootc host image** (`01_build_image/build_assets/Containerfile`)
   - Base: `quay.io/fedora/fedora-bootc:42`
   - Adds NVIDIA CUDA repo, installs `nvidia-container-toolkit`, `podman`, `openssh-server`, `cloud-init`.
   - Bakes in systemd units: `bootc-host-test.service`, `nvidia-cdi-refresh.service` + `.path`.
   - Bakes in Quadlets at `/usr/share/containers/systemd/`: `devpod.kube` + `devpod.yaml`.
   - Enables `sshd`, `cloud-init.target` (for downstream NoCloud-seed key injection), and the bootc-specific units above.
   - Console autologin for root on tty1 (`autologin.conf`) is the recovery fallback — no per-user identity is baked in.
   - Three access paths are supported: `./run_container.sh` for local exploration; `build_vm.sh` + `run_vm.sh` for a VM with SSH key injected at qcow2 build time; cloud-init NoCloud seed for downstream users of a pre-built binary. See README "Access" section.

2. **Dev container** (`dev-container.Containerfile`)
   - Base: `nvcr.io/nvidia/pytorch:26.03-py3` (large — this dominates push time).
   - CMD runs `dev_container_start.sh` → `dev_container_test.py` → `tail -f /dev/null` (stays alive for `podman exec`).

3. **Backup sidecar** (`backup-container.Containerfile`) — Fedora 42 base with a placeholder `backup_stub.sh`. Exists only to validate the multi-container pod wiring; no real backup logic yet.

The dev and backup containers run together as a pod defined by `devpod.yaml`, managed by the `devpod.kube` Quadlet. At boot: systemd starts `nvidia-cdi-refresh.service` (generates `/etc/cdi/nvidia.yaml` via `nvidia-ctk cdi generate`) → Quadlet generator turns `devpod.kube` into a `devpod.service` → pod starts with `nvidia.com/gpu=all` GPU access via CDI.

### Ownership rules (enforced across this codebase)

This is the key mental model — violations of it are the most common way to break the design:

- **Host (bootc image)** owns: SSH, systemd services, Quadlet definitions, GPU driver/CDI generation, boot orchestration.
- **Containers** own: workload runtimes (PyTorch stack, app code) and their startup commands. No in-container systemd.
- **Quadlet** is the only bridge — host systemd manages *when* containers start, container CMD decides *what* they do.

When adding a new behavior, ask "who owns this: machine, container, or separate cooperating service?" and place it accordingly. `process_separation_model.md` is the full decision guide.

### CDI is generated at runtime, not baked in
GPU device mappings must come from `nvidia-ctk cdi generate` running on the actual host hardware (via `nvidia-cdi-refresh.service`). Do not hardcode device paths into the image or pod manifest.

### Image registry
All three images are tagged under `quay.io/m0ranmcharles/fedora_init` with distinct tags (`:latest` for host, `:dev-container`, `:backup-container`). The `devpod.yaml` references the Quay paths directly — a freshly booted VM will pull them on first pod start unless preloaded.

## Known caveats when editing

- `01_build_image/docs/image_build.md` and `image_readme.md` are **stale snapshots** of earlier file contents (they still reference `ghcr.io/YOURORG/...` placeholder images and an older Containerfile layout). Treat them as historical context, not source of truth. The live files under `build_assets/` are authoritative.
- `01_build_image/docs/REVIEW_FINDINGS.md` flags two open issues that are still relevant: the `nvidia.com/gpu=all: 1` resource key syntax in `devpod.yaml` has not been validated against current Podman/NVIDIA-toolkit versions, and the pod pulls from Quay at boot (no preload mechanism).
- `.gitignore` excludes `estimate_push_time.py` from commits even though it's tracked as an executable script in the repo root.
- `GEMINI.md` is a parallel project-context file for Gemini; keep it roughly in sync when architecture changes, but don't treat it as canonical over this file.
