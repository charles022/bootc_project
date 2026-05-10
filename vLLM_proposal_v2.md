## Absolute requirement

We want to add a vLLM container to this project. There will be a single vLLM container, managed by the host, and used by the tenant OpenClaw agents. The following is a proposal for how it should be implemented.

---

## Recommended design

Use **one shared vLLM container as a local OpenAI-compatible HTTP API server**, then point each tenant’s Codex CLI / OpenClaw environment at that API endpoint.

The clean target shape is:

```text
tenant-a rootless container ┐
tenant-b rootless container ├── HTTP(S) / OpenAI-compatible API ──> shared vLLM container ──> GPU
tenant-c rootless container ┘
```

vLLM is explicitly built to expose an OpenAI-compatible server, including `/v1/completions`, `/v1/chat/completions`, and `/v1/responses`; Codex custom providers are configured around a `base_url`, API-key source, and model-provider entry. ([vLLM][1])

---

# The best minimal implementation

## Run vLLM as a **host-managed shared service**

Do **not** run one vLLM instance per tenant. Run **one** vLLM container as a system-level host Quadlet, for example:

```text
host admin user
└── systemd
    └── vllm.service / vllm.container
        └── system-level Podman container
            └── vLLM OpenAI-compatible API
```

Then each tenant container only needs:

```bash
OPENAI_BASE_URL=http://<local-vllm-endpoint>:8000/v1
OPENAI_API_KEY=<local shared or per-tenant token>
OPENAI_MODEL=<served model name>
```

This gives you:

| Goal                | Result                                                         |
| ------------------- | -------------------------------------------------------------- |
| Minimality          | One model server, one endpoint, simple env vars                |
| Efficiency          | Model weights loaded once, GPU shared by vLLM scheduler        |
| Tenant simplicity   | Tenants use the same protocol as remote OpenAI-compatible APIs |
| Isolation           | Tenants do not get GPU device access directly                  |
| Operational clarity | Host starts vLLM; tenants consume it                           |

vLLM’s official container documentation shows the OpenAI-compatible image and Podman GPU example using `--device nvidia.com/gpu=all`, port `8000`, and `--ipc=host` or `--shm-size` for PyTorch shared memory behavior. ([vLLM][2])

---

# Network choice

## Best practical choice: bind vLLM to localhost on the host

Expose the vLLM API only on the host loopback interface:

```bash
-p 127.0.0.1:8000:8000
```

Then configure each tenant container to reach the host’s local endpoint.

The key idea:

```text
vLLM listens on host: 127.0.0.1:8000
tenant containers call: host.containers.internal:8000 or equivalent host-gateway address
```

Inside the tenant container:

```bash
export OPENAI_BASE_URL='http://host.containers.internal:8000/v1'
export OPENAI_API_KEY='tenant-local-token'
export OPENAI_MODEL='Qwen/Qwen3-14B'
```

Then OpenClaw, Codex CLI, or any OpenAI-compatible client uses that base URL.

This is usually simpler than trying to put all tenants and vLLM into the same Podman network, because **rootless Podman networks are per-user**. Since your tenants are intentionally separated by different Linux users / service accounts, a single shared rootless bridge network across users is not the cleanest primitive. A host-local published port is the boring, reliable boundary.

---

# Why not put every tenant on the same Podman network?

Because your tenant isolation model is:

```text
one non-login service account per tenant
one rootless Podman environment per tenant
```

That is good for isolation, but it means each tenant’s rootless Podman runtime is naturally separated. You *can* create user-defined Podman networks, but those are easiest when the containers are managed by the same user/runtime. Podman supports network modes such as user-defined networks, `host`, `private`, `pasta`, `slirp4netns`, and others, but host networking is explicitly considered less secure because it gives the container broad access to local system services. ([Red Hat Documentation][3])

So avoid this:

```bash
--network=host
```

for tenants.

Use this instead:

```bash
vLLM:    published only to 127.0.0.1:8000
tenant:  normal rootless networking
tenant:  calls host-local vLLM endpoint
```

---

# Suggested concrete setup

## 1. vLLM service account and storage

Since the host is an immutable bootc image, the `vllm` service account must be baked into the image during the build process (e.g., via `sysusers.d` or a `RUN useradd` instruction in the `Containerfile`). It should not be created imperatively on the running host.

The vLLM service will use the platform's persistent storage layout:

```text
/var/lib/openclaw-platform/vllm-cache/
├── .cache/huggingface/
└── logs/
```

Tenant users should not own or modify the vLLM container or its cache.

---

## 2. Run vLLM via System Quadlet

Since rootless CDI is not yet validated in this architecture, vLLM should be run as a system-level Quadlet (`/etc/containers/systemd/vllm.container`) to guarantee GPU injection works correctly via the bootc CDI bridge.

```ini
[Unit]
Description=vLLM OpenAI-compatible API Server
After=nvidia-cdi-refresh.service
Requires=nvidia-cdi-refresh.service

[Container]
Image=docker.io/vllm/vllm-openai:latest
ContainerName=vllm-openai
User=vllm
Group=vllm

# Networking
PublishPort=127.0.0.1:8000:8000
PodmanArgs=--ipc=host

# GPU Injection (Relies on CDI)
PodmanArgs=--device=nvidia.com/gpu=all
PodmanArgs=--security-opt=label=disable

# Storage
Volume=/var/lib/openclaw-platform/vllm-cache/.cache/huggingface:/root/.cache/huggingface:Z

# Environment and Execution
Environment=HF_TOKEN=your-token-here
Exec=--model Qwen/Qwen3-14B --host 0.0.0.0 --port 8000 --api-key "${VLLM_API_KEY}" --generation-config vllm

[Install]
WantedBy=multi-user.target
```

Notes:

* `After/Requires=nvidia-cdi-refresh.service` ensures the CDI spec is generated before the container starts.
* `User=vllm` runs the container process under the dedicated `vllm` service account even though the Quadlet is system-managed.
* `--host 0.0.0.0` is inside the container.
* `PublishPort=127.0.0.1:8000:8000` keeps the service bound only to host loopback.
* `--api-key` makes clients send a bearer token.
* `--generation-config vllm` avoids silently inheriting generation defaults from the Hugging Face model repo; vLLM documents that Hugging Face `generation_config.json` can override sampling defaults unless disabled. ([vLLM][1])
* `--ipc=host` is recommended by vLLM docs as one option because PyTorch uses shared memory between processes; alternatively use `--shm-size`. ([vLLM][2])

---

# Tenant-side configuration

## Codex CLI

Codex supports custom model providers in `~/.codex/config.toml`. The relevant keys are `model_provider`, `model_providers.<id>.base_url`, and `model_providers.<id>.env_key`; current Codex docs also say the custom provider `wire_api` is `responses`. ([OpenAI Developers][4])

A tenant config would look like:

```toml
model = "Qwen/Qwen3-14B"
model_provider = "local-vllm"

[model_providers.local-vllm]
name = "Local vLLM"
base_url = "http://host.containers.internal:8000/v1"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
```

Tenant environment:

```bash
export OPENAI_API_KEY='tenant-local-token'
```

Important compatibility point: current vLLM docs list `/v1/responses` as supported, which matters because current Codex custom provider config documents `responses` as the supported provider protocol. ([vLLM][1])

## OpenClaw

Use the same pattern, assuming OpenClaw accepts OpenAI-compatible endpoint variables:

```bash
export OPENAI_BASE_URL='http://host.containers.internal:8000/v1'
export OPENAI_API_KEY='tenant-local-token'
export OPENAI_MODEL='Qwen/Qwen3-14B'
```

If OpenClaw has its own config file, the values are still the same:

```text
base_url: http://host.containers.internal:8000/v1
api_key: tenant-local-token
model: Qwen/Qwen3-14B
```

---

# Authentication model

## Minimal version

Use one local API key:

```text
VLLM_API_KEY=local-vllm-token
```

Every tenant gets:

```bash
OPENAI_API_KEY=local-vllm-token
```

This is the simplest setup.

## Better version

Put a tiny reverse proxy in front of vLLM and give each tenant a separate token:

```text
tenant-a token ┐
tenant-b token ├── nginx/caddy/envoy on 127.0.0.1:8000 ──> vLLM on 127.0.0.1:8001
tenant-c token ┘
```

This gives you:

* per-tenant access revocation
* per-tenant logs
* optional request-size limits
* optional concurrency limits later
* no changes to tenant client configuration

But since your stated goal is minimalism, I would **not** start with the proxy unless you need per-tenant revocation immediately.

Start with:

```text
tenant container -> vLLM directly
```

Then add:

```text
tenant container -> local proxy -> vLLM
```

only when needed.

---

# Recommended endpoint topology

Use two ports:

```text
127.0.0.1:8000  public-to-local-tenants endpoint
127.0.0.1:8001  optional private backend vLLM endpoint if adding proxy later
```

Minimal initial version:

```text
vLLM binds host 127.0.0.1:8000
tenants call http://host.containers.internal:8000/v1
```

Later proxy version:

```text
proxy binds host 127.0.0.1:8000
vLLM binds host 127.0.0.1:8001
tenants call proxy only
```

---

# Security boundary

The important rule:

> **Only the vLLM container gets GPU access. Tenant containers do not.**

Tenant containers should have:

```text
No /dev/nvidia*
No host network
No host PID namespace
No host IPC namespace
No host filesystem mounts except tenant-specific volumes
No access to vLLM model cache
No access to vLLM service account
```

vLLM gets:

```text
GPU devices
model cache
local API port
no tenant home directories
no host SSH keys
no tenant project files
```

This keeps the expensive shared capability centralized without giving tenants raw device access.

---

# What this looks like end-to-end

```text
Host
├── admin user
│   └── manages system
│
├── systemd (host level)
│   └── vllm.container Quadlet
│       └── system-level Podman container (running as vllm user)
│           ├── has GPU
│           ├── has model cache
│           └── exposes 127.0.0.1:8000
│
├── tenant-a service account
│   └── rootless tenant container
│       ├── Codex CLI
│       ├── OpenClaw
│       └── OPENAI_BASE_URL=http://host.containers.internal:8000/v1
│
├── tenant-b service account
│   └── rootless tenant container
│       ├── Codex CLI
│       ├── OpenClaw
│       └── OPENAI_BASE_URL=http://host.containers.internal:8000/v1
│
└── tenant-c service account
    └── rootless tenant container
        ├── Codex CLI
        ├── OpenClaw
        └── OPENAI_BASE_URL=http://host.containers.internal:8000/v1
```

---

# Why this is the right shape

## 1. It matches normal remote-model client behavior

From the client’s perspective, nothing special is happening:

```text
remote OpenAI API:
https://api.openai.com/v1

local vLLM API:
http://host.containers.internal:8000/v1
```

Same basic API pattern. Different base URL.

## 2. It keeps model serving centralized

You avoid:

```text
tenant-a loads model into VRAM
tenant-b loads model into VRAM
tenant-c loads model into VRAM
```

Instead:

```text
vLLM loads model once
vLLM batches/schedules requests
tenants share the model server
```

That is the efficient design.

## 3. It avoids overengineering

No Kubernetes.
No service mesh.
No per-tenant model containers.
No direct GPU exposure to tenants.
No complex multi-network Podman topology.
No need to make vLLM aware of tenants at first.

Just:

```text
one local API service
many API clients
```

---

# Minimal implementation spec

## Host

Install / configure:

```text
NVIDIA driver stack
nvidia-container-toolkit / CDI support
Podman
systemd
vLLM service account
tenant service accounts
```

## vLLM container

Required:

```text
GPU access
model cache volume
localhost-only published port
API key
systemd/Quadlet startup
```

Avoid:

```text
tenant project mounts
host network
host SSH material
tenant home access
```

## Tenant containers

Required:

```text
Codex CLI
OpenClaw
normal rootless networking
OPENAI_BASE_URL
OPENAI_API_KEY
OPENAI_MODEL
tenant project volume
```

Avoid:

```text
GPU device access
host network
shared tenant volumes
vLLM cache access
host secrets
```

---

# The answer in one sentence

Run **one shared vLLM container via a system-level host Quadlet** under a baked-in service account, publish its OpenAI-compatible API only to **host loopback**, and configure every tenant’s Codex CLI / OpenClaw container to use that endpoint as its `OPENAI_BASE_URL`, with tenant containers remaining isolated and never receiving direct GPU access.

[1]: https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html "OpenAI-Compatible Server - vLLM"
[2]: https://docs.vllm.ai/en/stable/deployment/docker/ "Using Docker - vLLM"
[3]: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_communicating-among-containers_building-running-and-managing-containers "Chapter 12. Communicating among containers | Building, running, and managing containers | Red Hat Enterprise Linux | 9 | Red Hat Documentation"
[4]: https://developers.openai.com/codex/config-reference "Configuration Reference – Codex | OpenAI Developers"

