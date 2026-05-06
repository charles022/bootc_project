# vLLM Integration Architecture Proposal

## Project Goal

Integrate an open-weight LLM, served by vLLM on the host's GPU, so that
OpenClaw agent containers can consume it efficiently while preserving the
deep tenant separation the rest of this codebase already enforces. The
serving runtime should sit alongside existing host services (`backup.container`,
`nvidia-cdi-refresh.service`) as a Platform Service, and access from agents
should reuse — not bypass — the per-tenant sidecar idiom already established
by `credential-proxy` and the `messaging-bridge-*` family.

## The Core Dilemma: Shared vs. Per-Tenant vLLM

When integrating an open-weight LLM via vLLM, we choose between a single
shared instance or per-tenant instances.

1. **Per-tenant vLLM (rejected).** Theoretically the strongest isolation,
   but functionally impractical. vLLM reserves a large fraction of GPU VRAM
   on startup (continuous batching + KV cache), so two instances on one GPU
   thrash or refuse to load.
2. **Shared vLLM as a host-managed Platform Service (recommended).** Host
   owns the serving runtime; tenants consume it through a brokered
   interface. This matches the ownership rule in
   `docs/concepts/ownership_model.md`: *host owns systemd services and
   Quadlets; containers own workload runtimes; Quadlet is the only bridge.*

## How Tenants Should Reach vLLM — Two Options

The serving side is uncontroversial. The interesting design question is how
agent containers reach the API. We considered two options.

### Option A — Shared Podman network (initially proposed, now rejected as primary)

Create an `openclaw-llm.network` Quadlet. vLLM binds only to that network's
internal IP. Each tenant's pod joins the same network and resolves
`http://vllm-service:8000` via Podman's DNS plugin. Rootless tenants are
allowed to join networks created by root.

**Why this is weaker than it looks in *this* repo:**

- **It introduces a new isolation primitive.** Nothing else in the codebase
  trusts network-level separation between tenants. Platform services are
  reached via per-tenant **UNIX sockets bind-mounted into the pod** —
  e.g. the agentctl socket at
  `01_build_image/build_assets/multi_tenant/agent_quadlet/agent-openclaw-runtime.container.tmpl:20`
  (`/run/openclaw-provisioner/tenants/${TENANT}.sock`). A shared L3 network
  is a regression from that posture.
- **No per-tenant identity on requests.** vLLM's OpenAI-compatible server
  has no native auth or multi-tenancy. If the agent talks to vLLM directly
  there is no place to:
  - attribute or quota tokens per tenant,
  - rate-limit prompts/generations (a single tenant can starve others
    because KV cache and continuous-batching scheduling are global),
  - apply a per-tenant model allow-list,
  - log or redact prompts into the tenant's own storage.
- **It collides with existing provisioner policy.** The provisioner has a
  closed set of network profiles
  (`openclaw-provisioner.py:67`:
  `ALLOWED_NETWORKS_DEFAULT = ["none", "messaging-only", "api-only", "restricted-internet"]`)
  and `forbidden.host_network: True` at
  `openclaw-provisioner.py:248`. Adding LLM access via "yet another
  network profile" or a second `Network=` line on rootless tenant pods is
  a new pattern that needs to be designed and validated, not assumed.
- **Tenants on the same network can see each other's IPs.** Even if no
  ports are exposed today, that's a soft guarantee that depends on every
  future sidecar being careful.

### Option B — Per-tenant `llm-proxy` sidecar over a UNIX socket (recommended)

Treat vLLM the way this repo already treats the credential broker and
messaging bridges. The agent never reaches vLLM over IP; it talks to a
tenant-local proxy via a UNIX socket bind-mounted into its pod, and the
proxy is the only thing on the host that can reach vLLM.

This is strictly more isolated, fits the existing provisioner and policy
machinery with no new primitives, and gives us the quota/audit layer we'll
want before the second tenant shows up.

| Concern | Option A (shared network) | Option B (sidecar proxy) |
|---|---|---|
| Matches existing patterns | New primitive | Reuses `credential-proxy` / `messaging-bridge-*` shape |
| Tenant→vLLM reachability | Network ACL on bind IP | Zero (UNIX socket only) |
| Per-tenant quotas/audit | Not possible without an extra service | Natural — lives in the proxy |
| Provisioner change | New network profile + cross-namespace join | One more `.tmpl` rendered into the existing pod |
| Failure blast radius | Abusive tenant degrades vLLM globally | Proxy sheds load per tenant |
| `policy.yaml` integration | None | `allowed_models`, `llm_token_budget` slot next to `allowed_credentials` |

## Recommended Architecture

### 1. The vLLM Quadlet (Host Layer)

A `vllm.container` Quadlet runs on the host as a system service, alongside
`backup.container`.

- **GPU access:** CDI (`--device nvidia.com/gpu=all`), consistent with
  `nvidia-cdi-refresh.service` generating `/etc/cdi/nvidia.yaml` at boot.
- **Binding:** Listens on a host-owned Unix domain socket, preferably
  `/run/openclaw-llm/vllm.sock`, via `vllm serve --uds`. No Podman network is
  shared with tenants and no TCP port is published.
- **Resource tuning:** `gpu_memory_utilization` set so the GPU isn't fully
  consumed at load time — see "GPU coexistence" below.
- **Model and cache externalised:** model name and HuggingFace cache path
  come from environment / a host-side volume, not baked into the OCI image.
  Same posture as the rest of the host image, which is deliberately
  credential- and identity-free (see `CLAUDE.md`, "No SSH keys or
  credentials are baked in").

### 2. The Per-Tenant `llm-proxy` Sidecar

Modeled directly on `credential-proxy.py` /
`tenant-credential-proxy.container.tmpl`.

- **New template:** `tenant-llm-proxy.container.tmpl` rendered by
  `openclaw-provisioner.py` into each tenant pod, the same way
  `credential-proxy` already is.
- **Listens** on a UNIX socket inside the pod, e.g. `/run/llm/llm.sock`,
  bind-mounted into the agent runtime container — the same idiom as
  `agentctl.sock` at
  `agent-openclaw-runtime.container.tmpl:20`.
- **Forwards** to the host vLLM socket by bind-mounting only
  `/run/openclaw-llm/vllm.sock` read-only into the proxy container. The tenant
  pod does not receive host networking or L3 reachability to host loopback;
  the agent runtime still has no network route to vLLM at all.
- **Enforces, per request:**
  - tenant-id tagging,
  - per-tenant token-rate / concurrent-request quotas, sourced from
    `policy.yaml` next to `allowed_credentials`
    (`openclaw-provisioner.py:240`),
  - per-tenant model allow-list,
  - prompt/response logging into the tenant's own volume layout (see
    `docs/concepts/tenant_storage_layout.md`),
  - optional prompt-redaction hooks.
- **Agent-runtime contract:** the runtime sees only
  `OPENAI_API_BASE=http://localhost/` over `/run/llm/llm.sock`. No DNS,
  no IP, no shared network.

### 3. Isolation Guarantees Under Option B

- **No L3 reachability** between tenants and vLLM. Compromise of a tenant
  yields a UNIX socket connected to that tenant's own proxy — nothing else.
- **Policy is enforced where identity exists.** The proxy is per-tenant and
  knows the tenant; vLLM doesn't need to.
- **User namespaces unchanged.** Tenants remain rootless in their own user
  namespaces; vLLM runs as a root-owned host service. A breakout from a
  tenant container provides no privileges on the host or inside vLLM.
- **No new provisioner-policy holes.** `forbidden.host_network` stays
  `True`; no new shared network is introduced.

### 4. GPU Coexistence

The dev pod (`devpod.yaml`) currently requests `nvidia.com/gpu=all`. vLLM
will hold a large slab of VRAM for its KV cache. We must decide explicitly:

- **Option (a) — coexist:** set `gpu_memory_utilization` low enough to
  leave headroom, document the split, accept that the dev pod may OOM under
  load.
- **Option (b) — mutually exclude:** add `Conflicts=devpod.service` to the
  vLLM unit (or vice-versa) so only one is active at a time.

Recommendation: **(b) for the workstation deployment** while there is a
single GPU. Revisit when MIG or a second GPU is in play. Either way the
choice should be made in the unit file, not left implicit.

## Implementation Steps

1. **Host Quadlet.** Add `vllm.container` to
   `01_build_image/build_assets/` and `COPY` it into
   `/usr/share/containers/systemd/` from
   `01_build_image/build_assets/Containerfile`. Decide GPU coexistence
   (`Conflicts=` with `devpod.service` is the recommended default). No
   `vllm.network` Quadlet — vLLM is exposed through the host-owned
   `/run/openclaw-llm/vllm.sock` UDS instead of TCP.
2. **`llm-proxy` image and template.** Add
   `01_build_image/build_assets/multi_tenant/llm-proxy.Containerfile` and
   `llm-proxy.py`, mirroring the structure of `credential-proxy.*`. Add
   `tenant-llm-proxy.container.tmpl` under
   `01_build_image/build_assets/multi_tenant/agent_quadlet/`.
3. **Provisioner wiring.** In
   `01_build_image/build_assets/multi_tenant/openclaw-provisioner.py`:
   - Render the new template into each agent pod (the existing
     `render_agent_quadlets` loop at line 390 already iterates `*.tmpl`).
   - Extend `DEFAULT_POLICY` (line ~228) with `allowed_models` and
     `llm_token_budget` keys, defaulting to a conservative empty/zero so
     LLM access is opt-in per tenant.
   - **Do not** add a new entry to `ALLOWED_NETWORKS_DEFAULT`
     (`openclaw-provisioner.py:67`); LLM access is socket-mediated, not
     network-mediated.
4. **Agent runtime template.** Update
   `agent-openclaw-runtime.container.tmpl` to bind-mount
   `/run/llm/llm.sock` from the pod and set `OPENAI_API_BASE` /
   `OPENAI_API_KEY` env vars pointing at it. Mirrors the existing
   `agentctl.sock` mount at line 20.
5. **Docs.** Add `docs/concepts/llm_platform_service.md` (concept) and
   `docs/reference/vllm_container.md` (reference, code-paired with the
   Quadlet — see `docs/contributing.md` for the contract). Update
   `docs/concepts/multi_tenant_architecture.md` to mention the new
   sidecar.

## Open Questions

- **Streaming and cancellation.** The proxy must forward SSE cleanly and
  propagate client-side disconnects so a tenant cancelling a long
  generation actually frees vLLM scheduler slots. Worth a smoke test
  before declaring quotas meaningful.
- **Fairness inside vLLM.** Per-tenant quotas at the proxy bound *demand*,
  but vLLM's batch scheduler is still global. If contention becomes real,
  investigate vLLM's priority/queueing knobs or run tenant requests
  through a single proxy-side scheduler that gates concurrency before
  hitting vLLM.
- **First-boot model pull.** Like `dev-container` and `backup-container`,
  the model weights must come from somewhere on first boot. Decide
  between baking a small default into a sidecar volume image vs. pulling
  from HuggingFace at first start (network-dependent, matches current
  `devpod.yaml` posture).
