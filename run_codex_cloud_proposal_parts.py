#!/usr/bin/env python3
"""Submit Codex Cloud implementation tasks for proposal sections.

Each submitted task receives the full proposal for context, then is assigned
one numbered implementation section to vet, plan, implement, and commit.
"""

from __future__ import annotations

import argparse
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_PROPOSAL = "proposal-gpu-dev-to-tenant.md"
DEFAULT_MODEL = "gpt-5.5"
DEFAULT_EFFORT = "medium"
YOLO_FLAGS = (
    "--yolo",
    "--dangerously-bypass-approvals-and-sandbox",
)


@dataclass(frozen=True)
class ProposalSection:
    index: int
    level: int
    title: str
    body: str

    @property
    def part_label(self) -> str:
        match = re.match(r"^(\d+)\.", self.title)
        if match:
            return match.group(1)
        return str(self.index)

    @property
    def slug(self) -> str:
        slug = re.sub(r"[^a-z0-9]+", "-", self.title.lower()).strip("-")
        return slug[:48] or f"section-{self.index}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Loop over proposal sections and submit one `codex cloud exec` "
            "task for each section."
        )
    )
    parser.add_argument(
        "--env",
        required=True,
        help="Codex Cloud environment ID to pass to `codex cloud exec --env`.",
    )
    parser.add_argument(
        "--proposal",
        default=DEFAULT_PROPOSAL,
        help=f"Proposal markdown file. Defaults to {DEFAULT_PROPOSAL}.",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Model override. Defaults to {DEFAULT_MODEL}.",
    )
    parser.add_argument(
        "--effort",
        default=DEFAULT_EFFORT,
        choices=("low", "medium", "high", "xhigh"),
        help=f"Reasoning effort override. Defaults to {DEFAULT_EFFORT}.",
    )
    parser.add_argument(
        "--branch-prefix",
        default="codex/gpu-dev-to-tenant",
        help=(
            "Branch prefix for submitted tasks. Each section gets a distinct "
            "branch suffix."
        ),
    )
    parser.add_argument(
        "--section-regex",
        default=r"^\d+\.\s+",
        help=(
            "Regex matched against heading text to choose sections. Defaults "
            "to numbered plan headings such as `0. Prove rootless...`."
        ),
    )
    parser.add_argument(
        "--include-level",
        type=int,
        default=3,
        help="Markdown heading level to scan. Defaults to 3 (`###`).",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help=(
            "Submit only sections whose title contains this text. May be "
            "repeated."
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Maximum number of sections to submit. Defaults to all matches.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the commands that would run without submitting tasks.",
    )
    parser.add_argument(
        "--codex-bin",
        default="codex",
        help="Codex CLI executable. Defaults to `codex`.",
    )
    parser.add_argument(
        "--no-yolo",
        action="store_true",
        help=(
            "Do not request YOLO-style Codex execution. By default, the script "
            "uses --yolo or --dangerously-bypass-approvals-and-sandbox when "
            "the installed CLI supports one of them."
        ),
    )
    return parser.parse_args()


def load_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"error: {path} does not exist") from None


def split_sections(markdown: str, heading_level: int) -> list[ProposalSection]:
    heading = "#" * heading_level
    pattern = re.compile(rf"^(?P<marks>{re.escape(heading)})\s+(?P<title>.+?)\s*$", re.M)
    matches = list(pattern.finditer(markdown))
    sections: list[ProposalSection] = []

    for index, match in enumerate(matches, start=1):
        start = match.end()
        end = matches[index].start() if index < len(matches) else len(markdown)
        sections.append(
            ProposalSection(
                index=index,
                level=heading_level,
                title=match.group("title").strip(),
                body=markdown[start:end].strip(),
            )
        )

    return sections


def select_sections(args: argparse.Namespace, proposal: str) -> list[ProposalSection]:
    title_re = re.compile(args.section_regex)
    sections = [
        section
        for section in split_sections(proposal, args.include_level)
        if title_re.search(section.title)
    ]

    for needle in args.only:
        needle_lower = needle.lower()
        sections = [section for section in sections if needle_lower in section.title.lower()]

    if args.limit:
        sections = sections[: args.limit]

    if not sections:
        raise SystemExit(
            "error: no proposal sections matched; adjust --include-level or --section-regex"
        )

    return sections


def build_prompt(section: ProposalSection, proposal_path: Path, proposal: str) -> str:
    return f"""You are Codex Cloud working in the bootc_project repository.

Background:
- This repository builds a bootc-based Fedora GPU workstation host image and managed workload containers.
- Active implementation lives mainly in `01_build_image/build_assets/`.
- Canonical docs are under `docs/`; before changing docs, read `docs/contributing.md`.
- Preserve the architecture: the host image owns hardware, boot, SSH, systemd, and CDI; tenant/rootless containers own workload runtimes.
- Do not bake SSH keys, passwords, registry credentials, or host-specific CDI files into images.

Overall goal:
Promote the existing system-wide GPU devpod capability into the tenant/agent architecture described in `{proposal_path}`, while keeping the implementation incremental and safe. The tenant GPU path should be built and validated before removing the old system dev pod.

Full proposal content:

```markdown
{proposal}
```

Assigned part {section.part_label}: {section.title}

Assigned part content:

```markdown
### {section.title}

{section.body}
```

Task:
1. Vet assigned part {section.part_label} against the current repository state. Read the relevant files before making claims or edits.
2. Create a concise implementation plan for assigned part {section.part_label}. Account for ordering, tests, documentation rules, and any hardware or network validation gates.
3. Complete the plan you created as far as this repository can support in Codex Cloud. If a step requires unavailable NVIDIA hardware, registry credentials, or another external dependency, implement the preparatory repository changes and document the remaining validation gate in the commit message or changed docs where appropriate.
4. Run focused validation. At minimum, run syntax/static checks for changed scripts or Python files; run documentation link checks if docs change.
5. Commit the changes with a short, descriptive commit message. Keep the commit focused on assigned part {section.part_label}: {section.title}.

Do not implement unrelated proposal sections except where strictly required by this part's dependencies.
"""


def command_for_section(
    args: argparse.Namespace,
    section: ProposalSection,
    prompt: str,
    yolo_flag: str | None,
) -> list[str]:
    branch = f"{args.branch_prefix}-part-{section.part_label}-{section.slug}"
    cmd = [
        args.codex_bin,
    ]
    if yolo_flag:
        cmd.append(yolo_flag)
    cmd.extend(
        [
            "cloud",
            "exec",
            "--env",
            args.env,
            "--branch",
            branch,
            "-c",
            f'model="{args.model}"',
            "-c",
            f'model_reasoning_effort="{args.effort}"',
            prompt,
        ]
    )
    return cmd


def shell_quote(argv: list[str]) -> str:
    return shlex.join(argv)


def supported_yolo_flag(codex_bin: str) -> str | None:
    try:
        completed = subprocess.run(
            [codex_bin, "--help"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except FileNotFoundError:
        raise SystemExit(f"error: {codex_bin!r} was not found") from None

    help_text = completed.stdout
    for flag in YOLO_FLAGS:
        if flag in help_text:
            return flag
    return None


def main() -> int:
    args = parse_args()
    proposal_path = Path(args.proposal)
    proposal = load_text(proposal_path)
    sections = select_sections(args, proposal)
    yolo_flag = None if args.no_yolo else supported_yolo_flag(args.codex_bin)

    print(f"Matched {len(sections)} proposal section(s):")
    for section in sections:
        print(f"  part {section.part_label}: {section.title}")
    if args.no_yolo:
        print("YOLO-style execution disabled by --no-yolo.")
    elif yolo_flag:
        print(f"Using Codex YOLO-style flag: {yolo_flag}")
    else:
        print("Installed Codex CLI does not expose a YOLO-style flag; submitting without one.")

    for ordinal, section in enumerate(sections, start=1):
        prompt = build_prompt(section, proposal_path, proposal)
        cmd = command_for_section(args, section, prompt, yolo_flag)
        print(
            f"\n[{ordinal}/{len(sections)}] submitting part "
            f"{section.part_label}: {section.title}"
        )
        print(shell_quote(cmd[:-1] + ["<prompt>"]))
        if args.dry_run:
            continue

        completed = subprocess.run(cmd, check=False)
        if completed.returncode != 0:
            print(
                f"error: codex cloud exec failed for part {section.part_label} "
                f"with exit code {completed.returncode}",
                file=sys.stderr,
            )
            return completed.returncode

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
