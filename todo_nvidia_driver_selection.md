## Targeted proposal: NVIDIA driver strategy for Fedora bootc host

We need the host image driver strategy finalized and implemented around **NVIDIA’s upstream/open driver path**, not RPM Fusion.

### Objective

Define and implement the NVIDIA GPU driver layer for the Fedora bootc host image using:

```text
nvidia-open
nvidia-container-toolkit
```

Do **not** use:

```text
akmod-nvidia
RPM Fusion driver packages
```

### Scope

Address only the **host-level NVIDIA driver strategy**.

The host bootc image should provide:

1. NVIDIA kernel/user driver support through `nvidia-open`
2. NVIDIA container runtime integration through `nvidia-container-toolkit`
3. GPU exposure to Podman containers, preferably through CDI
4. A validation path proving that the official NVIDIA PyTorch container can see and use the GPU

The CUDA toolkit, cuDNN, NCCL, PyTorch, JAX, TensorFlow, and other ML userspace development tools should remain inside the dev container, not on the host.

### Desired host/container split

```text
Fedora bootc host:
  - nvidia-open
  - nvidia-container-toolkit
  - Podman
  - CDI/device exposure
  - systemd/Quadlet orchestration

NVIDIA PyTorch dev container:
  - CUDA userspace stack
  - PyTorch
  - ML/development tooling
  - training/inference workloads
```

### Required deliverables

The agent should produce:

1. A recommended Fedora bootc `Containerfile.host` driver section using NVIDIA’s repo/packages.
2. Any required repo setup for installing `nvidia-open`.
3. Required installation/configuration steps for `nvidia-container-toolkit`.
4. The preferred Podman GPU exposure method.
5. A minimal validation procedure:

   * host-level driver validation
   * container-level GPU validation
   * PyTorch CUDA validation
6. Clear notes on what can be tested in a VM versus what requires bare metal or GPU passthrough.

### Validation target

The final validation should include a command equivalent to:

```bash
podman run --rm \
  --device nvidia.com/gpu=all \
  nvcr.io/nvidia/pytorch:latest \
  python3 - <<'PY'
import torch

print("cuda:", torch.cuda.is_available())
print("device_count:", torch.cuda.device_count())

if torch.cuda.is_available():
    print("device:", torch.cuda.get_device_name(0))
    x = torch.randn(4096, 4096, device="cuda")
    y = x @ x
    print(float(y[0, 0]))
PY
```

### Constraints

* Do not use RPM Fusion.
* Do not use `akmod-nvidia`.
* Do not install the full CUDA development stack on the host unless strictly required for driver/container runtime validation.
* Keep the host minimal.
* Keep ML framework/toolkit dependencies in the NVIDIA PyTorch dev container.
* Prefer a strategy that is scriptable and compatible with bootc image builds.
* Explicitly separate:

  * normal VM boot validation
  * GPU passthrough VM validation
  * bare-metal GPU validation

### Expected conclusion

The agent should return a concrete, scriptable driver strategy centered on:

```text
NVIDIA repo + nvidia-open + nvidia-container-toolkit + Podman CDI
```

with enough detail to add it to the bootc host image build and test pipeline.

