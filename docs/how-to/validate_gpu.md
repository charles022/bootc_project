# Validate GPU passthrough

## Goal
Verify the chain: host driver → CDI spec → dev pod → CUDA visible inside the dev container.

## Prerequisites
- The host image is deployed on a machine with an NVIDIA GPU.
- You have shell access (see `concepts/access_model.md`).
- The dev pod has had time to start (it is started by a Quadlet at boot).

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
sudo cat /etc/cdi/nvidia.yaml
```
This file is created at boot by `nvidia-cdi-refresh.service`. It must list the host's GPU devices, libraries, and a top-level `nvidia.com/gpu=all` entry.

### 3. Confirm the dev pod is running
Check the status of the pod service and the pod itself:
```bash
sudo systemctl status devpod.service
sudo podman pod ps
```
`devpod.service` should be `active (running)`. The pod should contain both the `dev-container` and the `backup-sidecar`.

### 4. Confirm the dev container sees the GPU
Run `nvidia-smi` inside the running dev container:
```bash
sudo podman exec -it devpod-dev-container nvidia-smi
```
The output should match the host output from Step 1.

### 5. Confirm CUDA is visible from PyTorch
Run the baked-in smoke test inside the dev container:
```bash
sudo podman exec -it devpod-dev-container python3 /workspace/dev_container_test.py
```
This script (refer to `01_build_image/build_assets/dev_container_test.py` in the repo) validates the Python stack. Expected output:
- `torch_version=...`
- `cuda_available=True`
- `gpu_name=NVIDIA <model>`

## Verify
The `bootc-host-test.service` runs automatically at boot and provides a summary of this validation chain in the system journal:
```bash
sudo journalctl -u bootc-host-test.service --no-pager
```

## Troubleshooting

- **`nvidia-smi` reports "No devices were found"**: The kernel module failed to load. This usually happens if the `nvidia-open` DKMS build at image-build time was pinned against a different kernel version than the one running on the deployed host. See `concepts/gpu_stack.md` for fallback paths using `kernel-devel` matching or `akmod-nvidia-open`.
- **`/etc/cdi/nvidia.yaml` is missing**: The `nvidia-cdi-refresh.service` failed. Check its logs with `sudo journalctl -u nvidia-cdi-refresh.service`. Note that `nvidia-cdi-refresh.path` re-runs the service when `/dev/nvidiactl` appears; if the device node is missing, the spec will not generate.
- **`devpod.service` failed to start**: Inspect the service logs with `sudo journalctl -u devpod.service`. Common causes include image pull failures due to networking issues or missing credentials for `quay.io`.
- **`cuda_available=False` inside the dev container**: The CDI device was not injected into the container. Confirm that the pod manifest (`/usr/share/containers/systemd/devpod.yaml`) includes the `resources.limits[nvidia.com/gpu=all]: 1` selector.
