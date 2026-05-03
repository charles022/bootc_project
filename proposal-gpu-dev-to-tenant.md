# High-Level Architectural Proposal: Tenant-Scoped GPU Dev Environment

## What You Have Today

Two parallel architectures share a host image but have separate runtime models:

| | Single-host devpod | Multi-tenant agent pod |
|---|---|---|
| **Identity** | system-wide (no tenant) | `tenant_<name>` service account |
| **GPU access** | yes (`nvidia.com/gpu=all` via kube YAML) | no |
| **Dev image** | `nvcr.io/nvidia/pytorch:26.03-py3` | policy-selected env image, defaulting to `onboarding-env` |
| **Orchestration** | `/usr/share/containers/systemd/devpod.kube` | `/etc/containers/systemd/users/<UID>/` |
| **Lifecycle** | system Quadlet, manually or boot started | rootless Podman, per-tenant user manager |

The `devpod` exists outside the multi-tenant control plane. The multi-tenant path already has a per-agent `dev-env` slot via `agent-dev-env.container.tmpl`, but the default tenant policy currently points agent environments at the lightweight `onboarding-env` stub.

The onboarding pod also has an `onboarding-env` container. That is a first-time enrollment shell, not the same role as a per-agent GPU development environment. It should stay lightweight unless we intentionally decide every tenant's always-on onboarding pod should pull and expose the GPU image.

---

## The Core Change

**Promote GPU development into the tenant/agent architecture, then remove the system-wide devpod only after tenant GPU injection is proven.**

This is mostly an image, policy, and Quadlet-template change. The key technical unknown is whether rootless `.container` Quadlets can consume the NVIDIA CDI selector in the way this project needs. The current repo intentionally uses a `.kube` Quadlet for the system dev pod because `podman kube play` has documented support for CDI resource selectors, while `.container` `AddDevice=` is documented as a host device path mapping.

The work is:

1. Prove rootless tenant GPU injection.
2. Make the per-agent `dev-env` slot GPU-capable.
3. Give that slot the right image (`dev-env`, NVIDIA-based).
4. Update default tenant policy and build/push pipelines.
5. Promote the admin/operator to a first-class tenant.
6. Remove the system-wide devpod only after the tenant path passes hardware validation.

---

## Step-by-Step Plan

### 0. Prove rootless tenant GPU injection

Before deleting or renaming anything, run a narrow hardware spike on a dev VM/host with NVIDIA hardware:

1. Create a test tenant.
2. Render or hand-edit one test agent dev-env Quadlet with CDI device injection.
3. Start the tenant user manager unit.
4. Verify `nvidia-smi` and `python3 /workspace/dev_container_test.py` inside the agent dev-env container.

The first candidate should be:

```ini
# in agent-dev-env.container.tmpl
AddDevice=nvidia.com/gpu=all
```

Use the same selector spelling as the current Kubernetes pod manifest: `nvidia.com/gpu=all`, not `nvidia.com/gpu:all`.

If `.container` + `AddDevice=nvidia.com/gpu=all` does not work rootless, do not proceed with the simple template-line approach. The fallback design should be one of:

- A per-agent `.kube` template that keeps the documented `resources.limits[nvidia.com/gpu=all]: 1` path.
- Direct host device mappings such as `AddDevice=/dev/nvidia0`, `AddDevice=/dev/nvidiactl`, and `AddDevice=/dev/nvidia-uvm`, with the explicit list generated from the host. This is less clean than CDI and needs careful validation against the NVIDIA userspace library mounts.

Also verify that `/etc/cdi/` and `/etc/cdi/nvidia.yaml` are readable by tenant service accounts. If permissions are too strict, fix the host image or `nvidia-cdi-refresh.service` so generated CDI specs are readable without giving tenants write access.

### 1. Create a tenant dev image

Create a new `dev-env.Containerfile` for tenant agent development. It should:

- Use the NVIDIA PyTorch base, or a lighter `nvcr.io/nvidia/cuda:*-devel` base if image weight is a concern.
- Add `sudo` and any required shell/process utilities.
- Add SSH server only if the tenant access model still needs sshd inside the dev environment.
- Retain the `dev_container_start.sh` wrapper and `dev_container_test.py` smoke test.
- Tag as `quay.io/m0ranmcharles/fedora_init:dev-env`.

Do not delete `onboarding-env.Containerfile` as part of this step unless the onboarding flow is explicitly being retired or replaced. The onboarding container is a distinct first-time enrollment shell and can remain lightweight.

After `dev-env` is proven and all references are migrated, `dev-container.Containerfile` can be removed with the system `devpod`.

**Code changed:** add `dev-env.Containerfile`; keep `dev_container_start.sh` and `dev_container_test.py` in the build context or move them with corresponding script updates.

### 2. Add GPU access to the agent dev-env template

After the spike passes, add CDI access to the per-agent dev environment template:

```ini
# in agent_quadlet/agent-dev-env.container.tmpl
AddDevice=nvidia.com/gpu=all
```

Do not add GPU access to `tenant-onboard-env.container.tmpl` in the first implementation. That would make the always-on onboarding pod GPU-capable for every tenant. If there is a product requirement for GPU access in the onboarding shell, handle it as a separate decision with the same rootless CDI validation.

**Code changed:** one `.tmpl` file, plus any host-image permission fix needed for rootless CDI reads.

### 3. Update the default policy and provisioner

Both `platformctl.sh` (the `policy.yaml` template written at tenant create) and `openclaw-provisioner.py` (the `DEFAULT_POLICY` dict) list allowed environment images. Change `allowed_images.environments` from:

```yaml
- quay.io/m0ranmcharles/fedora_init:onboarding-env
```

to:

```yaml
- quay.io/m0ranmcharles/fedora_init:dev-env
```

Also update examples and help text that show `onboarding-env` as the agent environment image, including:

- `docs/reference/agentctl.md`
- `docs/how-to/create_an_agent.md`
- `docs/how-to/enroll_messaging.md`
- `openclaw-runtime-router.py` example text

### 4. Update build, push, and update pipelines

The image rename must be reflected everywhere images are built, saved, pushed, or documented:

- `build_image.sh`: build `quay.io/m0ranmcharles/fedora_init:dev-env` from `dev-env.Containerfile`; stop building `:dev-container` once `devpod` is removed.
- `push_images.sh`: push `:dev-env`; stop pushing `:dev-container` once it is retired.
- `01_build_image/build_assets/os-builder.sh`: build/save the new dev image if `SAVE_ALL=1` should still include it.
- `docs/reference/images.md`, `docs/reference/registry.md`, `docs/reference/scripts.md`, and `docs/how-to/push_to_quay.md`: update image names and tags.

Do this before changing default policy to `:dev-env` in a released host image. Otherwise new tenants will receive policies pointing at an image that may not exist in Quay.

### 5. Admin becomes a tenant

The admin/operator no longer has a system-wide dev pod. Instead, run:

```bash
platformctl tenant create admin
```

Then create an admin agent/dev environment using the allowlisted `:dev-env` image. The admin retains host SSH access for platform management; `platformctl` and `platformctl agent` commands work unchanged.

The docs should describe the transition sequence explicitly:

1. Upgrade to a host image that contains the tenant GPU path and `:dev-env` policy.
2. Create the `admin` tenant.
3. Create an admin agent/dev environment using `:dev-env`.
4. Validate GPU access.
5. Only then remove the system-wide `devpod`.

### 6. Remove the system-wide devpod

After the tenant path is validated on real hardware:

- Delete `devpod.kube` and `devpod.yaml`.
- Remove their two `COPY` lines from the host `Containerfile`.
- Remove or replace the `devpod.service` check in `bootc_host_test.sh`.
- Stop building and pushing the old `:dev-container` image.
- Update all docs that describe the system-wide dev pod as current behavior.

There are no `systemctl enable` changes currently required for `devpod`; Kube Quadlets in `/usr/share/containers/systemd/` are discovered by the generator. Removal is still more than deleting the two files because tests, scripts, registry docs, and validation procedures refer to it.

---

## What Stays Completely Unchanged

- `openclaw-broker.py` behavior
- `agentctl.py` behavior, though examples/docs may need the new image name
- All messaging-bridge images and templates
- `openclaw-runtime.Containerfile` and template
- `credential-proxy.Containerfile` and template
- `tenant-cloudflared.container.tmpl`, `tenant-onboard-env.container.tmpl`, and `tenant-credential-proxy.container.tmpl` in the first implementation
- The full `agent_quadlet/` template set except `agent-dev-env.container.tmpl`
- Tenant identity, policy validation mechanics, quotas, audit logs, broker sockets, and provisioner request flow
- Backup container and CDI refresh behavior

---

## Risk Register

| Risk | Likelihood | Mitigation |
|---|---|---|
| `.container` Quadlet cannot consume `nvidia.com/gpu=all` rootless | Medium | Make this a phase-0 spike; fall back to per-agent `.kube` templates or explicit `/dev/nvidia*` mappings if needed |
| CDI spec exists but is unreadable by tenant service accounts | Medium | Verify `/etc/cdi/` and `/etc/cdi/nvidia.yaml` permissions; adjust the host image or refresh unit so specs are tenant-readable and root-writable |
| Wrong CDI selector spelling | Medium | Use `nvidia.com/gpu=all`, matching the existing `devpod.yaml`; do not use `nvidia.com/gpu:all` |
| NVIDIA/PyTorch image is very large per tenant/agent | Medium | Start with a single allowlisted `:dev-env`; consider a lighter CUDA devel base as a later policy option |
| Onboarding pod becomes unnecessarily GPU-capable | Medium | Do not add GPU access to `tenant-onboard-env.container.tmpl` in the first implementation |
| Policy points to an image that was not built or pushed | Medium | Update `build_image.sh`, `push_images.sh`, and `os-builder.sh` before changing default policy |
| Admin loses direct dev access during transition | Low | Admin creates and validates their tenant dev environment before removing `devpod` |
| Existing devpod data loss | None | `devpod` has no persistent volumes; it is stateless by design |
| Docs and smoke tests continue referring to removed devpod | High | Update `bootc_host_test.sh` and all current docs that mention `devpod`, `dev-container`, or `onboarding-env` as the agent environment image |

---

## Net Effect on the Codebase

| | Count |
|---|---|
| Files added | 1 (`dev-env.Containerfile`) |
| Files deleted after validation | 3 (`devpod.kube`, `devpod.yaml`, `dev-container.Containerfile`) |
| Files kept | `onboarding-env.Containerfile`, unless onboarding is intentionally merged later |
| Files with small edits | `agent-dev-env.container.tmpl`, host `Containerfile`, `platformctl.sh`, `openclaw-provisioner.py`, `build_image.sh`, `push_images.sh`, `os-builder.sh`, `bootc_host_test.sh` |
| Files with doc updates | More than 4: at minimum overview, GPU stack, images, registry, scripts, Quadlet docs, systemd units, platformctl/agentctl refs, GPU validation, staged validation, push-to-Quay, create-agent, messaging enrollment, repository layout, roadmap |

The multi-tenant control plane remains structurally unchanged: tenant identity, policy validation, credential broker, provisioner request flow, quota/audit model, and rootless Podman ownership stay intact. The implementation still touches more than image naming because the system-wide dev pod is referenced by tests, scripts, and docs.

---

## What to Confirm Before Coding

1. **Rootless CDI access**: spin up a test tenant on a dev VM, add `AddDevice=nvidia.com/gpu=all` to an agent dev-env Quadlet, and verify `nvidia-smi` runs inside. This is the single technical gate. If CDI mode does not work rootless, use a per-agent `.kube` template or direct host device mappings instead of deleting `devpod`.

2. **Image weight**: PyTorch vs. a CUDA devel base is a product question. The Containerfile change is similar either way; the `FROM` line and included tooling differ.

3. **Onboarding scope**: decide whether onboarding remains lightweight. Recommended first implementation: leave `tenant-onboard-env` unchanged and make only per-agent `dev-env` GPU-capable.

4. **Image publication order**: ensure `:dev-env` is built and pushed before default policy points to it.

5. **Removal timing**: remove `devpod` only in the same change that updates smoke tests and docs, after tenant GPU validation has passed.
