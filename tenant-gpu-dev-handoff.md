# Tenant GPU dev environment handoff

This note records what was intentionally not completed in the tenant-scoped GPU dev environment work, why it was not completed, and what the next session should investigate or implement. It is a working handoff, not canonical user-facing documentation.

## Current implemented state

- `01_build_image/build_assets/multi_tenant/dev-env.Containerfile` exists.
- `dev-env` uses `nvcr.io/nvidia/pytorch:26.03-py3`.
- `dev-env` copies:
  - `dev_container_start.sh` to `/usr/local/bin/dev_container_start.sh`
  - `dev_container_test.py` to `/workspace/dev_container_test.py`
- `build_image.sh` builds `quay.io/m0ranmcharles/fedora_init:dev-env`.
- `push_images.sh` pushes `quay.io/m0ranmcharles/fedora_init:dev-env`.
- `01_build_image/build_assets/os-builder.sh` builds and optionally saves `dev-env` as `dev-env.tar`.
- `agent_quadlet/agent-dev-env.container.tmpl` includes:

  ```ini
  AddDevice=nvidia.com/gpu=all
  ```

- New tenant policies default `allowed_images.environments` to:

  ```text
  quay.io/m0ranmcharles/fedora_init:dev-env
  ```

  This is true in both:
  - `platformctl.sh`
  - `openclaw-provisioner.py` `DEFAULT_POLICY`

- `openclaw-runtime-router.py` help text now shows `:dev-env` as the create-agent environment example.
- `nvidia-cdi-refresh.service` now forces:

  ```ini
  ExecStartPost=/usr/bin/chmod 0755 /etc/cdi
  ExecStartPost=/usr/bin/chmod 0644 /etc/cdi/nvidia.yaml
  ```

  Known intent: tenant service accounts should be able to read the CDI spec, while only root can replace it.

- Docs were updated to describe the tenant dev environment as the current default agent environment and the legacy `devpod` as a fallback until rootless CDI is proven on NVIDIA hardware.

## Validation completed in this session

These checks passed:

```bash
git ls-files '*.sh' -z | xargs -0 -r bash -n
python3 -m py_compile 01_build_image/build_assets/dev_container_test.py 01_build_image/build_assets/multi_tenant/openclaw-provisioner.py
git diff --check
```

The docs internal link check from `docs/contributing.md` passed with `OK`.

The forbidden terminology grep from `docs/contributing.md` passed cleanly for the checked paths:

```bash
grep -rn '\bbootc image\b\|\bOS image\b' docs/concepts docs/reference docs/how-to docs/overview.md docs/README.md
```

The citation-marker check is known to flag existing literal examples in:

- `docs/DOCS_PLAN.md`
- `docs/contributing.md`

Those were not introduced by this work. A narrower grep excluding those files produced no findings.

The `dev-env` image built successfully:

```bash
podman build -t quay.io/m0ranmcharles/fedora_init:dev-env \
  -f 01_build_image/build_assets/multi_tenant/dev-env.Containerfile \
  01_build_image/build_assets
```

A no-GPU container smoke test passed:

```bash
podman run --rm --entrypoint python3 \
  quay.io/m0ranmcharles/fedora_init:dev-env \
  /workspace/dev_container_test.py
```

Observed result:

```text
torch_version=2.11.0a0+a6c236b9fd.nv26.03.46836102
cuda_available=False
```

This proves the image starts and PyTorch imports on this machine. It does not prove GPU access.

The host image built successfully:

```bash
podman build -t gpu-bootc-host:tenant-dev-env-check \
  -f 01_build_image/build_assets/Containerfile \
  01_build_image/build_assets
```

The built host image was checked for the updated template and policy defaults:

```bash
podman run --rm --entrypoint /usr/bin/grep \
  gpu-bootc-host:tenant-dev-env-check \
  -n 'AddDevice=nvidia.com/gpu=all' \
  /var/lib/openclaw-platform/templates/agent_quadlet/agent-dev-env.container.tmpl

podman run --rm --entrypoint /usr/bin/grep \
  gpu-bootc-host:tenant-dev-env-check \
  -n 'quay.io/m0ranmcharles/fedora_init:dev-env' \
  /usr/local/bin/platformctl /usr/local/bin/openclaw-provisioner
```

Both checks found the expected content.

## What was not done

### Rootless tenant GPU validation was not performed

What was not done:

- No tenant was created on a machine with NVIDIA hardware.
- No agent pod was started under a tenant service account with the new `dev-env` image.
- No rootless tenant container ran `nvidia-smi`.
- No rootless tenant container ran `python3 /workspace/dev_container_test.py` with CUDA expected to be available.
- No confirmation was made that `AddDevice=nvidia.com/gpu=all` works for a rootless Podman `.container` Quadlet on the deployed host.

Why:

- The user explicitly said GPU testing will not be done at this point.
- The current machine/session did not validate against real NVIDIA hardware.
- The original implementation plan marked this as a hardware gate.

Known facts:

- The rendered template now contains `AddDevice=nvidia.com/gpu=all`.
- The project previously used the `.kube` Quadlet path for the system `devpod`, with CDI requested through Kubernetes `resources.limits`.
- The proposal called out uncertainty about rootless `.container` CDI behavior and named rootless GPU validation as the gate.
- This session did not research official Podman or NVIDIA documentation to settle whether this exact `.container` syntax is officially supported.

Next session should:

- Research the current official Podman Quadlet documentation for `.container` `AddDevice=`.
- Research the current official Podman CDI device selector documentation.
- Research the current official NVIDIA Container Toolkit CDI documentation.
- Decide whether `AddDevice=nvidia.com/gpu=all` is documented and appropriate for rootless Quadlet containers.
- If official docs do not support this shape, replace it before hardware testing with a design that is supported by official docs.

### The legacy system `devpod` was not removed

What was not done:

- `01_build_image/build_assets/devpod.kube` was not deleted.
- `01_build_image/build_assets/devpod.yaml` was not deleted.
- `01_build_image/build_assets/dev-container.Containerfile` was not deleted.
- The host `Containerfile` still copies `devpod.kube` and `devpod.yaml` into `/usr/share/containers/systemd/`.
- `build_image.sh` still builds `quay.io/m0ranmcharles/fedora_init:dev-container`.
- `push_images.sh` still pushes `quay.io/m0ranmcharles/fedora_init:dev-container`.
- Docs still describe `devpod` and `dev-container` as a legacy fallback.

Why:

- The original plan explicitly said to retire `devpod` only after rootless tenant GPU validation passes on NVIDIA hardware.
- That validation was not performed.
- Removing `devpod` now would remove the known fallback path before the new path is proven.

Known facts:

- The system dev pod is still present and built into the host image.
- The tenant dev environment is now the default for newly created tenant agent policies.
- The repository is currently in a transitional state: tenant agent `dev-env` is preferred, system `devpod` remains as fallback.

Next session should:

- Keep `devpod` until either hardware validation passes or an officially documented tenant GPU path replaces the current template line.
- After validation passes, remove `devpod.kube`, `devpod.yaml`, and `dev-container.Containerfile`.
- After removal, update:
  - host `Containerfile`
  - `build_image.sh`
  - `push_images.sh`
  - `bootc_host_test.sh`
  - `docs/reference/images.md`
  - `docs/reference/quadlets.md`
  - `docs/reference/systemd_units.md`
  - `docs/reference/repository_layout.md`
  - GPU validation docs and any remaining references.

### `bootc_host_test.sh` was not changed to perform tenant GPU validation

What was not done:

- The old `systemctl status devpod.service --no-pager || true` smoke check remains.
- No tenant-specific GPU validation was added to `bootc_host_test.sh`.
- No automated check creates a tenant, creates an agent, starts a tenant dev environment, or runs `nvidia-smi`.

Why:

- Tenant GPU validation depends on NVIDIA hardware and on proving the rootless CDI path.
- The original plan says to replace the `devpod.service` smoke check after tenant GPU validation passes.
- An automatic boot smoke test that creates tenants/agents would be stateful and more invasive than the current host-level smoke test.

Known facts:

- The current boot smoke test still reports host GPU/CDI status and legacy `devpod.service` status.
- Docs now describe manual tenant GPU validation in `docs/how-to/validate_gpu.md`.

Next session should:

- Decide what `bootc_host_test.sh` should check before `devpod` removal.
- A careful next step may be to make `bootc_host_test.sh` report:
  - `nvidia-cdi-refresh.service` state
  - `/etc/cdi/nvidia.yaml` presence and permissions
  - whether the agent dev-env template contains GPU injection
  - a message pointing to tenant GPU validation docs
- Avoid auto-creating tenants or agents at boot unless that becomes an explicit design decision.

### Official documentation research was not performed

What was not done:

- No official Podman docs were checked during this session.
- No official NVIDIA Container Toolkit docs were checked during this session.
- No official systemd/Quadlet docs were checked during this session.

Why:

- The session focused on implementing the previous plan and validating build/static behavior.
- The user now wants the next session to handle research, planning, and validation from this detailed handoff.

Known facts:

- The current implementation uses `AddDevice=nvidia.com/gpu=all` because that was specified by the prior plan.
- The prior proposal itself called out that `.container` CDI selector support was the key technical unknown.
- The repository's legacy path uses `.kube` plus Kubernetes `resources.limits` for `nvidia.com/gpu=all`.

Next session should:

- Treat `AddDevice=nvidia.com/gpu=all` as an unvalidated implementation detail until official docs confirm it.
- If official docs say `AddDevice=` only supports host device paths, do not ship this as the final design.
- If official docs support CDI names/selectors in `AddDevice=`, document the exact source and then proceed to hardware validation when possible.

### Per-agent `.kube` fallback was not implemented

What was not done:

- No per-agent Kubernetes YAML template was added.
- No provisioner logic was added to render per-agent `.kube` Quadlets.
- No fallback path using Kubernetes `resources.limits[nvidia.com/gpu=all]: 1` was implemented for tenant agents.

Why:

- The previous plan first attempted the simpler `.container` `AddDevice=` path.
- Without official-doc research or hardware validation, it was premature to implement a larger provisioner/template change.

Known facts:

- The existing system `devpod.yaml` uses the Kubernetes resource selector shape:

  ```yaml
  resources:
    limits:
      nvidia.com/gpu=all: 1
  ```

- The existing system `devpod.kube` points Quadlet at that YAML file.
- The provisioner currently renders `.pod` and `.container` templates for agent pods.

Next session should:

- Research whether a rootless per-agent `.kube` Quadlet is the better officially documented tenant path.
- If chosen, design the smallest provisioner/template change needed to render a per-agent `.kube` unit and YAML manifest.
- Be careful with naming, cleanup, and lifecycle parity with the current `.pod` + `.container` templates.

### Explicit `/dev/nvidia*` device mapping fallback was not implemented

What was not done:

- No code generates explicit `AddDevice=/dev/nvidia*` mappings.
- No code maps NVIDIA userspace libraries into tenant containers.
- No device-discovery script was added.

Why:

- Explicit device mapping was listed as a fallback only if CDI selector injection fails.
- It is riskier than CDI because GPU library injection and device list completeness must be validated carefully.

Known facts:

- The host image installs `nvidia-container-toolkit` and generates `/etc/cdi/nvidia.yaml`.
- CDI is intended to describe devices and required mounts dynamically from the actual host.

Next session should:

- Prefer CDI if official docs and validation support it.
- Only consider explicit `/dev/nvidia*` mappings after CDI options are ruled out.
- If explicit mappings are chosen, research what NVIDIA libraries and device nodes are required and use official NVIDIA documentation as the source.

### `dev-env` was not pushed to Quay

What was not done:

- `podman push --format v2s2 quay.io/m0ranmcharles/fedora_init:dev-env` was not run.
- The complete `push_images.sh` script was not run.

Why:

- Pushing changes remote registry state.
- The user did not explicitly ask this session to publish images.

Known facts:

- The local `dev-env` image exists and built successfully.
- New tenant policies now point at `quay.io/m0ranmcharles/fedora_init:dev-env`.
- A released host image with these policy defaults assumes `:dev-env` exists in Quay.

Next session should:

- Push `:dev-env` before publishing or deploying a host image that defaults tenant policies to `:dev-env`.
- Verify the tag exists in Quay before releasing the host image.
- Consider whether `push_images.sh` order should make `dev-env` push happen before the host image push. It currently pushes `dev-container`, `os-builder`, tenant images including `dev-env`, then the host image.

### Full `./build_image.sh` was not run end-to-end

What was not done:

- The full top-level `./build_image.sh` was not run.

Why:

- The session separately built the new `dev-env` image and the host image, which are the most relevant changed build surfaces.
- Running the full script would rebuild many images already unrelated to the tenant GPU change.

Known facts:

- `dev-env` built successfully.
- The host image built successfully.
- Shell syntax validation passed for `build_image.sh`.

Next session should:

- Run `./build_image.sh` before a release candidate if time and disk space allow.
- Confirm all images listed by the script are produced.

### The host image was not tagged as `gpu-bootc-host:latest` or `:latest`

What was not done:

- The successful host build used a validation tag:

  ```text
  gpu-bootc-host:tenant-dev-env-check
  ```

- It did not overwrite:
  - `gpu-bootc-host:latest`
  - `quay.io/m0ranmcharles/fedora_init:latest`

Why:

- This was a validation build, not a release build.

Known facts:

- The host Containerfile can build with the changed files.
- The validation tag contains the expected template and policy defaults.

Next session should:

- Use `./build_image.sh` or an intentional `podman build` command when ready to update release tags.

### Runtime tenant provisioning flow was not exercised

What was not done:

- No tenant was created with `platformctl tenant create`.
- No agent was created with `platformctl agent create`.
- No rendered agent files were inspected on a live host.
- No `systemctl --user --machine=tenant_<tenant>@ ...` commands were run.

Why:

- This workspace validated image build artifacts, not a booted host with systemd/user managers.
- Runtime validation belongs on a deployed host or VM.

Known facts:

- The built host image includes the updated source files.
- The policy/template content is present in the image.

Next session should:

- On a booted host or VM, create a tenant and inspect the generated `policy.yaml`.
- Confirm new tenant policy contains only `:dev-env` under `allowed_images.environments`.
- Create a test agent and inspect the rendered `agent-dev-env.container`.
- Confirm the rendered file contains `AddDevice=nvidia.com/gpu=all`.
- If no GPU testing is allowed, stop there and document that runtime rendering works but GPU access remains unvalidated.

### Existing tenants are not migrated

What was not done:

- No migration logic updates existing tenant `policy.yaml` files from `:onboarding-env` to `:dev-env`.
- No tool rewrites existing agents that were created with `:onboarding-env`.

Why:

- The code change affects new tenant default policy rendering and the provisioner's fallback default policy.
- Existing tenant state lives under `/var/lib/openclaw-platform/tenants/<tenant>/policy/policy.yaml` and is deployment-time mutable state.

Known facts:

- `platformctl tenant create` writes a policy file at tenant creation time.
- The provisioner reads the tenant policy file on each `agent_create`.
- Existing policies will keep whatever was previously written unless an admin edits them.

Next session should:

- Decide whether a migration helper is needed.
- At minimum, document an admin procedure:

  ```bash
  sudo sed -i \
    's#quay.io/m0ranmcharles/fedora_init:onboarding-env#quay.io/m0ranmcharles/fedora_init:dev-env#g' \
    /var/lib/openclaw-platform/tenants/<tenant>/policy/policy.yaml
  ```

- Be careful: do not blindly edit all tenants unless that is an explicit operational decision.

### Tests for policy defaults were not added

What was not done:

- No unit tests were added for `platformctl.sh` policy rendering.
- No unit tests were added for `openclaw-provisioner.py` `DEFAULT_POLICY`.
- No test asserts `agent-dev-env.container.tmpl` contains GPU injection.

Why:

- The repository currently has no CI suite or established unit test harness for these scripts.
- Validation was done through static checks, image build checks, and grep checks against the built host image.

Known facts:

- The repository's documented validation model is mostly static checks plus runtime smoke tests.

Next session should:

- Consider adding small shell/Python checks if a lightweight test pattern exists or is desired.
- A simple future check could verify:
  - `platformctl.sh` policy heredoc contains `:dev-env`
  - `openclaw-provisioner.py DEFAULT_POLICY` contains `:dev-env`
  - `agent-dev-env.container.tmpl` contains `AddDevice=nvidia.com/gpu=all`

### `os-builder.sh` was not runtime-tested inside `os-builder`

What was not done:

- `os-builder.sh` was not run inside the `os-builder` container.
- `SAVE_ALL=1` behavior was not exercised.

Why:

- The host image and dev-env image were built directly.
- Running the scheduled update builder requires a source repo and output directory workflow beyond the local build validation done here.

Known facts:

- Shell syntax validation passed.
- The script now points to `multi_tenant/dev-env.Containerfile`.
- The top-level build proved that `multi_tenant/dev-env.Containerfile` can build with `01_build_image/build_assets` as context.

Next session should:

- Run the os-builder path before relying on scheduled updates for this change.
- Specifically test `SAVE_ALL=1` and confirm `dev-env.tar` is written.
- Decide whether downstream tooling expects the old `dev.tar` name. If anything consumes `dev.tar`, update it or preserve compatibility.

### Documentation was updated, but not all legacy docs were modernized

What was not done:

- Legacy docs such as `docs/DOCS_PLAN.md` and `docs/README.legacy.md` were not updated.
- Root-level historical notes were not updated.

Why:

- `docs/contributing.md` says root-level Markdown files are legacy whiteboard notes unless explicitly requested.
- `DOCS_PLAN.md` and `README.legacy.md` are excluded from the link-check script.

Known facts:

- Current canonical docs under `docs/concepts`, `docs/reference`, `docs/how-to`, and `docs/overview.md` were updated where directly relevant.

Next session should:

- Avoid using legacy docs as source of truth unless explicitly asked.
- If a future cleanup removes or rewrites legacy docs, do it as a separate documentation task.

## Known repo/worktree notes

These untracked files existed before or outside the implementation work and were not touched:

- `error.log`
- `run_codex_cloud_proposal_parts.py`

This handoff file is newly added:

- `tenant-gpu-dev-handoff.md`

## Recommended next-session sequence

This is not a final plan; it is a sequence grounded in what is currently known.

1. Read this handoff and inspect the actual changed files.
2. Research official docs for:
   - Podman Quadlet `.container` `AddDevice=`
   - Podman CDI selector support
   - NVIDIA Container Toolkit CDI usage
   - rootless Podman + CDI constraints, if documented
3. Decide whether `AddDevice=nvidia.com/gpu=all` is officially supported.
4. If officially supported, keep the current template and prepare non-GPU runtime rendering checks.
5. If not officially supported, replace the template approach before release:
   - likely with per-agent `.kube` templates if official docs support CDI selectors there
   - or another documented CDI mechanism
6. Run a booted-host or VM test without GPU if GPU is still unavailable:
   - create tenant
   - inspect generated policy
   - create agent
   - inspect rendered `agent-dev-env.container`
   - confirm service naming and template rendering
7. Push `:dev-env` before publishing any host image that defaults tenants to it.
8. Run full `./build_image.sh` before release if resources allow.
9. Keep `devpod` until actual NVIDIA hardware validation proves the tenant path.

