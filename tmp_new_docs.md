
--- START OF FILE: ./docs/DOCS_PLAN.md ---
# Docs Plan — Structure and Content Guidance

This document is the build instruction for a from-scratch rewrite of the
project docs. It sets the structure, the role of each document, the rules
that keep the set coherent, and an explicit mapping from existing source
material to the new destinations.

The model executing this plan should treat it as the single source of truth
for *what to write and where*. The existing `.md` files in the repo root and
`docs/README.md` are raw material — mine them, but do not preserve their
shape. Most of them mix registers (polished prose + scratch notes + checklists
+ open questions in the same file) and duplicate each other heavily. The
rewrite's job is to consolidate.

---

## 1. Diagnosis of the current state

What's already good and should be preserved as content:
- A clear **3-layer mental model** (host owns boot/hardware, container owns
  workload, Quadlet bridges them) — already well articulated across several
  files.
- A worked-out **GPU integration story** with rationale — `nvidia-open` +
  `nvidia-container-toolkit` on host, CUDA/cuDNN/PyTorch in container, CDI
  generated at boot, `.kube` Quadlet chosen over `.container` for documented
  CDI selectors.
- A coherent **ostree/bootc storage and update model** — content-addressed
  store, `/usr` immutable, `/etc` 3-way merged, `/var` persistent, ephemeral
  build → RAM-disk → `bootc switch` pipeline.
- A real **access matrix** (local container exec, build-and-run VM with
  injected key, downstream cloud-init NoCloud seed).
- An honest **roadmap** (the 24-item checklist) and **open questions** list.

What's wrong:
- **Massive duplication.** The ownership model is restated in
  `process_separation_model.md`, `README.md`, `bootc_and_container_build.md`,
  and `pieces_of_design_and_techimplementation.md`. The GPU story is split
  across `where_nvidia_belongs.md`, `gpu_integration_path.md`, and
  `explanaition_of_gpu_integration_path.md`. The bootc/ostree story is split
  across `ostree_notes.md`, `ostree_architecture.md`, and
  `immutable_os_deployment_pipeline.md`.
- **Mixed registers in single files.** `README.md` is simultaneously a
  whitepaper, a how-to, a roadmap, an open-questions log, and an
  architecture explainer. `bootc_and_container_build.md` (1179 lines) is a
  long-form scratch pad with successive revisions stacked on top of each
  other.
- **No on-ramp.** Nothing tells a new reader where to start.
- **No reference layer.** Nothing in the docs describes what each file in
  the repo actually *is* — `build_image.sh`, `devpod.kube`,
  `nvidia-cdi-refresh.service`, etc. The information exists in CLAUDE.md and
  scattered prose, but not as a reference.
- **Aspirational vs. current state are blended.** The README's "current
  implementation" section describes the OLD USB-flash workflow being
  replaced, and the new bootc workflow is described in the same prose. A
  reader can't tell what is built today vs. planned.

---

## 2. Top-level structure

```
docs/
├── README.md             # landing page + map; not content
├── overview.md           # 2-page "what this project is"
├── concepts/             # the "why" — design, architecture, mental models
├── reference/            # the "what" — close to the source files
├── how-to/               # the "do" — task-oriented procedures
├── roadmap.md            # planned work + open questions
└── DOCS_PLAN.md          # this file (delete after the rewrite is accepted)
```

One-line purpose for each:

| Path | Purpose | Audience | Voice |
|---|---|---|---|
| `README.md` | Map of the docs. Links out to everything. No prose explanations. | First-time visitor | Index |
| `overview.md` | What the project is, the 3-layer model, the one-sentence rationale for bootc. | First-time visitor | Pitch |
| `concepts/` | Decisions and the reasoning behind them. Stable across implementations. | Future-self, contributors | Explanatory |
| `reference/` | Catalog of the actual artifacts in the repo. Updated when files change. | Anyone editing the code | Descriptive |
| `how-to/` | Recipes for specific tasks. Each doc answers one question. | Operator running the pipeline | Imperative |
| `roadmap.md` | Checklist of remaining work + open questions. | Author + collaborators | Planning |

The split between `concepts/`, `reference/`, and `how-to/` is the load-bearing
choice. It is borrowed from Diátaxis (concepts ≈ explanation, reference ≈
reference, how-to ≈ how-to). Tutorials are deliberately omitted — this is an
infrastructure project, not a product with an onboarding curriculum.

---

## 3. Mid-level content plan

### `docs/README.md` (index, ~50 lines)

Purpose: hand the reader a map. Three sections only:

1. **Start here** — link to `overview.md`.
2. **By role** — three short bullet lists:
   - "I want to use the published image" → `how-to/distribute_image.md`,
     `concepts/access_model.md`.
   - "I want to build and test locally" → `how-to/build_images.md`,
     `how-to/build_and_run_vm.md`, `how-to/validate_gpu.md`.
   - "I want to understand why it's built this way" → `overview.md`,
     `concepts/`.
3. **Full index** — flat list of every doc with a one-line description.

No architecture diagrams, no rationale prose, no code samples in this file.

### `docs/overview.md` (~2 pages)

Single coherent pitch. Sections:
- **What this is** — one paragraph: bootc-based GPU workstation, immutable
  host, containerized workloads, weekly rebuild pipeline.
- **The 3-layer model** — one short diagram (the one in
  `gpu_integration_path.md` is the right shape) plus one paragraph each on
  host / container / Quadlet ownership.
- **What's built today vs. planned** — two short lists. Today: host image
  builds, dev+backup pod, VM build path, Quay push, GPU CDI plumbing.
  Planned: scheduled rebuild pipeline, btrfs-based state persistence, cloud
  backup, system wipe-and-restore. Link to `roadmap.md` for the full list.
- **Where to go next** — three links by role (same as `README.md`'s "by
  role" section, but in prose).

### `docs/concepts/` (the "why" — 6 documents)

Each concept doc follows this shape:
- **What** — one paragraph, the decision in plain English.
- **Why** — the load-bearing reasons. Name the alternative. Don't restate
  the alternative's full case; say what it would have given up.
- **Implications** — what this commits the rest of the project to.
- **See also** — links to relevant `reference/` and `how-to/` docs.

Cap each at ~3 pages. If a concept is sprawling, split it.

| File | Covers | Consolidates |
|---|---|---|
| `concepts/ownership_model.md` | Host vs. container vs. Quadlet split. The "who owns this?" decision rule. | `process_separation_model.md` (most of it), the duplicate restatements in `README.md` and `bootc_and_container_build.md` |
| `concepts/bootc_and_ostree.md` | What bootc is. How ostree stores files (content-addressed, hardlinks, deltas). The `/usr` immutable / `/etc` merged / `/var` persistent split. `rpm-ostree` vs. `dnf` tradeoffs. | `ostree_notes.md` §"bootc's mutability model", `ostree_architecture.md`, the relevant slice of `README.md` |
| `concepts/update_pipeline.md` | The ephemeral-build → RAM-disk → `bootc switch` pipeline. Why builds happen in a container. Why the artifact never touches disk. Rollback semantics. | `immutable_os_deployment_pipeline.md`, the "scheduled update pipeline" section of `README.md` |
| `concepts/gpu_stack.md` | Where each NVIDIA piece lives (host: `nvidia-open` + toolkit; runtime: CDI; container: CUDA/cuDNN/framework). The `.kube` vs. `.container` Quadlet choice for CDI selectors. The DKMS-at-build-time risk. | `where_nvidia_belongs.md`, `gpu_integration_path.md`, `explanaition_of_gpu_integration_path.md` |
| `concepts/state_and_persistence.md` | The Category 1–4 model (transient → ws-env-persistent → host-persistent → cloud). Where btrfs send/receive fits. What `bootc upgrade` preserves. | The "process for wiping system post-bootc" section of `README.md`, the persistence-related fragments scattered through `ostree_notes.md` |
| `concepts/access_model.md` | The keyless OCI image. Three access paths: local container exec, VM with injected key, downstream cloud-init seed. Console-autologin recovery fallback. Why credentials are deployment-time, not image-time. | The "Access" section of `README.md`, the SSH discussion in `ostree_notes.md` |

### `docs/reference/` (the "what" — 6 documents)

These are catalogs. They describe artifacts that exist in the repo today.
They should be updated whenever the corresponding files change. Voice:
descriptive, terse, factual.

Each reference doc follows this shape:
- One section per artifact.
- For each: **Path**, **Purpose** (1 sentence), **Key fields/flags**,
  **Depends on**, **Notes** (only if non-obvious).
- Code snippets are excerpts only — point readers at the real file rather
  than reproducing it.

| File | Covers |
|---|---|
| `reference/repository_layout.md` | Top-level tree of the repo. One line per directory and per top-level script. Where to look for what. |
| `reference/images.md` | The three images: `gpu-bootc-host`, `dev-container`, `backup-container`. Base images, what each adds, Quay tags, what's baked in vs. pulled at runtime. |
| `reference/systemd_units.md` | Every unit baked into the host image: `bootc-host-test.service`, `nvidia-cdi-refresh.service`, `nvidia-cdi-refresh.path`, `autologin.conf`, plus the units enabled by default (`sshd`, `cloud-init.target`). Order of activation at boot. |
| `reference/quadlets.md` | `devpod.kube` and `devpod.yaml`. Field-by-field explanation. The `nvidia.com/gpu=all` resource selector. Where systemd-generated units land. |
| `reference/scripts.md` | Every shell script: `build_image.sh`, `run_container.sh`, `push_images.sh`, `02_build_vm/build_vm.sh`, `02_build_vm/run_vm.sh`. For each: what it does, env vars (`SSH_PUB_KEY_FILE`, `VM_NAME`, `IMAGE_NAME`), preconditions, side effects (touches `/var/lib/libvirt/images`, edits `~/.ssh/config`, etc.). |
| `reference/registry.md` | Quay account setup, encrypted CLI password flow, image tagging convention, why `--format v2s2`. | Consolidates `quay_repository.md`. |

### `docs/how-to/` (the "do" — 6–7 documents)

Each how-to answers one question with a numbered procedure. No theory —
link to `concepts/` for that. Voice: imperative, second-person.

Shape:
- **Goal** (one sentence)
- **Prerequisites**
- **Steps** (numbered, copy-pasteable commands)
- **Verify** (the one command that proves it worked)
- **Troubleshooting** (only known failures, not speculative ones)

| File | Question it answers |
|---|---|
| `how-to/build_images.md` | "How do I build all three container images locally?" |
| `how-to/run_locally.md` | "How do I poke at the host image without booting a VM?" |
| `how-to/build_and_run_vm.md` | "How do I build a qcow2 from the host image and SSH into it?" |
| `how-to/push_to_quay.md` | "How do I publish images to Quay?" |
| `how-to/distribute_image.md` | "I want to give someone else the published image. How do they boot it with their own SSH key?" (cloud-init NoCloud seed) |
| `how-to/validate_gpu.md` | "How do I confirm GPU passthrough end-to-end?" (nvidia-smi → CDI spec → pod → torch.cuda) |
| `how-to/write_a_systemd_unit_for_the_host.md` | "I want to run something at host boot. Where does it go?" (Pulls together the `bootc_init_cmd.md` content: why CMD/ENTRYPOINT don't work, oneshot units, `ConditionFirstBoot=yes`, where to drop the file, how to enable it.) |

### `docs/roadmap.md` (~1 page)

Three sections, in this order:
1. **Built today** — short bullet list of what works.
2. **Planned** — the 24-item checklist from `README.md`, regrouped under
   the original headings (`base`, `flash system`, `base image build
   structure`, `enhance testing`, `system wipe/build/use/backup/recovery`).
   Each item one line.
3. **Open questions** — the bulleted block currently at lines 200–217 of
   `README.md`. Each question on its own bullet, no prose around it.

This file is allowed to be loose — it's a planning artifact, not reference.

---

## 4. Cross-cutting rules

These apply to every doc the rewrite produces. Treat them as hard constraints.

1. **One canonical home per topic.** The ownership model lives in
   `concepts/ownership_model.md` and nowhere else. Other docs link to it.
   If you find yourself restating it, stop and link instead.
2. **Distinguish current from planned.** Concept docs describe the
   *intended* model and may include planned pieces, but must mark them
   `(planned)` inline. Reference docs describe only what is currently in the
   repo. How-to docs describe only procedures that work today.
3. **Code excerpts are illustrative, not authoritative.** When a doc shows
   the contents of `devpod.kube`, it is showing the shape, not the file.
   Always include a path and a "see the file in the repo for the
   authoritative version" pointer. This avoids drift.
4. **Linkable section headings.** Every meaningful concept gets its own
   `##` or `###` heading so other docs can deep-link to it.
5. **No essays.** The existing source docs contain a lot of "let me walk
   you through this comparison" prose. Compress: state the decision, name
   the alternative in one sentence, give one paragraph of rationale. If a
   reader needs the full comparison, they can read the source repo's git
   history.
6. **No nested decisions inside how-to.** A how-to with "if X, do A;
   otherwise do B" is signal that the decision belongs in `concepts/` and
   the how-to should branch into two files.
7. **Drop the Gemini citation noise.** The `[cite_start]...[cite: 65, 466]`
   markers in `ostree_architecture.md` are an artifact of an export, not
   real citations. Strip them.
8. **Consistent terminology.** Pick one name per concept and use it
   everywhere:
   - "host image" (not "bootc image" or "OS image" — the others are
     ambiguous).
   - "dev pod" for the `devpod` Quadlet's pod.
   - "dev container" for the GPU/PyTorch container inside the pod.
   - "backup sidecar" for the placeholder backup container.
   - "Quay" for the registry, "the registry" only when generic.
9. **Don't promote CLAUDE.md or GEMINI.md content into docs verbatim.** Those
   are agent-context files. Their content can inform docs, but the docs
   themselves should not refer to them.

---

## 5. Source-to-destination mapping

This table tells the rewriter exactly where each existing piece of content
goes. Sources appear in multiple rows where they cover multiple topics.

| Source file | Section / topic | Destination |
|---|---|---|
| `docs/README.md` | "goal, purpose" + "current implementation" + "implementation we are building" | `overview.md` (compressed); `concepts/update_pipeline.md` (the pipeline subsection) |
| `docs/README.md` | "Access" section + access table | `concepts/access_model.md`; how-to specifics split into `how-to/build_and_run_vm.md` and `how-to/distribute_image.md` |
| `docs/README.md` | "Checklist/Plan" 24 items | `roadmap.md` |
| `docs/README.md` | "open questions" block | `roadmap.md` |
| `docs/README.md` | "process for wiping system post-bootc" + Category 1–4 | `concepts/state_and_persistence.md` |
| `docs/README.md` | "Surface" + "Workflow" + "bootc image breakdown" sections | merged into `concepts/ownership_model.md` and `concepts/update_pipeline.md`; example Containerfile/Quadlet snippets become illustrative excerpts in `reference/images.md` and `reference/quadlets.md` |
| `process_separation_model.md` | All of it | `concepts/ownership_model.md` (compress aggressively — the source is ~500 lines of repeated framing; target ~150 lines) |
| `ostree_notes.md` | "bootc's mutability model" | `concepts/bootc_and_ostree.md` |
| `ostree_notes.md` | "three main patterns" | `concepts/ownership_model.md` |
| `ostree_notes.md` | "What you may not be considering" | `concepts/state_and_persistence.md` (the `/etc` vs `/var` discipline note); the `bootc switch` and `podman auto-update` notes go into `concepts/update_pipeline.md` |
| `ostree_architecture.md` | All of it (strip cite markers) | `concepts/bootc_and_ostree.md` |
| `immutable_os_deployment_pipeline.md` | All of it | `concepts/update_pipeline.md` |
| `where_nvidia_belongs.md` | All of it | `concepts/gpu_stack.md` |
| `gpu_integration_path.md` | All of it | `concepts/gpu_stack.md` (merge with `where_nvidia_belongs.md`); the validation commands go to `how-to/validate_gpu.md`; the DKMS risk goes to `concepts/gpu_stack.md` §"known risks" |
| `explanaition_of_gpu_integration_path.md` | All of it | `concepts/gpu_stack.md` §".kube vs .container" (single subsection, keep it tight) |
| `bootc_init_cmd.md` | "Why CMD/ENTRYPOINT don't apply" + systemd unit examples | `how-to/write_a_systemd_unit_for_the_host.md` |
| `bootc_init_cmd.md` | Quadlet placement + `[Install]` discussion | `reference/quadlets.md` (the placement rules) and `how-to/write_a_systemd_unit_for_the_host.md` (the auto-start recipe) |
| `quay_repository.md` | All of it | `reference/registry.md` (account setup, encrypted-password flow) and `how-to/push_to_quay.md` (the actual push procedure) |
| `bootc_and_container_build.md` | The "Two-artifact build" + "where to define startup actions" sections | `concepts/ownership_model.md` (already covered — use as a sanity check, do not duplicate) |
| `bootc_and_container_build.md` | "4-staged test build" + "Updated staged process" | `roadmap.md` (the staged validation plan is roadmap, not built today) — or drop entirely if subsumed by the existing checklist |
| `bootc_and_container_build.md` | Containerfile / dev-container / pod YAML excerpts | `reference/images.md`, `reference/quadlets.md` (excerpts only; real files in `01_build_image/build_assets/` are authoritative) |
| `pieces_of_design_and_techimplementation.md` | All of it | DELETE after the rewrite — this file is the author's first-pass plan; this DOCS_PLAN.md supersedes it |

---

## 6. Order of writing

Recommended order so each doc can link to the ones it depends on:

1. `concepts/bootc_and_ostree.md` (foundational; everything else assumes it)
2. `concepts/ownership_model.md`
3. `concepts/gpu_stack.md`
4. `concepts/update_pipeline.md`
5. `concepts/state_and_persistence.md`
6. `concepts/access_model.md`
7. `reference/repository_layout.md`
8. `reference/images.md`
9. `reference/systemd_units.md`
10. `reference/quadlets.md`
11. `reference/scripts.md`
12. `reference/registry.md`
13. `how-to/*` (any order)
14. `overview.md` (after concepts settle, so it can summarize accurately)
15. `roadmap.md`
16. `docs/README.md` (last — it indexes everything else)

After acceptance: delete the source `.md` files in the repo root and
`docs/README.md` (the current whitepaper version), delete
`pieces_of_design_and_techimplementation.md`, delete the empty
`docs/design/` and `docs/technical_implementation/` placeholder
directories, and delete this `DOCS_PLAN.md`.

---

## 7. Style notes

- Prefer short sentences and concrete nouns.
- Headings as statements, not questions ("Why CDI is generated at boot",
  not "Why is CDI generated at boot?").
- Code blocks are tagged with their language.
- Paths are in `inline code`. Section references are in `concepts/foo.md`
  form, not bare names.
- Diagrams: the few ASCII diagrams in the source files (the GPU stack tree
  in `gpu_integration_path.md`, the Quadlet indirection in
  `explanaition_of_gpu_integration_path.md`) are good — preserve their
  shape when migrating.
- No emojis.

--- START OF FILE: ./docs/concepts/ownership_model.md ---
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

Crucially, there is a strict **no in-container systemd** rule. The container command should run the workload, wait, or exit, but it must never run a service manager.

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

### Service patterns
When orchestrating workloads, there is a three-pattern taxonomy: single-app containers, multi-container pods, or user-pods. This project uses a **multi-container pod via Quadlet** to group the dev container and the backup sidecar into a single dev pod. This pattern provides a shared lifecycle and network namespace for tightly coupled services while keeping distinct operational roles in independently updatable containers distributed via Quay.

## See also
- `concepts/bootc_and_ostree.md`
- `concepts/gpu_stack.md`
- `concepts/update_pipeline.md`
- `reference/quadlets.md`
- `reference/systemd_units.md`
- `how-to/write_a_systemd_unit_for_the_host.md`

--- START OF FILE: ./docs/concepts/gpu_stack.md ---
# GPU stack

## What

The NVIDIA software split spans the host image, a runtime bridge, and the workload container. The host image carries the kernel module and toolkit, the runtime bridge generates dynamic device paths at boot, and the dev container holds the CUDA toolkit and machine learning frameworks.

## Why

The load-bearing reason for this split is hardware decoupling. The alternative is baking the toolkit into every container or putting CUDA on the host OS, both of which tie application lifecycles directly to hardware driver lifecycles.

## Implications

This layered split shapes the project by decoupling updates: the host image updates slowly for OS and driver changes, while the dev pod and its containers can iterate rapidly without modifying the underlying host.

## The stack diagram

```text
bootc host image
  ├─ nvidia-open                    # open kernel module + userspace driver libs
  ├─ nvidia-container-toolkit       # CDI generator + runtime bridge (nvidia-ctk)
  ├─ nvidia-cdi-refresh.service     # oneshot: nvidia-ctk cdi generate -> /etc/cdi/nvidia.yaml
  ├─ nvidia-cdi-refresh.path        # re-run the service when /dev/nvidiactl appears
  ├─ devpod.kube                    # Quadlet that starts the pod at boot
  └─ devpod.yaml                    # Pod manifest, one persistent dev pod with GPU access

workload container (pulled from Quay at pod start)
  └─ nvcr.io/nvidia/pytorch:26.03-py3   # CUDA + cuDNN + PyTorch
```

## What lives where, and why

### Host image

The kernel module and userspace driver libraries live in the host image via `nvidia-open`. These must match the running kernel and are tied directly to the hardware. The `nvidia-container-toolkit` also installs here to provide the `nvidia-ctk` CLI used for CDI generation.

### Runtime bridge

The CDI specification at `/etc/cdi/nvidia.yaml` maps actual device files and library paths for container injection. It is generated dynamically at boot by `nvidia-cdi-refresh.service` calling `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`. The companion `nvidia-cdi-refresh.path` unit re-runs generation when `/dev/nvidia*` device nodes change. CDI device mappings must come from real hardware, so they are never baked into the image.

### Workload containers

The CUDA toolkit, cuDNN, and ML frameworks live entirely inside the dev container (e.g., PyTorch in `nvcr.io/nvidia/pytorch:26.03-py3`). Only the userspace CUDA bits go here. The backup sidecar runs alongside it but does not require GPU tools.

## The Quadlet `.kube` vs. `.container` choice

The dev pod uses a `.kube` Quadlet referencing `devpod.yaml` instead of a `.container` Quadlet. Kubernetes-style pod manifests support requesting GPUs via the documented CDI device selector:

```yaml
resources:
  limits:
    nvidia.com/gpu=all: 1
```

*(See `01_build_image/build_assets/devpod.yaml` in the repo for the authoritative version.)*

Podman's `kube play` formally documents this selector syntax. A standard `.container` Quadlet relies on `AddDevice=`, which accepts direct device paths but lacks an equivalent stable selector mechanism for CDI.

## Known risks

### DKMS at build time

The `nvidia-open` package builds the kernel module via DKMS during `dnf install`, pinning against the bootc base image's running kernel. If the deployed host runs a different kernel, the module will not load. The fallback paths are either installing `kernel-devel` matching the base image's kernel, or swapping to RPM Fusion's `akmod-nvidia-open` to trigger the build at first boot.

### CDI selector syntax not validated

The `nvidia.com/gpu=all` resource key in `devpod.yaml` has not been validated end-to-end against current Podman and NVIDIA-toolkit versions. First boot on real GPU hardware is the validation point.

## See also

- `concepts/ownership_model.md`
- `reference/systemd_units.md`
- `reference/quadlets.md`
- `reference/images.md`
- `how-to/validate_gpu.md`

--- START OF FILE: ./docs/concepts/update_pipeline.md ---
# Update pipeline

## What

The scheduled update pipeline is an automated local process that rebuilds and stages a new host image without polluting the live filesystem. A timer (`bootc-update.timer`) periodically fires an orchestrator script (`bootc-update.sh`), which launches an ephemeral builder container (the prebuilt `os-builder` image, defined by `os-builder.Containerfile`). The builder clones the project repo into an ephemeral working directory inside the container, builds the host image (and its sibling images) with `podman build --no-cache --pull`, and writes the host image as an `oci-archive` tarball into `/run/bootc-update/host.tar` — a tmpfs path on the host (the service's `RuntimeDirectory`). The orchestrator then runs `bootc switch --transport oci-archive` to stage the archive as a parallel ostree deployment, and writes a pending marker (`/var/lib/bootc-update/pending`) that the login nudge picks up. A reboot activates the new deployment. (A fully remote CI orchestrator that performs these builds centrally is `(planned)`.)

Separately, `bootc-firstboot-push.service` runs on every boot but no-ops unless the operator has set `push_to_quay=TRUE` in `/etc/bootc-update/reboot.env` before rebooting into a freshly staged image. When the flag is set, it copies the booted image from container storage to Quay via `skopeo copy --format v2s2` and clears the flag. This is the bootstrap path for publishing a locally-validated image, gated on operator intent — not an automatic post-update sync.

## Why

We build in an ephemeral container and hand off via RAM-disk rather than performing in-place `dnf` upgrades or a standard `bootc upgrade` from a remote registry to guarantee the host remains clean of build tools while ensuring deterministic, network-resilient updates.

## Implications

### The host remains free of build dependencies
Heavy dependencies like package managers, DKMS, and CUDA repository metadata live exclusively inside the ephemeral builder container. The host system never installs or caches build-time tools.

### Build artifacts never touch physical disk
By routing the artifact through `/run` (tmpfs), the massive OCI archive and intermediate container layers never touch persistent storage. Only the byte-for-byte delta of modified files is written to the host's `/usr` partition during the `bootc switch` phase. Managing persistent `/var` state via btrfs snapshots during this process is `(planned)`.

### Rollbacks are instantaneous and safe
Because the compilation happens offline and the staging is atomic, the live system is never subjected to mid-air mutations. If an update introduces instability, the previous deployment remains perfectly intact. `bootc rollback` simply flips the active deployment pointer back to the previous set of hardlinks, restoring the older system state instantly upon reboot.

### Updates do not require an upstream registry
The local rebuild pipeline ensures the workstation can update itself without relying on external registries to compute the artifact. Once the locally built image proves successful by booting, the first-boot push mechanism synchronizes it back to Quay for other machines.

## See also

- `concepts/bootc_and_ostree.md`
- `concepts/ownership_model.md`
- `reference/systemd_units.md`
- `reference/scripts.md`
- `how-to/build_images.md`

--- START OF FILE: ./docs/concepts/state_and_persistence.md ---
# State and persistence

## What

The system categorizes state into four distinct levels of persistence, depending on whether it belongs to a running process, the workstation environment, the host machine, or off-host storage.

### Category 1: Transient
State that lives only inside running containers. This includes Python REPL sessions, scratch tensors, and `/tmp` files within the dev container. This state is intentionally lost on container restart. It requires no persistence policy.

### Category 2: Workstation-environment-persistent
State that should follow the dev pod environment but is independent of the host OS. Examples: editor settings inside the dev container, dotfiles for the dev pod user. The intent is for this to live in named Podman volumes attached to the dev pod so it survives container restarts. The dev pod manifest does not declare any volumes today, so this category is `(planned)`.

### Category 3: Host-persistent
State owned by the host machine. This includes SSH host keys, the machine ID, cloud-init seed-derived users, anything written to `/etc` after the first boot, and anything in `/var` (such as container storage for the dev container and the backup sidecar pulled from Quay). This state survives a `bootc upgrade` because of the ostree filesystem model.

### Category 4: Cloud-persistent
Irreplaceable state that must survive a complete machine wipe. This includes source code, trained models, and datasets. This state lives in remote storage, utilizing cloud backups pushed by the backup sidecar `(planned)`.

### The `/etc` versus `/var` discipline
The bootc host image enforces a strict filesystem model during updates:

- `/etc` is for configuration. It holds small, hand-edited files. During a `bootc upgrade`, changes here are preserved through a three-way merge between your local edits, the old image, and the new image.
- `/var` is for data. It holds larger, machine-written state like databases or Podman volumes. It is completely untouched and carried over during an upgrade.
- `/usr` is immutable and owned by the host image. Anything written here locally is lost on the next image update.

### What `bootc upgrade` preserves
When the scheduled update pipeline deploys a new host image, the upgrade process preserves:
- `/etc` (via three-way merge)
- `/var` (left untouched)
- Bootloader state
- Cryptographic identity

The upgrade process explicitly loses:
- Anything in `/usr` that is not part of the new host image
- Transient container state
- Kernel parameters set outside the image definition

### Where btrfs send and receive fits `(planned)`
We plan to use btrfs subvolumes to snapshot Category 2 state and selected Category 3 state. These snapshots will be shipped off-host using a pipeline like `btrfs send | ssh ... btrfs receive`. This provides a reliable wipe-and-restore mechanism for the workstation environment without bundling user state into the immutable host image.

## Why

Treating all state uniformly creates monolithic backups and fragile upgrades, so separating state by lifecycle allows us to wipe or update layers independently without losing critical data.

## Implications

The categorization dictates exactly what survives different lifecycle events.

| State category | Survives container restart | Survives `bootc upgrade` | Survives full machine wipe |
| --- | --- | --- | --- |
| Category 1 (Transient) | No | No | No |
| Category 2 (Workstation) | Yes | Yes | No |
| Category 3 (Host) | Yes | Yes | No |
| Category 4 (Cloud) | Yes | Yes | Yes |

## See also

- `concepts/bootc_and_ostree.md`
- `concepts/ownership_model.md`
- `concepts/access_model.md`
- `reference/quadlets.md`

--- START OF FILE: ./docs/concepts/access_model.md ---
# Access model

## What

The published bootc OCI image is intentionally keyless: no SSH keys, no passwords, and no per-user identity are baked into it. The credentials required to access the host system are injected at *deployment* time. 

This provides three primary access paths: local container execution, VM builds with injected SSH keys, and cloud-init NoCloud seeds for downstream users.

## Three access paths

### Local container exec

You can run the host image locally as an ephemeral container to explore its contents without network or SSH access.

```bash
./run_container.sh
```

This drops you into a root bash shell inside the host image on your development machine. No systemd, no SSH, and no services are running. It is purely for poking at installed packages and file layouts.

See `how-to/run_locally.md` for more details.

### VM with SSH key injected at qcow2 build

When testing the host image locally in a VM, the build script injects your personal SSH key directly into the VM's disk image.

```bash
./02_build_vm/build_vm.sh
./02_build_vm/run_vm.sh
```

`build_vm.sh` reads your public key (auto-detecting `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`, or via the `SSH_PUB_KEY_FILE` environment variable). It writes a `[[customizations.user]]` block into the `bootc-image-builder` config, so the resulting qcow2 includes the key for the `root` user. 

`run_vm.sh` boots the VM, detects its IP, and writes a `Host fedora-init` entry into your `~/.ssh/config` file. You can then connect immediately:

```bash
ssh fedora-init
```

See `how-to/build_and_run_vm.md` for more details.

### Cloud-init NoCloud seed (downstream users)

Downstream users pulling the published `quay.io/m0ranmcharles/fedora_init:latest` image provide their own SSH key by mounting a NoCloud datasource at first boot. The image enables `cloud-init.target` to support this out of the box.

The user creates a NoCloud seed (a cidata ISO with `user-data` and `meta-data`) containing their SSH key. On first boot, cloud-init picks up the seed and writes their key into root's `authorized_keys`.

See `how-to/distribute_image.md` for more details on building and attaching the NoCloud seed.

### Summary

| Scenario | Mechanism | Key source | First command |
|----------|-----------|------------|---------------|
| Poke at the image | `./run_container.sh` | None needed | `./run_container.sh` |
| Build + run VM locally | `build_vm.sh` + `run_vm.sh` | Your `~/.ssh/*.pub` (auto) | `ssh fedora-init` |
| Distribute pre-built binary | Cloud-init NoCloud seed | Recipient's own key | `ssh root@<ip>` |

## Console autologin recovery fallback

A console root autologin fallback is included for emergencies. `autologin.conf` is baked into the image as a getty drop-in, giving the root user an autologin on tty1. 

This exists purely for the case where SSH and cloud-init both fail at first boot, allowing you to get a shell on the console (e.g., via `virsh console`) to debug. Because it requires the virtual console and is not exposed over the network, it does not compromise the security of the published image.

## Why credentials are deployment-time, not image-time

The alternative to deployment-time credentials is baking an SSH key directly into the OCI image. We avoid this for several reasons:

1. **Security of the OCI artifact:** The OCI image is pushed to a public Quay namespace. Baking keys into it would either expose private key material to the internet or force every consumer to share a single, well-known identity.
2. **Multiple consumers:** Different consumers (the project author, downstream users, and future automated test machines) have different keys and identities.
3. **Platform standards:** Cloud-init is the standard, well-supported mechanism for injecting instance-specific metadata (like SSH keys) across virtualization and cloud platforms.

## Implications

- The image is safe to push publicly to Quay.
- Credentials are an operational concern of the deployment environment (the qcow2 build step, or the VM hypervisor), not a concern of the image build step.

## See also

- `concepts/ownership_model.md`
- `concepts/state_and_persistence.md`
- `reference/scripts.md`

--- START OF FILE: ./docs/concepts/bootc_and_ostree.md ---
# Bootc and OSTree

## What
This project uses **bootc** to deploy the host operating system as a bootable OCI container image. The host *is* the container. Underneath, it uses **OSTree**, which acts as a version-controlled, content-addressed object store for operating system binaries.

## Why
Deploying a pre-compiled image prevents the mid-air collisions that occur when updating live, running binaries. The alternative is a traditional mutable host managed by `dnf`, where complex dependencies like NVIDIA kernel modules are compiled dynamically via DKMS. If an upstream update fails to compile dynamically, the system can become unbootable. Shifting compilation to an ephemeral container build ensures the host only receives atomic, rollback-capable updates.

## Implications
Treating the host as a container commits the project to strict filesystem mutability rules and image-based update workflows.

### OSTree object store and delta updates
OSTree hashes every file in the deployed image (SHA256) and stores unique files in a central repository at `/sysroot/ostree/repo/objects/`. The bootable filesystem is constructed entirely of read-only hardlinks pointing to these objects.

When deploying a new image, OSTree downloads the OCI layers and stages the new tree alongside the current one without touching the active system. It writes only the byte-for-byte deltas (the changed files) to disk, creating hardlinks for unchanged files. Rollback is instant because it only requires updating the bootloader to point to the previous set of hardlinks.

### The `/usr`, `/etc`, and `/var` mutability split
The filesystem is divided into three persistence zones:

- `/usr` is immutable. It is owned by the image and replaced completely on updates. Any local modifications are destroyed.
- `/etc` is mutable and persistent. It receives a 3-way merge during updates, blending the new image's defaults with your local changes.
- `/var` is fully mutable and persistent. It survives updates unchanged.

This enforces strict state separation: binaries and unit files belong in the image (`/usr`), host configuration belongs in `/etc`, and persistent data belongs in `/var`.

### `rpm-ostree` vs. `dnf`
Because `/usr` is mounted read-only on the host, imperative `dnf install` commands do not work. Traditional `dnf` and DKMS are used exclusively inside the container build process to assemble the static image.

On the deployed host, package management is handled by image updates rather than live mutation.
- `bootc upgrade` fetches and stages the newest version of the current image.
- `bootc switch` changes the system to a different image or a local OCI archive.
- `bootc usroverlay` mounts a temporary, writable overlay over `/usr` for transient debugging. The overlay and any changes made within it are discarded on the next reboot.

## See also
- `concepts/ownership_model.md`
- `concepts/update_pipeline.md`
- `concepts/state_and_persistence.md`
- `reference/repository_layout.md`
- `how-to/build_images.md`

--- START OF FILE: ./docs/reference/repository_layout.md ---
# Repository layout

A descriptive catalog of the files and directories in this repository.

## Top-level tree

```text
.
├── 01_build_image/
│   └── build_assets/
├── 02_build_vm/
│   ├── _detect_ssh_key.sh
│   ├── build_vm.sh
│   └── run_vm.sh
├── docs/
│   ├── concepts/
│   ├── how-to/
│   ├── reference/
│   ├── technical_implementation/
│   ├── DOCS_PLAN.md
│   ├── overview.md
│   ├── README.md
│   └── roadmap.md
├── build_image.sh
├── push_images.sh
├── run_container.sh
├── CLAUDE.md
├── GEMINI.md
├── bootc_and_container_build.md
├── bootc_init_cmd.md
├── explanaition_of_gpu_integration_path.md
├── gpu_integration_path.md
├── immutable_os_deployment_pipeline.md
├── ostree_architecture.md
├── ostree_notes.md
├── pieces_of_design_and_techimplementation.md
├── process_separation_model.md
├── quay_repository.md
└── where_nvidia_belongs.md
```

## Top-level files

| File | Description |
| :--- | :--- |
| `build_image.sh` | Orchestrates the multi-stage build of the host image, dev container, and backup sidecar. |
| `run_container.sh` | Convenience script for running the host image as a local container for inspection. |
| `push_images.sh` | Tags and pushes the three project images to Quay. |
| `CLAUDE.md` | Agent context for Claude Code. Not user-facing documentation. |
| `GEMINI.md` | Agent context for Gemini. Not user-facing documentation. |
| `*.md` (other repo-root) | Pre-rewrite design notes and whiteboards. Canonical content is being migrated into `docs/concepts/`; treat the rewritten docs as authoritative once present. |

## Directories

### `01_build_image/`
Contains the logic for building the OCI images. The `build_assets/` subdirectory is separated to keep the build root clean and to scope the files injected into the images.

### `01_build_image/build_assets/`
The primary collection of artifacts baked into or used to build the project images.

**Containerfiles**
- `Containerfile`: Primary definition for the host image.
- `dev-container.Containerfile`: Definition for the dev container (GPU/PyTorch).
- `backup-container.Containerfile`: Definition for the placeholder backup sidecar.
- `os-builder.Containerfile`: Definition for the image used in the scheduled update pipeline.

**Systemd units**
- `bootc-firstboot-push.service`: Pushes the booted host image to Quay on first boot when `push_to_quay=TRUE` is set in `/etc/bootc-update/reboot.env`.
- `bootc-host-test.service`: Runs host-level validation tests.
- `bootc-update.service`: Unit that executes the system upgrade check.
- `bootc-update.timer`: Timer that schedules periodic update checks.
- `nvidia-cdi-refresh.service`: Generates CDI specifications at boot time.
- `nvidia-cdi-refresh.path`: Monitors for device changes to trigger CDI refreshes.

**Pod & Quadlet definitions**
- `devpod.kube`: Quadlet file defining the systemd-managed pod.
- `devpod.yaml`: Kubernetes Pod specification for the dev pod.

**Scripts**
- `backup_stub.sh`: Placeholder logic for the backup sidecar.
- `bootc_host_test.sh`: Execution logic for host-level tests.
- `bootc-firstboot-push.sh`: Implementation of the first-boot push to Quay.
- `bootc-update-nudge.sh`: Script to notify the user of pending updates.
- `bootc-update.sh`: Orchestration logic for system updates.
- `dev_container_start.sh`: Entrypoint script for the dev container.
- `os-builder.sh`: Script for the automated image rebuild pipeline.

**Configuration & Tests**
- `autologin.conf`: Systemd override for console autologin.
- `dev_container_test.py`: Validation tests for the dev container environment.

### `02_build_vm/`
Tools for local validation of the host image in a virtual machine environment.
- `build_vm.sh`: Converts the host image OCI artifact into a qcow2 disk and installs it into libvirt.
- `run_vm.sh`: Starts the VM via `virt-install` and configures local SSH access.
- `_detect_ssh_key.sh`: Helper script to locate the local SSH public key for injection.

### `docs/`
The project documentation tree.
- `concepts/`: High-level architecture and design rationale.
- `how-to/`: Task-oriented procedural guides.
- `reference/`: Factual catalogs and artifact descriptions.
- `overview.md`: Project summary and core mental models.
- `roadmap.md`: Current status, planned work, and open questions.
- `README.md`: Entry point and map for the documentation.
- `DOCS_PLAN.md`: The blueprint for the current documentation rewrite.

--- START OF FILE: ./docs/reference/images.md ---
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
    - **Orchestration**: Quadlet definitions (`devpod.kube`, `devpod.yaml`) at `/usr/share/containers/systemd/`.
- **Tags**:
    - Local: `gpu-bootc-host:latest`
    - Quay: `quay.io/m0ranmcharles/fedora_init:latest`
- **Baked-in vs. pulled at runtime**: Baked-in as the system image.
- **Notes**: The host image is keyless; SSH keys and user credentials must be injected at deployment time (e.g., via `cloud-init`).

## Dev container

The GPU-accelerated development environment where workloads run.

- **Path**: `01_build_image/build_assets/dev-container.Containerfile`
- **Purpose**: Provides a decoupled workstation environment with a full PyTorch and CUDA stack.
- **Base image**: `nvcr.io/nvidia/pytorch:26.03-py3`
- **Key adds**: `bash`, `procps`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:dev-container`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman on the host.
- **Notes**: Orchestrated by the host's Quadlet as part of the `devpod` pod.

## Backup sidecar

A placeholder service for managing persistent data backups.

- **Path**: `01_build_image/build_assets/backup-container.Containerfile`
- **Purpose**: Designed to run alongside the dev container to handle state persistence and cloud sync (planned).
- **Base image**: `registry.fedoraproject.org/fedora:42`
- **Key adds**: `bash`, `coreutils`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:backup-container`
- **Baked-in vs. pulled at runtime**: Pulled at runtime by Podman on the host.

## OS builder

An ephemeral environment used for automated host image rebuilds.

- **Path**: `01_build_image/build_assets/os-builder.Containerfile`
- **Purpose**: Clones the project repository and builds fresh versions of all images during the scheduled update cycle.
- **Base image**: `quay.io/fedora/fedora:42`
- **Key adds**: `podman`, `buildah`, `skopeo`, `git`, `ca-certificates`.
- **Tags**: `quay.io/m0ranmcharles/fedora_init:os-builder`
- **Baked-in vs. pulled at runtime**: Pulled and run as an ephemeral container by the host's `bootc-update.service`.

## Common properties

### Build context
The build context for all images is the `01_build_image/build_assets/` directory. Any files copied via `COPY` instructions must reside within this folder.

### Registry
All images are published to the `quay.io/m0ranmcharles/fedora_init` namespace. See `reference/registry.md` for details on tagging and push procedures.

### Security
All images are "keyless" by design. They do not contain embedded SSH keys, API credentials, or private configuration. This allows the images to be shared publicly on Quay while maintaining security through deployment-time identity injection.

### Source of truth
The Containerfiles in the repository are the authoritative definitions for these images. Code excerpts in this documentation are for illustrative purposes only.

--- START OF FILE: ./docs/reference/systemd_units.md ---
# Systemd units

This document catalogs the systemd units authored for this project and the native host services enabled in the host image.

## Project-specific units

### bootc-host-test.service
- **Path**: `/usr/lib/systemd/system/bootc-host-test.service`
- **Type**: oneshot service
- **Purpose**: Runs a suite of health checks to verify host networking, GPU availability, and Quadlet state.
- **Triggers**: Starts automatically during normal boot.
- **Implements**: `/opt/project/bootc_host_test.sh`
- **Enabled at build time?**: Yes
- **Notes**: Runs after `sshd.service` and `nvidia-cdi-refresh.service`.

### bootc-update.timer
- **Path**: `/usr/lib/systemd/system/bootc-update.timer`
- **Type**: timer
- **Purpose**: Triggers a weekly rebuild and staging of the host image.
- **Triggers**: Fires every Sunday at 03:00; uses `Persistent=true` to catch up if the host was powered off.
- **Implements**: `bootc-update.service`
- **Enabled at build time?**: Yes

### bootc-update.service
- **Path**: `/usr/lib/systemd/system/bootc-update.service`
- **Type**: oneshot service
- **Purpose**: Rebuilds the host image in an ephemeral container and stages it to the local OSTree repository.
- **Triggers**: Activated by `bootc-update.timer`.
- **Implements**: `/usr/local/bin/bootc-update.sh`
- **Enabled at build time?**: No (triggered by timer)

### bootc-firstboot-push.service
- **Path**: `/usr/lib/systemd/system/bootc-firstboot-push.service`
- **Type**: oneshot service
- **Purpose**: Conditionally pushes a freshly-booted image to Quay to verify its health before distribution.
- **Triggers**: Runs only on the first boot of a new deployment (`ConditionFirstBoot=yes`).
- **Implements**: `/usr/local/bin/bootc-firstboot-push.sh`
- **Enabled at build time?**: Yes

### nvidia-cdi-refresh.path
- **Path**: `/usr/lib/systemd/system/nvidia-cdi-refresh.path`
- **Type**: path watcher
- **Purpose**: Monitors for the presence of NVIDIA device nodes to trigger CDI generation.
- **Triggers**: Fires when `/dev/nvidiactl` exists.
- **Implements**: `nvidia-cdi-refresh.service`
- **Enabled at build time?**: Yes

### nvidia-cdi-refresh.service
- **Path**: `/usr/lib/systemd/system/nvidia-cdi-refresh.service`
- **Type**: oneshot service
- **Purpose**: Generates the Container Device Interface (CDI) specification for NVIDIA GPUs.
- **Triggers**: Activated by `nvidia-cdi-refresh.path` or starts at boot.
- **Implements**: `nvidia-ctk cdi generate`
- **Enabled at build time?**: Yes

### getty@tty1.service drop-in
- **Path**: `/etc/systemd/system/getty@tty1.service.d/override.conf`
- **Type**: drop-in configuration
- **Purpose**: Enables automatic login for the root user on the physical or virtual console.
- **Triggers**: Starts when `getty@tty1.service` is activated.
- **Implements**: `/sbin/agetty` flags
- **Enabled at build time?**: Yes (active by default for tty1)
- **Notes**: Intended for recovery and VM console access; does not affect SSH or network security.

## Native host services

These services are part of the base Fedora Bootc image or installed via `dnf` and are explicitly enabled during the build.

### sshd
- **Purpose**: Provides remote shell access.
- **Enabled at build time?**: Yes

### cloud-init.target
- **Purpose**: Orchestrates the four stages of cloud-init (generator, local, network, config) for first-boot provisioning.
- **Enabled at build time?**: Yes

## Quadlet-generated units

Quadlet files located in `/usr/share/containers/systemd/` are processed by `systemd-quadlet-generator` at boot time. This project includes `devpod.kube`, which results in a `devpod.service` unit. See `reference/quadlets.md` for the field-by-field breakdown and `concepts/ownership_model.md` for the role Quadlet plays in the architecture.

## Boot order

On a typical first boot of a new deployment, units activate in this approximate sequence:

1. **`cloud-init.target`**: Processes any provided user data or SSH keys.
2. **`nvidia-cdi-refresh.service`**: Generates the CDI spec once drivers and device nodes are ready.
3. **`devpod.service`**: (Generated from Quadlet) Starts the dev pod once Podman and CDI are available.
4. **`sshd.service`**: Enables remote access.
5. **`bootc-host-test.service`**: Validates the health of the entire stack.
6. **`bootc-firstboot-push.service`**: Pushes the verified image to Quay if requested by configuration.

--- START OF FILE: ./docs/reference/quadlets.md ---
# Quadlets

Quadlets are the mechanism for bridging systemd and Podman in this project. They allow containerized workloads to be managed as standard system services, ensuring they start at boot and restart on failure.

## Placement rules

Quadlet files in this project are baked into the **host image** during the build process.

* **System-wide (Standard):** Files are installed at `/usr/share/containers/systemd/`. This directory is for immutable units provided by the image.
* **Mutable/Local:** Files placed at `/etc/containers/systemd/` are mutable but subject to three-way merges during bootc updates.
* **User-scoped:** Quadlets can also live in `~/.config/containers/systemd/` for services that should run under a specific user session (not used in the current host image).

## The .kube vs. .container choice

This project uses a `.kube` Quadlet rather than a `.container` Quadlet. This choice was made specifically to enable the use of CDI (Container Device Interface) selectors (`nvidia.com/gpu=all`) within a standard Kubernetes Pod manifest. This ensures that the GPU request follows a documented path supported by Podman's `kube play` functionality. For more details on this architectural decision, see `concepts/gpu_stack.md`.

---

## devpod.kube

The entry point for the development environment's lifecycle management.

* **Path in repo:** `01_build_image/build_assets/devpod.kube`
* **Path in host image:** `/usr/share/containers/systemd/devpod.kube`
* **Type:** Kubernetes-style Quadlet unit.
* **Generated systemd unit:** `devpod.service`.

### Field walkthrough

The following excerpts are illustrative. See the file in the repo for the authoritative version.

#### [Unit] block
Defines the dependencies of the pod.
```ini
[Unit]
Description=Dev pod with dev container and backup sidecar
After=network-online.target sshd.service nvidia-cdi-refresh.service
Wants=network-online.target
Requires=nvidia-cdi-refresh.service
```
* **After/Requires:** Ensures the pod only starts after the network is up and the `nvidia-cdi-refresh.service` has generated the CDI specification.

#### [Kube] block
Points Quadlet to the actual workload definition.
```ini
[Kube]
Yaml=/usr/share/containers/systemd/devpod.yaml
```
* **Yaml:** The absolute path to the Pod manifest on the host filesystem.

#### [Install] block
Ensures the generated service starts automatically.
```ini
[Install]
WantedBy=multi-user.target
```
* **WantedBy:** Integrates the generated `devpod.service` into the standard boot target.

---

## devpod.yaml

The Pod manifest defining the containers and their resources.

* **Path in repo:** `01_build_image/build_assets/devpod.yaml`
* **Path in host image:** `/usr/share/containers/systemd/devpod.yaml`
* **Type:** Kubernetes Pod manifest.

### Field walkthrough

The following excerpts are illustrative. See the file in the repo for the authoritative version.

#### Metadata and Spec
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: devpod
spec:
  restartPolicy: Always
```
* **restartPolicy: Always:** Ensures that if a container inside the pod exits, Podman will restart it.

#### Containers: dev-container
The primary workload environment.
```yaml
    - name: dev-container
      image: quay.io/m0ranmcharles/fedora_init:dev-container
      stdin: true
      tty: true
      workingDir: /workspace
      resources:
        limits:
          nvidia.com/gpu=all: 1
```
* **stdin/tty:** Allows for interactive sessions via `podman exec`.
* **resources.limits:** Uses the CDI selector `nvidia.com/gpu=all` to request access to the host's NVIDIA GPU.

#### Containers: backup-container
A placeholder sidecar used for validating pod wiring and persistence.
```yaml
    - name: backup-container
      image: quay.io/m0ranmcharles/fedora_init:backup-container
      stdin: true
      tty: true
      workingDir: /workspace
```
* This container runs alongside the **dev container** in the same network and IPC namespace.

--- START OF FILE: ./docs/reference/scripts.md ---
# Scripts

A reference catalog of the shell and Python scripts used to build, deploy, and maintain the bootc system.

## Top-level

### `build_image.sh`
- **Path**: `build_image.sh`
- **Purpose**: Builds the four primary container images (dev-container, backup-container, os-builder, and the bootc host image).
- **Env vars / args**: None.
- **Preconditions**: Podman must be installed; build assets must exist in `01_build_image/build_assets/`.
- **Side effects**: Creates local Podman images tagged for the local registry and Quay.
- **Notes**: This is the primary entry point for local development.

### `run_container.sh`
- **Path**: `run_container.sh`
- **Purpose**: Runs an ephemeral interactive shell inside a container image for inspection.
- **Env vars / args**: `IMAGE_NAME` (optional, defaults to `gpu-bootc-host:latest`).
- **Preconditions**: The target image must exist in local container storage.
- **Side effects**: Starts an interactive container session.
- **Notes**: Changes made inside the container are lost upon exit.

### `push_images.sh`
- **Path**: `push_images.sh`
- **Purpose**: Pushes the built images to the Quay registry using the Docker V2 schema 2 format.
- **Env vars / args**: None.
- **Preconditions**: Images must be built locally; user must be logged into Quay via `podman login quay.io`.
- **Side effects**: Uploads images to the remote registry.
- **Notes**: Uses `--format v2s2` for compatibility with the bootc update logic.

## `02_build_vm/`

### `02_build_vm/build_vm.sh`
- **Path**: `02_build_vm/build_vm.sh`
- **Purpose**: Converts the host image into a bootable `qcow2` virtual disk and installs it into the libvirt storage pool.
- **Env vars / args**: `IMAGE_NAME` (optional arg, defaults to `gpu-bootc-host:latest`), `VM_NAME` (optional env var), `SSH_PUB_KEY_FILE` (optional env var).
- **Preconditions**: Requires `bootc-image-builder`, `libvirt`, and `sudo` access.
- **Side effects**: Generates a `config.toml` with injected SSH keys, creates a `qcow2` image, and copies it to `/var/lib/libvirt/images/`.
- **Notes**: Automatically detects and injects the local user's SSH public key into the VM's `root` account.

### `02_build_vm/run_vm.sh`
- **Path**: `02_build_vm/run_vm.sh`
- **Purpose**: Starts the VM using `virt-install`, detects its IP, and configures a local SSH alias.
- **Env vars / args**: `VM_NAME` (optional env var), `SSH_PUB_KEY_FILE` (optional env var).
- **Preconditions**: The VM disk must have been created by `build_vm.sh`.
- **Side effects**: Destroys any existing VM of the same name, starts a new VM, and modifies `~/.ssh/config`.
- **Notes**: Creates a `fedora-init` SSH host block with `StrictHostKeyChecking no` to simplify access.

### `02_build_vm/_detect_ssh_key.sh`
- **Path**: `02_build_vm/_detect_ssh_key.sh`
- **Purpose**: Helper script to locate a valid SSH public key for injection into images or VMs.
- **Env vars / args**: `SSH_PUB_KEY_FILE` (optional env var).
- **Preconditions**: An SSH key must exist in `~/.ssh/` if `SSH_PUB_KEY_FILE` is not provided.
- **Side effects**: Sets the `SSH_PUB_KEY_FILE` environment variable.
- **Notes**: Sourced by other scripts; not intended for standalone execution.

## Host-side

### `bootc-update.sh`
- **Path**: `/usr/local/bin/bootc-update.sh` (source: `01_build_image/build_assets/bootc-update.sh`)
- **Purpose**: Orchestrates the scheduled OS update by running the `os-builder` container and staging the result.
- **Env vars / args**: `BUILDER_IMAGE` (optional env var).
- **Preconditions**: Must be run on the host; requires internet access to pull the builder and clone the source repo.
- **Side effects**: Stages a new bootc deployment via `bootc switch` and creates a pending update marker.
- **Notes**: Configured via `/etc/bootc-update/source.env`.

### `bootc-firstboot-push.sh`
- **Path**: `/usr/local/bin/bootc-firstboot-push.sh` (source: `01_build_image/build_assets/bootc-firstboot-push.sh`)
- **Purpose**: Optionally publishes the currently booted host image to Quay on the first boot after an update.
- **Env vars / args**: Reads `push_to_quay` from `/etc/bootc-update/reboot.env`.
- **Preconditions**: Requires `skopeo` and valid Quay credentials in root's container storage.
- **Side effects**: Pushes the booted image to Quay and clears the `push_to_quay` flag.
- **Notes**: Executed by `bootc-firstboot-push.service`; clears the update pending marker on completion.

### `bootc-update-nudge.sh`
- **Path**: `/etc/profile.d/bootc-update-nudge.sh` (source: `01_build_image/build_assets/bootc-update-nudge.sh`)
- **Purpose**: Notifies interactive users when a new OS deployment is staged and waiting for a reboot.
- **Env vars / args**: None.
- **Preconditions**: A pending update marker must exist at `/var/lib/bootc-update/pending`.
- **Side effects**: Prints a notification message to stdout during shell login.
- **Notes**: Part of the host image's update UX.

### `bootc_host_test.sh`
- **Path**: `/opt/project/bootc_host_test.sh` (source: `01_build_image/build_assets/bootc_host_test.sh`)
- **Purpose**: Performs a basic smoke test of host services, GPU state, and Quadlet status at boot.
- **Env vars / args**: None.
- **Preconditions**: Run on the host system.
- **Side effects**: Writes status information and diagnostic data to the system journal.
- **Notes**: Triggered automatically by `bootc-host-test.service`.

### `os-builder.sh`
- **Path**: `/usr/local/bin/os-builder.sh` (source: `01_build_image/build_assets/os-builder.sh`)
- **Purpose**: Rebuilds all project images from source and exports the host image as an OCI archive.
- **Env vars / args**: `SOURCE_REPO`, `SOURCE_BRANCH`, `OUTPUT_DIR`, `SAVE_ALL`.
- **Preconditions**: Run inside the `os-builder` container.
- **Side effects**: Clones the repository and writes `.tar` image archives to the output directory.
- **Notes**: This script is the `ENTRYPOINT` for the `os-builder` image.

## Container-side

### `dev_container_start.sh`
- **Path**: `/usr/local/bin/dev_container_start.sh` (source: `01_build_image/build_assets/dev_container_start.sh`)
- **Purpose**: Serves as the startup entry point for the dev container, running tests before entering a wait loop.
- **Env vars / args**: None.
- **Preconditions**: Run inside the dev container.
- **Side effects**: Executes `dev_container_test.py` and maintains a persistent process.
- **Notes**: This is the `CMD` for the dev container.

### `dev_container_test.py`
- **Path**: `/workspace/dev_container_test.py` (source: `01_build_image/build_assets/dev_container_test.py`)
- **Purpose**: Validates the Python environment, PyTorch installation, and CUDA visibility inside the dev container.
- **Env vars / args**: None.
- **Preconditions**: Python 3 and PyTorch must be installed.
- **Side effects**: Prints diagnostic information about the GPU and torch version.
- **Notes**: Used as a smoke test during container startup.

### `backup_stub.sh`
- **Path**: `/usr/local/bin/backup_stub.sh` (source: `01_build_image/build_assets/backup_stub.sh`)
- **Purpose**: Acts as a placeholder entry point for the backup sidecar container.
- **Env vars / args**: None.
- **Preconditions**: Run inside the backup sidecar container.
- **Side effects**: Maintains a persistent process to keep the container running.
- **Notes**: This is the `CMD` for the backup sidecar; real backup logic is planned.

--- START OF FILE: ./docs/reference/registry.md ---
# Registry

This project uses Quay.io as the central registry for distributing the host image and its associated workload containers.

## Namespace and repository

The canonical namespace for the project is `quay.io/m0ranmcharles/fedora_init`. This single repository hosts all project components, distinguished by their tags.

Forks or alternative deployments should use their own Quay namespace and update the `REPO` variable in `push_images.sh` accordingly.

## Tagging convention

The project maintains four primary tags in the `fedora_init` repository:

- `:latest`: The **host image** (bootable container).
- `:dev-container`: The **dev container** containing the GPU/PyTorch stack.
- `:backup-container`: The **backup sidecar** (currently a placeholder).
- `:os-builder`: The ephemeral builder image used by the scheduled update pipeline.

## Authentication

Quay.io requires an encrypted CLI password for authentication, which is separate from your web login password.

- **Generation**: Encrypted passwords must be generated via the Quay UI under **Account Settings** > **Generate Encrypted Password**.
- **Usage**: Use `podman login quay.io` with your username and the generated encrypted password.

For the step-by-step procedure, see `how-to/push_to_quay.md`.

## Manifest format (v2s2)

All images are pushed using the Docker V2, Schema 2 (`v2s2`) manifest format. The `push_images.sh` script enforces this via the `--format v2s2` flag.

This format is required because `bootc` and related OS-level tooling expect `v2s2` manifests when consuming images from a registry. Using the default OCI format can lead to compatibility issues during the `bootc install` or `bootc upgrade` phases.

## Visibility and access

The repository is configured as **Public**.

The OCI images are keyless by design, allowing them to be pulled by any client without authentication. Security and identity are managed at deployment time (e.g., via SSH keys or cloud-init) rather than being baked into the image itself.

For more details on the security architecture, see `concepts/access_model.md`.

--- START OF FILE: ./docs/how-to/build_images.md ---
# Build images

## Goal
Build the host image, dev container, backup sidecar, and os-builder images on a local workstation.

## Prerequisites
- Podman installed and rootless builds functional (run `podman info` to confirm).
- Sufficient disk space (approximately 30 GB); the dev container is the largest layer due to the PyTorch base image.
- Network access to pull base images from:
  - `quay.io/fedora/fedora-bootc:42`
  - `nvcr.io/nvidia/pytorch:26.03-py3`
  - `registry.fedoraproject.org/fedora:42`
  - `quay.io/fedora/fedora:42`
- The repository cloned locally.

## Steps
1. Navigate to the repository root.
2. Execute the build script:
   ```bash
   ./build_image.sh
   ```
3. Wait for the process to complete. The first run takes significant time as it pulls the large NVIDIA PyTorch base layer.

The `build_image.sh` script orchestrates four `podman build` invocations sequentially. It tags the host image both locally (`gpu-bootc-host:latest`) and for the remote registry (`quay.io/m0ranmcharles/fedora_init:latest`).

## Verify
Confirm the images exist in local storage:
```bash
podman images | grep -E 'fedora_init|gpu-bootc-host'
```
The output should list four distinct image entries: the host image, the dev container, the backup sidecar, and the os-builder.

## Troubleshooting
- **Network unreachable pulling NVIDIA base**: The NVIDIA Container Registry (`nvcr.io`) may occasionally rate-limit requests. Retry the build, or run `podman login nvcr.io` if you have specific credentials.
- **No space left on device**: Building these images, especially the dev container, is resource-intensive. Clean your local image cache with `podman system prune -a` and ensure `/var/lib/containers` or your rootless storage path has enough headroom.
- **Permission denied**: Ensure you are running the script as a user with permission to execute Podman commands. Rootless Podman is recommended.

--- START OF FILE: ./docs/how-to/run_locally.md ---
# Run the host image locally

## Goal
Run an ephemeral root shell inside the host image to inspect installed packages, file layouts, and baked-in unit files without booting a virtual machine.

## Prerequisites
- The host image must be built locally. See `how-to/build_images.md` for build instructions.
- Podman must be installed and available on your system.

## Steps
Run the inspection script from the repository root.

1. Execute the default run command:
   ```bash
   ./run_container.sh
   ```
   By default, this attempts to run the local `gpu-bootc-host:latest` image.

2. Optionally, specify a different image name (such as one from Quay):
   ```bash
   ./run_container.sh quay.io/m0ranmcharles/fedora_init:latest
   ```

## Verify
After running the script, you should be at a root bash prompt inside the container.

1. Confirm the operating system:
   ```bash
   cat /etc/os-release
   ```
   The output should show Fedora bootc.

2. Verify the presence of baked-in files:
   ```bash
   ls /usr/lib/systemd/system/nvidia-cdi-refresh.service
   ```

## Troubleshooting
If the command fails with an image not found error, ensure you have successfully completed the build steps in `how-to/build_images.md`.

## What this is NOT
- **Not a full boot:** This method starts a shell, not the systemd init process. `systemctl` commands will not work.
- **No services:** SSH, cloud-init, and other host services are not active.
- **Ephemeral:** All changes to the filesystem are discarded when the shell exits.

To validate the full boot sequence, including systemd units and SSH access, see `how-to/build_and_run_vm.md`. For more on the broader project permissions, see `concepts/access_model.md`.

--- START OF FILE: ./docs/how-to/build_and_run_vm.md ---
# Build and run a VM

## Goal
Convert the host image into a bootable qcow2 disk, install it into the libvirt storage pool, boot it under KVM, and connect via SSH using a pre-configured alias.

## Prerequisites
- **Host image**: Built locally and available in your local container storage (see `how-to/build_images.md`).
- **Virtualization**: libvirt, KVM, and `virt-install` installed. Your user must have `sudo` privileges for libvirt operations.
- **SSH Key**: A public key at `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub` for automatic detection. To use a different key, set `SSH_PUB_KEY_FILE=/path/to/key.pub` before running the scripts.
- **Image Builder**: The `bootc-image-builder` tool, accessible via `sudo podman pull quay.io/centos-bootc/bootc-image-builder:latest`.

## Steps

### 1. Build the qcow2 disk
Run the build script from the repository root:

```bash
./02_build_vm/build_vm.sh
```

This script performs the following:
- Detects your SSH public key and generates a temporary `config.toml` to inject it into the VM's root account.
- Invokes `bootc-image-builder` to convert the `gpu-bootc-host:latest` image (or a specified image name) into a qcow2 file.
- Copies the resulting disk to `/var/lib/libvirt/images/${VM_NAME}.qcow2` (default `VM_NAME=gpu-bootc-test`).
- Sets the file ownership to `qemu:qemu` so the virtualization service can access it.

### 2. Boot the VM and configure SSH
Start the VM and set up the local SSH alias:

```bash
./02_build_vm/run_vm.sh
```

This script performs the following:
- Tears down any existing VM with the same name.
- Starts a new VM with 16 GB RAM, 8 vCPUs, UEFI boot, and a virtio network interface.
- Polls `virsh domifaddr` until the VM receives an IP address from the default libvirt network.
- Updates your `~/.ssh/config` file with a `# BEGIN fedora-init` block, enabling you to connect using a simple alias.

### 3. Connect
Once the script completes, connect to the running VM:

```bash
ssh fedora-init
```

## Verify
- **Access**: `ssh fedora-init` should land you in a root shell on the VM without a password prompt.
- **Services**: Run `systemctl is-active sshd cloud-init.target nvidia-cdi-refresh.service`. All should report `active`. Note that `cloud-init.target` may take a moment to reach this state on the first boot.
- **Deployment**: Run `bootc status` to verify the VM is running the expected image version and is tracking the correct registry.

## Troubleshooting
- **IP not detected**: If the script times out waiting for an IP, attach to the console with `sudo virsh console gpu-bootc-test` (detach with `Ctrl+]`) to inspect the boot logs. You can also run `sudo virsh domifaddr gpu-bootc-test` manually.
- **Disk not found**: Ensure you ran `build_vm.sh` before `run_vm.sh`. If you customized `VM_NAME`, ensure it was exported consistently for both scripts.
- **Permission errors**: Confirm your user is in the `libvirt` group or has appropriate `sudo` access. Verify the libvirt daemon is active with `systemctl status libvirtd`.

--- START OF FILE: ./docs/how-to/push_to_quay.md ---
# Push images to Quay

## Goal
Push the four project images to the Quay registry:
- `quay.io/m0ranmcharles/fedora_init:latest` (host image)
- `quay.io/m0ranmcharles/fedora_init:dev-container`
- `quay.io/m0ranmcharles/fedora_init:backup-container`
- `quay.io/m0ranmcharles/fedora_init:os-builder`

## Prerequisites
- A Quay.io account (uses Red Hat SSO).
- A public repository named `fedora_init` under your namespace.
- All images built locally (see `how-to/build_images.md`).
- If your namespace differs from `m0ranmcharles`, update the `REPO` variable in `push_images.sh`.

## One-time auth setup
Quay requires an encrypted password for CLI authentication.

1. Sign in to [quay.io](https://quay.io) with your Red Hat account.
2. Create a public repository named `fedora_init` (see `reference/registry.md` for visibility notes).
3. Generate a CLI password:
   - Click your username (top right) -> **Account Settings**.
   - Select **CLI Password** and set a password if prompted.
   - Click the **Generate Encrypted Password** link.
4. Log in via your terminal:
   ```bash
   podman login quay.io
   ```
   Provide your username and the long encrypted password generated by Quay.
5. Confirm the session: `podman login --get-login quay.io`.

## Steps
1. Confirm images exist locally:
   ```bash
   podman images | grep fedora_init
   ```
2. Run the push script:
   ```bash
   ./push_images.sh
   ```
   The script re-tags the local `gpu-bootc-host:latest` and pushes all four images using the `--format v2s2` flag required by bootc.

## Verify
- Observe the script output for the "Push Complete" message.
- Visit `https://quay.io/repository/m0ranmcharles/fedora_init?tab=tags` and verify that all four tags are present with recent timestamps.

## Troubleshooting
- **`podman push: unauthorized`**: Your login session has expired or the `REPO` namespace in `push_images.sh` does not match your account. Re-run `podman login quay.io` and verify the script configuration.
- **`podman push: blob upload unknown`**: This is typically a transient registry error. The script is restartable; simply run it again.
- **Slow dev-container push**: The PyTorch base layer is several gigabytes. Subsequent pushes will be faster as only modified layers are uploaded.

--- START OF FILE: ./docs/how-to/distribute_image.md ---
# Distribute the host image to a third party

## Goal
Help a downstream user pull the published `quay.io/m0ranmcharles/fedora_init:latest` image, build a qcow2 virtual disk, and inject their own SSH key via a cloud-init NoCloud seed at first boot.

## Prerequisites
- Downstream user has Podman and libvirt installed (for the VM path).
- An SSH key pair on the downstream user's machine.
- Access to the target machine for bare-metal deployment (out of scope for this how-to — see `concepts/state_and_persistence.md` for context).

## Steps

### 1. Pull the host image
The downstream user pulls the keyless host image from the public registry:
```bash
sudo podman pull quay.io/m0ranmcharles/fedora_init:latest
```

### 2. Author a NoCloud seed
Create two files, `user-data` and `meta-data`, to define the first-boot configuration.

`user-data`:
```yaml
#cloud-config
ssh_authorized_keys:
  - ssh-ed25519 AAAA... user@host
```

`meta-data`:
```yaml
instance-id: gpu-bootc-deploy-1
local-hostname: gpu-bootc
```

Bake these files into a `cidata` ISO:
```bash
genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data
```
Alternatively, use `cloud-localds seed.iso user-data meta-data` if available.

### 3. Build the qcow2
The downstream user converts the OCI image to a qcow2 disk. Note that the project's internal `02_build_vm/build_vm.sh` is optimized for local development; for distribution, use `bootc-image-builder` directly:

```bash
sudo podman run --rm --privileged \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --rootfs xfs \
  --local quay.io/m0ranmcharles/fedora_init:latest
```

### 4. Boot the qcow2 and attach the seed ISO
Attach the `seed.iso` as a CD-ROM device during the initial boot. Using `virt-install`:

```bash
sudo virt-install \
  --name gpu-bootc \
  --memory 16384 --vcpus 8 \
  --disk path=./output/qcow2/disk.qcow2,format=qcow2 \
  --disk path=./seed.iso,device=cdrom \
  --import \
  --os-variant fedora-unknown \
  --network network=default \
  --boot uefi
```

At first boot, cloud-init detects the `cidata` label, reads the seed, and writes the SSH key into `/root/.ssh/authorized_keys`.

### 5. Connect
Find the VM's IP address and connect via SSH:
```bash
sudo virsh domifaddr gpu-bootc
ssh root@<ip>
```

## Verify
- Run `bootc status` on the VM to confirm the deployed image matches the pulled OCI tag.
- Verify `/root/.ssh/authorized_keys` contains the key provided in the `user-data` file.

## Troubleshooting
- **No SSH access** — Connect via `virsh console gpu-bootc` (leveraging the emergency autologin fallback) and check the cloud-init logs with `journalctl -u cloud-init`. Ensure the seed ISO was created with the correct `cidata` volume label.
- **Image pull fails** — Confirm the registry repository is public and accessible from the downstream environment using `sudo podman pull`.

--- START OF FILE: ./docs/how-to/validate_gpu.md ---
# Validate GPU passthrough

## Goal
Verify the chain: host driver → CDI spec → dev pod → CUDA visible inside the dev container.

## Prerequisites
- The host image is deployed on a machine with an NVIDIA GPU.
- You have shell access (see `concepts/access_model.md`).
- The dev pod has had time to start (it is started by a Quadlet at boot).

## Steps

### 1. Confirm the host driver loaded
Run `nvidia-smi` on the host:
```bash
nvidia-smi
```
On a working host, this lists the GPU devices and the driver version. If nothing is listed or an error occurs, the kernel module is not loaded. See Troubleshooting.

### 2. Confirm the CDI spec was generated
Check for the CDI specification file:
```bash
sudo cat /etc/cdi/nvidia.yaml
```
This file is created at boot by `nvidia-cdi-refresh.service`. It must list the host's GPU devices, libraries, and a top-level `nvidia.com/gpu=all` entry.

### 3. Confirm the dev pod is running
Check the status of the pod service and the pod itself:
```bash
sudo systemctl status devpod.service
sudo podman pod ps
```
`devpod.service` should be `active (running)`. The pod should contain both the `dev-container` and the `backup-sidecar`.

### 4. Confirm the dev container sees the GPU
Run `nvidia-smi` inside the running dev container:
```bash
sudo podman exec -it devpod-dev-container nvidia-smi
```
The output should match the host output from Step 1.

### 5. Confirm CUDA is visible from PyTorch
Run the baked-in smoke test inside the dev container:
```bash
sudo podman exec -it devpod-dev-container python3 /workspace/dev_container_test.py
```
This script (refer to `01_build_image/build_assets/dev_container_test.py` in the repo) validates the Python stack. Expected output:
- `torch_version=...`
- `cuda_available=True`
- `gpu_name=NVIDIA <model>`

## Verify
The `bootc-host-test.service` runs automatically at boot and provides a summary of this validation chain in the system journal:
```bash
sudo journalctl -u bootc-host-test.service --no-pager
```

## Troubleshooting

- **`nvidia-smi` reports "No devices were found"**: The kernel module failed to load. This usually happens if the `nvidia-open` DKMS build at image-build time was pinned against a different kernel version than the one running on the deployed host. See `concepts/gpu_stack.md` for fallback paths using `kernel-devel` matching or `akmod-nvidia-open`.
- **`/etc/cdi/nvidia.yaml` is missing**: The `nvidia-cdi-refresh.service` failed. Check its logs with `sudo journalctl -u nvidia-cdi-refresh.service`. Note that `nvidia-cdi-refresh.path` re-runs the service when `/dev/nvidiactl` appears; if the device node is missing, the spec will not generate.
- **`devpod.service` failed to start**: Inspect the service logs with `sudo journalctl -u devpod.service`. Common causes include image pull failures due to networking issues or missing credentials for `quay.io`.
- **`cuda_available=False` inside the dev container**: The CDI device was not injected into the container. Confirm that the pod manifest (`/usr/share/containers/systemd/devpod.yaml`) includes the `resources.limits[nvidia.com/gpu=all]: 1` selector.

--- START OF FILE: ./docs/how-to/write_a_systemd_unit_for_the_host.md ---
# Write a systemd unit for the host

## Goal
Add a service that runs at boot on the deployed host image.

## Background
A bootc host boots via GRUB → kernel → systemd as PID 1. The OCI image's `CMD` or `ENTRYPOINT` are container-runtime concepts and are **ignored** at boot. To run something at boot, write a systemd unit and bake it into the host image. While `CMD` and `ENTRYPOINT` still execute when running the image locally with `./run_container.sh`, they have no effect on the actual host boot process.

## Steps

1.  **Write the unit.** Drop a service file in `01_build_image/build_assets/`, e.g., `my-startup.service`:
    ```ini
    [Unit]
    Description=Run my custom startup script
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/my-startup.sh
    RemainAfterExit=yes
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    ```

2.  **Write the script.** Drop the executable in `01_build_image/build_assets/`, e.g., `my-startup.sh`. Make sure it is executable (`chmod +x`).

3.  **Wire it into the host `Containerfile`.** Edit `01_build_image/build_assets/Containerfile` to copy and enable the unit:
    ```dockerfile
    COPY my-startup.sh /usr/local/bin/my-startup.sh
    COPY my-startup.service /usr/lib/systemd/system/my-startup.service
    RUN chmod 0755 /usr/local/bin/my-startup.sh
    RUN systemctl enable my-startup.service
    ```
    *See the file in the repo for the authoritative version of the host image definition.*

4.  **Rebuild and redeploy.** Run `./build_image.sh` and then re-run the VM as described in `how-to/build_and_run_vm.md`. If the image is already published, use `bootc upgrade` on the host.

## Verify
On the booted host, check the status and logs:
```bash
systemctl status my-startup.service
journalctl -u my-startup.service --no-pager
```

## Variations

### Every boot (default)
The example above runs every time the system boots.

### First boot only
Add `ConditionFirstBoot=yes` to the `[Unit]` section. systemd evaluates this against the machine ID state; once the host has booted once and initialized the machine ID, the unit is skipped on subsequent reboots:
```ini
[Unit]
ConditionFirstBoot=yes
```
This pattern is used by `bootc-firstboot-push.service`. See `reference/systemd_units.md` for details.

### Triggered by a path appearing
For "wait until file/device X exists, then run," use a `.path` unit to activate the service. In this project, `nvidia-cdi-refresh.path` activates `nvidia-cdi-refresh.service` when `/dev/nvidiactl` appears. See `reference/systemd_units.md`.

### Triggered by a timer
To run on a schedule, use a `.timer` unit. For example, `bootc-update.timer` fires `bootc-update.service` weekly. See `reference/systemd_units.md`.

## Where files go in the host image (placement rules)

- `/usr/lib/systemd/system/` — Preferred location for image-provided units baked into the host.
- `/etc/systemd/system/` — Mutable local units (subject to ostree's `/etc` 3-way merge on upgrade).
- `/usr/share/containers/systemd/` — Location for Quadlet files (see `reference/quadlets.md`).
- `~/.config/containers/systemd/` — User-scoped Quadlets (not used by this project).

## What this doc is NOT
- Not a Quadlet primer (see `reference/quadlets.md` and `concepts/ownership_model.md`).
- Not an exhaustive systemd reference (see `man systemd.service` and `man systemd.unit`).

## Sources
- `bootc_init_cmd.md` — Rationale for why `CMD`/`ENTRYPOINT` don't apply.
- `01_build_image/build_assets/Containerfile` — Standard pattern for COPY and enable.
- `concepts/ownership_model.md` — General project separation of concerns.

--- START OF FILE: ./docs/overview.md ---
# Overview

## What this is

This project provides a bootc-based GPU workstation architecture that pairs an immutable host system with containerized workload environments and a scheduled rebuild pipeline. By decoupling the machine layer from the application stack, it yields a highly reproducible, easily cleanable workspace. The host OS handles hardware orchestration and updates safely, while development environments remain focused, isolated, and rapidly iterable.

## The 3-layer model

```text
Host Image (Hardware & Boot)
  │
  ├─ Quadlet (Lifecycle Bridge)
  │    │
  │    └─ devpod.kube / devpod.yaml
  │
  └─ Workload Container (Application)
       ├─ dev container
       └─ backup sidecar
```

The system splits responsibility across three distinct layers:

**Host image ownership:** The host image owns anything tied to the machine, hardware, boot order, or platform access. It acts as an immutable appliance handling SSH access, OS-level updates, GPU driver installation (`nvidia-open`), and boot orchestration. 

**Container ownership:** Containers own their internal workload environments and execution logic. They handle the PyTorch/CUDA runtime, application code, and development tools. Containers strictly execute workloads and do not run service managers.

**Quadlet ownership:** Podman Quadlet acts as the bridge between the host and containers. It dictates when containers start and stop relative to the host boot, manages restart policies, and handles pod composition. Host systemd manages when something runs; the container command decides what runs.

## What's built today vs. planned

**Today:**
- Host image build pipeline.
- Dev pod and backup sidecar definitions.
- VM build path (qcow2 conversion with SSH key injection).
- Image push to Quay.
- GPU CDI plumbing and dynamic boot-time generation.
- Scheduled local rebuild pipeline (`bootc-update.timer`, `os-builder`, and first-boot push).

**Planned:**
- Remote/CI rebuild orchestration (planned).
- Btrfs-based state persistence (planned).
- Real backup logic (planned).
- System wipe-and-restore pipeline (planned).

See `roadmap.md` for a complete list of upcoming work and open questions.

## Where to go next

If you are thinking "I want to use the published image", refer to `how-to/distribute_image.md` to deploy the image and `concepts/access_model.md` to understand the keyless authentication design.

If you are thinking "I want to build and test locally", begin with `how-to/build_images.md` to compile the artifacts, test them with `how-to/build_and_run_vm.md`, and verify hardware integration through `how-to/validate_gpu.md`.

If you are thinking "I want to understand why it's built this way", explore the `concepts/` directory to read the structural rationale behind these choices.

--- START OF FILE: ./docs/roadmap.md ---
# Roadmap

## Built today
- host image build
- dev pod & backup sidecar definition
- GPU CDI plumbing (`nvidia-cdi-refresh.{service,path}`)
- Quadlet at `/usr/share/containers/systemd/`
- qcow2 build path with key injection
- Quay push
- scheduled local rebuild pipeline (`bootc-update.timer` + `bootc-update.service` + `os-builder` image)
- first-boot push (gated by `push_to_quay=TRUE` flag)
- boot-time host smoke test (`bootc-host-test.service`)
- boot-time dev container smoke test (`dev_container_test.py`)

## Planned

### base
1. build bootc image (no enhancements) (done)
2. run bootc image as container (done)
3. choose vm software (done)
4. build bootc image as iso
5. run bootc image as vm (done)
6. push to quay (done)
7. add to bootc image: pull from quay on reboot (push that update to quay) (done)

### flash system
8. compress + encrypt files, push as backup to GDrive
9. build v1.0 image, push to quay (done)
10. pull v1.0 image, build as ISO (w/ anaconda)
11. flash image to USB, wipe + install to system

### base image build structure
12. build Containerfile (simple git install) (add to image build, test as container + vm) (done)
13. build Quadlet (simple ws-env, no integration) (add to image build, test as container + vm) (done)

### enhance testing
14. test GPU passthrough w/ standard vm
15. test GPU passthrough w/ bootc image
16. test GPU passthrough w/ bootc image + nvidia container
17. write as automated CI/CD for image testing
    (smoke tests via `bootc-host-test.service` and `dev_container_test.py` exist; full CI/CD with image testing on real GPU hardware is not yet wired up)

### system wipe/build/use/backup/recovery
18. ws-env: build access to ws-env via ssh (done)
19. ws-env: map persistent memory location /etc
20. create system btrfs backup on D:/var/
21. automate backup: ws-env -> sys-btrfs
22. automate recovery: sys-btrfs -> ws-env directory
23. automate backup: system btrfs backup compress/encrypt -> cloud
24. automate recovery: cloud -> sys-btrfs

## Open questions
- in the bootc image build, we can provide --fs ext4 (or ideally btrfs). can/should we provide btrfs so that we can use as a true sys admin/root?
- can we build w/o root?
- for the initial iso that we flash to a drive and boot to, we SHOULD work out all details ahead of time, then use the bare ISO rather than use the gui installer, purely for reproducability. If there are other benefits to the anaconda installer, then maybe we will keep the anaconda installer. we want to discuss this and work out an intended approach.
- more thoroughly document the process for adding Category1-4 (outlined in "process for wiping system post-bootc) + workstation container into the bootc image (probably through the containerfile).
- how to wipe /etc and potentially /var? use a dedicated script? when to do either? we want the periodic updates of the bootc image to go through regularly so that we can keep the software and kernels and kernel modules up to date. We also want to be able to leave the workstation container at the drop of the hat and come back to it without fear that our work will be lost. So we should have a set pipeline script to create a clean and complete btrfs backup, then to do a full wipe and boot back with the latest image and a completely clean system.

--- START OF FILE: ./docs/README.legacy.md ---

This is the whitepaper for our project. The document ostree_notes.md contains some recommendations about the project, and all other documents should be a dedicated document for each piece of the Checklist/Plan section of this document.


## goal, purpose
- high level process:
    - develop on the system, experiment, build
        - install software, update configs, build artifacts, etc as needed
    - functional/stable system components are moved to fedora_init as installation/setup scripts
    - all software in development is saved on remote git repo
    - periodically wipe entire system, reinitialize environment using fedora_init
    - anything created during experimentation/dev and not explicitly saved to fedora_init is wiped
- purpose:
    - recreates system environement
    - removes any transient files from the previous environment
        - old files can be reference via separate backup as needed
    - this keeps the workspace clean
    - removes any software not intentionally saved to fedora_init
    - all software up to date with minimal dependencies
- current implementation:
    - maintain a set of scripts (fedora_init) to setup our system from scratch
    - to wipe/reinitialize...
    - save all files as a compressed backup to a separate location
    - save fedora_init to a separate USB
        - place minimal init setup of fedora_init on USB
        - init setup script pulls the rest of fedora_init from remote git repo
    - flash the latest Fedora OS to a separate USB
    - install OS on the machine via USB
    - wipe the drive during installing
    - run fedora_init to setup environment
        - USB content does...
        - authenticates the user
        - pulls full fedora_init from remote repo
        - runs full fedora_init on system
- implementation we are building: bootc image of Fedora + containerized environments and componets
    - image:
        - core Fedora bootc image
        - + software installation/configuration
        - + systemd services for host boot functions and hardware orchestration
        - + podman quadlets (.kube, create systemd services) for container orchestration
        - + pods for container integration
        - + dev environment container for user environment
        - + container for backup functionality
    - scheduled update pipeline: rebuild and deploy the image to the ostree
        - see *immutable_os_deployment_pipeline.md*
        - build the image in a ephemeral container
        - write the image to ram
        - host system pushes the image from ram to ostree
        - ostree stores images with delta updates
            - storage architecture is a content-addressed object store
            - uses delta updates via file-level hardlinking for saving space
        - optional: push image to quay
        - purpose...
        - image builds are in a container
            - container building the image will contain everything needed
            - identical builds across different (original) host OSs
            - no artifacts left on the host system
        - interim/experimental updates can go through with dnf or rpm-ostree
            - see *ostree_architecture.md*
            - reoccurring image build installs/updates through dnf
            - potential opportunity for rpm-ostree updates
                - faster and more efficient image updates
                - small drift against pre-built images
                - more technically intricate system config merges w/ user additions to files
                - may not work with kernel module and driver updates (nvidia, cuda)


        
    






      setup goes directly into the bootc image Containerfile
      
      pipeline that runs weekly to rebuild the image (which will pull the latest
      version of all software during the build, including the latest quadlets and
      container images), push the newly built image to quay, then refresh the system
      with that latest image. We will then, manually or through an automated schedule,
      reboot to the latest image on a weekly basis. One of the quadlets we will
      incorporate will be a workstation image and container for using the system in
      day to day operation. We will be using btrfs send to save snapshots of our work,
      while allowing all but a couple specific directories to be kept clean. We will
      keep the container persistent so that installed software is kept, but we also
      have the option to save the containers in their state, back them up,
      then redeploy as freshly built containers, potentially after placing some of
      those changes into the next workstation image build. We'll be creating
      scheduled cron jobs or systemd timers to backup snapshots of the workstation
      directories to our separate larger drive on the same system. Those btrfs
      backups will remain untouched. We will periodically compress and encrypt
      these backups then push them to the cloud at longer intervals. 


## Access

The published OCI image is intentionally keyless: no SSH keys, no passwords,
no per-user identity is baked in. Credentials are injected at deployment
time, so the same image on Quay is safe to share publicly.

Console root autologin on tty1 (`autologin.conf`) is baked in as a recovery
fallback. It requires the virtual console, not the network, so it does not
compromise published images.

Three supported access paths:

### 1. Explore the image locally (no network, no SSH)
```bash
./run_container.sh
```
Drops you into a root bash shell inside the host image — no systemd, no SSH,
no services. Useful for poking at installed packages and file layouts.

### 2. Build and SSH into a VM from this machine
Two steps, so you can reboot the VM without re-converting the OCI image:
```bash
./02_build_vm/build_vm.sh   # auto-detects ~/.ssh/id_ed25519.pub (or id_rsa.pub),
                            # injects it into the qcow2 via bootc-image-builder,
                            # installs the disk into /var/lib/libvirt/images/
./02_build_vm/run_vm.sh     # tears down any prior VM, boots a fresh one,
                            # detects its IP, writes a 'fedora-init' block
                            # into ~/.ssh/config
ssh fedora-init             # connects with your existing key
```
Override the key lookup with `SSH_PUB_KEY_FILE=/path/to/key.pub` on either
script. Re-running `run_vm.sh` alone rebuilds the VM from the existing disk
without going through `bootc-image-builder` again.

### 3. Anyone else downloads the image and boots it (cloud-init)
The image ships with `cloud-init` installed and enabled. A downstream user
who has a pre-built qcow2/ISO doesn't need to rebuild anything — they create
a NoCloud seed with their own SSH key and attach it at boot:
```bash
# user-data with their key
cat > user-data <<EOF
#cloud-config
users:
  - name: root
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... their-key
EOF
echo "instance-id: iid-local01
local-hostname: bootc-vm" > meta-data

# build a NoCloud seed.iso
cloud-localds seed.iso user-data meta-data

# attach it to the VM (example with virt-install)
virt-install ... --disk path=disk.qcow2 --disk path=seed.iso,device=cdrom
```
First boot, cloud-init picks up the seed and writes their key into root's
`authorized_keys`. Subsequent reboots don't need the seed.

### Summary

| Scenario | Mechanism | Key source |
|----------|-----------|------------|
| Poke at the image | `./run_container.sh` | none needed |
| Build + run VM locally | `build_vm.sh` + `run_vm.sh` | your `~/.ssh/*.pub` (auto) |
| Distribute pre-built binary | cloud-init NoCloud seed | recipient's own key |



Checklist/Plan:
---
# base
    1. build bootc image (no enhancements)
        ./01_build_image/
    2. run bootc image as container
    3. choose vm software
    4. build bootc image as iso
    5. run bootc image as vm
    6. push to quay
    7. add to bootc image: pull from quay on reboot (push that update to quay)
# flash system
    8. compress + encrypt files, push as backup to GDrive
    9. build v1.0 image, push to quay
    10. pull v1.0 image, build as ISO (w/ anaconda)
    11. flash image to USB, wipe + install to system
# base image build structure
    12. build Containerfile (simple git install) (add to image build, test as container + vm)
    13. build Quadlet (simple ws-env, no integration) (add to image build, test as container + vm)
# enhance testing
    14. test GPU passthrough w/ standard vm
    15. test GPU passthrough w/ bootc image
    16. test GPU passthrough w/ bootc image + nvidia container
    17. write as automated CI/CD for image testing
        (add to image_build + fedora_init, push to quay + github, reboot)
# system wipe/build/use/backup/recovery
    18. ws-env: build access to ws-env via ssh
    19. ws-env: map persistent memory location /etc
    20. create system btrfs backup on D:/var/
    21. automate backup: ws-env -> sys-btrfs
    22. automate recovery: sys-btrfs -> ws-env directory
    23. automate backup: system btrfs backup compress/encrypt -> cloud
    24. automate recovery: cloud -> sys-btrfs


## open questions / things to finish conceptualizing
-- in the bootc image build, we can provide --fs ext4 (or ideally btrfs). can/should we provide btrfs so that we can use as a true sys admin/root?
** can we build w/o root?
** for the initial iso that we flash to a drive and boot to, we SHOULD work out all
details ahead of time, then use the bare ISO rather than use the gui installer, purely
for reproducability. If there are other benefits to the anaconda installer, then maybe
we will keep the anaconda installer. we want to discuss this and work out an intended
approach.
** more thoroughly document the process for adding Category1-4 (outlined in "process
for wiping system post-bootc) + workstation container into the bootc image (probably
through the containerfile).
** how to wipe /etc and potentially /var? use a dedicated script? when to do either?
we want the periodic updates of the bootc image to go through regularly so that we can
keep the software and kernels and kernel modules up to date. We also want to be able
to leave the workstation container at the drop of the hat and come back to it without
fear that our work will be lost. So we should have a set pipeline script to create a
clean and complete btrfs backup, then to do a full wipe and boot back with the latest
image and a completely clean system.

## process for wiping system post-bootc
- on bootc update
    - /usr is replaced
    - /etc remains
    - bootc image needs additional separate pods, quads, containers (workspace container)
    - on wipe, bootc image loads (like with bootc update)
        - bootc update would be a separate process from wipe
        - btrfs send (backup, periodically regardless of wipe)
            - could keep the backup structure and send structure in place
            - btrfs would treat these as new blocks
            - allow us to easily roll back between different wipes
            - ** could we do compression on btrfs backups between wipes? part of the CI/CD
    Category 1: write from workstation, wipe on reentry
        - anything not in specific directories
        - could still include these in the btrfs backups just in case
    Category 2: persist workstation container reboots
        - anything in $HOME/code, $HOME/notes
        - ** map to /etc or /var?
    Category 3: persist system wipes
        - anything in D:/
        - mainly: btrfs backups (uncompressed, unencrypted)
            - periodically compress, encrypt, push to cloud
        - + selective, large content (machine learning models)
    Category 4: cloud: compressed encrypted backups of Category 3 btrfs backups



- `/usr/share/containers/systemd/` — replaced wholesale by the new image. Any local edits are gone.
- `/etc/containers/systemd/` — 3-way merged. Your local edits are preserved unless the new image also changed the same lines, in which case you get a merge conflict to resolve (same as `/etc/ssh/sshd_config`).



Surface:
- bootc image:
    - kernel relevant build (nvidia-akmods, dnf update)
    - items w/ large/complex setup + minimal runtime surface
        - ssh configuration, backup process
        - systemd processes
        - can still access/modify these by logging into the server itself
            - updates maintained between reboots as layers in /etc
            - realtime changes should be worked into the bootc image build for the next build
- quadlets + pods + containers:
    - user workstation container (ws-env)
        - maps specific directories to /etc or /var to persist across reboots
        - all other files and software installs are transient until baked into ws-env image build
        - all files, including transient ones, are backed up with btrfs to /D:/var/backup
    - all will share resources and visibility as needed
    - ** future: nvidia container for building and running models
        - ** shared access w/ workstation-container to persistent directories
        - ** allows workstation-container to function w/ latest and reliable software
    - ** future: openclaw container: specific and limited access
    - ** future: containers may include things like ssh, cloudflared, btrfs-backup, etc
        - ** would allow these to be built and tested separately from core bootc image


### Workflow:
- cron job weekly
    - rebuilds bootc image w/ latest image, kernels, software
    - push image to quay
- manual reboots
    - pull the latest (by default) available image from quay
    - boots to that latest image
        - ** can we integrate automated new images/kernels/software updates without reboot? for minor updates ('dnf update ...'-esk updates) w/o shutting down the server?
- enhancements
    - pull latest image from quay
    - build locally
    - light test: run as container
    - full test:
        - wrap as VM ISO
        - run in VM
    - add new content to the image build script + ContainerFile


### bootc image breakdown
    - Containerfile (install, configure), Quadlets (run as service)
    - quadlet container images
        - services to run at startup
        - workstation container, nvidia container
    - pod quadlets
        - quadlet services w/ shared resources
        - system level, store in /etc
## 1. image Containerfile
- software installation + configuration

```dockerfile
FROM quay.io/fedora/fedora-bootc:42
RUN dnf install -y openssh-server && \
    systemctl enable sshd
COPY sshd_config_baseline /etc/ssh/sshd_config.d/99-custom.conf
```

## 2. podman quadlets (baked into the bootc image)
- pull/run containers on boot
- Fedora endorsed
- process:
    - image build includes the quadlet (a .container, .pod, .network, .volume file)
    - quadlet defines what container images to pull/build/run on boot
    - systemd-generator converts the container + quadlet definition into a systemd unit
- update container images separately from the bootc image
- latest container images are pulled and run on reboot
- sytem-wide quadlet location:
    - read-only, from your bootc image: `/usr/share/containers/systemd/`
    - mutable, for runtime additions: '/etc/containers/systemd/`

```quadlet
# /usr/share/containers/systemd/workstation.container
[Unit]
Description=Workstation container
After=network-online.target

[Container]
Image=quay.io/m0ranmcharles/fedora_init:dev-container
AutoUpdate=registry
Volume=/var/workstation-home:/home/user:Z
Network=host          # or a named network
Exec=/usr/bin/sleep infinity

[Install]
WantedBy=multi-user.target
```

### Future: 3. Podman pods via Quadlets
- potential for system services (backup CI/CD, logger, ssh)
- where services need shared resources
- would allow us to test and deploy components separately from base functional bootc
  image
- Best for tightly coupled services that need shared network/IPC namespace
- think...
    - service + its sidecar proxy
    - database + its exporter
- howto:
    - define a `.pod` Quadlet +  `.container` Quadlets that reference it
- benefit:
    - shared-namespace in pods
    - processes talk over localhost or share IPC without network overhead

```
# workstation.pod
[Pod]
PodName=workstation

# app.container
[Container]
Pod=workstation.pod
Image=quay.io/m0ranmcharles/fedora_init:dev-container

# proxy.container  
[Container]
Pod=workstation.pod
Image=quay.io/m0ranmcharles/fedora_init:backup-container
```



# workflow
- one time setup
    - push image to quay
    - build image as ISO, reboot to image (future pulls from quay)
- build, deploy
    - cron to build the latest images with updated kernels etc, push to quay
    - reboots always pull latest bootc image + quadlet containers
- enchance
    - pull image + quadlets from quay
    - light test as a container
    - full test: build as ISO, test as VM



--- START OF FILE: ./docs/README.md ---
# Documentation

## Start here
- [overview.md](overview.md) — Project vision, the 3-layer model, and the rationale for a bootc-based GPU workstation.

## By role
- **I want to use the published image**
  - [how-to/distribute_image.md](how-to/distribute_image.md)
  - [concepts/access_model.md](concepts/access_model.md)
- **I want to build and test locally**
  - [how-to/build_images.md](how-to/build_images.md)
  - [how-to/build_and_run_vm.md](how-to/build_and_run_vm.md)
  - [how-to/validate_gpu.md](how-to/validate_gpu.md)
- **I want to understand why it's built this way**
  - [overview.md](overview.md)
  - [concepts/](concepts/)
- **I want to add or update docs**
  - [contributing.md](contributing.md)

## Full index
- [overview.md](overview.md) — Project vision, the 3-layer model, and the rationale for a bootc-based GPU workstation.
- [roadmap.md](roadmap.md) — Current progress, the 24-item project checklist, and open design questions.
- [contributing.md](contributing.md) — How to find, use, and update these docs; format and structure rules for new contributions.

### Concepts
- [concepts/access_model.md](concepts/access_model.md) — The keyless image strategy and the three paths for injecting credentials at deployment.
- [concepts/bootc_and_ostree.md](concepts/bootc_and_ostree.md) — How bootc and OSTree provide an immutable, versioned filesystem for the host OS.
- [concepts/gpu_stack.md](concepts/gpu_stack.md) — Architectural split of NVIDIA drivers, toolkit, and CDI across host and container layers.
- [concepts/ownership_model.md](concepts/ownership_model.md) — The 3-layer division of responsibility between the host, containers, and Quadlets.
- [concepts/state_and_persistence.md](concepts/state_and_persistence.md) — Categorization of system state into four persistence levels across host and containers.
- [concepts/update_pipeline.md](concepts/update_pipeline.md) — The automated ephemeral-build and staging process for host image updates.

### Reference
- [reference/images.md](reference/images.md) — Factual catalog of the host, dev, backup, and builder container images.
- [reference/quadlets.md](reference/quadlets.md) — Explanation of Quadlet placement rules and their role in bridging systemd and Podman.
- [reference/registry.md](reference/registry.md) — Configuration details for the Quay.io namespace and image tagging conventions.
- [reference/repository_layout.md](reference/repository_layout.md) — Descriptive catalog of the directories, files, and top-level scripts in the repository.
- [reference/scripts.md](reference/scripts.md) — Reference catalog of the shell and Python scripts for building and maintaining the system.
- [reference/systemd_units.md](reference/systemd_units.md) — Catalog of project-specific systemd units and native host services enabled in the image.

### How-to
- [how-to/build_and_run_vm.md](how-to/build_and_run_vm.md) — Procedure for converting the image to qcow2 and booting it with libvirt.
- [how-to/build_images.md](how-to/build_images.md) — Procedure for building the host image and its associated containers on a local workstation.
- [how-to/distribute_image.md](how-to/distribute_image.md) — Instructions for a third party to boot the published image with their own SSH key.
- [how-to/push_to_quay.md](how-to/push_to_quay.md) — Guide for publishing the built images to the Quay registry.
- [how-to/run_locally.md](how-to/run_locally.md) — Steps to run an ephemeral root shell in the host image without a virtual machine.
- [how-to/validate_gpu.md](how-to/validate_gpu.md) — End-to-end verification of GPU passthrough from host driver to the dev container.
- [how-to/write_a_systemd_unit_for_the_host.md](how-to/write_a_systemd_unit_for_the_host.md) — Recipe for adding and enabling new host-level services in the image.

--- START OF FILE: ./docs/contributing.md ---
# Contributing to the docs

The operating manual for keeping `docs/` accurate, searchable, and stable as the project grows. Read this before adding, editing, removing, or reorganizing a doc.

## How the docs are organized

Three categories, each answering one question. The split is borrowed from Diátaxis — never blur the registers.

| Category | Question | Voice | Lifetime |
|---|---|---|---|
| `concepts/` | *Why* is it built this way? | Explanatory | Stable across implementations |
| `reference/` | *What* artifacts exist in the repo? | Descriptive, terse, factual | Updated whenever the code changes |
| `how-to/` | *How* do I do X? | Imperative, second-person | Updated when the procedure changes |

Plus three top-level docs:
- `overview.md` — the 2-page pitch.
- `roadmap.md` — built / planned / open questions.
- `README.md` — the index. No prose; just links.

## Finding things

- **By role:** `docs/README.md` § "By role".
- **By topic:** start with the index, then browse the category that matches your question.
- **By keyword:** `grep -rn 'term' docs/`. Each topic has exactly one canonical home; if a term appears in several files, prefer the file under `concepts/` named for it.
- **By artifact:** look in `reference/`. A Containerfile lives in `reference/images.md`, a systemd unit in `reference/systemd_units.md`, etc.

## How to use what you find

- **Reference and how-to docs describe what's in the repo today.** If a doc conflicts with the actual file, the file wins. Open an issue or fix the doc.
- **Concept docs describe intent.** If a concept doc says "X is built this way" but the code disagrees, treat it as a divergence to investigate, not a fact.
- **`(planned)` markers** flag aspirational content. Reference and how-to docs describe only what works today; planned features may appear in concepts and overview, but must carry the marker.

## Updating docs when the code changes

The reference layer is intentionally code-paired. When you change one of these, update the matching doc in the same commit:

| You changed… | Update… |
|---|---|
| A Containerfile | `reference/images.md` |
| A systemd unit (`.service`, `.path`, `.timer`, drop-in `.conf`) | `reference/systemd_units.md` |
| A Quadlet (`.kube`, `.yaml`, `.container`) | `reference/quadlets.md` |
| A shell or Python script (repo root or `build_assets/`) | `reference/scripts.md` |
| Quay account / tagging conventions | `reference/registry.md` |
| Tree shape (new top-level dirs, new repo-root files) | `reference/repository_layout.md` |
| A procedure (build / run / push / validate / distribute) | the matching file in `how-to/` |
| Architecture or rationale | the matching file in `concepts/` |

When something planned becomes built: drop the `(planned)` marker and move the line from "Planned" to "Built today" in `roadmap.md`.

## Adding a new doc

1. **Decide the category** by the question it answers — *why* (concept), *what* (reference), or *do* (how-to).
2. **Check for overlap.** If your topic mostly belongs in an existing doc, add a section there instead. The docs work because each topic has exactly one canonical home.
3. **Follow the shape** for that category:
   - **Concept**: `## What`, `## Why`, `## Implications`, `## See also`. Cap ~3 pages.
   - **Reference**: one section per artifact, with `Path`, `Purpose` (1 sentence), key fields, `Notes` only if non-obvious. Link to the source file; never reproduce it whole.
   - **How-to**: `## Goal`, `## Prerequisites`, `## Steps` (numbered, copy-pasteable), `## Verify`, `## Troubleshooting` (only real failures, not speculative).
4. **Add it to `README.md`** under the matching category in "Full index" with a one-line description.
5. **Verify links** before committing (see "Mechanical checks" below).

## Style and structure rules

Hard constraints. PR review will flag violations.

- **Sentence-case headings**: `# Update pipeline`, not `# Update Pipeline`.
- **Headings as statements**, not questions: `## Why CDI is generated at boot`, not `## Why is CDI generated at boot?`.
- **Inline code for paths**: `` `01_build_image/build_assets/Containerfile` ``.
- **Cross-doc references** as on-disk paths: write `` `concepts/<topic>.md` `` (e.g. `` `concepts/gpu_stack.md` ``), not bare names like "the GPU stack concept doc".
- **Code blocks tagged** with their language (`bash`, `yaml`, `ini`, `dockerfile`, `text` for ASCII diagrams).
- **No emojis.**
- **Terminology contract** — use these terms exactly:
  - **host image** (NOT "bootc image" or "OS image")
  - **dev pod**, **dev container**, **backup sidecar**
  - **Quay** for the registry by name; "the registry" only when generic
- **No essays.** State the decision, name the alternative in one sentence, give one paragraph of rationale.
- **Code excerpts are illustrative.** Always give a path and a "see the file in the repo for the authoritative version" pointer. Don't reproduce whole files.

## Reviewing, consolidating, and removing

- **Duplication signal.** If you can't decide where to put something because two docs both seem to fit, the docs already overlap — consolidate first, then add.
- **Stale reference docs** are the most common form of rot. When a Containerfile, unit, or script is deleted or renamed, search `docs/reference/` for any mention and update or remove.
- **Removing a doc.** If a topic disappears entirely, delete the file and its `README.md` index entry in the same commit. Don't leave behind "deprecated" stubs — git history is the archive.
- **Renaming a doc.** Update every cross-reference and the `README.md` index entry. Keep no stub at the old path.

## Mechanical checks before committing

Run from the repo root:

```bash
# 1. All internal links resolve
python3 - <<'PY'
import re, pathlib
docs = pathlib.Path('docs')
broken = []
for f in docs.rglob('*.md'):
    if f.name in ('DOCS_PLAN.md', 'README.legacy.md'):
        continue
    text = f.read_text()
    for m in re.finditer(r'\]\(([^)]+)\)', text):
        link = m.group(1).split('#')[0].strip()
        if not link or link.startswith(('http://', 'https://', 'mailto:')):
            continue
        if not (f.parent / link).resolve().exists():
            broken.append((str(f), link))
    for m in re.finditer(r'`((?:concepts|reference|how-to)/[^`\s]+\.md)`', text):
        link = m.group(1)
        if any(c in link for c in '<*'):  # skip illustrative placeholders like `concepts/<topic>.md`
            continue
        if not (docs / link).resolve().exists():
            broken.append((str(f), link))
print('OK' if not broken else broken)
PY

# 2. No leaked Gemini citation markers
! grep -rn '\[cite_start\]\|\[cite:' docs/

# 3. No forbidden terminology in newly authored docs
#    (roadmap.md preserves source wording from the original checklist; ignore matches there.)
grep -rn '\bbootc image\b\|\bOS image\b' \
  docs/concepts docs/reference docs/how-to docs/overview.md docs/README.md
```

If any check flags something, fix the doc before merging.

## Guidance for AI agents

If you're an AI agent writing or editing these docs:

- **Read the actual repo file before describing it.** Do not paraphrase from memory or from a sibling doc — every reference-doc claim must trace to the file in the repo at HEAD.
- **Prefer editing an existing doc to creating a new one.** If you create a new file, justify the new path against the categories above and add it to the `README.md` index in the same change.
- **Keep `(planned)` markers honest.** If the code shows the feature is built, drop the marker. If it's still aspirational, keep it.
- **Write to disk.** When asked to produce a file, use a file-write tool; do not dump content into a chat reply.
- **Don't promote `CLAUDE.md` or `GEMINI.md` content into the docs verbatim.** Those are agent-context files, not source material.
--- END OF FILE: ./docs/contributing.md ---
