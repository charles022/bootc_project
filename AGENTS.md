# Repository Guidelines

## Project Structure & Module Organization

This repository builds a bootc-based Fedora GPU workstation image and its managed workload containers. Active implementation lives in `01_build_image/build_assets/`: Containerfiles, systemd units, Quadlet files, pod manifests, and startup/test scripts. VM conversion helpers live in `02_build_vm/`. Canonical user-facing documentation is under `docs/`, split into `concepts/`, `reference/`, and `how-to/`; root-level Markdown files are legacy whiteboard notes unless a task explicitly asks about them.

Before adding, editing, removing, or reorganizing documentation, read `docs/contributing.md`; it defines the docs structure, terminology, update rules, and mechanical checks.

## Build, Test, and Development Commands

- `./build_image.sh`: builds the dev container, backup sidecar, os-builder image, and host image.
- `./run_container.sh [IMAGE]`: opens an ephemeral shell in the host image for inspection; it does not run systemd.
- `./02_build_vm/build_vm.sh [IMAGE]`: converts the host image to qcow2 and injects the local SSH public key.
- `./02_build_vm/run_vm.sh`: boots the VM and writes/updates the `ssh fedora-init` alias.
- `./push_images.sh`: pushes project images to Quay using `--format v2s2`.

Useful static checks:

```bash
git ls-files '*.sh' -z | xargs -0 -r bash -n
python3 -m py_compile 01_build_image/build_assets/dev_container_test.py
```

## Coding Style & Naming Conventions

Use Bash with `set -euo pipefail` for executable scripts. Keep paths and image tags centralized near the top of scripts where practical. Use lowercase, hyphenated names for shell scripts, systemd units, and image artifacts, matching existing patterns such as `bootc-update.sh`, `nvidia-cdi-refresh.service`, and `dev-container.Containerfile`. Keep comments short and only where they clarify bootc, systemd, or Podman behavior.

## Testing Guidelines

There is no CI suite or coverage target. Validation is mostly static checks plus runtime smoke tests: `bootc-host-test.service` runs `bootc_host_test.sh` on the host, and the dev container runs `dev_container_test.py` at startup. GPU validation requires a booted host with NVIDIA hardware; follow `docs/how-to/validate_gpu.md`.

## Commit & Pull Request Guidelines

Recent commits use short, descriptive sentence-style messages rather than a strict prefix convention. Keep commits focused and mention the affected area, for example `docs: clarify update pipeline` or `fix cdi smoke test path`. Pull requests should describe behavior changes, list validation performed, and call out any untested hardware-dependent paths. When changing Containerfiles, scripts, systemd units, or Quadlets, update the matching `docs/reference/` page in the same change.

## Architecture & Security Notes

Preserve the three-layer model: the host image owns hardware, boot, SSH, systemd, and CDI; containers own workload runtimes; Quadlet bridges lifecycle management. Do not bake SSH keys, passwords, registry credentials, or host-specific CDI files into images. Credentials belong in deployment-time config such as `bootc-image-builder` config or cloud-init NoCloud seeds.
