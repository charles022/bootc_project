# Bootc and OSTree

## What
This project uses **bootc** to deploy the host operating system as a bootable OCI container image. The host *is* the container. Underneath, it uses **OSTree**, which acts as a version-controlled, content-addressed object store for operating system binaries.

## Why
Deploying a pre-compiled image prevents the mid-air collisions that occur when updating live, running binaries. The alternative is a traditional mutable host managed by `dnf`, where complex dependencies like NVIDIA kernel modules are compiled dynamically via DKMS. If an upstream update fails to compile dynamically, the system can become unbootable. Shifting compilation to an ephemeral container build ensures the host only receives atomic, rollback-capable updates.

## Implications
Treating the host as a container commits the project to strict filesystem mutability rules and image-based update workflows.

### OSTree object store and delta updates
OSTree hashes every file in the deployed image (SHA256) and stores unique files in a central repository at `/sysroot/ostree/repo/objects/`. The bootable filesystem is constructed entirely of read-only hardlinks pointing to these objects.

When deploying a new image, OSTree downloads the OCI layers and stages the new tree alongside the current one without touching the active system. It writes only the byte-for-byte deltas (the changed files) to disk, creating hardlinks for unchanged files. Rollback is instant because it only requires updating the bootloader to point to the previous set of hardlinks.

### The `/usr`, `/etc`, and `/var` mutability split
The filesystem is divided into three persistence zones:

- `/usr` is immutable. It is owned by the image and replaced completely on updates. Any local modifications are destroyed.
- `/etc` is mutable and persistent. It receives a 3-way merge during updates, blending the new image's defaults with your local changes.
- `/var` is fully mutable and persistent. It survives updates unchanged.

This enforces strict state separation: binaries and unit files belong in the image (`/usr`), host configuration belongs in `/etc`, and persistent data belongs in `/var`.

### `rpm-ostree` vs. `dnf`
Because `/usr` is mounted read-only on the host, imperative `dnf install` commands do not work. Traditional `dnf` and DKMS are used exclusively inside the container build process to assemble the static image.

On the deployed host, package management is handled by image updates rather than live mutation.
- `bootc upgrade` fetches and stages the newest version of the current image.
- `bootc switch` changes the system to a different image or a local OCI archive.
- `bootc usroverlay` mounts a temporary, writable overlay over `/usr` for transient debugging. The overlay and any changes made within it are discarded on the next reboot.

## See also
- `concepts/ownership_model.md`
- `concepts/update_pipeline.md`
- `concepts/state_and_persistence.md`
- `reference/repository_layout.md`
- `how-to/build_images.md`
