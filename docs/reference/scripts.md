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
- **Notes**: Automatically detects and injects the local user's SSH public key into the VM's `root` account.

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
