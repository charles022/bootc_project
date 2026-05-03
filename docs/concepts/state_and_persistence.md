# State and persistence

## What

The system categorizes state into four distinct levels of persistence, depending on whether it belongs to a running process, the workstation environment, the host machine, or off-host storage.

### Category 1: Transient
State that lives only inside running containers. This includes Python REPL sessions, scratch tensors, and `/tmp` files within the dev container. This state is intentionally lost on container restart. It requires no persistence policy.

### Category 2: Workstation-environment-persistent
State that should follow the dev pod environment but is independent of the host OS. Examples: editor settings inside the dev container, dotfiles for the dev pod user. The intent is for this to live in named Podman volumes attached to the dev pod so it survives container restarts. The dev pod manifest does not declare any volumes today, so this category is `(planned)`.

### Category 3: Host-persistent
State owned by the host machine. This includes SSH host keys, the machine ID, cloud-init seed-derived users, anything written to `/etc` after the first boot, and anything in `/var` (such as container storage for the dev container pulled from Quay). This state survives a `bootc upgrade` because of the ostree filesystem model.

### Category 4: Cloud-persistent
Irreplaceable state that must survive a complete machine wipe. This includes source code, trained models, and datasets. This state lives in remote storage, utilizing cloud backups pushed by the host backup service `(planned)`.

### The `/etc` versus `/var` discipline
The bootc host image enforces a strict filesystem model during updates:

- `/etc` is for configuration. It holds small, hand-edited files. During a `bootc upgrade`, changes here are preserved through a three-way merge between your local edits, the old image, and the new image.
- `/var` is for data. It holds larger, machine-written state like databases or Podman volumes. It is completely untouched and carried over during an upgrade.
- `/usr` is immutable and owned by the host image. Anything written here locally is lost on the next image update.

### What `bootc upgrade` preserves
When the scheduled update pipeline deploys a new host image, the upgrade process preserves:
- `/etc` (via three-way merge)
- `/var` (left untouched)
- Bootloader state
- Cryptographic identity

The upgrade process explicitly loses:
- Anything in `/usr` that is not part of the new host image
- Transient container state
- Kernel parameters set outside the image definition

### Where btrfs send and receive fits `(planned)`
We plan to use btrfs subvolumes to snapshot Category 2 state and selected Category 3 state. These snapshots will be shipped off-host using a pipeline like `btrfs send | ssh ... btrfs receive`. This provides a reliable wipe-and-restore mechanism for the workstation environment without bundling user state into the immutable host image.

## Why

Treating all state uniformly creates monolithic backups and fragile upgrades, so separating state by lifecycle allows us to wipe or update layers independently without losing critical data.

## Implications

The categorization dictates exactly what survives different lifecycle events.

| State category | Survives container restart | Survives `bootc upgrade` | Survives full machine wipe |
| --- | --- | --- | --- |
| Category 1 (Transient) | No | No | No |
| Category 2 (Workstation) | Yes | Yes | No |
| Category 3 (Host) | Yes | Yes | No |
| Category 4 (Cloud) | Yes | Yes | Yes |

## See also

- `concepts/bootc_and_ostree.md`
- `concepts/ownership_model.md`
- `concepts/access_model.md`
- `reference/quadlets.md`
