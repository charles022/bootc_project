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

Crucially, there is a strict **no in-container systemd** rule. The container command should run the workload, wait, or exit, but it must never run a service manager. The dev container is also reached via `podman exec` from the host rather than its own `sshd` — see `concepts/access_model.md`.

#### Exceptions

In-container systemd may be acceptable for tightly coupled legacy stacks that genuinely supervise multiple long-lived processes designed around init semantics. Treat it as a special case, not the default.

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

### When to split a process out of the dev container

Move a behavior into its own container when one or more of these are true:

1. **Lifecycle independence** — it must start, stop, or restart on a schedule different from the dev shell (e.g., a one-shot smoke test vs. a long-lived shell).
2. **Image dependency stack** — it needs a different base image or a much smaller dependency set (a serving runtime, a single exporter binary).
3. **Restart policy** — it should auto-restart, fail loudly, or stay idle on terms different from the dev shell.
4. **Security boundary** — it has different privileges or data access (an auth helper, a backup uploader, a metrics agent).
5. **Testability** — a dedicated image is easier to promote and reason about than a multi-purpose one.

Examples of services that would be split out (planned): inference APIs, metrics exporters, reverse proxies.

Periodic *workload* jobs (e.g., scheduled model evaluation, data refresh) belong in their own containerized job — a oneshot pod or a host systemd timer plus a dedicated Quadlet — not crammed into the dev container. Periodic *machine* jobs (snapshot, host health check) belong in host systemd directly.

### Long-lived dev container vs. per-job pods

The dev pod is deliberately long-lived (`restartPolicy: Always`, container kept alive with `sleep infinity` / `tail -f /dev/null`) and driven interactively from inside via `podman exec`. The alternative — spinning up a fresh pod per job — is rejected for the day-to-day workflow because it adds startup latency and obscures the interactive debugging loop.

When automated runs are added later, the CDI path does not change. There are two options (planned):

- replace the dev container's startup script with the workload, or
- add a parallel oneshot pod alongside the dev pod via a second Quadlet.

### Service patterns
When orchestrating workloads, there is a three-pattern taxonomy: single-app containers, multi-container pods, or user-pods. This project uses a **multi-container pod via Quadlet** to group the dev container and the backup sidecar into a single dev pod. This pattern provides a shared lifecycle and network namespace for tightly coupled services while keeping distinct operational roles in independently updatable containers distributed via Quay.

## See also
- `concepts/bootc_and_ostree.md`
- `concepts/gpu_stack.md`
- `concepts/update_pipeline.md`
- `reference/quadlets.md`
- `reference/systemd_units.md`
- `how-to/write_a_systemd_unit_for_the_host.md`
