# vLLM Integration Architecture Proposal

## Project Goal
To enhance our multi-tenant architecture, we propose integrating an open-weight, open-source Large Language Model (LLM) powered by vLLM. The objective is to allow OpenClaw containers to access this local LLM efficiently, using an Nvidia vLLM container as the base image. This integration must ensure optimal resource sharing (specifically GPU VRAM) while rigorously maintaining the deep separation and security of individual tenants within the system.

## The Core Dilemma: Shared vs. Per-Tenant

When integrating an open-weight LLM using a vLLM container, we face a choice between deploying a single shared instance or per-tenant instances.

1. **Per-Tenant vLLM (Not Recommended):** While this provides the ultimate theoretical isolation, it is functionally impractical for LLMs. vLLM is highly memory-intensive and reserves a large chunk of GPU VRAM by default. Running multiple vLLM instances would quickly exhaust GPU resources, even with small models.
2. **Shared vLLM Platform Service (Recommended):** The most efficient and secure approach is to treat the vLLM container as a "Platform Service" managed by the host, sitting alongside existing host services like the backup service.

## Recommended Architecture: The Shared Platform Service

To achieve high efficiency while maintaining "deeply separate" tenants, we can leverage Podman's networking and User Namespaces.

### 1. The vLLM Quadlet (Host Layer)
We create a `vllm.container` Quadlet that runs on the host as a system service.
* **GPU Access:** It uses CDI (`--device nvidia.com/gpu=all`) to get direct hardware access.
* **Resource Tuning:** We configure vLLM's memory utilization parameters (e.g., `gpu_memory_utilization`) to ensure it leaves VRAM available if other tenant workloads need direct GPU access.

### 2. Isolated API Networking (The "Invisible" Connection)
To prevent tenants from improperly accessing the host or other tenants via the central node:
* **Dedicated Network:** We create a Podman network Quadlet (e.g., `openclaw-llm.network`) on the host.
* **Rootless to Root:** Podman allows rootless containers (tenants) to join networks created by root.
* **Strict Binding:** The vLLM container is configured to bind *only* to the IP address of this internal network. It does not publish ports to the host's public interfaces.
* **DNS Resolution:** Using Podman's built-in DNS plugin, tenant containers can reach the API via a predictable internal hostname (e.g., `http://vllm-service:8000`).

### 3. Isolation Guarantees
* **API-Only Access:** Tenant containers can only interact with the specific port exposed by the vLLM API. They cannot access the vLLM filesystem, the host filesystem, or bypass the API.
* **User Namespaces:** Tenant containers are rootless and isolated in their own User Namespaces. A breakout from a tenant container provides no privileges on the host or inside the host-managed vLLM container.
* **Tenant Separation:** While tenants on the same network can theoretically see each other's IP addresses, they do not expose open ports to one another.

## Implementation Steps

1. **Create Host Quadlets:** Write `vllm.network` and `vllm.container` definitions and add them to the host image build process in `01_build_image/build_assets/Containerfile`.
2. **Update Agent Templates:** Modify the OpenClaw runtime template (`01_build_image/build_assets/multi_tenant/agent_quadlet/agent-openclaw-runtime.container.tmpl`) to include a `Network=openclaw-llm.network` directive and the necessary environment variables (like `LLM_API_BASE`).
3. **Update Provisioner Logic:** Ensure `openclaw-provisioner.py` correctly handles these new network assignments when spinning up new agents.