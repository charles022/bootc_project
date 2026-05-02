# Quadlets

Quadlets are the mechanism for bridging systemd and Podman in this project. They allow containerized workloads to be managed as standard system services, ensuring they start at boot and restart on failure.

## Placement rules

Quadlet files in this project are baked into the **host image** during the build process.

* **System-wide (Standard):** Files are installed at `/usr/share/containers/systemd/`. This directory is for immutable units provided by the image. The system dev pod (`devpod.kube`) lives here.
* **Mutable/Local:** Files placed at `/etc/containers/systemd/` are mutable but subject to three-way merges during bootc updates.
* **User-scoped:** Quadlets can also live in `~/.config/containers/systemd/` for services that should run under a specific user session (not used by the system dev pod).
* **Per-UID admin-managed:** Files placed under `/etc/containers/systemd/users/<UID>/` are admin-authored, root-owned, and processed by the user-mode Quadlet generator only for the matching UID. The multi-tenant layer renders tenant pods here so the **host owns the desired config** while the **tenant service account owns runtime state**. See `reference/tenant_quadlets.md`.

## Lifecycle

The Quadlet generator runs at boot and on `systemctl daemon-reload`. Editing a `.kube`, `.container`, `.pod`, or referenced `.yaml` file under `/etc/containers/systemd/` followed by `sudo systemctl daemon-reload` regenerates the corresponding `.service` without a reboot. Files baked into `/usr/share/containers/systemd/` change only via a host image update.

## Container image updates independent of the OS

Adding `AutoUpdate=registry` to a `.container` (or a `.kube`'s referenced manifest, where supported) lets `podman auto-update` (manual or via its systemd timer) refresh the container image on its own cadence. This is orthogonal to the bootc OS update path — the host image lifecycle and the workload container lifecycles are decoupled.

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

⚠️ **DESIGN DEBT** — The backup sidecar inside the dev pod is a temporary placeholder. The final backup implementation will be a **host-level systemd service** that operates independently, creating automatic backups of dev environment files without requiring a sidecar container in the pod. Do not deepen the pod-sidecar pattern before this is redesigned.

### Keepalive in the container command

The dev container's startup script ends with `tail -f /dev/null` (the equivalent of `sleep infinity`) so the container stays alive after the smoke test exits and remains reachable via `podman exec`. Without it, the pod would terminate as soon as the smoke test returned, and `restartPolicy: Always` would loop it.
