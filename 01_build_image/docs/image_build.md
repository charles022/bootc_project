
# Project layout

```text
gpu-bootc/                              # top-level project directory
├── Containerfile                       # bootc host image definition
├── bootc-host-test.service             # host systemd unit for boot-time host test
├── bootc_host_test.sh                  # host startup test script
├── devpod.kube                         # Quadlet that starts the pod automatically
├── devpod.yaml                         # pod manifest containing dev + backup containers
├── dev-container.Containerfile         # dev container image definition
├── dev_container_start.sh              # dev container startup wrapper
├── dev_container_test.py               # dev container startup test
├── backup-container.Containerfile      # backup sidecar image definition
└── backup_stub.sh                      # placeholder backup sidecar startup script
```

---

# File contents

## `Containerfile`

```dockerfile
# Use Fedora bootc as the host operating system image.
FROM quay.io/fedora/fedora-bootc:42

# Install only the host packages we actually need.
RUN dnf -y install \
    openssh-server \
    podman \
    nvidia-container-toolkit-base \
    bash \
    coreutils \
    && dnf clean all

# Create only the directories we need in the host image.
RUN mkdir -p /usr/share/containers/systemd \
    && mkdir -p /usr/lib/systemd/system \
    && mkdir -p /opt/project

# Copy the host startup test and its systemd unit into the image.
COPY bootc_host_test.sh /opt/project/bootc_host_test.sh
COPY bootc-host-test.service /usr/lib/systemd/system/bootc-host-test.service

# Make the host startup test executable.
RUN chmod 0755 /opt/project/bootc_host_test.sh

# Copy the Quadlet files that define the pod-managed containers.
COPY devpod.kube /usr/share/containers/systemd/devpod.kube
COPY devpod.yaml /usr/share/containers/systemd/devpod.yaml

# Enable the host-native services that should start on boot.
RUN systemctl enable sshd \
    && systemctl enable bootc-host-test.service \
    && systemctl enable nvidia-cdi-refresh.path \
    && systemctl enable nvidia-cdi-refresh.service
```

---

## `bootc-host-test.service`

```ini
# Run the host startup test automatically at boot.
[Unit]
Description=Run bootc host startup test
After=network-online.target sshd.service nvidia-cdi-refresh.service
Wants=network-online.target

# Define how the host test runs.
[Service]
Type=oneshot
ExecStart=/opt/project/bootc_host_test.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

# Start this service during normal boot.
[Install]
WantedBy=multi-user.target
```

---

## `bootc_host_test.sh`

```bash
#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines. # strict bash mode
set -euo pipefail # strict execution

# Emit a clear start marker in the journal. # host test banner
echo "=== bootc_host_test.sh starting ===" # start marker

# Print a timestamp for visibility. # timestamp output
date --iso-8601=seconds # current time

# Confirm host SSH service state. # sshd state check
systemctl is-enabled sshd || true # print enabled state
systemctl is-active sshd || true # print active state

# Confirm NVIDIA CDI refresh unit state. # cdi service state check
systemctl is-enabled nvidia-cdi-refresh.path || true # print path unit enabled state
systemctl is-enabled nvidia-cdi-refresh.service || true # print service unit enabled state

# Confirm whether the runtime CDI file exists. # cdi file presence check
if [[ -f /var/run/cdi/nvidia.yaml ]]; then echo "CDI spec present: /var/run/cdi/nvidia.yaml"; else echo "CDI spec not present yet"; fi # presence message

# Run a host GPU smoke check if nvidia-smi exists. # host gpu smoke test
if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi || true; else echo "nvidia-smi not installed on host"; fi # optional gpu check

# Confirm that the pod service is known to systemd. # pod service visibility check
systemctl status devpod.service --no-pager || true # generated Quadlet service status

# Emit a clear completion marker. # host test footer
echo "=== bootc_host_test.sh completed ===" # completion marker
```

---

## `devpod.kube`

```ini
# Define the Quadlet-managed pod that contains the dev and backup containers.
[Unit]
Description=Dev pod with dev container and backup sidecar
After=network-online.target sshd.service nvidia-cdi-refresh.service
Wants=network-online.target
Requires=nvidia-cdi-refresh.service

# Point Quadlet at the pod manifest.
[Kube]
Yaml=/usr/share/containers/systemd/devpod.yaml

# Make the generated pod service part of normal boot.
[Install]
WantedBy=multi-user.target
```

---

## `devpod.yaml`

```yaml
# Define a pod containing the dev container and backup sidecar. # pod manifest header
apiVersion: v1 # Kubernetes API version
kind: Pod # define a pod
metadata: # begin metadata block
  name: devpod # pod name

# Define pod behavior and its child containers. # pod spec block
spec: # begin spec
  restartPolicy: Always # keep pod containers running

  containers: # begin container list
    # Main dev container that owns the development environment and startup test. # dev container entry
    - name: dev-container # dev container name
      image: ghcr.io/YOURORG/dev-container:latest # dev container image reference
      stdin: true # allow interactive stdin
      tty: true # allocate tty for podman exec sessions
      workingDir: /workspace # default working directory
      resources: # begin resource limits
        limits: # resource limit block
          nvidia.com/gpu=all: 1 # request GPU access through CDI

    # Placeholder backup sidecar used only to validate pod wiring. # backup sidecar entry
    - name: backup-container # backup container name
      image: ghcr.io/YOURORG/backup-container:latest # backup sidecar image reference
      stdin: true # allow interactive stdin if needed
      tty: true # allocate tty for inspection
      workingDir: /workspace # default working directory
```

---

## `dev-container.Containerfile`

```dockerfile
# Use NVIDIA's PyTorch image as the dev container base.
FROM nvcr.io/nvidia/pytorch:26.03-py3

# Install only the minimum extra packages we need.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
       bash \
       procps \
    && rm -rf /var/lib/apt/lists/*

# Create the working directory used by the dev container.
RUN mkdir -p /workspace

# Copy the dev startup wrapper and startup test into the image.
COPY dev_container_start.sh /usr/local/bin/dev_container_start.sh
COPY dev_container_test.py /workspace/dev_container_test.py

# Make the startup wrapper executable.
RUN chmod 0755 /usr/local/bin/dev_container_start.sh

# Start the wrapper when the container starts.
CMD ["/usr/local/bin/dev_container_start.sh"]
```

---

## `dev_container_start.sh`

```bash
#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines. # strict bash mode
set -euo pipefail # strict execution

# Emit a clear start marker for container logs. # dev startup banner
echo "=== dev_container_start.sh starting ===" # start marker

# Run the dev container startup test. # execute startup test
python3 /workspace/dev_container_test.py # run dev startup test

# Emit a message indicating the container will remain alive. # keepalive message
echo "=== dev container startup complete; staying alive ===" # keepalive marker

# Keep the container alive so we can enter it later with podman exec. # persistent foreground loop
tail -f /dev/null # keep container running
```

---

## `dev_container_test.py`

```python
#!/usr/bin/env python3

# Import required modules for the startup smoke test. # import modules
import sys # provide stderr and exits
import time # provide timing visibility

# Try importing torch so the container validates its Python stack. # torch import block
try: # begin guarded import
    import torch # import pytorch
except Exception as exc: # catch import failure
    print(f"ERROR: failed to import torch: {exc}", file=sys.stderr, flush=True) # report import error
    raise SystemExit(1) # exit nonzero on failure

# Emit a clear startup marker. # test banner
print("=== dev_container_test.py starting ===", flush=True) # start marker

# Report the installed torch version. # torch version output
print(f"torch_version={torch.__version__}", flush=True) # print torch version

# Report CUDA visibility. # cuda status output
print(f"cuda_available={torch.cuda.is_available()}", flush=True) # print CUDA availability

# Print the first GPU name if CUDA is visible. # gpu info output
if torch.cuda.is_available(): # only run when CUDA is available
    print(f"gpu_name={torch.cuda.get_device_name(0)}", flush=True) # print GPU name

# Sleep briefly so logs are easy to read in order. # readability pause
time.sleep(1) # short delay

# Emit a clear completion marker. # test footer
print("=== dev_container_test.py completed ===", flush=True) # completion marker
```

---

## `backup-container.Containerfile`

```dockerfile
# Use a small Fedora base for the backup sidecar.
FROM registry.fedoraproject.org/fedora:42

# Install only the minimal tools needed for the placeholder sidecar.
RUN dnf -y install \
    bash \
    coreutils \
    && dnf clean all

# Create a workspace directory for future backup logic.
RUN mkdir -p /workspace

# Copy the placeholder backup script into the image.
COPY backup_stub.sh /usr/local/bin/backup_stub.sh

# Make the backup script executable.
RUN chmod 0755 /usr/local/bin/backup_stub.sh

# Start the placeholder backup script when the container starts.
CMD ["/usr/local/bin/backup_stub.sh"]
```

---

## `backup_stub.sh`

```bash
#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines. # strict bash mode
set -euo pipefail # strict execution

# Emit a clear start marker for the backup sidecar logs. # backup banner
echo "=== backup_stub.sh starting ===" # start marker

# Explain that this sidecar is only a placeholder for pod validation. # placeholder note
echo "backup sidecar placeholder: no real backup logic implemented yet" # placeholder message

# Keep the sidecar alive so the pod can be inspected. # persistent foreground loop
tail -f /dev/null # keep sidecar running
```

---

## `build_images.sh`

```bash
#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

# Navigate to the script directory to ensure relative paths work.
cd "$(dirname "$0")"

echo "=== Starting Build Process ==="

# 1. Build the dev container image
echo "Building dev-container..."
podman build -t ghcr.io/YOURORG/dev-container:latest -f dev-container.Containerfile .

# 2. Build the backup sidecar image
echo "Building backup-container..."
podman build -t ghcr.io/YOURORG/backup-container:latest -f backup-container.Containerfile .

# 3. Build the bootc host image
echo "Building bootc host image..."
# Note: The host image tag is local as it is the final bootable output.
podman build -t gpu-bootc-host:latest -f Containerfile .

echo "=== Build Complete ==="
echo "Images created:"
echo "  - ghcr.io/YOURORG/dev-container:latest"
echo "  - ghcr.io/YOURORG/backup-container:latest"
echo "  - gpu-bootc-host:latest"
```

---

## `run_bootc_vm.sh`

```bash
#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

# The container image to convert and run (e.g., gpu-bootc-host:latest)
IMAGE_NAME="${1:-gpu-bootc-host:latest}"

echo "=== Converting $IMAGE_NAME to qcow2 ==="

# Ensure a fresh output directory
mkdir -p ./output
sudo rm -rf ./output/*

# 1. Convert the Bootable Container to a Disk Image
sudo podman run \
  --rm \
  --privileged \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --local "localhost/$IMAGE_NAME"

echo "=== Starting VM with virt-install ==="

# 2. Boot the VM with virt-install
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

---

# version

## Access model

The intended operator flow is now:

```bash
# SSH to the host from your workstation. # operator access step
ssh user@bootc-host # enter bootc host

# Inspect the running pod and containers on the host. # check pod state
sudo podman ps # list running containers

# Enter the dev container from the host. # enter dev container
sudo podman exec -it <dev-container-name> /bin/bash # open shell in dev container
```

That keeps all SSH configuration and SSH exposure on the **host**, which is exactly the simplification you wanted.

# Ownership model

* **host** owns:

  * SSH
  * boot-time services
  * pod/container orchestration
  * NVIDIA CDI refresh availability

* **dev container** owns:

  * the dev environment
  * the startup test
  * staying alive for interactive `podman exec`

* **backup sidecar** owns:

  * nothing yet beyond validating the pod pattern

Avoids rewriting SSH setup for every future container you build.
