📁 docs/design/ (Architecture & Design Choices)

This bucket should house the conceptual models, architectural decisions, and the "why" behind the
project.

 * System Architecture & The Ownership Model
     * Concept: The strict 3-layer separation of concerns.
     * Specifics: The Host (Bootc Image) owns hardware, boot, and systemd. The Dev Container owns the
       workload runtime (PyTorch, tools). Quadlets own the bridge (container lifecycle).
     * Sourced from: process_separation_model.md, README.md, bootc_and_container_build.md
 * Filesystem Mutability & State Persistence
     * Concept: How the bootc/ostree filesystem operates and where to store data.
     * Specifics: /usr is immutable (replaced on upgrade), /etc is mutable (3-way merged on upgrade),
       and /var is fully persistent. This drives decisions on where to put system configurations versus
       workstation data.
     * Sourced from: ostree_notes.md, README.md
 * GPU Integration Strategy
     * Concept: The decoupled approach to exposing hardware acceleration.
     * Specifics: Why the open kernel modules and container toolkit live on the host, while CUDA and ML
       frameworks live exclusively in the containers.
     * Sourced from: where_nvidia_belongs.md, gpu_integration_path.md
 * Quadlet Design Logic (Why .kube over .container)
     * Concept: The orchestration strategy for GPU passthrough.
     * Specifics: The deliberate choice to use Kubernetes-style Pod YAMLs and .kube Quadlets to access
       the documented nvidia.com/gpu=all CDI selector, rather than relying on undocumented paths in
       .container files.
     * Sourced from: explanaition_of_gpu_integration_path.md, gpu_integration_path.md
 * Access & Authentication Philosophy
     * Concept: Building "keyless" and secure OCI images.
     * Specifics: Why the host image contains no baked-in SSH keys or passwords, relying instead on
       deployment-time injection via config.toml or cloud-init.
     * Sourced from: README.md

📁 docs/technical_implementation/ (Methods, Code, and Specifics)

This bucket should house the concrete implementation details, code snippets, CLI workflows, and the
"how-to" aspects of the project.

 * Bootc Initialization & Startup Commands
     * Specifics: Why OCI CMD and ENTRYPOINT fail on bare-metal bootc. The exact systemd oneshot unit
       syntax required to run startup scripts, and how to use ConditionFirstBoot=yes to prevent repeated
       execution.
     * Sourced from: bootc_init_cmd.md
 * NVIDIA CDI Generation Implementation
     * Specifics: The exact packages installed via dnf (nvidia-open, nvidia-container-toolkit). The code
       for nvidia-cdi-refresh.service that runs nvidia-ctk cdi generate at boot to create
       /etc/cdi/nvidia.yaml.
     * Sourced from: bootc_and_container_build.md, where_nvidia_belongs.md, gpu_integration_path.md
 * Quadlet and Pod YAML Syntax
     * Specifics: Code snippets for devpod.kube (including the [Install] section for auto-start) and
       devpod.yaml (including the resources.limits for GPU and the sleep infinity command for the
       interactive dev environment).
     * Sourced from: bootc_and_container_build.md, ostree_notes.md
 * Staged Testing & Validation Pipeline
     * Specifics: The 4-stage integration testing process (manual run -> auto-start container ->
       auto-start workload). The exact train_smoke.py script used to validate the PyTorch/CUDA
       connection.
     * Sourced from: bootc_and_container_build.md
 * VM Conversion & Execution Commands
     * Specifics: The complex CLI workflow for testing: piping the image to sudo podman save/load,
       running bootc-image-builder to generate a qcow2 virtual disk, generating the config.toml for SSH
       key injection, and booting with virt-install.
     * Sourced from: bootc_and_container_build.md, README.md
 * Quay Registry Workflows
     * Specifics: Step-by-step CLI instructions for generating Quay encrypted passwords, podman login,
       tagging, and pushing the v2s2 formatted images.
     * Sourced from: quay_repository.md
 * Kernel Module (DKMS) Building Edge-Cases
     * Specifics: The technical nuance and risk of nvidia-open building kernel modules via DKMS inside
       the unbooted container build, and the strategy to fallback to akmods on first boot if needed.
     * Sourced from: where_nvidia_belongs.md, gpu_integration_path.md

We have a lot of duplicated context across files like where_nvidia_belongs.md, gpu_integration_path.md,
and bootc_and_container_build.md. Rewriting these into consolidated documents inside your new directory
structure will make the repository much easier to maintain. Would you like me to start drafting any of
these consolidated documents?

