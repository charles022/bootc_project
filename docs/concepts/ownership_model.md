# Ownership model

## What
This project splits responsibility across three distinct layers: the host image owns hardware and boot orchestration, container images own specific workload runtimes, and Podman Quadlets act as the bridge to manage container lifecycles via host systemd. 

## Why
A unified mental model prevents architectural drift. The alternative is either running everything in a monolithic bare-metal host with locally-installed services, or stuffing a full init system inside a giant dev container. Separating the host from the workload allows the host to act as an immutable, easily updated appliance while keeping the development environment focused solely on application dependencies.

## Implications

### Host image ownership
The host image owns anything tied to the machine, hardware, boot order, or platform access. It handles:
- SSH access (`sshd`) and console autologin recovery.
- Boot orchestration and timers (`bootc-update.timer`, `bootc-update.service`, `bootc-firstboot-push.service`, `bootc-host-test.service`).
- GPU driver installation (`nvidia-open`, `nvidia-container-toolkit`) and dynamic CDI generation (`nvidia-cdi-refresh.service`, `nvidia-cdi-refresh.path`).
- Quadlet definitions baked into `/usr/share/containers/systemd/devpod.kube`.

### Container ownership
Containers own their internal workload environments and execution logic. They handle:
- Workload runtimes, such as the PyTorch/CUDA stack in the dev container.
- Application code and development tools.
- The startup behavior defined by their `CMD` or `ENTRYPOINT`. 

Crucially, there is a strict **no in-container systemd** rule. The container command should run the workload, wait, or exit, but it must never run a service manager.

### Quadlet ownership
Podman Quadlet owns the handoff between host and container. As the bridge, it dictates:
- When containers start and stop relative to host boot.
- Restart policies and failure handling.
- Pod composition. 

Host systemd manages *when* something runs; the container `CMD` decides *what* runs.

### The decision rule
When adding new behavior, do not ask if it should be a systemd service or a container process. Instead, ask:
> "Who owns this behavior: the machine, the container, or a separate cooperating service?"

- If the machine owns it, implement it via host systemd.
- If the container owns it, implement it via the container command.
- If a separate cooperating service owns it, place it in a separate container.

### Service patterns
When orchestrating workloads, there is a three-pattern taxonomy: single-app containers, multi-container pods, or user-pods. This project uses a **multi-container pod via Quadlet** to group the dev container and the backup sidecar into a single dev pod. This pattern provides a shared lifecycle and network namespace for tightly coupled services while keeping distinct operational roles in independently updatable containers distributed via Quay.

## See also
- `concepts/bootc_and_ostree.md`
- `concepts/gpu_stack.md`
- `concepts/update_pipeline.md`
- `reference/quadlets.md`
- `reference/systemd_units.md`
- `how-to/write_a_systemd_unit_for_the_host.md`
