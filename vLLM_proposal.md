# vLLM Integration Architecture Proposal

## Scope (this phase)

Add vLLM as a host-managed service so the operator can run an
open-weight LLM on the workstation's GPU. **No tenant-facing access
path.** Tenant isolation is preserved by not introducing any new
tenant→host surface. Tenant access, GPU arbitration, quotas, and
audit are deferred.

## Why this is so small

Earlier drafts coupled three independent problems: (a) running vLLM on
the host, (b) giving tenants a path to reach it, and (c) arbitrating
the GPU between vLLM and tenant pods. Only (a) is needed now. The
machinery for (b) and (c) — per-tenant socket fanout, sidecar proxy,
policy keys, template edits, admission gates — has no consumer until
tenants actually need the LLM. Building it now is premature.

## What we add

A single host Quadlet at `01_build_image/build_assets/vllm.container`,
alongside `backup.container`. It:

- Pulls a vLLM image with CDI GPU access (`--device nvidia.com/gpu=all`),
  consistent with `nvidia-cdi-refresh.service` generating
  `/etc/cdi/nvidia.yaml` at boot.
- Binds the OpenAI-compatible server to a host-only address (UNIX
  socket under `/run/openclaw-llm/` or loopback — operator's choice).
- Sources model name and HuggingFace cache from environment / a
  host-side volume so the OCI image stays credential- and identity-free.

## What we change in the existing image

One line in `01_build_image/build_assets/Containerfile`:

```
COPY vllm.container /usr/share/containers/systemd/vllm.container
```

That is the entire implementation surface for this phase. **No
provisioner changes, no new policy keys, no new sidecars, no template
edits.**

## Why this preserves tenant isolation

Nothing tenants can reach is added. Tenant pods already have no path
to host loopback or to host-owned UNIX sockets unless those sockets
are explicitly bind-mounted, and none of the existing agent Quadlet
templates mount `/run/openclaw-llm/`. The host gains a service;
tenants are unchanged.

## Deferred (next phase)

- **Tenant access path.** Likely shape: per-tenant socket fanout
  mirroring `openclaw-broker`, plus a per-tenant proxy sidecar
  exposing pod-local OpenAI-compatible HTTP. Sketched in prior drafts;
  not landing here.
- **GPU coexistence.** vLLM and tenant agent dev envs (which today
  request `nvidia.com/gpu=all` via
  `01_build_image/build_assets/multi_tenant/agent_quadlet/agent-dev-env.container.tmpl`)
  will contend for VRAM. The operator manages this manually until
  policy lands.
- **First-boot model pull.** Same shape as `dev-container` and
  `backup-container` — pulled from a registry on first start. Choose
  between a small baked default vs. a HuggingFace pull at first start
  when the access path lands.
