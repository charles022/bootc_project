# Validate GPU passthrough

## Goal
Verify the chain: host driver -> CDI spec -> tenant agent dev environment -> CUDA visible inside the container.

## Prerequisites
- The host image is deployed on a machine with an NVIDIA GPU.
- You have shell access (see `concepts/access_model.md`).
- `quay.io/m0ranmcharles/fedora_init:dev-env` has been built and pushed before creating the tenant agent.
- A tenant exists and can create agents (`how-to/create_a_tenant.md`, `how-to/create_an_agent.md`).

## Steps

### 1. Confirm the host driver loaded
Run `nvidia-smi` on the host:
```bash
nvidia-smi
```
On a working host, this lists the GPU devices and the driver version. If nothing is listed or an error occurs, the kernel module is not loaded. See Troubleshooting.

### 2. Confirm the CDI spec was generated
Check for the CDI specification file:
```bash
sudo test -r /etc/cdi/nvidia.yaml
ls -ld /etc/cdi /etc/cdi/nvidia.yaml
grep -n 'nvidia.com/gpu=all' /etc/cdi/nvidia.yaml
```
This file is created at boot by `nvidia-cdi-refresh.service`. It must list the host's GPU devices, libraries, and a top-level `nvidia.com/gpu=all` entry. `/etc/cdi/` should be readable by tenant service accounts and writable only by root.

### 3. Create a tenant agent with the dev environment
Create an agent that uses the GPU-capable tenant dev environment:
```bash
sudo platformctl agent create alice \
    --name gpu-test \
    --runtime quay.io/m0ranmcharles/fedora_init:openclaw-runtime \
    --environment quay.io/m0ranmcharles/fedora_init:dev-env \
    --network restricted-internet
```

Confirm the rendered dev-env Quadlet includes CDI device injection:
```bash
UID_=$(id -u tenant_alice)
sudo grep -n 'PodmanArgs=--device=nvidia.com/gpu=all' \
    /etc/containers/systemd/users/${UID_}/alice-gpu-test-dev-env.container
sudo grep -n 'PodmanArgs=--security-opt=label=disable' \
    /etc/containers/systemd/users/${UID_}/alice-gpu-test-dev-env.container
```

### 4. Confirm the dev environment sees the GPU
Run `nvidia-smi` inside the rootless tenant container:
```bash
sudo machinectl shell tenant_alice@ /usr/bin/podman exec -it alice-gpu-test-dev-env nvidia-smi
```
The output should match the host output from Step 1.

### 5. Confirm CUDA is visible from PyTorch
Run the baked-in smoke test inside the tenant dev environment:
```bash
sudo machinectl shell tenant_alice@ /usr/bin/podman exec -it alice-gpu-test-dev-env \
    python3 /workspace/dev_container_test.py
```
This script (refer to `01_build_image/build_assets/dev_container_test.py` in the repo) validates the Python stack. Expected output:
- `torch_version=...`
- `cuda_available=True`
- `gpu_name=NVIDIA <model>`

### 6. Fallback check while devpod is retained
Until rootless tenant CDI passes on NVIDIA hardware, the legacy system dev pod remains available as a fallback:
```bash
sudo systemctl status devpod.service
sudo podman exec -it devpod-dev-container nvidia-smi
sudo podman exec -it devpod-dev-container python3 /workspace/dev_container_test.py
```

## Verify
The `bootc-host-test.service` runs automatically at boot and provides host-side GPU and CDI state in the system journal:
```bash
sudo journalctl -u bootc-host-test.service --no-pager
```

## Troubleshooting

- **`nvidia-smi` reports "No devices were found"**: The kernel module failed to load. This usually happens if the `nvidia-open` DKMS build at image-build time was pinned against a different kernel version than the one running on the deployed host. See `concepts/gpu_stack.md` for fallback paths using `kernel-devel` matching or `akmod-nvidia-open`.
- **`/etc/cdi/nvidia.yaml` is missing**: The `nvidia-cdi-refresh.service` failed. Check its logs with `sudo journalctl -u nvidia-cdi-refresh.service`. Note that `nvidia-cdi-refresh.path` re-runs the service when `/dev/nvidiactl` appears; if the device node is missing, the spec will not generate.
- **`PodmanArgs=--device=nvidia.com/gpu=all` is missing**: The host image does not contain the updated `agent-dev-env.container.tmpl`, or the agent was created before the template update. Recreate the agent after upgrading the host image. The template should also include `PodmanArgs=--security-opt=label=disable`.
- **Tenant service account cannot read `/etc/cdi/nvidia.yaml`**: Check `nvidia-cdi-refresh.service` logs and file modes. The directory should be `0755` and the spec should be `0644`.
- **Rootless tenant `nvidia-smi` fails but legacy `devpod` works**: Keep `devpod` in place and switch the tenant design to a per-agent `.kube` template or explicit `/dev/nvidia*` mappings after validating NVIDIA library injection.
- **`cuda_available=False` inside the dev environment**: The CDI device was not injected into the container. Confirm the rendered agent dev-env Quadlet includes `PodmanArgs=--device=nvidia.com/gpu=all` and that `/etc/cdi/nvidia.yaml` contains the selector.
