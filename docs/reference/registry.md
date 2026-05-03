# Registry

This project uses Quay.io as the central registry for distributing the host image and its associated workload containers.

## Namespace and repository

The canonical namespace for the project is `quay.io/m0ranmcharles/fedora_init`. This single repository hosts all project components, distinguished by their tags.

Forks or alternative deployments should use their own Quay namespace and update the `REPO` variable in `push_images.sh` accordingly.

## Tagging convention

The project maintains four primary tags in the `fedora_init` repository:

- `:latest`: The **host image** (bootable container).
- `:dev-container`: The **dev container** containing the GPU/PyTorch stack.
- `:backup-container`: The **host backup service** (currently a placeholder).
- `:os-builder`: The ephemeral builder image used by the scheduled update pipeline.

## Authentication

Quay.io requires an encrypted CLI password for authentication, which is separate from your web login password.

- **Generation**: Encrypted passwords must be generated via the Quay UI under **Account Settings** > **Generate Encrypted Password**.
- **Usage**: Use `podman login quay.io` with your username and the generated encrypted password.

For the step-by-step procedure, see `how-to/push_to_quay.md`.

## Manifest format (v2s2)

All images are pushed using the Docker V2, Schema 2 (`v2s2`) manifest format. The `push_images.sh` script enforces this via the `--format v2s2` flag.

This format is required because `bootc` and related OS-level tooling expect `v2s2` manifests when consuming images from a registry. Using the default OCI format can lead to compatibility issues during the `bootc install` or `bootc upgrade` phases.

## Visibility and access

The repository is configured as **Public**.

The OCI images are keyless by design, allowing them to be pulled by any client without authentication. Security and identity are managed at deployment time (e.g., via SSH keys or cloud-init) rather than being baked into the image itself.

For more details on the security architecture, see `concepts/access_model.md`.
