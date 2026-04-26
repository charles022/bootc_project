# Access model

## What

The published bootc OCI image is intentionally keyless: no SSH keys, no passwords, and no per-user identity are baked into it. The credentials required to access the host system are injected at *deployment* time. 

This provides three primary access paths: local container execution, VM builds with injected SSH keys, and cloud-init NoCloud seeds for downstream users.

## Three access paths

### Local container exec

You can run the host image locally as an ephemeral container to explore its contents without network or SSH access.

```bash
./run_container.sh
```

This drops you into a root bash shell inside the host image on your development machine. No systemd, no SSH, and no services are running. It is purely for poking at installed packages and file layouts.

See `how-to/run_locally.md` for more details.

### VM with SSH key injected at qcow2 build

When testing the host image locally in a VM, the build script injects your personal SSH key directly into the VM's disk image.

```bash
./02_build_vm/build_vm.sh
./02_build_vm/run_vm.sh
```

`build_vm.sh` reads your public key (auto-detecting `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`, or via the `SSH_PUB_KEY_FILE` environment variable). It writes a `[[customizations.user]]` block into the `bootc-image-builder` config, so the resulting qcow2 includes the key for the `root` user. 

`run_vm.sh` boots the VM, detects its IP, and writes a `Host fedora-init` entry into your `~/.ssh/config` file. You can then connect immediately:

```bash
ssh fedora-init
```

See `how-to/build_and_run_vm.md` for more details.

### Cloud-init NoCloud seed (downstream users)

Downstream users pulling the published `quay.io/m0ranmcharles/fedora_init:latest` image provide their own SSH key by mounting a NoCloud datasource at first boot. The image enables `cloud-init.target` to support this out of the box.

The user creates a NoCloud seed (a cidata ISO with `user-data` and `meta-data`) containing their SSH key. On first boot, cloud-init picks up the seed and writes their key into root's `authorized_keys`.

See `how-to/distribute_image.md` for more details on building and attaching the NoCloud seed.

### Summary

| Scenario | Mechanism | Key source | First command |
|----------|-----------|------------|---------------|
| Poke at the image | `./run_container.sh` | None needed | `./run_container.sh` |
| Build + run VM locally | `build_vm.sh` + `run_vm.sh` | Your `~/.ssh/*.pub` (auto) | `ssh fedora-init` |
| Distribute pre-built binary | Cloud-init NoCloud seed | Recipient's own key | `ssh root@<ip>` |

## Console autologin recovery fallback

A console root autologin fallback is included for emergencies. `autologin.conf` is baked into the image as a getty drop-in, giving the root user an autologin on tty1. 

This exists purely for the case where SSH and cloud-init both fail at first boot, allowing you to get a shell on the console (e.g., via `virsh console`) to debug. Because it requires the virtual console and is not exposed over the network, it does not compromise the security of the published image.

## Why credentials are deployment-time, not image-time

The alternative to deployment-time credentials is baking an SSH key directly into the OCI image. We avoid this for several reasons:

1. **Security of the OCI artifact:** The OCI image is pushed to a public Quay namespace. Baking keys into it would either expose private key material to the internet or force every consumer to share a single, well-known identity.
2. **Multiple consumers:** Different consumers (the project author, downstream users, and future automated test machines) have different keys and identities.
3. **Platform standards:** Cloud-init is the standard, well-supported mechanism for injecting instance-specific metadata (like SSH keys) across virtualization and cloud platforms.

## Implications

- The image is safe to push publicly to Quay.
- Credentials are an operational concern of the deployment environment (the qcow2 build step, or the VM hypervisor), not a concern of the image build step.

## See also

- `concepts/ownership_model.md`
- `concepts/state_and_persistence.md`
- `reference/scripts.md`
