# GPU stack

## What

The NVIDIA software split spans the host image, a runtime bridge, and the workload container. The host image carries the kernel module and toolkit, the runtime bridge generates dynamic device paths at boot, and the dev container holds the CUDA toolkit and machine learning frameworks.

## Why

The load-bearing reason for this split is hardware decoupling. The alternative is baking the toolkit into every container or putting CUDA on the host OS, both of which tie application lifecycles directly to hardware driver lifecycles.

## Implications

This layered split shapes the project by decoupling updates: the host image updates slowly for OS and driver changes, while the dev pod and its containers can iterate rapidly without modifying the underlying host.

## The stack diagram

```text
bootc host image
  ├─ nvidia-open                    # open kernel module + userspace driver libs
  ├─ nvidia-container-toolkit       # CDI generator + runtime bridge (nvidia-ctk)
  ├─ nvidia-cdi-refresh.service     # oneshot: nvidia-ctk cdi generate -> /etc/cdi/nvidia.yaml
  ├─ nvidia-cdi-refresh.path        # re-run the service when /dev/nvidiactl appears
  ├─ devpod.kube                    # Quadlet that starts the pod at boot
  └─ devpod.yaml                    # Pod manifest, one persistent dev pod with GPU access

workload container (pulled from Quay at pod start)
  └─ nvcr.io/nvidia/pytorch:26.03-py3   # CUDA + cuDNN + PyTorch
```

## What lives where, and why

### Host image

The kernel module and userspace driver libraries live in the host image via `nvidia-open`. These must match the running kernel and are tied directly to the hardware. The `nvidia-container-toolkit` also installs here to provide the `nvidia-ctk` CLI used for CDI generation.

### Runtime bridge

The CDI specification at `/etc/cdi/nvidia.yaml` maps actual device files and library paths for container injection. It is generated dynamically at boot by `nvidia-cdi-refresh.service` calling `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`. The companion `nvidia-cdi-refresh.path` unit re-runs generation when `/dev/nvidia*` device nodes change. CDI device mappings must come from real hardware, so they are never baked into the image.

### Workload containers

The CUDA toolkit, cuDNN, and ML frameworks live entirely inside the dev container (e.g., PyTorch in `nvcr.io/nvidia/pytorch:26.03-py3`). Only the userspace CUDA bits go here. The backup sidecar runs alongside it but does not require GPU tools.

## The Quadlet `.kube` vs. `.container` choice

The dev pod uses a `.kube` Quadlet referencing `devpod.yaml` instead of a `.container` Quadlet. Kubernetes-style pod manifests support requesting GPUs via the documented CDI device selector:

```yaml
resources:
  limits:
    nvidia.com/gpu=all: 1
```

*(See `01_build_image/build_assets/devpod.yaml` in the repo for the authoritative version.)*

Podman's `kube play` formally documents this selector syntax. A standard `.container` Quadlet relies on `AddDevice=`, which accepts direct device paths but lacks an equivalent stable selector mechanism for CDI. The literal equivalent — `AddDevice=nvidia.com/gpu=all` in a `.container` file — may work in practice but is not formally documented for CDI selectors, so we take the documented `.kube` path.

### Boot-time flow

```text
devpod.kube                       # systemd reads this (when to run, deps)
    |
    v
systemd Quadlet generator         # at boot, and on `systemctl daemon-reload`
    |
    v
podman kube play devpod.yaml      # generated devpod.service runs this
    |
    v
sees nvidia.com/gpu=all in resources.limits
    |
    v
reads /etc/cdi/nvidia.yaml        # produced by nvidia-cdi-refresh.service
    |
    v
injects /dev/nvidia* into pod
```

## Known risks

### DKMS at build time

The `nvidia-open` package builds the kernel module via DKMS during `dnf install`, pinning against the bootc base image's running kernel. If the deployed host runs a different kernel, the module will not load. The fallback paths are either installing `kernel-devel` matching the base image's kernel, or swapping to RPM Fusion's `akmod-nvidia-open` to trigger the build at first boot.

### Why `nvidia-open` over the alternatives

- `cuda-drivers` (NVIDIA's proprietary kernel module path) is rejected because the open kernel module is NVIDIA's documented forward direction on Fedora and avoids the proprietary licensing surface for a workstation image we publish to a public registry.
- `akmod-nvidia` (RPM Fusion proprietary) is rejected for the same proprietary-path reason; `akmod-nvidia-open` remains the deferred-build fallback if the in-Containerfile DKMS path proves unreliable.
- The toolkit/driver split keeps userspace CUDA inside the workload container via `nvidia-container-toolkit` + CDI, rather than exposing CUDA on the host. This avoids tying application lifecycles to the host driver lifecycle.

### CDI selector syntax not validated

The `nvidia.com/gpu=all` resource key in `devpod.yaml` has not been validated end-to-end against current Podman and NVIDIA-toolkit versions. First boot on real GPU hardware is the validation point.

## See also

- `concepts/ownership_model.md`
- `reference/systemd_units.md`
- `reference/quadlets.md`
- `reference/images.md`
- `how-to/validate_gpu.md`