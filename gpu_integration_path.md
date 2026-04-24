# GPU integration path

## Shape

The bootc host image carries the host-side GPU software. Workloads live in
separate container images. Podman's CDI (Container Device Interface) is the
runtime handoff between them.

```text
bootc host image
  ├─ nvidia-open                    # open kernel module + userspace driver libs
  ├─ nvidia-container-toolkit       # CDI generator + runtime bridge (nvidia-ctk)
  ├─ nvidia-cdi-refresh.service     # oneshot: nvidia-ctk cdi generate -> /etc/cdi/nvidia.yaml
  ├─ nvidia-cdi-refresh.path        # re-run the service when /dev/nvidiactl appears
  ├─ devpod.kube                    # Quadlet that starts the pod at boot
  └─ devpod.yaml                    # Pod manifest, one persistent dev pod with GPU access

workload container (pulled from Quay at pod start)
  └─ nvcr.io/nvidia/pytorch:<tag>   # CUDA + cuDNN + PyTorch
```

The host image adds the NVIDIA CUDA repo and installs `nvidia-open` and
`nvidia-container-toolkit` at build time. CUDA/cuDNN/framework content stays in
the workload container — never in the host image.

## Why CDI, and why a `.kube` Quadlet

The CDI spec at `/etc/cdi/nvidia.yaml` describes the GPU to Podman: device
files, driver library mounts, environment variables. Podman consumes it when
a container requests `nvidia.com/gpu=all`. The spec references runtime device
paths, so it cannot be baked into the image — `nvidia-cdi-refresh.service`
runs `nvidia-ctk cdi generate` at boot, and the `.path` unit re-triggers it if
the GPU device node appears later.

A `.kube` Quadlet (not a `.container` Quadlet) is used so the pod manifest can
request the GPU via the documented Kubernetes-style selector:

```yaml
resources:
  limits:
    nvidia.com/gpu=all: 1
```

Podman's `kube play` documents this selector. The equivalent
`AddDevice=nvidia.com/gpu=all` on a `.container` Quadlet is not formally
documented for CDI selectors, so we take the documented path.

## Pod model

`devpod.yaml` is a long-lived development pod — `restartPolicy: Always`, both
containers (dev and backup sidecar) stay up via `tail -f /dev/null` so you can
`podman exec` into them. This is deliberately **not** a batch-job model:
workloads are driven interactively from inside the running container, not by
spinning up a fresh pod per job.

When we later want automated training/inference runs, the mechanism stays the
same — replace the dev container's startup script with the workload, or add a
second Quadlet that runs a oneshot pod alongside the dev pod. The CDI path
does not change.

## Validating end-to-end

On the booted host:

```bash
sudo nvidia-smi                                    # driver + hardware OK
sudo systemctl status nvidia-cdi-refresh.service   # CDI spec generated
sudo test -f /etc/cdi/nvidia.yaml                  # spec present
sudo systemctl status devpod.service               # Quadlet-generated pod service
sudo podman ps                                     # dev + backup containers running
sudo podman exec -it devpod-dev-container /bin/bash
  # inside the container:
  nvidia-smi                                       # GPU visible through CDI
  python3 /workspace/dev_container_test.py         # torch sees CUDA
```

## Risk: DKMS kernel-module build at image build time

`nvidia-open` uses DKMS to build the kernel module at `dnf install` time,
against the kernel present in the build environment. bootc base images ship a
specific kernel, so the module should build against that kernel and be correct
for the image that eventually boots. If the module fails to load at boot —
`nvidia-smi` fails, `/dev/nvidiactl` never appears — the two recovery paths
are:

1. Add `kernel-devel` matching the base image's kernel to the `dnf install`
   line so DKMS has what it needs at build time.
2. Switch to RPM Fusion's `akmod-nvidia-open`, which defers the build to
   first boot via `akmods`.

Start with (1) only if needed; (2) is a larger change.
