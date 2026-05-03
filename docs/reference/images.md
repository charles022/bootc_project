# Images

This document is a factual catalog of the container images built and used by this project. All images are built from definitions in `01_build_image/build_assets/`.

## Host image

The primary bootable container image containing the kernel, drivers, and system services.

- **Path**: `01_build_image/build_assets/Containerfile`
- **Purpose**: Provides the immutable host operating system for bare metal or virtual machines.
- **Base image**: `quay.io/fedora/fedora-bootc:42`
- **Key adds**:
    - **NVIDIA Stack**: `nvidia-open` (open kernel modules), `nvidia-container-toolkit`.
    - **Container Tools**: `podman`, `skopeo`.
    - **Management**: `cloud-init` (first-boot configuration), `openssh-server`.
    - **Update Pipeline**: `bootc-update.*` (systemd units and scripts for weekly rebuilds).
    - **Orchestration**: Legacy system Quadlet definitions (`devpod.kube`, `devpod.yaml`) at `/usr/share/containers/systemd/` plus tenant and agent Quadlet templates under `/var/lib/openclaw-platform/templates/`.
- **Tags**:
    - Local: `gpu-bootc-host:latest`
    - Quay: `quay.io/m0ranmcharles/fedora_init:latest`
- **Baked-in vs. pulled at runtime**: Baked-in as the system image.
- **Notes**: The host image is keyless; SSH keys and user credentials must be injected at deployment time (e.g., via `cloud-init`).

## Dev container

The legacy system-wide GPU development environment.

- **Path**: `01_build_image/build_assets/dev-container.Containerfile`
- **Purpose**: Provides a decoupled workstation environment with a full PyTorch and CUDA stack.
- **Base image**: `nvcr.io/nvidia/pytorch:26.03-py3`
- **Key adds**: `bash`, `procps`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:dev-container`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman on the host.
- **Notes**: Orchestrated by the host's Quadlet as part of the `devpod` pod.

## Dev environment

The tenant-scoped GPU development environment for agent pods.

- **Path**: `01_build_image/build_assets/multi_tenant/dev-env.Containerfile`
- **Purpose**: Provides a per-agent dev environment with the same PyTorch and CUDA base as the legacy dev container, but rendered through the tenant/agent Quadlet path.
- **Base image**: `nvcr.io/nvidia/pytorch:26.03-py3`
- **Key adds**: `bash`, `procps`, `dev_container_start.sh`, and `dev_container_test.py`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:dev-env`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by rootless Podman as part of a tenant agent pod.
- **Notes**: The default tenant policy allowlists this image for `allowed_images.environments`. The agent dev-env Quadlet passes `--device=nvidia.com/gpu=all` and `--security-opt=label=disable` through `PodmanArgs=`; validate this rootless CDI path on NVIDIA hardware before removing the system-wide `devpod`.

## Backup service (host)

A placeholder container for host-managed data backups.

- **Path**: `01_build_image/build_assets/backup-container.Containerfile`
- **Purpose**: Runs as a standalone host Quadlet (`backup.container`) activated by `backup.timer` to handle state persistence and cloud sync (planned). Isolated from the dev pod.
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `bash`, `coreutils`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:backup-container`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman on the host when `backup.timer` fires.

## OS builder

An ephemeral environment used for automated host image rebuilds.

- **Path**: `01_build_image/build_assets/os-builder.Containerfile`
- **Purpose**: Clones the project repository and builds fresh versions of all images during the scheduled update cycle.
- **Base image**: `quay.io/fedora/fedora:42`
- **Key adds**: `podman`, `buildah`, `skopeo`, `git`, `ca-certificates`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:os-builder`
- **Baked-in vs. pulled at runtime**: Pulled and run as an ephemeral container by the host's `bootc-update.service`.

## OpenClaw runtime

The agent control-loop container in a tenant pod. Ships `agentctl` plus the Phase-4 verb-table message router (`openclaw-runtime-router`). The router reads inbound message envelopes posted by the messaging-bridge sidecars, dispatches a small set of verbs to `agentctl`, and replies. A real LLM-driven loop drops in later without changing the host contract.

- **Path**: `01_build_image/build_assets/multi_tenant/openclaw-runtime.Containerfile`
- **Purpose**: Host an agent inside a tenant pod, locked down (no sudo, read-only filesystem) but with `agentctl` on `PATH` and the message-router as the default `CMD` so the agent can dispatch user messages through the per-tenant provisioner socket bind-mounted from the host.
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `bash`, `coreutils`, `python3`, `agentctl` at `/usr/local/bin/agentctl`, `openclaw-runtime-router` at `/usr/local/bin/openclaw-runtime-router`, plus the legacy `openclaw-runtime-stub.sh` (used by the onboarding pod which is SSH-driven, not message-driven).
- **Tags**: `quay.io/m0ranmcharles/fedora_init:openclaw-runtime`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman as part of a tenant pod. The agent Quadlet template mounts `/run/openclaw-provisioner/tenants/<tenant>.sock` into `/run/agentctl/agentctl.sock` read-only and the per-agent host directory `${PLATFORM_ROOT}/tenants/<tenant>/runtime/agents/<agent>/msgbus/` into `/run/messaging-bridge` for the pod-local message bus.

## Credential proxy

The pod-local credential proxy sidecar. Forwards in-pod agent requests to the host `openclaw-broker` via a tenant-specific socket bind-mounted from the host. Holds no master credentials.

- **Path**: `01_build_image/build_assets/multi_tenant/credential-proxy.Containerfile`
- **Purpose**: Re-expose `credential_request` / `agent_grants` / `ping` on a pod-local UNIX socket at `/run/credential-proxy/agent.sock`. Refuses every admin verb at the proxy boundary. See `concepts/credential_broker.md`.
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `python3`, the `credential-proxy.py` daemon at `/usr/local/bin/credential-proxy`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:credential-proxy`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman as part of a tenant pod. The Quadlet template mounts the host's `/run/openclaw-broker/tenants/<tenant>.sock` into `/run/credential-proxy/broker.sock` read-only.

## Onboarding env (Phase-0 stub)

The shell container the tenant SSHes into during initial enrollment. Phase-0 stub: idle, sshd installed but not started.

- **Path**: `01_build_image/build_assets/multi_tenant/onboarding-env.Containerfile`
- **Purpose**: Host the credential-enrollment flow that runs on first contact with a new tenant. Phase-0 ships a stub.
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `bash`, `coreutils`, `openssh-server`, `sudo`, the `onboarding-env-stub.sh` startup script.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:onboarding-env`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman as part of a tenant pod.

## Messaging-bridge sidecars (Phase 4)

Per-pod sidecars that convert external messaging traffic (email, Signal, WhatsApp) to and from the JSONL message-bus socket the `openclaw-runtime` router consumes. One image per transport. The provisioner only renders the matching `agent_quadlet/agent-messaging-bridge-<transport>.container.tmpl` when the agent's `messaging` list includes that transport. See `concepts/messaging_interface.md`.

### Email

- **Path**: `01_build_image/build_assets/multi_tenant/messaging-bridge-email.Containerfile`
- **Purpose**: IMAP poll for inbound messages from allow-listed senders; SMTP send for `{"op":"reply",...}` envelopes posted by the runtime.
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `python3`, `ca-certificates`, the `messaging-bridge-email.py` daemon at `/usr/local/bin/messaging-bridge-email`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:messaging-bridge-email`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman as a tenant-pod sidecar.

### Signal

- **Path**: `01_build_image/build_assets/multi_tenant/messaging-bridge-signal.Containerfile`
- **Purpose**: Wraps `signal-cli` in daemon mode. Receives messages from a linked Signal device and emits envelopes to the message bus; sends replies via `signal-cli send`.
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `python3`, `java-21-openjdk-headless`, `signal-cli` (downloaded at build time), the `messaging-bridge-signal.py` daemon at `/usr/local/bin/messaging-bridge-signal`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:messaging-bridge-signal`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman as a tenant-pod sidecar.

### WhatsApp (planned)

- **Path**: `01_build_image/build_assets/multi_tenant/messaging-bridge-whatsapp.Containerfile`
- **Purpose**: Stub. Emits `(planned)` log lines and idles. Real implementation needs a Meta Business webhook receiver behind a cloudflared `messaging-webhook` ingress route — Phase 5.
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `python3`, the placeholder `messaging-bridge-whatsapp.py` script.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:messaging-bridge-whatsapp`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman as a tenant-pod sidecar.

## Cloudflared sidecar (upstream image)

The Cloudflare Tunnel daemon that publishes tenant ingress routes.

- **Path**: not built locally; referenced by tenant Quadlet templates.
- **Image**: `docker.io/cloudflare/cloudflared:latest`
- **Notes**: Configuration / tunnel token is mounted read-only from `/var/lib/openclaw-platform/tenants/<tenant>/cloudflared/`. The container runs only as a tenant-pod sidecar; tunnel automation is planned (`concepts/multi_tenant_architecture.md`).

## Common properties

### Build context
The build context for all images is the `01_build_image/build_assets/` directory. Any files copied via `COPY` instructions must reside within this folder.

### Registry
All images are published to the `quay.io/m0ranmcharles/fedora_init` namespace. See `reference/registry.md` for details on tagging and push procedures.

### Security
All images are "keyless" by design. They do not contain embedded SSH keys, API credentials, or private configuration. This allows the images to be shared publicly on Quay while maintaining security through deployment-time identity injection.

### Source of truth
The Containerfiles in the repository are the authoritative definitions for these images. Code excerpts in this documentation are for illustrative purposes only.

## Appendix: NVIDIA NGC catalog

Reference summary of the relevant tag families on `nvcr.io/nvidia/`. Use this when picking a base image for a new container.

### CUDA base images — `nvcr.io/nvidia/cuda:<version>-<variant>-<distro>`
| Variant | When to use |
|---|---|
| `base` | Minimal CUDA runtime; smallest footprint, no math libs. |
| `runtime` | Adds cuBLAS, cuFFT, NCCL — for running pre-built CUDA binaries. |
| `runtime-cudnn` | Adds cuDNN for inference workloads that need it. |
| `devel` | Adds compiler and headers — for building CUDA code. Common in multi-stage builds. |
| `devel-cudnn` | Full development stack with cuDNN. |

### Framework images
| Image | When to use |
|---|---|
| `nvcr.io/nvidia/pytorch:<tag>` | Pre-tuned PyTorch + CUDA + cuDNN + NCCL for training. The dev container's base. |
| `nvcr.io/nvidia/tensorflow:<tag>` | TensorFlow equivalent. |
| `nvcr.io/nvidia/cuda-dl-base:<tag>` | Foundation layer with cuDNN, cuTensor, NCCL, and the CUDA Toolkit — for custom DL stacks. |

### Inference / serving images
| Image | When to use |
|---|---|
| `nvcr.io/nvidia/tritonserver:<tag>` | Triton Inference Server for multi-framework model serving. |
| `nvcr.io/nvidia/tensorrt:<tag>` | TensorRT-optimized inference runtime. |
| `nvcr.io/nvidia/vllm:<tag>` | vLLM, optimized for GPU-accelerated LLM inference. |
