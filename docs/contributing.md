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
  - **tenant** (a platform identity backed by a non-login service account; never "user" in the multi-tenant context)
  - **tenant service account** (e.g. `tenant_alice`); never "tenant user" or "guest user"
  - **OpenClaw runtime**, **dev environment**, **cloudflared sidecar**, **credential proxy** for the tenant pod's containers
  - **`platformctl`** (admin CLI), **`agentctl`** (agent CLI, planned), **`openclaw-broker`** (host service)
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
