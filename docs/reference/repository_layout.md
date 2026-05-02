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
Multi-tenant layer assets (`concepts/multi_tenant_architecture.md`, `concepts/credential_broker.md`, `concepts/agent_provisioning.md`, `concepts/messaging_interface.md`).
- `platformctl.sh`: Admin CLI installed at `/usr/local/bin/platformctl`.
- `openclaw-broker.py` + `openclaw-broker.service`: Phase-2 host credential broker daemon (Fernet-encrypted store, grants, audit, admin + per-tenant sockets).
- `openclaw-provisioner.py` + `openclaw-provisioner.service`: Phase-3+4 host agent-provisioning daemon (policy / quota / grant / messaging validation, agent Quadlet rendering including bridge sidecars, systemd start, audit).
- `agentctl.py`: Phase-3 tenant-side CLI shipped inside the openclaw-runtime container; carries the `--messaging` flag added in Phase 4.
- `credential-proxy.py` + `credential-proxy.Containerfile`: Phase-2 pod-local credential proxy sidecar image.
- `tenant-*.tmpl`: Tenant onboarding-pod Quadlet templates rendered by `platformctl tenant create`.
- `agent_quadlet/agent-*.tmpl` + `agent_quadlet/agent.pod.tmpl`: Agent-pod Quadlet templates rendered by `openclaw-provisioner` on each `agent_create`. Phase 4 adds three messaging-bridge sidecar templates (`agent-messaging-bridge-{email,signal,whatsapp}.container.tmpl`).
- `openclaw-runtime.Containerfile` + `openclaw-runtime-router.py`: Agent runtime image. Phase 4 replaces the Phase-0 idle stub with a verb-table message router.
- `messaging-bridge-{email,signal,whatsapp}.{Containerfile,py}`: Phase-4 transport sidecars. Email + Signal are real implementations; WhatsApp ships as a stub.
- `onboarding-env.Containerfile` + `onboarding-env-stub.sh`: Stub onboarding env image (Phase 0).

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
