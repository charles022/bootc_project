# Staged validation of the tenant dev environment

## Goal
Validate GPU development in three explicit stages, peeling back manual steps one at a time so each layer of automation can be verified in isolation.

## Why staged
Each stage isolates one new piece of automation. If something breaks at stage 3, you know it isn't the image, the CDI generation, or the Quadlet — it's the workload startup.

## The three stages

### Stage 1 — host driver and legacy fallback
Confirm the host driver and CDI spec are healthy before involving tenant rootless Podman:

```bash
nvidia-smi
sudo test -r /etc/cdi/nvidia.yaml
grep -n 'nvidia.com/gpu=all' /etc/cdi/nvidia.yaml
```

While `devpod` is retained, it can also prove the documented `.kube` CDI path:

```bash
sudo systemctl start devpod.service
sudo podman exec -it devpod-dev-container nvidia-smi
```

### Stage 2 — tenant agent start, manual job
Create an agent with the tenant `dev-env` image and confirm the rendered Quadlet requests the GPU:

```bash
sudo platformctl agent create alice \
    --name gpu-test \
    --runtime quay.io/m0ranmcharles/fedora_init:openclaw-runtime \
    --environment quay.io/m0ranmcharles/fedora_init:dev-env
UID_=$(id -u tenant_alice)
sudo grep -n 'PodmanArgs=--device=nvidia.com/gpu=all' \
    /etc/containers/systemd/users/${UID_}/alice-gpu-test-dev-env.container
sudo grep -n 'PodmanArgs=--security-opt=label=disable' \
    /etc/containers/systemd/users/${UID_}/alice-gpu-test-dev-env.container
sudo machinectl shell tenant_alice@ /usr/bin/podman exec -it alice-gpu-test-dev-env nvidia-smi
```

This is the rootless CDI validation gate. Do not remove the system dev pod until it passes on NVIDIA hardware.

### Stage 3 — tenant startup smoke test
Run the baked-in PyTorch test inside the tenant dev environment:

```bash
sudo machinectl shell tenant_alice@ /usr/bin/podman exec -it alice-gpu-test-dev-env \
    python3 /workspace/dev_container_test.py
```

The `dev_container_start.sh` entrypoint also runs this test on container startup and then keeps the container alive with `tail -f /dev/null` so you can enter it for manual work.

## The smoke test

The repo currently ships `dev_container_test.py` (see `reference/scripts.md`), which validates Python, PyTorch, and CUDA visibility. An expanded GPU smoke test should assert at minimum:

1. `torch.cuda.is_available()` returns `True`.
2. A tensor placed on `cuda:0` reports `device.type == "cuda"`.
3. A forward pass and `loss.backward()` complete on the GPU.

A 5–10-line sketch:

```python
import torch, torch.nn as nn
assert torch.cuda.is_available(), "CUDA not visible"
dev = torch.device("cuda:0")
m = nn.Linear(8, 4).to(dev)
x = torch.randn(16, 8, device=dev)
loss = m(x).sum()
loss.backward()
assert next(m.parameters()).device.type == "cuda"
print("SMOKE_TEST_SUCCESS")
```

Keep it tiny and deterministic; the goal is a fast pass/fail gate, not a benchmark.

## Why not bake `sshd` into the dev container

For stages 1 and 2, use `podman exec`, not in-container SSH. Baking `sshd` into the dev container adds an init concern orthogonal to GPU enablement, and re-introduces an in-container service manager. Keep access on the host (`concepts/access_model.md`) and the container focused on the workload.

## See also
- `concepts/ownership_model.md`
- `concepts/access_model.md`
- `reference/quadlets.md`
- `reference/scripts.md`
- `how-to/validate_gpu.md`
