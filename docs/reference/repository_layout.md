# Repository layout

A descriptive catalog of the files and directories in this repository.

## Top-level tree

```text
.
├── 01_build_image/
│   └── build_assets/
├── 02_build_vm/
│   ├── _detect_ssh_key.sh
│   ├── build_vm.sh
│   └── run_vm.sh
├── docs/
│   ├── concepts/
│   ├── how-to/
│   ├── reference/
│   ├── technical_implementation/
│   ├── DOCS_PLAN.md
│   ├── overview.md
│   ├── README.md
│   └── roadmap.md
├── build_image.sh
├── push_images.sh
├── run_container.sh
├── CLAUDE.md
├── GEMINI.md
├── bootc_and_container_build.md
├── bootc_init_cmd.md
├── explanaition_of_gpu_integration_path.md
├── gpu_integration_path.md
├── immutable_os_deployment_pipeline.md
├── ostree_architecture.md
├── ostree_notes.md
├── pieces_of_design_and_techimplementation.md
├── process_separation_model.md
├── quay_repository.md
└── where_nvidia_belongs.md
```

## Top-level files

| File | Description |
| :--- | :--- |
| `build_image.sh` | Orchestrates the multi-stage build of the host image, dev container, and backup sidecar. |
| `run_container.sh` | Convenience script for running the host image as a local container for inspection. |
| `push_images.sh` | Tags and pushes the three project images to Quay. |
| `CLAUDE.md` | Agent context for Claude Code. Not user-facing documentation. |
| `GEMINI.md` | Agent context for Gemini. Not user-facing documentation. |
| `*.md` (other repo-root) | Pre-rewrite design notes and whiteboards. Canonical content is being migrated into `docs/concepts/`; treat the rewritten docs as authoritative once present. |

## Directories

### `01_build_image/`
Contains the logic for building the OCI images. The `build_assets/` subdirectory is separated to keep the build root clean and to scope the files injected into the images.

### `01_build_image/build_assets/`
The primary collection of artifacts baked into or used to build the project images.

**Containerfiles**
- `Containerfile`: Primary definition for the host image.
- `dev-container.Containerfile`: Definition for the dev container (GPU/PyTorch).
- `backup-container.Containerfile`: Definition for the placeholder backup sidecar.
- `os-builder.Containerfile`: Definition for the image used in the scheduled update pipeline.

**Systemd units**
- `bootc-firstboot-push.service`: Pushes the booted host image to Quay on first boot when `push_to_quay=TRUE` is set in `/etc/bootc-update/reboot.env`.
- `bootc-host-test.service`: Runs host-level validation tests.
- `bootc-update.service`: Unit that executes the system upgrade check.
- `bootc-update.timer`: Timer that schedules periodic update checks.
- `nvidia-cdi-refresh.service`: Generates CDI specifications at boot time.
- `nvidia-cdi-refresh.path`: Monitors for device changes to trigger CDI refreshes.

**Pod & Quadlet definitions**
- `devpod.kube`: Quadlet file defining the systemd-managed pod.
- `devpod.yaml`: Kubernetes Pod specification for the dev pod.

**Scripts**
- `backup_stub.sh`: Placeholder logic for the backup sidecar.
- `bootc_host_test.sh`: Execution logic for host-level tests.
- `bootc-firstboot-push.sh`: Implementation of the first-boot push to Quay.
- `bootc-update-nudge.sh`: Script to notify the user of pending updates.
- `bootc-update.sh`: Orchestration logic for system updates.
- `dev_container_start.sh`: Entrypoint script for the dev container.
- `os-builder.sh`: Script for the automated image rebuild pipeline.

**Configuration & Tests**
- `autologin.conf`: Systemd override for console autologin.
- `dev_container_test.py`: Validation tests for the dev container environment.

### `01_build_image/build_assets/multi_tenant/`
Phase-0 scaffold for the multi-tenant layer (`concepts/multi_tenant_architecture.md`).
- `platformctl.sh`: Admin CLI installed at `/usr/local/bin/platformctl`.
- `openclaw-broker.sh` + `openclaw-broker.service`: Phase-0 stub for the host credential broker.
- `tenant-*.tmpl`: Quadlet templates rendered per-tenant by `platformctl`.
- `openclaw-runtime.Containerfile` + `openclaw-runtime-stub.sh`: Stub agent runtime image.
- `credential-proxy.Containerfile` + `credential-proxy-stub.sh`: Stub credential-proxy sidecar image.
- `onboarding-env.Containerfile` + `onboarding-env-stub.sh`: Stub onboarding env image.

### `02_build_vm/`
Tools for local validation of the host image in a virtual machine environment.
- `build_vm.sh`: Converts the host image OCI artifact into a qcow2 disk and installs it into libvirt.
- `run_vm.sh`: Starts the VM via `virt-install` and configures local SSH access.
- `_detect_ssh_key.sh`: Helper script to locate the local SSH public key for injection.

### `docs/`
The project documentation tree.
- `concepts/`: High-level architecture and design rationale.
- `how-to/`: Task-oriented procedural guides.
- `reference/`: Factual catalogs and artifact descriptions.
- `overview.md`: Project summary and core mental models.
- `roadmap.md`: Current status, planned work, and open questions.
- `README.md`: Entry point and map for the documentation.
- `DOCS_PLAN.md`: The blueprint for the current documentation rewrite.
