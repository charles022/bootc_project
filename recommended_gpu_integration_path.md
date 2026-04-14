
## Recommended pattern

Use a **Fedora bootc image** to hold only:

* the **host-side NVIDIA driver path**
* **nvidia-container-toolkit**
* a **systemd unit** that generates the CDI spec at boot
* **Quadlet workload definitions**

Then run the actual ML workloads in **NVIDIA CUDA/PyTorch containers**. That matches bootc’s documented image-customization model, NVIDIA’s Podman guidance, and Podman’s current recommendation to use Quadlets under systemd. ([NVIDIA Docs][1])

The one change from the earlier draft is important:

* I do **not** recommend relying on `AddDevice=nvidia.com/gpu=all` inside a `.container` Quadlet.
* The safest current shape is to use a **`.kube` Quadlet** that points to a Podman kube YAML, because Podman explicitly documents CDI GPU selectors there via Kubernetes-style resource limits such as `nvidia.com/gpu=all`. ([Podman Documentation][2])

---

## Final architecture

```text
bootc image
  ├─ NVIDIA repo + host driver packages
  ├─ nvidia-container-toolkit
  ├─ systemd service: generate /etc/cdi/nvidia.yaml
  ├─ Quadlet: train-job.kube
  ├─ Quadlet: inference-job.kube
  └─ Kubernetes YAML files consumed by those .kube Quadlets

containers
  ├─ nvcr.io/nvidia/pytorch:<tag>   # training
  └─ nvcr.io/nvidia/cuda:<tag>      # inference or CUDA validation
```

This keeps the bootc image lean and declarative, while leaving CUDA/cuDNN/framework content in the container images where NVIDIA expects it to live. ([NVIDIA Docs][1])

---

## 1) Bootc `Containerfile`

This uses the **NVIDIA-direct** path with `nvidia-open`, which NVIDIA documents for Fedora as the open-kernel-module install path. If you later prefer RPM Fusion, you can swap just the repo/package section and keep the rest of the architecture the same. ([NVIDIA Docs][3])

```dockerfile
FROM quay.io/fedora/fedora-bootc:42

# NVIDIA repo and host-side packages only
RUN dnf -y install dnf-plugins-core \
    && dnf config-manager --add-repo \
       https://developer.download.nvidia.com/compute/cuda/repos/fedora42/x86_64/cuda-fedora42.repo \
    && dnf -y install \
       nvidia-open \
       nvidia-container-toolkit \
    && dnf clean all

# CDI generation service
COPY nvidia-cdi-refresh.service /usr/lib/systemd/system/nvidia-cdi-refresh.service

# Quadlet + kube workload definitions
COPY train-job.kube /usr/share/containers/systemd/train-job.kube
COPY inference-job.kube /usr/share/containers/systemd/inference-job.kube
COPY train-job.yaml /usr/share/containers/systemd/train-job.yaml
COPY inference-job.yaml /usr/share/containers/systemd/inference-job.yaml

RUN systemctl enable nvidia-cdi-refresh.service
```

Why this shape:

* bootc-derived images are meant to be customized with normal container build syntax like `RUN dnf -y install ...`, not `rpm-ostree install`. ([NVIDIA Docs][4])
* NVIDIA’s Fedora driver docs currently show `dnf install nvidia-open` for the open-kernel-module path. ([NVIDIA Docs][3])

---

## 2) CDI generation service

NVIDIA recommends **CDI** for Podman, and their toolkit provides `nvidia-ctk cdi generate`. The CDI spec must exist on the system that actually owns the GPU. In bare metal, that is the host OS. In a passthrough VM, that is the guest OS. ([NVIDIA Docs][1])

`/usr/lib/systemd/system/nvidia-cdi-refresh.service`

```ini
[Unit]
Description=Generate NVIDIA CDI specification
After=multi-user.target
ConditionPathExists=/usr/bin/nvidia-ctk

[Service]
Type=oneshot
ExecStart=/usr/bin/mkdir -p /etc/cdi
ExecStart=/usr/bin/sh -c '/usr/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

This gives you a stable, declarative step that can be re-run after driver/toolkit updates as needed. NVIDIA documents CDI generation with `nvidia-ctk`, and Podman’s default CDI spec directory is `/etc/cdi`. ([NVIDIA Docs][4])

---

## 3) Quadlet files

Use **`.kube` Quadlets**, not `.container` for the GPU-exposed workloads.

Podman’s Quadlet generator supports `.kube` units, and Podman’s kube support explicitly documents CDI GPU selectors in Kubernetes-style `resources.limits`, including `nvidia.com/gpu=all`. That is the cleanest documented way to express CDI GPU access in a declarative systemd-managed Podman workload today. ([Podman Documentation][5])

`/usr/share/containers/systemd/train-job.kube`

```ini
[Unit]
Description=GPU training job

[Kube]
Yaml=/usr/share/containers/systemd/train-job.yaml

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=900
```

`/usr/share/containers/systemd/inference-job.kube`

```ini
[Unit]
Description=GPU inference job

[Kube]
Yaml=/usr/share/containers/systemd/inference-job.yaml

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=900
```

Podman documents `.kube` as a supported Quadlet type and recommends Quadlets generally over older generated systemd units. ([Podman Documentation][5])

---

## 4) Kube YAML for the workloads

### Training job

`/usr/share/containers/systemd/train-job.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: train-job
spec:
  restartPolicy: Never
  containers:
    - name: trainer
      image: nvcr.io/nvidia/pytorch:24.12-py3
      command: ["python", "/train.py"]
      volumeMounts:
        - name: workload
          mountPath: /train.py
          subPath: train.py
      resources:
        limits:
          nvidia.com/gpu=all: 1
  volumes:
    - name: workload
      hostPath:
        path: /opt/workloads
        type: Directory
```

### Inference / CUDA validation job

`/usr/share/containers/systemd/inference-job.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: inference-job
spec:
  restartPolicy: Never
  containers:
    - name: inference
      image: nvcr.io/nvidia/cuda:12.6.3-runtime-ubuntu24.04
      command:
        - /bin/sh
        - -lc
        - |
          nvidia-smi && python3 - <<'PY'
          import subprocess
          print("cuda_validation_ok")
          PY
      resources:
        limits:
          nvidia.com/gpu=all: 1
```

The important line is:

```yaml
resources:
  limits:
    nvidia.com/gpu=all: 1
```

Podman’s kube documentation explicitly supports CDI selectors in this form. ([Podman Documentation][2])

---

## 5) How to use it

After you build and boot the image on the system that owns the GPU:

```bash
sudo systemctl status nvidia-cdi-refresh.service
sudo cat /etc/cdi/nvidia.yaml
sudo systemctl daemon-reload

sudo systemctl start train-job.service
sudo systemctl status train-job.service

sudo systemctl start inference-job.service
sudo systemctl status inference-job.service
```

What you want to verify:

```bash
nvidia-smi
podman info | grep -i cdi -A3
ls -l /etc/cdi/nvidia.yaml
journalctl -u nvidia-cdi-refresh.service -b
journalctl -u train-job.service -b
journalctl -u inference-job.service -b
```

NVIDIA documents that Podman should use CDI for GPU device access, and Podman documents `/etc/cdi` as the default CDI spec location. ([NVIDIA Docs][1])

---

## 6) What success looks like

I would call this setup validated when all of the following are true:

* `nvidia-smi` works on the OS that owns the GPU
* `nvidia-cdi-refresh.service` successfully creates `/etc/cdi/nvidia.yaml`
* the `.kube` Quadlet starts successfully under systemd
* the training container can allocate the GPU and complete a small training loop
* the inference/CUDA validation container can see the GPU and complete a simple run

That validates the exact layered model you want:

```text
bootc image
  -> host driver
  -> nvidia-container-toolkit
  -> CDI
  -> Podman/Quadlet
  -> CUDA container
  -> training/inference
```

This architecture stays close to Fedora/bootc’s documented image-building model, NVIDIA’s documented Podman/CDI model, and Podman’s current Quadlet model. ([NVIDIA Docs][4])

---

## Bottom line

**Yes — this is the corrected final version I recommend.**


* **Use `.kube` Quadlets with CDI selectors in the kube YAML**
* **Do not depend on undocumented `.container` `AddDevice=nvidia.com/gpu=all` behavior**

That keeps the whole thing on the most clearly documented path. ([Podman Documentation][2])

I can turn this next into a single copy-paste-ready repo layout with the files exactly named and placed.

[1]: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html?utm_source=chatgpt.com "Installing the NVIDIA Container Toolkit"
[2]: https://docs.podman.io/en/latest/markdown/podman-kube-play.1.html?utm_source=chatgpt.com "podman-kube-play"
[3]: https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/fedora.html?utm_source=chatgpt.com "Fedora — NVIDIA Driver Installation Guide"
[4]: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html?utm_source=chatgpt.com "Support for Container Device Interface"
[5]: https://docs.podman.io/en/latest/_sources/markdown/podman-systemd.unit.5.md.txt?utm_source=chatgpt.com "podman-systemd.unit.5.md.txt"

