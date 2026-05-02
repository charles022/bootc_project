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
- **I want to run the host as a multi-tenant platform**
  - [concepts/multi_tenant_architecture.md](concepts/multi_tenant_architecture.md)
  - [reference/platformctl.md](reference/platformctl.md)
  - [how-to/create_a_tenant.md](how-to/create_a_tenant.md)
  - [how-to/verify_tenant_isolation.md](how-to/verify_tenant_isolation.md)
  - [how-to/enroll_a_credential.md](how-to/enroll_a_credential.md)
  - [how-to/create_an_agent.md](how-to/create_an_agent.md)
  - [how-to/enroll_messaging.md](how-to/enroll_messaging.md)
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
- [concepts/agent_provisioning.md](concepts/agent_provisioning.md) — Agent self-provisioning via `agentctl`: policy / quota / grant validation pipeline, wire protocol, on-disk layout.
- [concepts/bootc_and_ostree.md](concepts/bootc_and_ostree.md) — How bootc and OSTree provide an immutable, versioned filesystem for the host OS.
- [concepts/credential_broker.md](concepts/credential_broker.md) — Tenant credential ownership, encrypted store, scoped grants, audit log, wire protocol.
- [concepts/gpu_stack.md](concepts/gpu_stack.md) — Architectural split of NVIDIA drivers, toolkit, and CDI across host and container layers.
- [concepts/messaging_interface.md](concepts/messaging_interface.md) — Phase-4 messaging-bridge sidecars, runtime verb-table router, sender allow-listing.
- [concepts/multi_tenant_architecture.md](concepts/multi_tenant_architecture.md) — Multi-tenant rootless-Podman platform: per-tenant non-login service accounts, host control plane, OpenClaw agent pods.
- [concepts/ownership_model.md](concepts/ownership_model.md) — The 3-layer division of responsibility between the host, containers, and Quadlets.
- [concepts/state_and_persistence.md](concepts/state_and_persistence.md) — Categorization of system state into four persistence levels across host and containers.
- [concepts/tenant_identity_model.md](concepts/tenant_identity_model.md) — Non-login service accounts, subuid/subgid, rootless Podman per tenant.
- [concepts/tenant_storage_layout.md](concepts/tenant_storage_layout.md) — `/var/lib/openclaw-platform/` filesystem layout and mount policy.
- [concepts/update_pipeline.md](concepts/update_pipeline.md) — The automated ephemeral-build and staging process for host image updates.

### Design
- [design/multi_tenant_architecture.md](design/multi_tenant_architecture.md) — The full 23-section plan for the multi-tenant rootless-Podman platform.

### Reference
- [reference/agentctl.md](reference/agentctl.md) — Tenant-side CLI inside the openclaw-runtime container for self-provisioning.
- [reference/images.md](reference/images.md) — Factual catalog of the host, dev, backup, and builder container images.
- [reference/platformctl.md](reference/platformctl.md) — Admin CLI for tenant lifecycle on the multi-tenant host.
- [reference/quadlets.md](reference/quadlets.md) — Explanation of Quadlet placement rules and their role in bridging systemd and Podman.
- [reference/registry.md](reference/registry.md) — Configuration details for the Quay.io namespace and image tagging conventions.
- [reference/repository_layout.md](reference/repository_layout.md) — Descriptive catalog of the directories, files, and top-level scripts in the repository.
- [reference/scripts.md](reference/scripts.md) — Reference catalog of the shell and Python scripts for building and maintaining the system.
- [reference/systemd_units.md](reference/systemd_units.md) — Catalog of project-specific systemd units and native host services enabled in the image.
- [reference/tenant_quadlets.md](reference/tenant_quadlets.md) — Tenant-pod Quadlet templates and per-UID placement under `/etc/containers/systemd/users/`.

### How-to
- [how-to/build_and_run_vm.md](how-to/build_and_run_vm.md) — Procedure for converting the image to qcow2 and booting it with libvirt.
- [how-to/build_images.md](how-to/build_images.md) — Procedure for building the host image and its associated containers on a local workstation.
- [how-to/create_a_tenant.md](how-to/create_a_tenant.md) — Admin walkthrough for `platformctl tenant create`.
- [how-to/create_an_agent.md](how-to/create_an_agent.md) — Phase-3 agent provisioning via `platformctl agent create` or `agentctl create-agent`.
- [how-to/distribute_image.md](how-to/distribute_image.md) — Instructions for a third party to boot the published image with their own SSH key.
- [how-to/enroll_a_credential.md](how-to/enroll_a_credential.md) — Phase-2 credential enrollment, grants, and verification through the broker.
- [how-to/enroll_messaging.md](how-to/enroll_messaging.md) — Phase-4 walkthrough: enroll email / Signal credentials, set sender allow-list, attach a bridge to the main agent.
- [how-to/verify_tenant_isolation.md](how-to/verify_tenant_isolation.md) — Phase-1 isolation checks via `platformctl tenant verify-isolation`.
- [how-to/push_to_quay.md](how-to/push_to_quay.md) — Guide for publishing the built images to the Quay registry.
- [how-to/run_locally.md](how-to/run_locally.md) — Steps to run an ephemeral root shell in the host image without a virtual machine.
- [how-to/staged_validation.md](how-to/staged_validation.md) — Three-stage process for validating the dev pod by peeling back manual steps as automation is verified.
- [how-to/validate_gpu.md](how-to/validate_gpu.md) — End-to-end verification of GPU passthrough from host driver to the dev container.
- [how-to/write_a_systemd_unit_for_the_host.md](how-to/write_a_systemd_unit_for_the_host.md) — Recipe for adding and enabling new host-level services in the image.
