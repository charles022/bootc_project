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
- [how-to/staged_validation.md](how-to/staged_validation.md) — Three-stage process for validating the dev pod by peeling back manual steps as automation is verified.
- [how-to/validate_gpu.md](how-to/validate_gpu.md) — End-to-end verification of GPU passthrough from host driver to the dev container.
- [how-to/write_a_systemd_unit_for_the_host.md](how-to/write_a_systemd_unit_for_the_host.md) — Recipe for adding and enabling new host-level services in the image.
