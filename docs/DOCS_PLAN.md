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
  builds, dev pod + backup service (host Quadlet), VM build path, Quay push, GPU CDI plumbing.
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
   - "backup service (host)" for the host-managed backup container.
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
