#!/usr/bin/env python3
"""Patch NVIDIA 590 DKMS sources for Linux 6.19 API changes."""

from __future__ import annotations

import os
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> bool:
    text = path.read_text()
    if new in text:
        return False
    if old not in text:
        raise SystemExit(f"{path}: expected text not found")
    path.write_text(text.replace(old, new, 1))
    return True


def insert_once(path: Path, marker: str, insertion: str) -> bool:
    text = path.read_text()
    if insertion.strip() in text:
        return False
    if marker not in text:
        raise SystemExit(f"{path}: marker not found")
    path.write_text(text.replace(marker, marker + insertion, 1))
    return True


def patch_tree(root: Path) -> None:
    uvm_hmm = root / "kernel-open/nvidia-uvm/uvm_hmm.c"
    uvm_pmm = root / "kernel-open/nvidia-uvm/uvm_pmm_gpu.c"

    insert_once(
        uvm_hmm,
        '#include "uvm_tools.h"\n',
        "\n#include <linux/version.h>\n",
    )
    replace_once(
        uvm_hmm,
        "        zone_device_page_init(dpage);\n",
        """#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0)
        zone_device_page_init(dpage, NULL, 0);
#else
        zone_device_page_init(dpage);
#endif
""",
    )

    insert_once(
        uvm_pmm,
        '#include "uvm_linux.h"\n',
        "\n#include <linux/version.h>\n",
    )
    replace_once(
        uvm_pmm,
        "static void devmem_page_free(struct page *page)\n{\n",
        """#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0)
static void devmem_folio_free(struct folio *folio)
{
    struct page *page = &folio->page;
#else
static void devmem_page_free(struct page *page)
{
#endif
""",
    )
    replace_once(
        uvm_pmm,
        "    .page_free = devmem_page_free,\n    .migrate_to_ram = devmem_fault_entry,\n",
        """#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0)
    .folio_free = devmem_folio_free,
#else
    .page_free = devmem_page_free,
#endif
    .migrate_to_ram = devmem_fault_entry,
""",
    )
    replace_once(
        uvm_pmm,
        "static void device_p2p_page_free(struct page *page)\n{\n",
        """#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0)
static void device_p2p_folio_free(struct folio *folio)
{
    struct page *page = &folio->page;
#else
static void device_p2p_page_free(struct page *page)
{
#endif
""",
    )
    replace_once(
        uvm_pmm,
        "static void device_coherent_page_free(struct page *page)\n{\n    device_p2p_page_free(page);\n}\n",
        """#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0)
static void device_coherent_folio_free(struct folio *folio)
{
    device_p2p_folio_free(folio);
}
#else
static void device_coherent_page_free(struct page *page)
{
    device_p2p_page_free(page);
}
#endif
""",
    )
    replace_once(
        uvm_pmm,
        "    .page_free = device_coherent_page_free,\n",
        """#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0)
    .folio_free = device_coherent_folio_free,
#else
    .page_free = device_coherent_page_free,
#endif
""",
    )
    replace_once(
        uvm_pmm,
        "    .page_free = device_p2p_page_free,\n",
        """#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0)
    .folio_free = device_p2p_folio_free,
#else
    .page_free = device_p2p_page_free,
#endif
""",
    )


def main() -> None:
    src_root = Path(os.environ.get("NVIDIA_DKMS_SRC_ROOT", "/usr/src"))
    roots = sorted(src_root.glob("nvidia-*"))
    if not roots:
        raise SystemExit(f"no {src_root}/nvidia-* DKMS source tree found")

    for root in roots:
        patch_tree(root)
        print(f"patched {root}")


if __name__ == "__main__":
    main()
