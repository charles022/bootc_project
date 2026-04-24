

## Two-arifact build

1. a **bootc host image** that contains the NVIDIA host stack, CDI generation, and the `.kube` Quadlet that launches that dev container
2. a **GPU dev container image** that already contains GPU usage

clean responsibilities:
    - the bootc image makes the VM GPU-capable and able to launch the workload container
    - workload container contains the code to run


## where to define startup actions

The bootc host image uses systemd for boot-time actions, long-running services, timers, and orchestration. These units can be baked into the image build. Use RUN in the bootc image Containerfile for build-time installation/configuration, not for host startup behavior.

The dev container owns its runtime environment and usually one primary operational role. Its startup behavior is defined by the container layer, either in the image itself or, in our design, preferably in the Pod YAML / Quadlet-managed runtime definition.

Quadlets manage the automated startup and lifecycle of containers and pods, and can be included in the bootc image build so host systemd manages them at boot.

Pods are useful when major functions should be separated into different containers but still need tight coupling, such as shared lifecycle or close communication. In those cases, keep the functions in separate containers and let Quadlet + host systemd manage the pod and its containers.

In-container systemd is possible but should be treated as an exception rather than the default model.








1. bootc host image
    - uses systemd
    - implemented as systemd units, timers, config, and Quadlets
    - * not done through containerfile startup commands
2. quadlet
    - host-managed mechanism that owns handoff between bootc host image and dev
      container
2. dev container
    - image contents
    - startup command
    - Quadlet definition that tells host systemd when and how to run it
3. pods
    - when appropriate, separate processes into separate, connected containers
    - still managed by quadlet




1. bootc host
    - defined as systemd services in the containerfile
    - only use containerfile RUN for 1-time build processes on first boot
    - automatically start containers quadlets:
        - 
2. containers
    - define with RUN in the containerfile
    - should not manage their own systemd services
3. quadlets
    - containers that are started at boot




bootc host image uses systemd for init commands and services, which are baked into the
image build. systemd services can be built and included in the bootc image build
containerfile. RUN is fine in the bootc image Containerfile for build-time
installation and setup, but it is not the mechanism for runtime startup behavior

do not use "RUN" in the bootc image containerfile for automatic startup actions.

or initial commands defined in the image build. multiple

container startup commands and running actions are definied in the containerfile.
containers should primarily own 1 thing, and should not own their own systemd
services.

quadlets manage the automated startup and coordination of containers. quadlets are
injested in the bootc image build.

pods are for when we should have separate containers. Because containers primarily
"own" one purpose and their initial command and continuous actions are definied in the
containerfile initial run command, we can separate major functions (like backup
functionality vs dev environment) into separate containers, then link them tightly via
the pod. A Quadlet still manages the startup and coordination of contaiers and pods.




## 4-staged test build

1. manually run tests: start and enter containers and run test code
2. ++ automatically start dev container (via Containerfile)
3. ++ automatically run bootc host GPU configuration test (nvidia-smi)
    3a. via Containerfile-like initial command
    3b. via systemd-like service
4. ++ automatically start GPU test from dev container (pytorch model build/train/inference)
    4a. via Containerfile-like initial command
    4b. via systemd-like service



prereqs:
    - bootc host image GPU test is bootc_gpu_test.sh and contains a light check of GPU
      configuration, like 'nvidia-smi'
    - dev container GPU test is dev_container_gpu_test.py and contains a brief small
      model build, train, and inference using GPU

1. manually run tests: start and enter bootc host image and dev container and run test code
2. ++ automatically start dev container (via systemd)
3. ++ automatically run bootc host GPU configuration test (bootc_gpu_test.sh, via systemd)
4. ++ automatically run dev container initial command (via Containerfile, /bin/bash so that we can enter it on start)
5. ++ automatically run dev container GPU test (via systemd, )




Podman Quadlet supports `.kube` units read at boot or on `systemctl daemon-reload`, and NVIDIA recommends CDI for Podman GPU access. ([Podman Documentation][1])

** there are 2 ways to 'run on start': 1) via containerfile, 2) systemd
** here we'll use the containerfile approach, but system build components in production will primarily use systemd flows (some may still use containerfile initial commands)
** TODO: add a separate layer of tests to test our systemd workflow functionality:
    - bootc host systemd services
    - dev container systemd services


# Updated staged process

## Stage 1

* boot the **bootc image as a VM**
* log into the VM
* manually run 'nvidia-smi' or similar on bootc host image
* manually start the GPU dev container
* manually enter the GPU dev container
* manually run `train_smoke.py`

## Stage 2

* boot the **bootc image as a VM**
* the GPU dev container starts automatically
* log into the VM
* manually run 'nvidia-smi' or similar on bootc host
* manually enter the GPU dev container
* manually run `train_smoke.py`

## Stage 3

* boot the **bootc image as a VM**
* the GPU dev container starts automatically
* the bootc host GPU test runs automatically
* log into the VM
* manually enter the GPU dev container
* manually run `train_smoke.py`

## Stage 4

* boot the **bootc image as a VM**
* the GPU dev container starts automatically
* the bootc host GPU test runs automatically
* the GPU dev container starts automatically

* log into the VM
* manually enter the GPU dev container
* manually run `train_smoke.py`



* boot the **bootc image as a VM**


* the container automatically runs `train_smoke.py` as its initial command

That separation means the only thing that changes from stage to stage is service enablement and then the container’s startup command; the GPU plumbing stays the same throughout. ([Podman Documentation][1])

# Artifact 1: GPU dev container image

Because `train_smoke.py` must be present in the container from the start, the simplest defensible path is to make a small custom dev image on top of NVIDIA’s PyTorch container rather than the plain CUDA runtime image. NVIDIA’s PyTorch NGC container includes a prebuilt PyTorch install in the default Python environment and is intended for GPU-accelerated model work, which makes it a better base for a training+inference smoke test than `nvcr.io/nvidia/cuda:*runtime*`. ([NVIDIA NGC][2])

Use a container build context like this:

```text
01_build_image/build_assets/
├── dev-container.Containerfile
└── train_smoke.py
```

## `dev-container.Containerfile`

Pin a specific NGC PyTorch tag in your pipeline. Example:

```dockerfile
FROM nvcr.io/nvidia/pytorch:26.03-py3

WORKDIR /workspace
COPY train_smoke.py /workspace/train_smoke.py
RUN chmod 0755 /workspace/train_smoke.py
```

NVIDIA publishes PyTorch containers monthly and documents the available versions and contents, so pinning a specific tag is the stable choice for repeatable testing. ([NVIDIA Docs][3])

## Build and push the dev image

```bash
podman build -t quay.io/m0ranmcharles/fedora_init:dev-container -f 01_build_image/build_assets/dev-container.Containerfile 01_build_image/build_assets/
podman push quay.io/m0ranmcharles/fedora_init:dev-container
```

The important part is that the image referenced by the Quadlet is already built and already contains `train_smoke.py`, so no in-VM setup is needed before you run it. That matches your requirement exactly. 

# Artifact 2: bootc host image

Use the same bootc host concept as before, but now point the workload at your custom `dev-container` image instead of a raw NVIDIA runtime image.

## Bootc image build context

```text
01_build_image/build_assets/
├── Containerfile
├── config.toml
├── nvidia-cdi-refresh.service
├── devpod.kube
└── devpod.yaml
```

## `01_build_image/build_assets/Containerfile`

```dockerfile
FROM quay.io/fedora/fedora-bootc:42

RUN dnf -y install \
      podman \
      nvidia-open \
      nvidia-container-toolkit \
    && dnf clean all

COPY nvidia-cdi-refresh.service /usr/lib/systemd/system/nvidia-cdi-refresh.service
COPY devpod.kube /usr/share/containers/systemd/devpod.kube
COPY devpod.yaml /usr/share/containers/systemd/devpod.yaml

RUN systemctl enable nvidia-cdi-refresh.service
```

Fedora bootc images are customized through a standard `Containerfile`, and NVIDIA’s toolkit docs state that `nvidia-ctk` is the tool used for CDI generation while Podman should use CDI for NVIDIA devices. ([Fedora Project Documentation][4])

## `nvidia-cdi-refresh.service`

```ini
[Unit]
Description=Generate NVIDIA CDI specification
After=multi-user.target
ConditionPathExists=/usr/bin/nvidia-ctk

[Service]
Type=oneshot
ExecStart=/usr/bin/mkdir -p /etc/cdi
ExecStart=/usr/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

NVIDIA documents `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` as the CDI-generation step, and their Podman guidance points to CDI as the recommended model for GPU access. ([NVIDIA Docs][5])

# VM-first test flow

From here on, all testing happens in a **VM first**, including the GPU container testing. Fedora’s bootc docs say you convert a bootable container into a disk image with `bootc-image-builder`, and the qemu/libvirt docs describe producing a `.raw` or `.qcow2` image for virtualization. ([Fedora Project Documentation][4])

## 1) Build the bootc host image

```bash
podman build -t localhost/gpu-bootc-host:latest 01_build_image/build_assets/
```

## 2) Create a `config.toml` for VM login

Use SSH key auth so you do not need plaintext passwords. The `bootc-image-builder` examples support injecting a user and SSH key through `config.toml`. ([GitHub][6])

Example `01_build_image/build_assets/config.toml`:

```toml
[[customizations.user]]
name = "chuck"
key = "ssh-ed25519 AAAA...your-public-key..."
groups = ["wheel"]
```

## 3) Convert the bootc image into a qcow2 VM disk

```bash
mkdir -p output

sudo podman pull localhost/gpu-bootc-host:latest || true

sudo podman run \
  --rm \
  --privileged \
  -v ./output:/output \
  -v ./output/config.toml:/config.toml:ro \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --rootfs xfs \
  --config /config.toml \
  --local localhost/gpu-bootc-host:latest
```

Fedora’s bootc docs and the upstream `bootc-image-builder` examples both show this overall pattern: run `bootc-image-builder` inside a privileged container, mount `/output`, mount the local container storage, and pass `--type qcow2`; the upstream examples also show using `config.toml` to inject a user and SSH key. ([GitHub][6])

## 4) Boot the qcow2 as a VM

Use `virt-install` to import the qcow2. Fedora’s virtualization docs point to `virt-install` for command-line VM creation, and Fedora’s VM setup guidance notes UEFI boot for these kinds of images. ([Fedora Project Documentation][7])

A practical command shape is:

```bash
sudo virt-install \
  --name gpu-bootc-test \
  --memory 16384 \
  --vcpus 8 \
  --disk path=./output/qcow2/disk.qcow2,format=qcow2,bus=virtio \
  --import \
  --os-variant fedora-unknown \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --boot uefi
```

For the GPU portion of the test, the VM must also have access to the physical GPU via your chosen passthrough method; the smoke test only proves the GPU path if the guest actually owns the GPU. That part is outside the Quadlet/CDI design and belongs to your VM passthrough setup. Your `README.md` already treats GPU passthrough validation as a distinct testing step. 

## 5) Enter the VM

Once it boots, SSH into the VM using the injected key:

```bash
ssh chuck@<vm-ip>
```

That is the cleanest way to “enter and test from there” without relying on an interactive console workflow. `bootc-image-builder` explicitly supports user/key injection through `config.toml`. ([GitHub][6])

# Quadlet and Pod YAML

## `devpod.kube` for stage 1

```ini
[Unit]
Description=GPU development container
After=network-online.target nvidia-cdi-refresh.service
Wants=network-online.target
Requires=nvidia-cdi-refresh.service

[Kube]
Yaml=/usr/share/containers/systemd/devpod.yaml
```

Quadlet reads `.kube` units from `/usr/share/containers/systemd/` for distribution-provided system units and generates `.service` units at boot or after `systemctl daemon-reload`. ([Podman Documentation][1])

## `devpod.kube` for stages 2 and 3

```ini
[Unit]
Description=GPU development container
After=network-online.target nvidia-cdi-refresh.service
Wants=network-online.target
Requires=nvidia-cdi-refresh.service

[Kube]
Yaml=/usr/share/containers/systemd/devpod.yaml

[Install]
WantedBy=multi-user.target
```

The `[Install]` section is the only change needed to make the container start automatically at boot. ([Podman Documentation][1])

## `devpod.yaml` for stages 1 and 2

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: devpod
spec:
  restartPolicy: Never
  containers:
    - name: dev-container
      image: quay.io/m0ranmcharles/fedora_init:dev-container
      command:
        - /bin/bash
        - -lc
        - |
          sleep infinity
      stdin: true
      tty: true
      resources:
        limits:
          nvidia.com/gpu=all: 1
```

Podman’s kube-play GPU path is the documented place to use CDI GPU selectors such as `nvidia.com/gpu=all` through `resources.limits`. ([Fedora Project Documentation][4])

## `devpod.yaml` for stage 3

For stage 3, change only the command:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: devpod
spec:
  restartPolicy: Never
  containers:
    - name: dev-container
      image: quay.io/m0ranmcharles/fedora_init:dev-container
      command:
        - /bin/bash
        - -lc
        - |
          ./train_smoke.py
      workingDir: /workspace
      stdin: true
      tty: true
      resources:
        limits:
          nvidia.com/gpu=all: 1
```

That satisfies your revised design exactly: the same container image is used in all three stages, and stage 3 simply replaces the idle shell command with `./train_smoke.py`. 

# How to test inside the VM

## Common validation after boot

Inside the VM:

```bash
sudo nvidia-smi
sudo systemctl status nvidia-cdi-refresh.service
sudo test -f /etc/cdi/nvidia.yaml
```

This validates the guest-side driver and CDI generation, which is the prerequisite for the Podman GPU container path NVIDIA documents. ([NVIDIA Docs][5])

## Stage 1 inside the VM

```bash
sudo systemctl daemon-reload
sudo systemctl start devpod.service
sudo podman ps
sudo podman exec -it devpod-dev-container /bin/bash
cd /workspace
./train_smoke.py
```

## Stage 2 inside the VM

Enable the service once:

```bash
sudo systemctl daemon-reload
sudo systemctl enable devpod.service
sudo systemctl start devpod.service
```

After reboot, the container should already be running:

```bash
sudo podman ps
sudo podman exec -it devpod-dev-container /bin/bash
cd /workspace
./train_smoke.py
```

## Stage 3 inside the VM

After boot:

```bash
sudo systemctl status devpod.service
sudo podman logs devpod-dev-container
```

You should see `train_smoke.py` run automatically on container startup. Quadlet-generated services are managed directly through `systemctl`, and Podman containers can be inspected with normal `podman ps` and `podman logs` flows. ([Podman Documentation][1])

# Actual `train_smoke.py`

This script is intentionally small, deterministic, and does both a tiny training step and a tiny inference step on CUDA. It exits nonzero if CUDA is unavailable or if the GPU operations fail.

```python
#!/usr/bin/env python3

import os
import sys
import time
import random

import torch
import torch.nn as nn


def fail(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr, flush=True)
    raise SystemExit(code)


def seed_everything(seed: int = 1234) -> None:
    random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


class TinyNet(nn.Module):
    def __init__(self, in_features: int = 32, hidden: int = 64, out_features: int = 4) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(in_features, hidden),
            nn.ReLU(),
            nn.Linear(hidden, out_features),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


def main() -> int:
    print("=== train_smoke.py starting ===", flush=True)
    print(f"torch_version={torch.__version__}", flush=True)

    if not torch.cuda.is_available():
        fail("torch.cuda.is_available() returned False")

    device = torch.device("cuda:0")
    gpu_name = torch.cuda.get_device_name(device)
    print(f"cuda_available=True", flush=True)
    print(f"gpu_name={gpu_name}", flush=True)

    seed_everything()

    # Keep sizes tiny so the test is fast and deterministic.
    batch_size = 256
    in_features = 32
    num_classes = 4
    steps = 8

    model = TinyNet(in_features=in_features, hidden=64, out_features=num_classes).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=1e-3)
    criterion = nn.CrossEntropyLoss()

    model.train()

    start_train = time.perf_counter()
    last_loss = None

    for step in range(steps):
        x = torch.randn(batch_size, in_features, device=device)
        y = torch.randint(0, num_classes, (batch_size,), device=device)

        optimizer.zero_grad(set_to_none=True)
        logits = model(x)
        loss = criterion(logits, y)
        loss.backward()
        optimizer.step()

        last_loss = float(loss.detach().item())
        print(f"train_step={step} loss={last_loss:.6f}", flush=True)

    torch.cuda.synchronize()
    train_seconds = time.perf_counter() - start_train

    # Inference pass
    model.eval()
    with torch.inference_mode():
        x_inf = torch.randn(128, in_features, device=device)
        start_infer = time.perf_counter()
        logits_inf = model(x_inf)
        probs = torch.softmax(logits_inf, dim=1)
        preds = torch.argmax(probs, dim=1)
        torch.cuda.synchronize()
        infer_seconds = time.perf_counter() - start_infer

    if preds.numel() != 128:
        fail("unexpected inference output shape")

    # Sanity check that parameters are actually on CUDA.
    first_param = next(model.parameters())
    if first_param.device.type != "cuda":
        fail("model parameters are not on CUDA")

    print("=== smoke test summary ===", flush=True)
    print(f"final_loss={last_loss:.6f}", flush=True)
    print(f"train_seconds={train_seconds:.6f}", flush=True)
    print(f"infer_seconds={infer_seconds:.6f}", flush=True)
    print(f"pred_sample={preds[:10].tolist()}", flush=True)
    print("SMOKE_TEST_SUCCESS", flush=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

## Why this script is a good fit

* It verifies **PyTorch sees CUDA**.
* It performs an actual **forward + backward + optimizer step** on the GPU.
* It then performs a separate **inference pass** on the GPU.
* It is tiny enough to run quickly in a test VM.
* It fails loudly and early if the GPU path is broken.

That makes it appropriate both for manual execution in stages 1–2 and for automatic execution in stage 3. NVIDIA’s PyTorch containers are specifically intended to provide a validated Python/PyTorch GPU environment, which is why this script belongs in that container rather than in the host image. ([NVIDIA NGC][2])

# Final shape

After these additions, the path becomes:

## 1) Manual container start, manual entry, manual job

* build/push `quay.io/m0ranmcharles/fedora_init:dev-container` with `train_smoke.py` baked in
* build bootc host image
* convert bootc host image to qcow2
* boot qcow2 as a VM
* SSH into the VM
* manually start `devpod.service`
* `podman exec` into the container
* run `./train_smoke.py`

## 2) Automatic container start, manual entry, manual job

* same as above, but add `[Install]` to `devpod.kube`
* enable the service
* after reboot, SSH into the VM, `podman exec` in, run `./train_smoke.py`

## 3) Automatic container start, automatic job

* same image
* same VM boot flow
* same auto-started service
* replace `sleep infinity` with `./train_smoke.py`

That gives you the exact three checkpoints you wanted, with `train_smoke.py` present from the beginning and all testing happening in the VM first.

The next best step is for me to turn this into a polished documentation artifact with the file contents grouped by stage and a single end-to-end command sequence for the VM test path.

[1]: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html "podman-systemd.unit — Podman  documentation"
[2]: https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch?utm_source=chatgpt.com "PyTorch | NVIDIA NGC"
[3]: https://docs.nvidia.com/deeplearning/frameworks/pytorch-release-notes/rel-26-03.html?utm_source=chatgpt.com "PyTorch Release 26.03 - NVIDIA Docs"
[4]: https://docs.fedoraproject.org/en-US/bootc/getting-started/?utm_source=chatgpt.com "Getting Started with Bootable Containers :: Fedora Docs"
[5]: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html "Installing the NVIDIA Container Toolkit — NVIDIA Container Toolkit"
[6]: https://github.com/osbuild/bootc-image-builder?utm_source=chatgpt.com "osbuild/bootc-image-builder: A container for deploying ..."
[7]: https://docs.fedoraproject.org/en-US/quick-docs/virtualization-getting-started/?utm_source=chatgpt.com "Virtualization – Getting Started :: Fedora Docs"








############### previous #############


Yes — that separation is the right way to structure it.

You are really building **three layers of behavior** on top of the same GPU-capable host foundation:

1. **GPU-capable host + GPU-capable container definition**
2. **Container auto-start**
3. **Job auto-start inside that container**

Those should be implemented independently so you can validate each layer cleanly. That fits the staged build/test/deploy model in your `README.md`, and it preserves the most defensible GPU path from `gpu_integration_path.md`: Podman `.kube` Quadlets plus Kubernetes-style CDI GPU limits.   NVIDIA recommends CDI for Podman GPU access, `nvidia-ctk cdi generate` creates the CDI spec, and Podman documents GPU CDI selectors in `kube play` via `resources.limits` such as `nvidia.com/gpu=all`. ([NVIDIA Docs][1])

---

# The model

## Stage 1

Boot the system, then **manually start** the GPU-capable container, **manually enter** it, and **manually run** training/inference.

## Stage 2

Boot the system, the GPU-capable container **starts automatically**, then you **manually enter** it and **manually run** training/inference.

## Stage 3

Boot the system, the GPU-capable container **starts automatically**, and a **GPU-powered test job runs automatically** without user entry.

The key point is that **Stage 2 adds only service enablement**, and **Stage 3 adds only container command/job behavior**. The GPU plumbing itself should already be proven in Stage 1. ([NVIDIA Docs][2])

---

# What stays the same in all three stages

These pieces are common to all stages:

* the bootc host image
* the NVIDIA host driver
* Podman
* NVIDIA Container Toolkit / `nvidia-ctk`
* the systemd unit that generates `/etc/cdi/nvidia.yaml`
* the `.kube` Quadlet
* the Pod YAML with:

  ```yaml
  resources:
    limits:
      nvidia.com/gpu=all: 1
  ```

That is the documented GPU-enablement path. The only thing that changes across the stages is whether the Quadlet is enabled at boot, and what the container command does after it starts. ([NVIDIA Docs][1])

---

# End-to-end process

## 0) Build context

Use a directory like this:

```text
01_build_image/build_assets/
├── Containerfile
├── nvidia-cdi-refresh.service
├── devpod.kube
├── devpod.yaml
├── bootc_host_test.sh
└── dev_container_test.py
```

`train_smoke.py` is only needed for Stage 3. `run-gpu-smoke.sh` is only needed for Stage 3. The other four files are enough for Stages 1 and 2. Fedora bootc supports deriving images from a base image via a normal `Containerfile`, and Fedora documents embedding containerized workloads into the bootc image. ([Fedora Docs][3])

---

## 1) Host image: `Containerfile`

This is the shared base for all three stages.

```dockerfile
FROM quay.io/fedora/fedora-bootc:42

RUN dnf -y install \
      podman \
      nvidia-open \
      nvidia-container-toolkit \
    && dnf clean all

COPY nvidia-cdi-refresh.service /usr/lib/systemd/system/nvidia-cdi-refresh.service
COPY devpod.kube /usr/share/containers/systemd/devpod.kube
COPY devpod.yaml /usr/share/containers/systemd/devpod.yaml

# Stage 3 only:
COPY run-gpu-smoke.sh /usr/local/bin/run-gpu-smoke.sh
COPY train_smoke.py /usr/local/bin/train_smoke.py
RUN chmod 0755 /usr/local/bin/run-gpu-smoke.sh

RUN systemctl enable nvidia-cdi-refresh.service
```

Notes:

* `nvidia-open` installs the open-source kernel module plus the userspace driver libraries. `nvidia-container-toolkit` is the bridge layer that injects the driver into containers via CDI. Both are needed on the host.

---

## 2) CDI generation service: `nvidia-cdi-refresh.service`

```ini
[Unit]
Description=Generate NVIDIA CDI specification
After=multi-user.target
ConditionPathExists=/usr/bin/nvidia-ctk

[Service]
Type=oneshot
ExecStart=/usr/bin/mkdir -p /etc/cdi
ExecStart=/usr/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

This is what makes the host GPU available to CDI-aware Podman workloads. NVIDIA documents `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`, and notes that Podman should use CDI for NVIDIA device access. ([NVIDIA Docs][1])

---

## 3) Quadlet: `devpod.kube`

This file remains nearly identical across all three stages.

```ini
[Unit]
Description=GPU development container
After=network-online.target nvidia-cdi-refresh.service
Wants=network-online.target
Requires=nvidia-cdi-refresh.service

[Kube]
Yaml=/usr/share/containers/systemd/devpod.yaml
```

For Stage 2 and Stage 3, you will add an `[Install]` section so it starts automatically. Podman documents `.kube` Quadlets as a supported Quadlet type consumed by the systemd generator. ([Podman Documentation][5])

---

# Stage 1

# Manually start container, manually enter container, manually run job

This is the first target state.

## 4A) Pod YAML for Stage 1: `devpod.yaml`

Use a long-lived idle command so the container stays up and you can enter it later.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: devpod
spec:
  restartPolicy: Never
  containers:
    - name: dev-container
      image: nvcr.io/nvidia/cuda:12.6.3-runtime-ubuntu24.04
      command:
        - /bin/sh
        - -lc
        - |
          sleep infinity
      stdin: true
      tty: true
      resources:
        limits:
          nvidia.com/gpu=all: 1
```

The important parts are:

* `sleep infinity` keeps the container alive
* `stdin: true` and `tty: true` make interactive entry more convenient
* `resources.limits.nvidia.com/gpu=all: 1` requests the GPU through the documented kube/CDI path Podman supports. ([NVIDIA Docs][2])

## 5A) Build the image

```bash
podman build -t localhost/gpu-bootc-host:latest .
```

Fedora bootc uses standard container build workflows for derived images. ([Fedora Docs][3])

## 6A) Boot/install the image on a GPU-owning host

Use your normal bootc install/test flow here. That is consistent with the process in your `README.md`: build image, test it, then deploy/boot it.

## 7A) Validate host GPU and CDI

```bash
sudo nvidia-smi
sudo systemctl status nvidia-cdi-refresh.service
sudo test -f /etc/cdi/nvidia.yaml
grep 'name:' /etc/cdi/nvidia.yaml
```

These validate the three prerequisite layers:

* host driver works
* CDI generation ran
* CDI device names exist for Podman to consume. NVIDIA documents all of these checks. ([NVIDIA Docs][4])

## 8A) Manually start the container

```bash
sudo systemctl daemon-reload
sudo systemctl start devpod.service
sudo systemctl status devpod.service
```

Quadlet-generated units appear after `daemon-reload`, and the `.kube` unit starts the Podman kube workload. ([Podman Documentation][5])

## 9A) Manually enter the running container

The simplest practical method is to use Podman exec rather than SSH at this stage.

```bash
sudo podman ps
sudo podman exec -it devpod-dev-container /bin/sh
```

The exact generated container name can vary a little depending on pod/container naming, so `podman ps` is the safe first check. This stage is about proving the container is GPU-capable and usable as a dev shell, not about in-container SSH yet. Podman’s standard workflow supports interactive `exec` into running containers. ([Fedora Docs][6])

## 10A) Manually run a GPU test inside the container

Inside the container:

```bash
nvidia-smi
```

Or, if you install your framework stack in the image you choose, run a small manual training or inference script from that shell. The point of Stage 1 is that the container is already GPU-capable; the job itself is still user-driven. NVIDIA documents that Podman CDI GPU containers should be able to run `nvidia-smi` when the setup is correct. ([NVIDIA Docs][4])

### What Stage 1 proves

Stage 1 proves only this:

* the host booted correctly
* the host driver works
* the CDI spec exists
* the `.kube` Quadlet can start a GPU-capable container
* you can manually enter that container and manually run GPU work

Nothing here depends on auto-start or auto-executed jobs. That is why Stage 1 is the core validation milestone. ([NVIDIA Docs][1])

---

# Stage 2

# Automatically start container, manually enter container, manually run job

Stage 2 should change **only one thing**: the container starts automatically at boot.

## 4B) Update `devpod.kube`

Add the install section:

```ini
[Unit]
Description=GPU development container
After=network-online.target nvidia-cdi-refresh.service
Wants=network-online.target
Requires=nvidia-cdi-refresh.service

[Kube]
Yaml=/usr/share/containers/systemd/devpod.yaml

[Install]
WantedBy=multi-user.target
```

That is what makes the service enable-able at boot under systemd. This does not change the GPU mechanism and does not change the container command. ([Podman Documentation][5])

## 5B) Enable it

After booting the image:

```bash
sudo systemctl daemon-reload
sudo systemctl enable devpod.service
sudo systemctl start devpod.service
```

Or, if baked and enabled in your image workflow, it will already come up at boot. The important conceptual point is that **Stage 2 is just service enablement**. It does not alter the GPU/CDI path. ([Podman Documentation][5])

## 6B) After reboot

```bash
sudo systemctl status devpod.service
sudo podman ps
```

You should now see the container already running after boot. Then you enter it the same way as Stage 1:

```bash
sudo podman exec -it devpod-dev-container /bin/sh
```

And run your jobs manually from inside. Because the Pod YAML still uses `sleep infinity`, the container behaves like a development environment rather than a batch job container. ([Podman Documentation][5])

### What Stage 2 proves

Stage 2 proves only this additional thing:

* the system boots and automatically launches the GPU-capable dev container

Everything else remains identical to Stage 1. That clean separation is exactly what you want. ([Fedora Docs][7])

---

# Stage 3

# Automatically start container, automatically run job, no user entry required

Stage 3 should change **only the container command/job behavior**.

There are two clean ways to do this:

* **Option A:** replace `sleep infinity` with a script that runs the job and exits
* **Option B:** run the job, then keep the container alive afterward for inspection

For CI/CD validation, **Option B** is usually better because the system can run the smoke test immediately and still leave the container up for inspection if something fails.

## 4C) Add a smoke-test wrapper: `run-gpu-smoke.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== host-visible test inside container: nvidia-smi ==="
nvidia-smi

echo "=== framework smoke test ==="
python3 /usr/local/bin/train_smoke.py

echo "=== smoke test completed successfully ==="

# Keep container running for inspection
sleep infinity
```

This script is the Stage 3 addition. It is the thing that makes “container started” become “job ran automatically.” It does not change the host GPU plumbing. ([NVIDIA Docs][2])

## 5C) Add a minimal training/inference smoke script: `train_smoke.py`

Example placeholder:

```python
import sys
print("Replace this with your actual tiny GPU smoke test.")
print("Examples:")
print("- tiny PyTorch tensor on CUDA")
print("- tiny CUDA sample binary")
print("- tiny inference pass")
sys.exit(0)
```

In your real test image, replace that with an actual GPU-using framework test. The principle is what matters here: the automatic job is just the container command path, layered on top of the already-proven GPU container startup path. ([NVIDIA Docs][1])

## 6C) Update `devpod.yaml`

Replace the idle command with the smoke-test wrapper:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: devpod
spec:
  restartPolicy: Never
  containers:
    - name: dev-container
      image: nvcr.io/nvidia/cuda:12.6.3-runtime-ubuntu24.04
      command:
        - /bin/sh
        - -lc
        - |
          /usr/local/bin/run-gpu-smoke.sh
      stdin: true
      tty: true
      resources:
        limits:
          nvidia.com/gpu=all: 1
```

Now the boot sequence becomes:

1. boot host
2. generate CDI spec
3. systemd starts Quadlet service
4. Podman launches GPU-capable container
5. container immediately runs smoke test
6. container remains alive for inspection because the script ends with `sleep infinity`

That is the cleanest representation of your production-test goal. ([NVIDIA Docs][2])

## 7C) Validate after boot

```bash
sudo systemctl status devpod.service
sudo journalctl -u devpod.service -b
sudo podman logs devpod-dev-container
```

Those logs should show:

* `nvidia-smi` ran
* your small training/inference job ran
* the container remained up if you kept `sleep infinity`

That gives you exactly the kind of automated validation gate you described before promoting an image toward production. This also matches the test-first/VM-first mindset in your `README.md`.  ([Podman Documentation][5])

---

# Mapping each stage to your three desired outcomes

## 1) Manually start container, manually enter container, manually run job

Use:

* `devpod.kube` **without** `[Install]`
* `devpod.yaml` with `sleep infinity`

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl start devpod.service
sudo podman exec -it <container-name> /bin/sh
```

That gives you a GPU-capable dev container, but nothing auto-starts except the CDI generation unit. ([NVIDIA Docs][2])

## 2) Automatically start container, manually enter container, manually run job

Use:

* `devpod.kube` **with** `[Install] WantedBy=multi-user.target`
* `devpod.yaml` still with `sleep infinity`

Then enable the service:

```bash
sudo systemctl enable devpod.service
```

Now the container starts on boot, but it still just waits for you. You enter it manually and run whatever you want. ([Podman Documentation][5])

## 3) Automatically start container, automatically run job, no user entry required

Use:

* `devpod.kube` **with** `[Install]`
* `devpod.yaml` with a command that runs your wrapper script
* `run-gpu-smoke.sh` to run `nvidia-smi` plus your tiny training/inference smoke test

Now booting the system automatically runs the GPU-capable test container and the GPU-powered job. ([NVIDIA Docs][2])

---

# Important clarification about “SSH into the container”

For the early stages, the cleanest path is **not** SSH inside the container. It is to use:

```bash
sudo podman exec -it <container> /bin/sh
```

That keeps Stage 1 and Stage 2 focused purely on GPU enablement and service lifecycle. If later you want this dev container to accept SSH, that is a **separate feature**: you would bake `sshd` into the container image, expose/configure it, and manage keys. That is orthogonal to the GPU/CDI setup. Separating those concerns will make debugging much easier. Your `README.md` already emphasizes keeping setup concerns distinct from runtime service behavior; this follows that same discipline.

---

# Recommended order of implementation

Build and validate in this exact order:

1. **Stage 1 first**
   Prove GPU plumbing and manual usability.
2. **Stage 2 second**
   Add only service auto-start.
3. **Stage 3 last**
   Add only automatic job execution.

That is the safest path because if Stage 3 fails, you already know whether the failure is:

* host driver
* CDI generation
* Quadlet startup
* container startup
* or the test script itself


[1]: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html?utm_source=chatgpt.com "Installing the NVIDIA Container Toolkit"
[2]: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html?utm_source=chatgpt.com "Support for Container Device Interface"
[3]: https://docs.fedoraproject.org/en-US/bootc/building-containers/?utm_source=chatgpt.com "How to build derived bootc container images - Fedora Docs"
[4]: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/1.13.1/install-guide.html?utm_source=chatgpt.com "Installation Guide — container-toolkit 1.13.1 documentation"
[5]: https://docs.podman.io/_/downloads/en/v5.4.0/epub/?utm_source=chatgpt.com "Podman"
[6]: https://docs.fedoraproject.org/en-US/neurofedora/containers/?utm_source=chatgpt.com "Using containers (Docker/Podman) - Fedora Docs"
[7]: https://docs.fedoraproject.org/en-US/bootc/getting-started/?utm_source=chatgpt.com "Getting Started with Bootable Containers :: Fedora Docs"








