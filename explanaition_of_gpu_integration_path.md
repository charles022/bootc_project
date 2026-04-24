# Why `.kube` Quadlets instead of `.container`

This is the one non-obvious choice in `gpu_integration_path.md`. Everything
else — drivers on the host, CDI generated at boot, workload in a container —
is standard. The `.kube` vs `.container` pick is worth explaining in its own
doc.

## What a Quadlet actually is

A Quadlet file is a config file that systemd reads and converts into a real
systemd unit at boot. Instead of writing a full `podman run ...` command
inside a systemd service file yourself, you write a declarative `.container`
or `.kube` file and the Quadlet generator produces the systemd unit for you.

## The obvious choice: `.container`

The natural way to run a container via Quadlet is a `.container` file:

```ini
[Container]
Image=nvcr.io/nvidia/cuda:12.6.3-runtime-ubuntu24.04
AddDevice=/dev/nvidia0
```

`AddDevice=` maps directly to `podman run --device=`. It works fine for
regular device paths like `/dev/nvidia0`. The problem: you don't want to
hardcode device paths. You want `nvidia.com/gpu=all` — a CDI selector — so
Podman handles device injection automatically regardless of how many GPUs
exist or how they're numbered.

You can write `AddDevice=nvidia.com/gpu=all` in a `.container` file. It may
even work. But Podman's official documentation for `.container` Quadlets
describes `AddDevice=` as accepting device paths — not CDI selectors. That
form is undocumented/untested in that context.

## The documented path: `.kube`

A `.kube` Quadlet doesn't run `podman run`. It runs `podman kube play`, which
takes a Kubernetes-style Pod YAML. In that YAML, GPU access is requested
like this:

```yaml
resources:
  limits:
    nvidia.com/gpu=all: 1
```

Podman's `kube play` documentation explicitly states that this syntax invokes
CDI device selection. Same outcome — same CDI lookup — but this path is
documented.

## The indirection

```text
devpod.kube                ← systemd reads this (when to run, dependencies, etc.)
    │
    └─► podman kube play devpod.yaml
                │
                └─► sees nvidia.com/gpu=all in resources.limits
                            │
                            └─► looks up /etc/cdi/nvidia.yaml
                                        │
                                        └─► injects GPU into container
```

The two-file structure exists because `.kube` separates systemd concerns (the
`.kube` file: start order, dependencies, install target) from container
concerns (the `.yaml` file: what image, what command, what resources).

## Bottom line

Both approaches probably work. The `.kube` path is chosen because CDI
selectors in `resources.limits` are documented by Podman and
`AddDevice=nvidia.com/gpu=all` in a `.container` file is not.
