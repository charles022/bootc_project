# Staged validation of the dev pod

## Goal
Validate the GPU dev container in the VM in three explicit stages, peeling back manual steps one at a time so each layer of automation can be verified in isolation.

## Why staged
Each stage isolates one new piece of automation. If something breaks at stage 3, you know it isn't the image, the CDI generation, or the Quadlet — it's the workload startup.

## The three stages

### Stage 1 — manual start, manual job
- `devpod.kube` ships **without** an `[Install]` section.
- Pod manifest's container command is `sleep infinity` (a long-running keepalive — see below).

```bash
sudo systemctl daemon-reload
sudo systemctl start devpod.service
sudo podman exec -it devpod-dev-container /bin/bash
# inside the container:
./train_smoke.py
```

Confirms the image, CDI plumbing, and pod can run a GPU workload at all.

### Stage 2 — auto start, manual job
- Add `[Install] WantedBy=multi-user.target` to `devpod.kube`.
- Manifest still uses `sleep infinity`.

After reboot, the pod is up. SSH in, `podman exec`, run the smoke test by hand.

### Stage 3 — auto start, auto job
- `[Install]` stays.
- Replace the container's `sleep infinity` (or the equivalent `tail -f /dev/null` keepalive) with the smoke-test wrapper, so the workload runs as the container's `CMD`.

Boot is now self-validating.

## The two staging tricks

- **Omitting `[Install]`** keeps the generated `devpod.service` from auto-starting at boot. You can still drive it with `systemctl start` for a manual run. Add `[Install]` only when you want boot-time start.
- **`sleep infinity` (or `tail -f /dev/null`) as the container command** keeps the pod alive after the smoke test exits, so you can `podman exec` in for manual work. Without it, a one-shot smoke test would exit and the pod would terminate.

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
