# Overview

## What this is

This project provides a bootc-based GPU workstation architecture that pairs an immutable host system with containerized workload environments and a scheduled rebuild pipeline. By decoupling the machine layer from the application stack, it yields a highly reproducible, easily cleanable workspace. The host OS handles hardware orchestration and updates safely, while development environments remain focused, isolated, and rapidly iterable.

## The 3-layer model

```text
Host Image (Hardware & Boot)
  │
  ├─ Quadlet (Lifecycle Bridge)
  │    │
  │    └─ devpod.kube / devpod.yaml
  │
  └─ Workload Container (Application)
       ├─ dev container
       └─ backup sidecar
```

The system splits responsibility across three distinct layers:

**Host image ownership:** The host image owns anything tied to the machine, hardware, boot order, or platform access. It acts as an immutable appliance handling SSH access, OS-level updates, GPU driver installation (`nvidia-open`), and boot orchestration. 

**Container ownership:** Containers own their internal workload environments and execution logic. They handle the PyTorch/CUDA runtime, application code, and development tools. Containers strictly execute workloads and do not run service managers.

**Quadlet ownership:** Podman Quadlet acts as the bridge between the host and containers. It dictates when containers start and stop relative to the host boot, manages restart policies, and handles pod composition. Host systemd manages when something runs; the container command decides what runs.

## What's built today vs. planned

**Today:**
- Host image build pipeline.
- Dev pod and backup sidecar definitions.
- VM build path (qcow2 conversion with SSH key injection).
- Image push to Quay.
- GPU CDI plumbing and dynamic boot-time generation.
- Scheduled local rebuild pipeline (`bootc-update.timer`, `os-builder`, and first-boot push).

**Planned:**
- Remote/CI rebuild orchestration (planned).
- Btrfs-based state persistence (planned).
- Real backup logic (planned).
- System wipe-and-restore pipeline (planned).

See `roadmap.md` for a complete list of upcoming work and open questions.

## Where to go next

If you are thinking "I want to use the published image", refer to `how-to/distribute_image.md` to deploy the image and `concepts/access_model.md` to understand the keyless authentication design.

If you are thinking "I want to build and test locally", begin with `how-to/build_images.md` to compile the artifacts, test them with `how-to/build_and_run_vm.md`, and verify hardware integration through `how-to/validate_gpu.md`.

If you are thinking "I want to understand why it's built this way", explore the `concepts/` directory to read the structural rationale behind these choices.
