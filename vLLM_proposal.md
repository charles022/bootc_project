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
- **No usable per-tenant control point.** vLLM's OpenAI-compatible server
  supports API keys, but those keys do not express this repo's tenant model.
  If the agent talks to vLLM directly there is no place to:
  - attribute or quota tokens per tenant,
  - rate-limit prompts/generations (a single tenant can starve others
    because KV cache and continuous-batching scheduling are global),
  - apply a per-tenant model allow-list,
  - produce tenant-scoped audit records or controlled prompt/response logs.
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

### Option B — Per-tenant `llm-proxy` sidecar with host-socket upstream (recommended)

Treat vLLM the way this repo already treats the credential broker and
messaging bridges. The agent never reaches vLLM over IP; it talks to a
tenant-local proxy over pod-local HTTP, and the proxy is the only tenant pod
container that can reach vLLM's host-owned Unix socket.

This is strictly more isolated, fits the existing provisioner and policy
machinery with no new primitives, and gives us the quota/audit layer we'll
want before the second tenant shows up.

| Concern | Option A (shared network) | Option B (sidecar proxy) |
|---|---|---|
| Matches existing patterns | New primitive | Reuses `credential-proxy` / `messaging-bridge-*` shape |
| Tenant→vLLM reachability | Network ACL on bind IP | No direct route; proxy-only host UDS |
| Per-tenant quotas/audit | Not possible without an extra service | Natural — lives in the proxy |
| Provisioner change | New network profile + cross-namespace join | One more `.tmpl` rendered into the existing pod |
| Failure blast radius | Abusive tenant degrades vLLM globally | Proxy sheds load per tenant |
| `policy.yaml` integration | None | `allowed_models`, LLM budgets, and `gpu_mode` next to `allowed_credentials` |

## Recommended Architecture

### 1. The vLLM Quadlet (Host Layer)

A `vllm.container` Quadlet runs on the host as a system service, alongside
`backup.container`.

- **GPU access:** CDI (`--device nvidia.com/gpu=all`), consistent with
  `nvidia-cdi-refresh.service` generating `/etc/cdi/nvidia.yaml` at boot.
- **Binding:** Listens on a host-owned Unix domain socket, preferably
  `/run/openclaw-llm/vllm.sock`, via `vllm serve --uds`. Current vLLM CLI
  docs describe `--uds` as the Unix socket path and ignore host/port when it
  is set. No Podman network is shared with tenants and no TCP port is
  published.
- **Resource tuning:** `gpu_memory_utilization` set so the GPU isn't fully
  consumed at load time — see "GPU coexistence" below.
- **Model and cache externalised:** model name and HuggingFace cache path
  come from environment / a host-side volume, not baked into the OCI image.
  Same posture as the rest of the host image, which is deliberately
  credential- and identity-free (see `docs/concepts/access_model.md` and
  `docs/concepts/ownership_model.md`).

### 2. The Per-Tenant `llm-proxy` Sidecar

Modeled directly on `credential-proxy.py` /
`agent-credential-proxy.container.tmpl`.

- **New template:** `agent-llm-proxy.container.tmpl` lives under
  `01_build_image/build_assets/multi_tenant/agent_quadlet/` and is rendered
  by `openclaw-provisioner.py` with the agent Quadlet templates. The
  provisioner derives agent output names by stripping the `agent-` prefix, so
  this sidecar must not use the `tenant-*` onboarding-template naming pattern.
- **Upstream transport:** bind-mount only
  `/run/openclaw-llm/vllm.sock` read-only into the proxy container. The tenant
  pod does not receive host networking or L3 reachability to host loopback.
- **Downstream runtime API:** expose pod-local HTTP on
  `127.0.0.1:8001/v1` inside the shared agent pod network namespace. The
  OpenClaw runtime uses ordinary OpenAI-compatible environment variables,
  e.g. `OPENAI_BASE_URL=http://127.0.0.1:8001/v1` and an opaque
  `OPENAI_API_KEY` accepted by the proxy. No client-specific Unix-socket
  transport adapter is required.
- **Enforces, per request:**
  - tenant-id tagging,
  - per-tenant quotas sourced from `policy.yaml` next to
    `allowed_credentials` (`openclaw-provisioner.py:240`), including
    concurrent requests, prompt-token budget, generated-token budget, and
    max total tokens per request,
  - per-tenant model allow-list,
  - metadata-only audit records by default into the tenant's own volume
    layout (see `docs/concepts/tenant_storage_layout.md`),
  - opt-in prompt/response logging only when policy defines retention,
    permissions, and redaction behavior,
  - optional prompt-redaction hooks.
- **Quota accounting:** count prompt tokens before admission, reserve the
  requested maximum generated tokens before forwarding, release unused
  generated-token reservation after the response finishes, and debit actual
  generated tokens from streaming or final usage metadata. Client
  cancellation must propagate upstream so vLLM scheduler slots are released
  and partially-generated tokens are charged consistently.

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

The legacy dev pod (`devpod.yaml`) currently requests `nvidia.com/gpu=all`,
and every provisioned tenant agent dev environment does the same through
`01_build_image/build_assets/multi_tenant/agent_quadlet/agent-dev-env.container.tmpl`.
vLLM will hold a large slab of VRAM for its KV cache, so GPU arbitration must
cover both host-level developer services and rootless per-tenant agent
containers. `Conflicts=devpod.service` only handles the legacy dev pod; it
does not stop already-running or newly-provisioned tenant agent dev
environments from competing with vLLM.

We must decide explicitly at policy/admission time:

- **Option (a) — shared contention:** set `gpu_memory_utilization` low enough
  to leave documented headroom, keep tenant agent dev environments on
  `nvidia.com/gpu=all`, and accept that vLLM or tenant workloads may OOM or
  experience latency spikes under load.
- **Option (b) — vLLM-exclusive GPU mode:** when vLLM mode is active, add
  `Conflicts=devpod.service` for the legacy dev pod **and** render or admit
  tenant agent dev environments without `--device=nvidia.com/gpu=all` unless
  a specific per-agent GPU admission policy grants access.
- **Option (c) — per-agent GPU admission:** extend tenant policy with an
  explicit GPU mode, such as `gpu_mode: vllm-exclusive | shared |
  per-agent`, plus per-agent grants. `validate_create_request` should reject
  requests that would create GPU-enabled agent environments while the node is
  in vLLM-exclusive mode.

Recommendation: **Option (b) for the single-GPU workstation deployment**,
implemented as a policy-controlled `gpu_mode` defaulting to
`vllm-exclusive` whenever host vLLM is enabled. Revisit shared or per-agent
admission when MIG or a second GPU is in play. Either way, the choice must be
made in policy and unit/template rendering, not left implicit in only the
vLLM unit file.

## Implementation Steps

1. **Host Quadlet.** Add `vllm.container` to
   `01_build_image/build_assets/` and `COPY` it into
   `/usr/share/containers/systemd/` from
   `01_build_image/build_assets/Containerfile`. Decide GPU coexistence
   (`Conflicts=` with `devpod.service` is necessary but not sufficient;
   policy must also govern GPU-enabled tenant agent dev environments). No
   `vllm.network` Quadlet — vLLM is exposed through the host-owned
   `/run/openclaw-llm/vllm.sock` UDS instead of TCP.
2. **`llm-proxy` image and template.** Add
   `01_build_image/build_assets/multi_tenant/llm-proxy.Containerfile` and
   `llm-proxy.py`, mirroring the structure of `credential-proxy.*`. Add
   `agent-llm-proxy.container.tmpl` under
   `01_build_image/build_assets/multi_tenant/agent_quadlet/` so it renders
   with each agent pod; `tenant-*` templates remain for tenant onboarding
   pods.
3. **Provisioner wiring.** In
   `01_build_image/build_assets/multi_tenant/openclaw-provisioner.py`:
   - Render the new template into each agent pod (the existing
     `render_agent_quadlets` loop at line 390 already iterates `*.tmpl`).
   - Extend `DEFAULT_POLICY` (line ~228) with `allowed_models`,
     `llm_token_budget`, and `gpu_mode` keys, defaulting to conservative
     values so LLM access is opt-in per tenant and GPU-enabled agent dev
     environments cannot silently contend with host vLLM.
   - Wire `gpu_mode` into `validate_create_request` and agent Quadlet
     rendering so vLLM-exclusive mode rejects or strips
     `--device=nvidia.com/gpu=all` from tenant agent dev environments unless
     policy grants per-agent GPU access.
   - **Do not** add a new entry to `ALLOWED_NETWORKS_DEFAULT`
     (`openclaw-provisioner.py:67`); LLM access is socket-mediated, not
     network-mediated.
4. **Agent runtime template.** Update
   `agent-openclaw-runtime.container.tmpl` to set `OPENAI_BASE_URL` and
   `OPENAI_API_KEY` for the pod-local proxy HTTP endpoint. Do not require
   ordinary OpenAI-compatible clients to speak Unix sockets directly.
5. **Docs.** If this proposal becomes canonical, move it under
   `docs/design/`. Add or update a concept page for the LLM platform service
   only if the design is still planned. When implementation lands, update the
   existing code-paired reference pages instead of adding
   `docs/reference/vllm_container.md`: Containerfiles belong in
   `docs/reference/images.md`, Quadlets in `docs/reference/quadlets.md` or
   `docs/reference/tenant_quadlets.md`, systemd units in
   `docs/reference/systemd_units.md`, and scripts in
   `docs/reference/scripts.md`. Update
   `docs/concepts/multi_tenant_architecture.md` to mention the sidecar.

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
