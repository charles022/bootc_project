Absolutely. Here is the **rewritten minimal project layout and file contents** with these updates applied:

* **host SSH only**
* **no SSH inside the dev container**
* **enter the dev container via `podman exec` from the host**
* **keep SSH configuration centralized on the bootc host**
* **keep the overall file count and configuration surface small**
* **keep NVIDIA CDI on the NVIDIA-provided runtime-refresh model**
* **keep the pod with both the dev container and backup sidecar**

This is much closer to your original “less is more” shape while still preserving the right ownership boundaries.

---

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
# Use Fedora bootc as the host operating system image. # host image base
FROM quay.io/fedora/fedora-bootc:42 # bootc base image

# Install only the host packages we actually need. # host package install
RUN dnf -y install \ # begin package install
    openssh-server \ # provide host sshd
    podman \ # provide podman and quadlet support
    nvidia-container-toolkit-base \ # provide NVIDIA CDI refresh support
    bash \ # provide shell for host scripts
    coreutils \ # provide standard utilities
    && dnf clean all # clean package metadata

# Create only the directories we need in the host image. # host directory setup
RUN mkdir -p /usr/share/containers/systemd \ # Quadlet system path
    && mkdir -p /usr/lib/systemd/system \ # systemd unit path
    && mkdir -p /opt/project # host project path

# Copy the host startup test and its systemd unit into the image. # host test install
COPY bootc_host_test.sh /opt/project/bootc_host_test.sh # host test script
COPY bootc-host-test.service /usr/lib/systemd/system/bootc-host-test.service # host test systemd unit

# Make the host startup test executable. # host script permissions
RUN chmod 0755 /opt/project/bootc_host_test.sh # executable host test

# Copy the Quadlet files that define the pod-managed containers. # Quadlet install
COPY devpod.kube /usr/share/containers/systemd/devpod.kube # Quadlet kube file
COPY devpod.yaml /usr/share/containers/systemd/devpod.yaml # pod manifest

# Enable the host-native services that should start on boot. # host boot services
RUN systemctl enable sshd \ # enable host sshd
    && systemctl enable bootc-host-test.service \ # enable host startup test
    && systemctl enable nvidia-cdi-refresh.path \ # enable NVIDIA CDI refresh path unit
    && systemctl enable nvidia-cdi-refresh.service # enable NVIDIA CDI refresh service
```

---

## `bootc-host-test.service`

```ini
# Run the host startup test automatically at boot. # host test unit
[Unit] # begin unit section
Description=Run bootc host startup test # host test description
After=network-online.target sshd.service nvidia-cdi-refresh.service # wait for network, sshd, and CDI refresh
Wants=network-online.target # prefer network online first

# Define how the host test runs. # service execution
[Service] # begin service section
Type=oneshot # run once and exit
ExecStart=/opt/project/bootc_host_test.sh # host test script path
RemainAfterExit=yes # keep successful state visible
StandardOutput=journal # log stdout to journal
StandardError=journal # log stderr to journal

# Start this service during normal boot. # boot activation
[Install] # begin install section
WantedBy=multi-user.target # standard boot target
```

---

## `bootc_host_test.sh`

```bash
#!/usr/bin/env bash # run with bash

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
# Define the Quadlet-managed pod that contains the dev and backup containers. # Quadlet kube file
[Unit] # begin unit section
Description=Dev pod with dev container and backup sidecar # pod description
After=network-online.target sshd.service nvidia-cdi-refresh.service # wait for host sshd and CDI refresh
Wants=network-online.target # prefer network online
Requires=nvidia-cdi-refresh.service # require CDI refresh before GPU pod start

# Point Quadlet at the pod manifest. # kube manifest reference
[Kube] # begin kube section
Yaml=/usr/share/containers/systemd/devpod.yaml # pod manifest path

# Make the generated pod service part of normal boot. # auto-start pod at boot
[Install] # begin install section
WantedBy=multi-user.target # standard boot target
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
# Use NVIDIA's PyTorch image as the dev container base. # dev container base
FROM nvcr.io/nvidia/pytorch:26.03-py3 # GPU-capable PyTorch base image

# Install only the minimum extra packages we need. # dev package install
RUN apt-get update \ # refresh apt metadata
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \ # install packages without prompts
       bash \ # provide shell for interactive use
       procps \ # provide ps and related tools
    && rm -rf /var/lib/apt/lists/* # clean apt metadata

# Create the working directory used by the dev container. # dev filesystem setup
RUN mkdir -p /workspace # workspace directory

# Copy the dev startup wrapper and startup test into the image. # dev runtime files
COPY dev_container_start.sh /usr/local/bin/dev_container_start.sh # startup wrapper
COPY dev_container_test.py /workspace/dev_container_test.py # startup test script

# Make the startup wrapper executable. # dev script permissions
RUN chmod 0755 /usr/local/bin/dev_container_start.sh # executable startup wrapper

# Start the wrapper when the container starts. # dev startup command
CMD ["/usr/local/bin/dev_container_start.sh"] # container runtime command
```

---

## `dev_container_start.sh`

```bash
#!/usr/bin/env bash # run with bash

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
#!/usr/bin/env python3 # run with python3

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
# Use a small Fedora base for the backup sidecar. # backup sidecar base
FROM registry.fedoraproject.org/fedora:42 # Fedora userspace base image

# Install only the minimal tools needed for the placeholder sidecar. # backup package install
RUN dnf -y install \ # begin package install
    bash \ # provide shell
    coreutils \ # provide standard tools
    && dnf clean all # clean package metadata

# Create a workspace directory for future backup logic. # backup filesystem setup
RUN mkdir -p /workspace # workspace directory

# Copy the placeholder backup script into the image. # backup runtime file
COPY backup_stub.sh /usr/local/bin/backup_stub.sh # backup stub path

# Make the backup script executable. # backup script permissions
RUN chmod 0755 /usr/local/bin/backup_stub.sh # executable backup stub

# Start the placeholder backup script when the container starts. # backup startup command
CMD ["/usr/local/bin/backup_stub.sh"] # backup container runtime command
```

---

## `backup_stub.sh`

```bash
#!/usr/bin/env bash # run with bash

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

# What changed from the previous version

## Removed

* all **dev container SSH**
* all **dev container SSH config**
* all **authorized_keys files**
* extra SSH layering and per-container SSH management
* extra NVIDIA config override file that was not necessary yet

## Kept

* **host SSH only**
* **host startup test via systemd**
* **NVIDIA built-in CDI refresh model**
* **Quadlet-managed pod**
* **dev container startup test**
* **backup sidecar in the same pod**

## Simplified access model

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

# Why this is the better fit

This version keeps the ownership model clean:

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

And it avoids rewriting SSH setup for every future container you build.

If you want, the next step should be to simplify this one more notch by deciding whether `bootc_host_test.sh` should also verify that the dev container test completed successfully through `podman logs`, so the host test becomes a single top-level validation point.

