# Run the host image locally

## Goal
Run an ephemeral root shell inside the host image to inspect installed packages, file layouts, and baked-in unit files without booting a virtual machine.

## Prerequisites
- The host image must be built locally. See `how-to/build_images.md` for build instructions.
- Podman must be installed and available on your system.

## Steps
Run the inspection script from the repository root.

1. Execute the default run command:
   ```bash
   ./run_container.sh
   ```
   By default, this attempts to run the local `gpu-bootc-host:latest` image.

2. Optionally, specify a different image name (such as one from Quay):
   ```bash
   ./run_container.sh quay.io/m0ranmcharles/fedora_init:latest
   ```

## Verify
After running the script, you should be at a root bash prompt inside the container.

1. Confirm the operating system:
   ```bash
   cat /etc/os-release
   ```
   The output should show Fedora bootc.

2. Verify the presence of baked-in files:
   ```bash
   ls /usr/lib/systemd/system/nvidia-cdi-refresh.service
   ```

## Troubleshooting
If the command fails with an image not found error, ensure you have successfully completed the build steps in `how-to/build_images.md`.

## What this is NOT
- **Not a full boot:** This method starts a shell, not the systemd init process. `systemctl` commands will not work.
- **No services:** SSH, cloud-init, and other host services are not active.
- **Ephemeral:** All changes to the filesystem are discarded when the shell exits.

To validate the full boot sequence, including systemd units and SSH access, see `how-to/build_and_run_vm.md`. For more on the broader project permissions, see `concepts/access_model.md`.
