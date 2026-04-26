# Update pipeline

## What

The scheduled update pipeline is an automated local process that rebuilds and stages a new host image without polluting the live filesystem. A timer (`bootc-update.timer`) periodically fires an orchestrator script (`bootc-update.sh`), which launches an ephemeral builder container (the prebuilt `os-builder` image, defined by `os-builder.Containerfile`). The builder clones the project repo into an ephemeral working directory inside the container, builds the host image (and its sibling images) with `podman build --no-cache --pull`, and writes the host image as an `oci-archive` tarball into `/run/bootc-update/host.tar` — a tmpfs path on the host (the service's `RuntimeDirectory`). The orchestrator then runs `bootc switch --transport oci-archive` to stage the archive as a parallel ostree deployment, and writes a pending marker (`/var/lib/bootc-update/pending`) that the login nudge picks up. A reboot activates the new deployment. (A fully remote CI orchestrator that performs these builds centrally is `(planned)`.)

Separately, `bootc-firstboot-push.service` runs on every boot but no-ops unless the operator has set `push_to_quay=TRUE` in `/etc/bootc-update/reboot.env` before rebooting into a freshly staged image. When the flag is set, it copies the booted image from container storage to Quay via `skopeo copy --format v2s2` and clears the flag. This is the bootstrap path for publishing a locally-validated image, gated on operator intent — not an automatic post-update sync.

## Why

We build in an ephemeral container and hand off via RAM-disk rather than performing in-place `dnf` upgrades or a standard `bootc upgrade` from a remote registry to guarantee the host remains clean of build tools while ensuring deterministic, network-resilient updates.

## Implications

### The host remains free of build dependencies
Heavy dependencies like package managers, DKMS, and CUDA repository metadata live exclusively inside the ephemeral builder container. The host system never installs or caches build-time tools.

### Build artifacts never touch physical disk
By routing the artifact through `/run` (tmpfs), the massive OCI archive and intermediate container layers never touch persistent storage. Only the byte-for-byte delta of modified files is written to the host's `/usr` partition during the `bootc switch` phase. Managing persistent `/var` state via btrfs snapshots during this process is `(planned)`.

### Rollbacks are instantaneous and safe
Because the compilation happens offline and the staging is atomic, the live system is never subjected to mid-air mutations. If an update introduces instability, the previous deployment remains perfectly intact. `bootc rollback` simply flips the active deployment pointer back to the previous set of hardlinks, restoring the older system state instantly upon reboot.

### Updates do not require an upstream registry
The local rebuild pipeline ensures the workstation can update itself without relying on external registries to compute the artifact. Once the locally built image proves successful by booting, the first-boot push mechanism synchronizes it back to Quay for other machines.

## See also

- `concepts/bootc_and_ostree.md`
- `concepts/ownership_model.md`
- `reference/systemd_units.md`
- `reference/scripts.md`
- `how-to/build_images.md`
