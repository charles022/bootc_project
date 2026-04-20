# Build/Test Reference

Goal: prove the pieces in this order before deploying anything to the machine.

1. Build and test the dev/backup containers locally.
2. Build the bootc host image and boot it as a local VM.
3. Push the same image names to a registry, rebuild the host with those names, and test the VM pull path.

## Image Names

`build_image.sh` is the control point for image names.

Defaults:

```bash
IMAGE_REGISTRY=localhost
IMAGE_NAMESPACE=bootc-dev
IMAGE_TAG=latest
BOOTC_IMAGE=localhost/gpu-bootc-host:$IMAGE_TAG
```

When `IMAGE_REGISTRY` is not `localhost`, the default bootc host image follows the registry namespace too:

```bash
IMAGE_REGISTRY=quay.io
IMAGE_NAMESPACE=<your-namespace>
BOOTC_IMAGE=quay.io/<your-namespace>/gpu-bootc-host:latest
```

The script passes the dev and backup image names into the bootc image build, so the Quadlet pod pulls the same images that were built and pushed.

Host image builds require an SSH key for `devuser`. The script uses `SSH_AUTHORIZED_KEY` first, then `~/.ssh/id_ed25519.pub`, then `~/.ssh/id_rsa.pub`. Set `ALLOW_NO_SSH_KEY=1` only when deliberately building an image with no SSH access.

## Local Container Check

```bash
./build_image.sh containers
./build_image.sh test-containers
```

If the local machine does not have a usable NVIDIA CDI device yet:

```bash
REQUIRE_CUDA=0 ./build_image.sh test-containers
```

That only proves the container starts. The real GPU check is `REQUIRE_CUDA=1`.

## Local VM Check

```bash
./build_image.sh all
./02_build_vm/run_bootc_vm.sh localhost/gpu-bootc-host:latest
```

Expected inside the VM:

```bash
systemctl is-active sshd
systemctl is-active devpod.service
sudo podman pod exists devpod
sudo podman ps
```

The host boot test is intentionally strict. It fails if SSH, NVIDIA CDI, `nvidia-smi`, or `devpod.service` is not healthy.

## Registry Pull Check

```bash
IMAGE_REGISTRY=quay.io \
IMAGE_NAMESPACE=<your-namespace> \
./build_image.sh all

IMAGE_REGISTRY=quay.io \
IMAGE_NAMESPACE=<your-namespace> \
./build_image.sh push

podman pull quay.io/<your-namespace>/gpu-bootc-host:latest
./02_build_vm/run_bootc_vm.sh quay.io/<your-namespace>/gpu-bootc-host:latest
```

Pass `SSH_AUTHORIZED_KEY="$(cat ~/.ssh/id_ed25519.pub)"` if the script cannot find a default public key.
