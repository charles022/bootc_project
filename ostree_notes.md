This is a well-reasoned instinct, but there's a critical detail about how bootc handles the filesystem that changes the calculus for SSH specifically — and probably for several of your other "system component" scripts too.

## bootc's mutability model

bootc (via ostree underneath) divides the filesystem into three zones:

- `/usr` — immutable, owned by the image, replaced on updates
- `/etc` — **mutable, persists across updates**, gets a 3-way merge (your local changes vs. old image vs. new image)
- `/var` — fully mutable and persistent, no merge logic, survives everything

This means `sshd_config`, `authorized_keys`, host keys — everything in `/etc/ssh/` — is already mutable and persistent by default. You can edit it live with a text editor and it will survive a `bootc upgrade` with no container abstraction needed. The same applies to most of your "once set up, occasionally tweak" system config scripts (sudoers, networking, etc.).

So the real question becomes: **what does a separate SSH container actually buy you?** For most of what you described, the answer is "nothing, at significant added complexity." sshd in a container requires `--network=host` and elevated privileges to bind port 22 and manage PAM/login sessions correctly — you're essentially fighting containerization's purpose to run something that's already well-served by the host.

---

## Where your model *does* make sense

The separate-container pattern becomes genuinely valuable for your **workstation / day-to-day environment** — the thing you'd log *into* rather than the thing that lets you log in. That's a legitimate and Fedora-endorsed use case.

Here's the actual recommended decomposition:

---

## The three main patterns, and when to use each

### 1. Bake it into the bootc image (Containerfile layer)

Best for: the OS skeleton, daemons whose config lives in `/etc`, anything that needs deep system integration.

```dockerfile
FROM quay.io/fedora/fedora-bootc:42
RUN dnf install -y openssh-server && \
    systemctl enable sshd
COPY sshd_config_baseline /etc/ssh/sshd_config.d/99-custom.conf
```

The baseline config ships with the image, but `/etc/ssh/` remains mutable so you can tune it live. A `bootc upgrade` will 3-way merge your local changes against the new image's baseline — your local edits win unless there's a genuine conflict. SSH, firewall config, systemd unit overrides, journald settings — all of these belong here.

### 2. Podman Quadlets baked into the bootc image

Best for: containerized services you want running on boot, with updatable images independent of the OS image. This is the **primary Fedora-endorsed pattern** for "container as system component."

A Quadlet is a `.container` (or `.pod`, `.network`, `.volume`) file that `systemd-generator` converts into a proper systemd unit at boot. You bake the Quadlet definition files into the image; the actual container image is pulled at runtime.

System-wide Quadlets live at `/usr/share/containers/systemd/` (read-only, from your bootc image) or `/etc/containers/systemd/` (mutable, for runtime additions).

```
# /usr/share/containers/systemd/workstation.container
[Unit]
Description=Workstation container
After=network-online.target

[Container]
Image=quay.io/m0ranmcharles/fedora_init:dev-container
AutoUpdate=registry
Volume=/var/workstation-home:/home/user:Z
Network=host          # or a named network
Exec=/usr/bin/sleep infinity

[Install]
WantedBy=multi-user.target
```

This gives you: automatic startup, `systemctl status workstation`, `journalctl -u workstation`, and `podman auto-update` for container-level updates without touching the OS image. The container image lifecycle is fully decoupled from the bootc image lifecycle.

### 3. Podman pods via Quadlets

Best for: tightly coupled services that need shared network/IPC namespace — think a service + its sidecar proxy, or a database + its exporter. You define a `.pod` Quadlet and then `.container` Quadlets that reference it.

```
# workstation.pod
[Pod]
PodName=workstation

# app.container
[Container]
Pod=workstation.pod
Image=quay.io/m0ranmcharles/fedora_init:dev-container

# proxy.container  
[Container]
Pod=workstation.pod
Image=quay.io/m0ranmcharles/fedora_init:backup-container
```

This is valid, but I'd push back on your specific SSH+workstation pod design. The shared-namespace benefit of pods is most useful when two processes need to talk over localhost without network overhead, or share IPC. SSH → workstation doesn't need that: you SSH to the host, then either `podman exec -it workstation bash` or configure SSH to drop you directly into the container via `ForceCommand`. The pod adds orchestration complexity without a clear gain here.

---

## Recommended architecture for your use case

```
bootc image (Containerfile)
├── sshd installed + enabled (config in /etc/ssh/, mutable)
├── podman installed
├── Quadlet definitions in /usr/share/containers/systemd/
│   ├── workstation.container   ← your day-to-day env
│   └── (other service containers as needed)
└── any other system config that belongs to the OS layer

/var/workstation-home/    ← persistent storage, survives bootc upgrades
/etc/ssh/                 ← mutable, survives bootc upgrades with merge
```

SSH to the host. From there, `podman exec -it workstation fish` (or whatever shell), or set up `Match User` in sshd_config with `ForceCommand podman exec -it workstation /bin/bash` to drop directly into the container on login. The workstation container image gets updated independently via `podman auto-update` or a manual `podman pull` + `systemctl restart workstation`.

---

## What you may not be considering

**`bootc switch` and image composition** — if you want true modularity at the OS layer, look at whether your components can be composed via layered Containerfiles rather than runtime containers. A "base" bootc image that other images `FROM`, each adding their layer. This is useful if you end up managing multiple machines with different roles.

**`/usr/lib/systemd/system/` drop-ins** — for service configuration that ships with the image but shouldn't be in `/etc` (which is user-territory), use `/usr/lib/` paths. They're image-owned and don't conflict with admin overrides in `/etc/systemd/system/`.

**`podman auto-update` with Quadlets** — set `AutoUpdate=registry` in your `.container` files and run `podman auto-update` (or enable the systemd timer for it) to get container image updates on a schedule without touching the bootc image at all.

**State separation discipline** — the most important long-term decision is being strict about what lives in `/var` vs. `/etc` vs. the image. `/etc` for config, `/var` for data, image for binaries and unit files. If you establish that discipline now, rollbacks become clean and predictable.
