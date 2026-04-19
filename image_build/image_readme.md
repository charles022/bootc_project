## Build the entire project and launch the VM with these two commands:

   1 cd gpu-bootc/
   2 ./build_images.sh
   3 ./run_bootc_vm.sh


## GPU Bootc Dev Environment — Overview

This project builds a **Fedora bootc host image** that automatically starts a **GPU-capable development pod**. The system is designed to be minimal, deterministic, and easy to reason about.

At boot:

* The **host OS** starts standard services and runs a **host startup test**
* NVIDIA’s toolkit generates the **CDI spec** for GPU access
* A **Quadlet-managed pod** starts automatically
* The **dev container** runs a startup test and remains alive for interactive use
* Access is via **SSH to the host**, then `podman exec` into the container

---

## Key Components

### 1) Bootc Host Image

* Defined by `Containerfile`
* Installs:

  * `openssh-server` (host access)
  * `podman` (container runtime + Quadlet)
  * `nvidia-container-toolkit` (GPU/CDI support)
* Enables:

  * `sshd`
  * `bootc-host-test.service`
  * NVIDIA `nvidia-cdi-refresh` units

### 2) Host Startup Test

* `bootc_host_test.sh`
* Triggered by `bootc-host-test.service`
* Validates:

  * SSH availability
  * CDI presence (`/var/run/cdi/nvidia.yaml`)
  * Optional `nvidia-smi`
  * Pod service visibility

### 3) Quadlet + Pod

* `devpod.kube` → systemd-managed unit
* `devpod.yaml` → pod definition

Pod contains:

* **dev container** (primary workload)
* **backup container** (placeholder sidecar)

### 4) Dev Container

* Built from `dev-container.Containerfile`
* On startup:

  * runs `dev_container_test.py`
  * stays alive (`tail -f /dev/null`)
* Entered via:

  ```bash
  podman exec -it <container> /bin/bash
  ```

### 5) Backup Sidecar

* Minimal container for validating multi-container pod structure
* No real functionality yet

---

## Build and Execution

### 1) Build Images
Use the provided script to build all containers in the correct order:
```bash
./build_images.sh
```

### 2) Run as VM
Convert the bootc host image to a disk image and boot it as a VM:
```bash
./run_bootc_vm.sh gpu-bootc-host:latest
```
This script handles the `bootc-image-builder` conversion to `.qcow2` and invokes `virt-install` with the required UEFI and resource parameters.

---

## Design Principles

### 1) Clear Ownership Boundaries

* **Host (bootc)** owns:

  * system initialization
  * SSH access
  * service orchestration (systemd + Quadlet)
  * GPU enablement (CDI)
* **Containers** own:

  * application/runtime behavior
  * startup logic
  * long-running processes

---

### 2) Use the Native Mechanism for Each Layer

| Layer         | Mechanism              | Purpose                       |
| ------------- | ---------------------- | ----------------------------- |
| Host          | `systemd`              | boot + services               |
| Containers    | `CMD` / startup script | runtime behavior              |
| Orchestration | `Quadlet`              | start containers/pods at boot |

---

### 3) Keep It Minimal

* Only include what is required to meet the current goal
* Avoid premature abstraction (no extra services, configs, or layers)
* Prefer **fewer files and simpler structure**

---

### 4) Single Access Point (SSH)

* SSH is **host-only**
* Containers are accessed via:

  ```bash
  podman exec
  ```
* Avoid duplicating SSH config across containers

---

### 5) One Primary Responsibility per Container

* Dev container → development environment + test
* Backup container → separate concern (future)
* Separation enables:

  * independent lifecycle
  * simpler reasoning
  * cleaner scaling later

---

### 6) Runtime Hardware Binding (CDI)

* Do **not** bake GPU mappings into the image
* Let NVIDIA’s toolkit generate CDI **at runtime**
* Ensures correctness for:

  * actual GPU devices
  * driver state
  * VM passthrough scenarios

---

## Operator Workflow

```bash
# SSH into the host
ssh user@host

# View running containers
sudo podman ps

# Enter dev container
sudo podman exec -it dev-container /bin/bash
```

---

## Summary

This project follows a strict separation:

* **bootc host = system + orchestration**
* **containers = workloads**
* **Quadlet = bridge between them**

The result is:

* minimal
* reproducible
* aligned with Fedora bootc + Podman design
* easy to extend without refactoring core structure

