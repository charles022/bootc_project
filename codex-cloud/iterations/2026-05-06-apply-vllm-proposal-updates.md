# Apply vLLM Proposal Updates

Generated: `2026-05-06T00:00:00Z`

## Canonical Input

```text
• Findings

  - High: Option B cannot reach 127.0.0.1:8000 as written.
    vLLM_proposal.md:98 says vLLM binds to host 127.0.0.1, while vLLM_proposal.md:122 says a per-tenant s idecar forwards to that endpoint without giving tenants L3 reachability. A rootless tenant pod’s 127.0.  0.1 is its own network namespace, not the host loopback. This design needs a real transport: preferably vLLM --uds on a host socket bind-mounted read-only into the llm-proxy, or a host-level broker/proxy that exposes per-tenant sockets. Current vLLM docs list --uds, so the proposal’s “if vLLM gains UNIX-socket support” note is stale. Sources: vLLM latest/stable CLI docs for --uds: https://docs.vllm.ai/en/latest/cli/serve/ and https://docs.vllm.ai/en/stable/cli/serve/.
  - High: The proposal undercounts GPU contention.
    vLLM_proposal.md:151 only calls out devpod.yaml, but tenant agent dev environments also request nvidia.com/gpu=all in 01_build_image/build_assets/multi_tenant/agent_quadlet/agent-dev-env.container.tm pl:12. Conflicts=devpod.service will not stop per-tenant rootless agent containers from competing with vLLM. The proposal needs a policy-level GPU mode: either disable GPU in agent env templates when vLLM is active, add per-agent GPU admission control, or explicitly accept shared contention.
  - High: The llm-proxy template naming/location is wrong.
    vLLM_proposal.md:115 calls it tenant-llm-proxy.container.tmpl, but 01_build_image/build_assets/ multi_tenant/openclaw-provisioner.py:421 expects agent templates under agent_quadlet/ and derives output names by stripping an agent- prefix at 01_build_image/build_assets/multi_tenant/openclaw- provisioner.py:432. This should be agent-llm-proxy.container.tmpl. A tenant-* name belongs to onboarding pod templates, and in the agent render loop it would produce bad output names.
  - Medium: “No native auth” is overstated.
    vLLM_proposal.md:49 says vLLM has no native auth. Current vLLM supports --api-key, including one or m ore keys in recent docs. The correct claim is narrower: vLLM API keys do not provide this repo’s requir ed per-tenant identity, quota, audit, and allow-list model. Source: https://docs.vllm.ai/en/latest/serving/openai_compatible_server/.
  - Medium: The agent runtime contract is not implementable with env vars alone.
    vLLM_proposal.md:133 says OPENAI_API_BASE=http://localhost/ “over /run/llm/llm.sock”. A base URL alone does not tell most OpenAI-compatible clients to use a Unix socket; Python clients generally need a custom HTTP transport. If the runtime should work with ordinary OpenAI-compatible env vars, the proxy should expose pod-local HTTP on 127.0.0.1:<port>/v1. If the Unix socket is mandatory, document the required client adapter and standard env names, likely OPENAI_BASE_URL plus project-specific socket variables.
  - Medium: Docs placement does not follow docs/contributing.md.
    vLLM_proposal.md:192 proposes docs/reference/vllm_container.md, but the docs contract says Containerfiles go in reference/images.md, Quadlets in reference/quadlets.md or reference/ tenant_quadlets.md, and systemd units in reference/systemd_units.md. A standalone reference page creates overlap unless this becomes a broader reference category.
  - Medium: The proposal cites CLAUDE.md as architectural source material.
    vLLM_proposal.md:107 cites CLAUDE.md, while docs/contributing.md says not to promote CLAUDE.md / GEMINI.md content into canonical docs. Use docs/concepts/access_model.md, docs/concepts/ ownership_model.md, or another docs source instead.
  - Medium: Prompt/response logging needs a security stance.
    vLLM_proposal.md:130 proposes prompt/response logging into tenant storage. That can capture secrets, credentials, source code, personal data, and model outputs. Make logging opt-in, define retention and permissions, and consider metadata-only logging by default.
  - Low: The quota model is underspecified.
    vLLM_proposal.md:126 names token-rate and concurrent-request quotas, but implementation needs specifics: prompt tokens vs generated tokens, max request tokens, streaming accounting, cancellation behavior, and what happens when usage is only known at the end of a response.

  Refactor-Level Recommendation
  Restructure the proposal around the transport decision first:
  1. Host vLLM transport: use vllm serve --uds /run/openclaw-llm/vllm.sock if available in the pinned vLLM image; otherwise explicitly design a host-reachable TCP path.
  2. Tenant access boundary: agent-llm-proxy.container.tmpl mounts only the vLLM UDS and exposes either pod-local HTTP or a documented project UDS contract to the runtime.
  3. Policy/admission: add allowed_models, LLM budgets, and GPU mode to policy.yaml; wire validation in validate_create_request.
  4. GPU arbitration: cover devpod.service and tenant agent-dev-env GPU access together.
  5. Docs: keep the proposal in docs/design/ if it is a plan, then update existing reference pages only when implementation lands.

  Overall: the sidecar-proxy direction is the right fit for the repo’s isolation model, but the current proposal is not yet implementation-safe because the host-loopback transport, GPU arbitration, and template naming are materially wrong.
```

## Shared Goal

Apply each update from `update_vLLM_proposal.txt` to `vLLM_proposal.md` so the proposal is internally consistent, implementation-safe for this repository, and aligned with the repository documentation rules.

## Repository Context

- Repository root: `/home/chuck/code/bootc_project`
- Current branch: `main`
- Origin: `git@github.com:charles022/bootc_project.git`
- Source file to update: `vLLM_proposal.md`
- Review/update source: `update_vLLM_proposal.txt`
- Canonical docs policy: read `docs/contributing.md` before changing documentation structure or documentation references.
- Preserve the architecture: host image owns hardware, boot, SSH, systemd, CDI, and platform services; tenant/rootless containers own workload runtimes; Quadlet bridges lifecycle management.

## Iteration Instructions

- Treat this file as the canonical source for the iteration.
- Each numbered section below is one Codex Cloud task.
- Use one shared cloud branch for these dependent updates so later tasks see earlier proposal edits.
- Edit `vLLM_proposal.md` only unless a narrow supporting change is required.
- Read the specific repository files named by the assigned item before changing the proposal.
- Commit focused changes for the assigned item to the current cloud branch.

## 1. Fix Option B host-to-tenant transport

### Original Item

```text
High: Option B cannot reach 127.0.0.1:8000 as written.
vLLM_proposal.md:98 says vLLM binds to host 127.0.0.1, while vLLM_proposal.md:122 says a per-tenant sidecar forwards to that endpoint without giving tenants L3 reachability. A rootless tenant pod's 127.0.0.1 is its own network namespace, not the host loopback. This design needs a real transport: preferably vLLM --uds on a host socket bind-mounted read-only into the llm-proxy, or a host-level broker/proxy that exposes per-tenant sockets. Current vLLM docs list --uds, so the proposal's "if vLLM gains UNIX-socket support" note is stale. Sources: vLLM latest/stable CLI docs for --uds: https://docs.vllm.ai/en/latest/cli/serve/ and https://docs.vllm.ai/en/stable/cli/serve/.
```

### Task Notes

- Update the recommended vLLM binding to a host-owned Unix domain socket, preferably `/run/openclaw-llm/vllm.sock`.
- Remove or demote the stale "if vLLM gains UNIX-socket support" language.
- Make clear how the per-tenant proxy reaches the host socket without tenant L3 access.

## 2. Account for all GPU contention

### Original Item

```text
High: The proposal undercounts GPU contention.
vLLM_proposal.md:151 only calls out devpod.yaml, but tenant agent dev environments also request nvidia.com/gpu=all in 01_build_image/build_assets/multi_tenant/agent_quadlet/agent-dev-env.container.tmpl:12. Conflicts=devpod.service will not stop per-tenant rootless agent containers from competing with vLLM. The proposal needs a policy-level GPU mode: either disable GPU in agent env templates when vLLM is active, add per-agent GPU admission control, or explicitly accept shared contention.
```

### Task Notes

- Read `01_build_image/build_assets/multi_tenant/agent_quadlet/agent-dev-env.container.tmpl`.
- Update the GPU coexistence section to cover legacy `devpod.service` and tenant agent dev environments.
- Add the policy/admission decision needed for vLLM mode versus tenant GPU mode.

## 3. Correct llm-proxy template naming and render location

### Original Item

```text
High: The llm-proxy template naming/location is wrong.
vLLM_proposal.md:115 calls it tenant-llm-proxy.container.tmpl, but 01_build_image/build_assets/multi_tenant/openclaw-provisioner.py:421 expects agent templates under agent_quadlet/ and derives output names by stripping an agent- prefix at 01_build_image/build_assets/multi_tenant/openclaw-provisioner.py:432. This should be agent-llm-proxy.container.tmpl. A tenant-* name belongs to onboarding pod templates, and in the agent render loop it would produce bad output names.
```

### Task Notes

- Read the provisioner template render loop before editing.
- Rename the proposed template to `agent-llm-proxy.container.tmpl`.
- Explain that it belongs under `multi_tenant/agent_quadlet/` and renders with the agent pod, not tenant onboarding templates.

## 4. Narrow the vLLM auth claim

### Original Item

```text
Medium: "No native auth" is overstated.
vLLM_proposal.md:49 says vLLM has no native auth. Current vLLM supports --api-key, including one or more keys in recent docs. The correct claim is narrower: vLLM API keys do not provide this repo's required per-tenant identity, quota, audit, and allow-list model. Source: https://docs.vllm.ai/en/latest/serving/openai_compatible_server/.
```

### Task Notes

- Update the Option A critique and any related security language.
- Preserve the reason a per-tenant proxy is still needed even if vLLM has API-key support.

## 5. Make the agent runtime API contract implementable

### Original Item

```text
Medium: The agent runtime contract is not implementable with env vars alone.
vLLM_proposal.md:133 says OPENAI_API_BASE=http://localhost/ "over /run/llm/llm.sock". A base URL alone does not tell most OpenAI-compatible clients to use a Unix socket; Python clients generally need a custom HTTP transport. If the runtime should work with ordinary OpenAI-compatible env vars, the proxy should expose pod-local HTTP on 127.0.0.1:<port>/v1. If the Unix socket is mandatory, document the required client adapter and standard env names, likely OPENAI_BASE_URL plus project-specific socket variables.
```

### Task Notes

- Choose an implementable default contract for tenant runtimes.
- Prefer ordinary OpenAI-compatible environment variables by having the proxy expose pod-local HTTP, unless the proposal explicitly documents a custom Unix-socket client adapter.
- Use current environment variable names consistently.

## 6. Align docs placement with docs/contributing.md

### Original Item

```text
Medium: Docs placement does not follow docs/contributing.md.
vLLM_proposal.md:192 proposes docs/reference/vllm_container.md, but the docs contract says Containerfiles go in reference/images.md, Quadlets in reference/quadlets.md or reference/tenant_quadlets.md, and systemd units in reference/systemd_units.md. A standalone reference page creates overlap unless this becomes a broader reference category.
```

### Task Notes

- Read `docs/contributing.md`.
- Update the documentation plan in `vLLM_proposal.md` so implementation documentation lands in existing reference pages.
- If the proposal remains a plan, prefer `docs/design/` for the proposal itself.

## 7. Replace CLAUDE.md as architectural source material

### Original Item

```text
Medium: The proposal cites CLAUDE.md as architectural source material.
vLLM_proposal.md:107 cites CLAUDE.md, while docs/contributing.md says not to promote CLAUDE.md / GEMINI.md content into canonical docs. Use docs/concepts/access_model.md, docs/concepts/ownership_model.md, or another docs source instead.
```

### Task Notes

- Remove the `CLAUDE.md` architectural citation.
- Replace it with canonical docs references that support the same security and ownership claims.

## 8. Add a security stance for prompt and response logging

### Original Item

```text
Medium: Prompt/response logging needs a security stance.
vLLM_proposal.md:130 proposes prompt/response logging into tenant storage. That can capture secrets, credentials, source code, personal data, and model outputs. Make logging opt-in, define retention and permissions, and consider metadata-only logging by default.
```

### Task Notes

- Update proxy logging/audit language.
- Make metadata-only logging the default unless there is a clear opt-in.
- Mention retention and tenant storage permissions.

## 9. Specify the quota model

### Original Item

```text
Low: The quota model is underspecified.
vLLM_proposal.md:126 names token-rate and concurrent-request quotas, but implementation needs specifics: prompt tokens vs generated tokens, max request tokens, streaming accounting, cancellation behavior, and what happens when usage is only known at the end of a response.
```

### Task Notes

- Expand quota language enough to guide implementation.
- Cover prompt tokens, generated tokens, max request tokens, streaming, cancellation, and post-response accounting.

## 10. Final structure and consistency pass

### Original Item

```text
Refactor-Level Recommendation
Restructure the proposal around the transport decision first:
1. Host vLLM transport: use vllm serve --uds /run/openclaw-llm/vllm.sock if available in the pinned vLLM image; otherwise explicitly design a host-reachable TCP path.
2. Tenant access boundary: agent-llm-proxy.container.tmpl mounts only the vLLM UDS and exposes either pod-local HTTP or a documented project UDS contract to the runtime.
3. Policy/admission: add allowed_models, LLM budgets, and GPU mode to policy.yaml; wire validation in validate_create_request.
4. GPU arbitration: cover devpod.service and tenant agent-dev-env GPU access together.
5. Docs: keep the proposal in docs/design/ if it is a plan, then update existing reference pages only when implementation lands.

Overall: the sidecar-proxy direction is the right fit for the repo's isolation model, but the current proposal is not yet implementation-safe because the host-loopback transport, GPU arbitration, and template naming are materially wrong.
```

### Task Notes

- Run after the specific finding tasks on the same branch.
- Re-read the whole proposal and make it coherent after the item-level edits.
- Reorder sections if needed so transport, tenant boundary, policy/admission, GPU arbitration, and docs plan are easy to follow.
- Keep the proposal focused; do not implement the vLLM feature in code unless the proposal explicitly requires a small supporting correction.
