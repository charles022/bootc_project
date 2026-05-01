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
- multi-tenant Phase 0 scaffold: `platformctl` admin CLI, per-tenant non-login service account creation, per-tenant Quadlet rendering under `/etc/containers/systemd/users/<UID>/`, tenant storage layout under `/var/lib/openclaw-platform/tenants/<tenant>/`, `openclaw-broker.service` stub, Phase-0 stub container images (`openclaw-runtime`, `credential-proxy`, `onboarding-env`)
- multi-tenant Phase 1 isolation: `platformctl tenant inspect`, `platformctl tenant verify-isolation` (pairwise + per-tenant), `platformctl tunnel set-config | set-credentials | show | list`, collision-free fallback subuid/subgid allocator, `how-to/verify_tenant_isolation.md` walkthrough
- multi-tenant Phase 2 credential broker: `openclaw-broker` daemon with Fernet-encrypted store, grant table, audit log, admin socket (UID-0-enforced) + per-tenant sockets; real `credential-proxy` container; `platformctl credential | grant | audit` admin subcommands; `tenant_register` / `tenant_unregister` integration in `tenant create | delete`; `how-to/enroll_a_credential.md` walkthrough
- multi-tenant Phase 3 agent provisioning: `openclaw-provisioner` daemon (policy + quota engines, broker-cross-checked credential validation, agent Quadlet rendering, systemd start/stop, audit); `agentctl` CLI shipped in the openclaw-runtime container; agent Quadlet templates at `templates/agent_quadlet/`; `platformctl agent create | list | inspect | start | stop | delete` and `platformctl policy show` admin subcommands; real default `policy.yaml` written by `platformctl tenant create`; `how-to/create_an_agent.md` walkthrough

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

### composition
25. layered host images (planned) — additional machine roles can be built as `FROM quay.io/m0ranmcharles/fedora_init:latest` Containerfiles that add role-specific packages, units, and Quadlets on top of the base host. This keeps a single base image canonical while letting other machines (e.g., a build host, a serving host) diverge by addition rather than fork.

### multi-tenant
26. Phase 0 — minimal proof of concept (done): `platformctl tenant create` produces a non-login service account, allocates subuid/subgid, lays out `/var/lib/openclaw-platform/tenants/<tenant>/`, renders the onboarding-pod Quadlets, enables lingering, and starts the pod under the tenant's user manager. Cloudflared sidecar restart-loops until a real tunnel token is provisioned. Phase-0 stubs ship for the `openclaw-runtime`, `credential-proxy`, and `onboarding-env` container images.
27. Phase 1 — proper tenant isolation (done): collision-free fallback subuid/subgid allocator (replaces the Phase-0 hardcoded range bug); `platformctl tenant inspect` and `platformctl tenant verify-isolation` for per-tenant invariants and pairwise checks (distinct UIDs, disjoint subuid/subgid ranges, distinct storage roots, cross-tenant filesystem-read denial, root-owned per-UID Quadlet dirs); `platformctl tunnel set-config | set-credentials | show | list` for separate cloudflared routes per tenant; `how-to/verify_tenant_isolation.md` walkthrough.
28. Phase 2 — credential broker (done): `openclaw-broker` daemon (Python, single file) at `/usr/local/bin/openclaw-broker`. Fernet-encrypted credential store, grant table, append-only audit log. Admin socket at `/run/openclaw-broker/admin.sock` (peer-UID 0 enforced via `SO_PEERCRED`); per-tenant socket at `/run/openclaw-broker/tenants/<tenant>.sock` chowned to `tenant_<tenant>`. Real `credential-proxy` container (replaces the Phase-0 stub) bind-mounts the per-tenant socket and re-exposes `credential_request` / `agent_grants` / `ping` on a pod-local agent socket. `platformctl credential | grant | audit` admin subcommands. `platformctl tenant create | delete` integrated with the broker via `tenant_register` / `tenant_unregister`. `how-to/enroll_a_credential.md` walkthrough. Login-URL OAuth flow and the in-tenant `openclaw-onboard` CLI remain planned (Phase 4); sealed/HSM-backed master key and scheduled rotation remain planned (Phase 5).
29. Phase 3 — agent provisioning (done): `openclaw-provisioner` daemon at `/usr/local/bin/openclaw-provisioner` (Python single-file, `Type=simple`, restart-on-failure). Reads per-tenant `policy.yaml`, validates `agent_create` against allowed images / credentials / networks / volumes / quotas / forbidden flags, cross-checks credentials with the broker, renders agent Quadlets from `/var/lib/openclaw-platform/templates/agent_quadlet/`, then `daemon-reload` + `systemctl --user --machine=tenant_<tenant>@ start <tenant>-<agent>-pod.service`. Records each agent at `tenants/<tenant>/agents/<agent>.json` per the §15.4 object model. Append-only audit log at `provisioner/audit.log`. Admin socket at `/run/openclaw-provisioner/admin.sock` (UID 0); per-tenant socket at `/run/openclaw-provisioner/tenants/<tenant>.sock` (chowned to `tenant_<tenant>`) — bind-mounted into the openclaw-runtime container at `/run/agentctl/agentctl.sock` so the in-container `agentctl` CLI can self-provision. `platformctl agent create | list | inspect | start | stop | delete` and `platformctl policy show` admin subcommands. `platformctl tenant create` now writes a real default `policy.yaml`. `how-to/create_an_agent.md` walkthrough. Still planned: `agentctl create-env`, `attach-storage`/`detach-storage`, per-agent cgroup enforcement, messaging-driven creation.
30. Phase 4 — messaging-first interface (planned): Signal/WhatsApp/email bridges, message-driven agent creation.
31. Phase 5 — production hardening (planned): backups, restore tests, host rollback tests, tenant deletion tests, credential revocation tests, SELinux review, network egress policy, resource quotas, logging/audit.

## Open questions
- in the bootc image build, we can provide --fs ext4 (or ideally btrfs). can/should we provide btrfs so that we can use as a true sys admin/root?
- can we build w/o root?
- for the initial iso that we flash to a drive and boot to, we SHOULD work out all details ahead of time, then use the bare ISO rather than use the gui installer, purely for reproducability. If there are other benefits to the anaconda installer, then maybe we will keep the anaconda installer. we want to discuss this and work out an intended approach.
- more thoroughly document the process for adding Category1-4 (outlined in "process for wiping system post-bootc) + workstation container into the bootc image (probably through the containerfile).
- how to wipe /etc and potentially /var? use a dedicated script? when to do either? we want the periodic updates of the bootc image to go through regularly so that we can keep the software and kernels and kernel modules up to date. We also want to be able to leave the workstation container at the drop of the hat and come back to it without fear that our work will be lost. So we should have a set pipeline script to create a clean and complete btrfs backup, then to do a full wipe and boot back with the latest image and a completely clean system.
