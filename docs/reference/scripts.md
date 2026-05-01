# Scripts

A reference catalog of the shell and Python scripts used to build, deploy, and maintain the bootc system.

## Top-level

### `build_image.sh`
- **Path**: `build_image.sh`
- **Purpose**: Builds the four primary container images (dev-container, backup-container, os-builder, and the bootc host image).
- **Env vars / args**: None.
- **Preconditions**: Podman must be installed; build assets must exist in `01_build_image/build_assets/`.
- **Side effects**: Creates local Podman images tagged for the local registry and Quay.
- **Notes**: This is the primary entry point for local development.

### `run_container.sh`
- **Path**: `run_container.sh`
- **Purpose**: Runs an ephemeral interactive shell inside a container image for inspection.
- **Env vars / args**: `IMAGE_NAME` (optional, defaults to `gpu-bootc-host:latest`).
- **Preconditions**: The target image must exist in local container storage.
- **Side effects**: Starts an interactive container session.
- **Notes**: Changes made inside the container are lost upon exit.

### `push_images.sh`
- **Path**: `push_images.sh`
- **Purpose**: Pushes the built images to the Quay registry using the Docker V2 schema 2 format.
- **Env vars / args**: None.
- **Preconditions**: Images must be built locally; user must be logged into Quay via `podman login quay.io`.
- **Side effects**: Uploads images to the remote registry.
- **Notes**: Uses `--format v2s2` for compatibility with the bootc update logic.

## `02_build_vm/`

### `02_build_vm/build_vm.sh`
- **Path**: `02_build_vm/build_vm.sh`
- **Purpose**: Converts the host image into a bootable `qcow2` virtual disk and installs it into the libvirt storage pool.
- **Env vars / args**: `IMAGE_NAME` (optional arg, defaults to `gpu-bootc-host:latest`), `VM_NAME` (optional env var), `SSH_PUB_KEY_FILE` (optional env var).
- **Preconditions**: Requires `bootc-image-builder`, `libvirt`, and `sudo` access.
- **Side effects**: Generates a `config.toml` with injected SSH keys, creates a `qcow2` image, and copies it to `/var/lib/libvirt/images/`.
- **Notes**: Automatically detects and injects the local user's SSH public key into the VM's `root` account. The script pipes the host image through `podman save | sudo podman load` because rootful `bootc-image-builder` reads from root's container storage, which is a separate path from the user's rootless storage; without the hand-off, the rootful builder cannot see a rootless-built image.

### `02_build_vm/run_vm.sh`
- **Path**: `02_build_vm/run_vm.sh`
- **Purpose**: Starts the VM using `virt-install`, detects its IP, and configures a local SSH alias.
- **Env vars / args**: `VM_NAME` (optional env var), `SSH_PUB_KEY_FILE` (optional env var).
- **Preconditions**: The VM disk must have been created by `build_vm.sh`.
- **Side effects**: Destroys any existing VM of the same name, starts a new VM, and modifies `~/.ssh/config`.
- **Notes**: Creates a `fedora-init` SSH host block with `StrictHostKeyChecking no` to simplify access.

### `02_build_vm/_detect_ssh_key.sh`
- **Path**: `02_build_vm/_detect_ssh_key.sh`
- **Purpose**: Helper script to locate a valid SSH public key for injection into images or VMs.
- **Env vars / args**: `SSH_PUB_KEY_FILE` (optional env var).
- **Preconditions**: An SSH key must exist in `~/.ssh/` if `SSH_PUB_KEY_FILE` is not provided.
- **Side effects**: Sets the `SSH_PUB_KEY_FILE` environment variable.
- **Notes**: Sourced by other scripts; not intended for standalone execution.

## Host-side

### `bootc-update.sh`
- **Path**: `/usr/local/bin/bootc-update.sh` (source: `01_build_image/build_assets/bootc-update.sh`)
- **Purpose**: Orchestrates the scheduled OS update by running the `os-builder` container and staging the result.
- **Env vars / args**: `BUILDER_IMAGE` (optional env var).
- **Preconditions**: Must be run on the host; requires internet access to pull the builder and clone the source repo.
- **Side effects**: Stages a new bootc deployment via `bootc switch` and creates a pending update marker.
- **Notes**: Configured via `/etc/bootc-update/source.env`.

### `bootc-firstboot-push.sh`
- **Path**: `/usr/local/bin/bootc-firstboot-push.sh` (source: `01_build_image/build_assets/bootc-firstboot-push.sh`)
- **Purpose**: Optionally publishes the currently booted host image to Quay on the first boot after an update.
- **Env vars / args**: Reads `push_to_quay` from `/etc/bootc-update/reboot.env`.
- **Preconditions**: Requires `skopeo` and valid Quay credentials in root's container storage.
- **Side effects**: Pushes the booted image to Quay and clears the `push_to_quay` flag.
- **Notes**: Executed by `bootc-firstboot-push.service`; clears the update pending marker on completion.

### `bootc-update-nudge.sh`
- **Path**: `/etc/profile.d/bootc-update-nudge.sh` (source: `01_build_image/build_assets/bootc-update-nudge.sh`)
- **Purpose**: Notifies interactive users when a new OS deployment is staged and waiting for a reboot.
- **Env vars / args**: None.
- **Preconditions**: A pending update marker must exist at `/var/lib/bootc-update/pending`.
- **Side effects**: Prints a notification message to stdout during shell login.
- **Notes**: Part of the host image's update UX.

### `bootc_host_test.sh`
- **Path**: `/opt/project/bootc_host_test.sh` (source: `01_build_image/build_assets/bootc_host_test.sh`)
- **Purpose**: Performs a basic smoke test of host services, GPU state, and Quadlet status at boot.
- **Env vars / args**: None.
- **Preconditions**: Run on the host system.
- **Side effects**: Writes status information and diagnostic data to the system journal.
- **Notes**: Triggered automatically by `bootc-host-test.service`.

### `os-builder.sh`
- **Path**: `/usr/local/bin/os-builder.sh` (source: `01_build_image/build_assets/os-builder.sh`)
- **Purpose**: Rebuilds all project images from source and exports the host image as an OCI archive.
- **Env vars / args**: `SOURCE_REPO`, `SOURCE_BRANCH`, `OUTPUT_DIR`, `SAVE_ALL`.
- **Preconditions**: Run inside the `os-builder` container.
- **Side effects**: Clones the repository and writes `.tar` image archives to the output directory.
- **Notes**: This script is the `ENTRYPOINT` for the `os-builder` image.

### `platformctl`
- **Path**: `/usr/local/bin/platformctl` (source: `01_build_image/build_assets/multi_tenant/platformctl.sh`)
- **Purpose**: Admin CLI for the multi-tenant layer. Manages tenant lifecycle (create, list, disable, enable, delete) and renders Quadlet templates per tenant.
- **Env vars / args**: `OPENCLAW_PLATFORM_ROOT`, `OPENCLAW_QUADLET_DIR`, `OPENCLAW_TEMPLATE_DIR`, `OPENCLAW_DRY_RUN`.
- **Preconditions**: Run as `root` on the host. Templates must exist at `${OPENCLAW_TEMPLATE_DIR}`.
- **Side effects**: Creates / removes a non-login service account, allocates subuid/subgid, builds the tenant storage subtree under `/var/lib/openclaw-platform/tenants/<tenant>/`, renders Quadlets into `/etc/containers/systemd/users/<UID>/`, enables lingering, reloads systemd, starts the tenant onboarding pod under the tenant's user manager.
- **Notes**: Full reference at `reference/platformctl.md`. Subcommands `agent`, `credential`, `tunnel`, `backup` are stubs that exit non-zero with a "planned" message.

### `openclaw-broker`
- **Path**: `/usr/local/bin/openclaw-broker` (source: `01_build_image/build_assets/multi_tenant/openclaw-broker.py`)
- **Purpose**: The host credential broker daemon. Encrypted credential store, grant table, audit log, admin and per-tenant UNIX sockets. See `concepts/credential_broker.md`.
- **Env vars / args**: `OPENCLAW_PLATFORM_ROOT` (default `/var/lib/openclaw-platform`), `OPENCLAW_BROKER_RUNTIME_DIR` (default `/run/openclaw-broker`).
- **Preconditions**: Run on the host by `openclaw-broker.service`. Requires `python3-cryptography`.
- **Side effects**: Creates and listens on `/run/openclaw-broker/admin.sock` and `/run/openclaw-broker/tenants/<tenant>.sock`. Reads / writes `${OPENCLAW_PLATFORM_ROOT}/broker/{key.bin,store.json,grants.json,audit.log,STATE}`.
- **Notes**: Single-file Python daemon. Admin operations gated by `SO_PEERCRED` UID 0; agent operations gated by which per-tenant socket the connection arrived on.

### `openclaw-provisioner`
- **Path**: `/usr/local/bin/openclaw-provisioner` (source: `01_build_image/build_assets/multi_tenant/openclaw-provisioner.py`)
- **Purpose**: The host agent-provisioning daemon. Reads per-tenant `policy.yaml`, validates `agent_create` requests against allowed images / credentials / networks / volumes / quotas / forbidden flags, cross-checks credentials with the broker, renders agent Quadlets from `/var/lib/openclaw-platform/templates/agent_quadlet/`, runs `daemon-reload` and `systemctl --user --machine=tenant_<tenant>@ start`. See `concepts/agent_provisioning.md`.
- **Env vars / args**: `OPENCLAW_PLATFORM_ROOT`, `OPENCLAW_AGENT_TEMPLATE_DIR`, `OPENCLAW_QUADLET_DIR`, `OPENCLAW_PROVISIONER_RUNTIME_DIR`, `OPENCLAW_BROKER_ADMIN_SOCK`.
- **Preconditions**: Run on the host by `openclaw-provisioner.service`. The broker should be running for credential cross-checks; the provisioner falls back to "credential not present" if the broker is unreachable.
- **Side effects**: Listens on `/run/openclaw-provisioner/admin.sock` and `/run/openclaw-provisioner/tenants/<tenant>.sock`. Reads / writes `${OPENCLAW_PLATFORM_ROOT}/provisioner/{audit.log,STATE}` and `${OPENCLAW_PLATFORM_ROOT}/tenants/<tenant>/agents/<agent>.json`.
- **Notes**: Single-file Python daemon. Same socket-and-peer-cred design as the broker. The YAML loader is a deliberately small subset (no anchors, no flow style, no multi-doc) — the policy file is host-owned and its schema is fixed.

### `agentctl`
- **Path**: `/usr/local/bin/agentctl` inside the `openclaw-runtime` container (source: `01_build_image/build_assets/multi_tenant/agentctl.py`).
- **Purpose**: Tenant-side CLI for self-provisioning. Talks JSONL over the per-tenant provisioner socket bind-mounted at `/run/agentctl/agentctl.sock`.
- **Env vars / args**: `OPENCLAW_AGENTCTL_SOCKET` (default `/run/agentctl/agentctl.sock`), `OPENCLAW_AGENTCTL_TIMEOUT` (default 10).
- **Preconditions**: The Quadlet template mounts the per-tenant provisioner socket; the provisioner must be running on the host.
- **Side effects**: Sends one JSONL request per invocation, prints the parsed reply on stdout. Exit `0` on `ok=true`, `1` otherwise, `3` on socket / connection failure.
- **Notes**: Subcommands intentionally exclude every host-administration verb — see `reference/agentctl.md`.

### `credential-proxy`
- **Path**: `/usr/local/bin/credential-proxy` inside the credential-proxy container (source: `01_build_image/build_assets/multi_tenant/credential-proxy.py`).
- **Purpose**: Pod-local proxy that forwards in-pod agent requests to the host `openclaw-broker` via a tenant-specific socket bind-mounted from the host. Holds no master credentials.
- **Env vars / args**: `OPENCLAW_TENANT` (required), `OPENCLAW_BROKER_SOCKET` (default `/run/credential-proxy/broker.sock`), `OPENCLAW_AGENT_SOCKET` (default `/run/credential-proxy/agent.sock`).
- **Preconditions**: The Quadlet template mounts the broker's per-tenant socket into the container; `openclaw-broker.service` must be running on the host.
- **Side effects**: Listens on `${OPENCLAW_AGENT_SOCKET}`; forwards `credential_request` / `agent_grants` / `ping` upstream and refuses every other op.
- **Notes**: This is the `CMD` for the `credential-proxy` container image.

## Container-side

### `dev_container_start.sh`
- **Path**: `/usr/local/bin/dev_container_start.sh` (source: `01_build_image/build_assets/dev_container_start.sh`)
- **Purpose**: Serves as the startup entry point for the dev container, running tests before entering a wait loop.
- **Env vars / args**: None.
- **Preconditions**: Run inside the dev container.
- **Side effects**: Executes `dev_container_test.py` and maintains a persistent process.
- **Notes**: This is the `CMD` for the dev container.

### `dev_container_test.py`
- **Path**: `/workspace/dev_container_test.py` (source: `01_build_image/build_assets/dev_container_test.py`)
- **Purpose**: Validates the Python environment, PyTorch installation, and CUDA visibility inside the dev container.
- **Env vars / args**: None.
- **Preconditions**: Python 3 and PyTorch must be installed.
- **Side effects**: Prints diagnostic information about the GPU and torch version.
- **Notes**: Used as a smoke test during container startup.

### `backup_stub.sh`
- **Path**: `/usr/local/bin/backup_stub.sh` (source: `01_build_image/build_assets/backup_stub.sh`)
- **Purpose**: Acts as a placeholder entry point for the backup sidecar container.
- **Env vars / args**: None.
- **Preconditions**: Run inside the backup sidecar container.
- **Side effects**: Maintains a persistent process to keep the container running.
- **Notes**: This is the `CMD` for the backup sidecar; real backup logic is planned.
