The right mental model is:

## The dev container is **not** your old server

In a traditional server workflow, the server itself is the long-lived runtime surface, so you naturally attach services directly to it with systemd. In the bootc + dev-container model, that responsibility is split:

* the **bootc host** owns **boot, orchestration, hardware integration, and host-level services**
* the **dev container** owns **the workload environment** and usually runs **one primary process pattern at a time**
* **Quadlet/systemd on the host** is the bridge that makes containers start, stop, and restart like managed services at boot. ([Podman Documentation][1])

That means the best translation from the old model is usually **not** “put systemd inside the dev container.” It is:

* **host systemd** for host concerns
* **Quadlet** for container lifecycle
* **container command/entrypoint** for the container’s main behavior
* **additional containers or pods** when you truly have multiple cooperating processes. ([Podman Documentation][1])

---

# The intended model for dev-container automatic behaviors

Think of the dev container as a **replaceable, purpose-built runtime envelope**.

It is designed to answer questions like:

* What image should my development/runtime environment come from?
* What command should it run when it starts?
* What mounts, environment, GPU access, and networks should it have?
* Should it stay alive waiting for me?
* Should it run a smoke test and exit?
* Should it run one long-lived service?

Those are all **container behavior** questions, and the normal levers are:

* the image contents
* the startup command
* the Quadlet definition that tells host systemd when and how to run it. ([Podman Documentation][1])

So the intended flow is usually:

1. **Bake environment into the dev image**
2. **Use the container command to choose what it does on startup**
3. **Use Quadlet to make that happen automatically on host boot if desired** ([Podman Documentation][1])

That is why your current staged design is sound:

* stage 1: command keeps container alive, you enter manually
* stage 2: same container behavior, but Quadlet auto-starts it
* stage 3: same container lifecycle, but command runs `train_smoke.py` automatically

That is the design as intended.

---

# The ownership model

## 1) Bootc host owns platform concerns

The host should own things that are fundamentally about the machine, boot, or orchestration:

* GPU driver installation and host GPU visibility
* CDI generation
* SSH to the VM or machine
* storage mounts
* system networking
* timers
* host-level logging and monitoring agents
* starting containers at boot
* restart policy and dependency ordering between services/containers. ([Fedora Project Documentation][2])

These remain **systemd-oriented**. In the bootc world, that means the ownership is:

* defined in the bootc image
* implemented as systemd units, timers, config, and Quadlets
* treated as part of the host OS build. ([Fedora Project Documentation][2])

## 2) Dev container owns the runtime environment for a workload

The dev container should own things like:

* Python/PyTorch/CUDA user-space stack
* tools and scripts like `train_smoke.py`
* interactive shell environment
* a single long-running app process
* a startup command that either waits, runs a test, or runs the app. ([Fedora Project Documentation][3])

This is **container-oriented**, not systemd-oriented.

## 3) Quadlet owns the handoff between the two

Quadlet is the host-managed mechanism that says:

* pull or use this image
* run this container or kube workload
* start it at boot
* restart it on failure
* make it depend on other host units
* make it part of the system boot graph. ([Podman Documentation][1])

So if you are coming from “I would normally write a systemd unit for this,” the translation is often:

* **host concern** → still a systemd unit
* **container lifecycle concern** → Quadlet
* **in-container main behavior** → container command

---

# How traditional server scenarios translate

Below is the practical mapping.

## Scenario A: “Run one command automatically when the environment starts”

### Old server model

You might:

* use `ExecStart=` in a systemd service
* or run a shell script from boot

### New model

* **Host startup command** → systemd oneshot or normal service on the **bootc host**
* **Dev container startup command** → container `command:` / entrypoint in the **dev container**
* **Auto-starting the container itself** → **Quadlet** on the host. ([Podman Documentation][1])

### Ownership

* host boot action: bootc host/systemd
* container boot action: dev container command
* “start container on boot”: host Quadlet

This is the most common translation.

---

## Scenario B: “Keep a process running continuously”

### Old server model

Create a systemd service and let systemd restart it.

### New model

Ask first: **where does this process logically belong?**

### If it is host/platform-related

Examples:

* host SSH
* CDI refresh
* host monitoring agent
* network setup helper
* backup timer/agent tied to host storage

Use:

* **bootc host systemd service**. ([Fedora Project Documentation][2])

### If it is workload-related

Examples:

* model server
* notebook server
* API process
* development daemon specific to that environment

Use:

* **container main process**
* launched and supervised by **Quadlet** on the host. ([Podman Documentation][1])

### Ownership

* host/platform continuous process: host systemd
* workload continuous process: container command + host Quadlet

This is the most important mindset shift.

---

## Scenario C: “Run a periodic job”

### Old server model

Systemd timer or cron on the server.

### New model

Still ask: **is the schedule tied to the machine or to the workload?**

### Machine/platform periodic job

Examples:

* snapshot creation
* cleanup
* host-level health check
* rebuilding cache on the host
* checking whether a service image should be updated

Use:

* **host systemd timer/service** in bootc. bootc itself ships with systemd services/timers as part of its operating model. ([Fedora Project Documentation][2])

### Workload periodic job

Examples:

* periodic model evaluation
* scheduled data refresh for an app
* smoke test in a dev image

Usually better as:

* a **separate containerized job**
* started by host systemd/Quadlet or another host-side trigger

Instead of keeping a big dev container around and making it behave like a mini-VM, create a dedicated job container if the periodic task is operationally distinct.

### Ownership

* schedule belongs to host
* job payload can live in its own image/container

This gives cleaner logs, clearer failure boundaries, and simpler replacement.

---

## Scenario D: “I want to log into the environment and work interactively”

### Old server model

SSH into the server and do the work there.

### New model

Usually:

* SSH into the **host/VM**
* then `podman exec` into the dev container
* or expose a deliberate access method into the container if you have a strong reason. ([Podman Documentation][4])

The dev container is generally **not** the place where you first introduce general-purpose init/service machinery just to mimic a traditional SSH-first server.

### Ownership

* access and authentication: host
* dev environment shell/tools: container

---

## Scenario E: “I need multiple cooperating services”

This is where you decide between:

* one container
* multiple containers
* a pod
* host systemd units

### Best practice translation

If you have multiple distinct services, do **not** default to putting them all inside one dev container under in-container systemd.

Instead prefer:

* **separate containers** when the services are logically separate
* possibly a **pod** when they need tight coupling, shared localhost/network namespace, or shared lifecycle. Podman defines pods as groups of containers managed together. ([Podman Documentation][5])

### Good candidates for separate containers

* app server + reverse proxy
* model server + metrics exporter
* worker + queue sidecar
* notebook + dedicated data-sync helper
* backup service separate from dev environment

### Good candidates for a pod

Use a pod when containers need:

* shared network namespace
* localhost communication
* shared lifecycle
* coordinated start/stop as one unit. ([Podman Documentation][5])

### Ownership

* pod/container lifecycle: host Quadlet/systemd
* each service’s runtime: its own container

This is much closer to the intended container model than “one giant dev server container with internal systemd.”

---

# When to move something to a separate container

Move it out of the dev container when one or more of these are true:

## 1) It has a different lifecycle

Example:

* dev shell should stay up for days
* smoke test should run once and exit
* inference API should restart independently

Those should not be the same process in the same container.

## 2) It has a different image dependency stack

Example:

* dev container needs editors, tools, notebooks
* serving container needs only runtime libs
* exporter needs only one tiny binary

Separate images are cleaner.

## 3) It has a different restart policy

Example:

* inference service should auto-restart
* training job should fail loudly and stop
* dev shell should stay idle until entered

Those are different operational roles.

## 4) It has a different security boundary

Example:

* cloudflared sidecar
* SSH helper
* backup uploader
* metrics agent

Put these in separate containers or on the host depending on their privileges and data access needs.

## 5) You want cleaner testing and promotion

A dedicated smoke-test container is easier to reason about than overloading the dev container for everything.

---

# When something should stay systemd-oriented

Keep it systemd-oriented when the ownership is really about the machine or orchestration.

## Keep on the bootc host if it is:

* needed before containers can work
* tied to hardware/devices
* tied to filesystems/mounts
* tied to boot order
* tied to network availability for the machine
* meant to supervise container lifecycle
* meant to schedule host-wide jobs. ([Podman Documentation][1])

Examples:

* `nvidia-cdi-refresh.service`
* host-level `nvidia-smi` validation service
* backup timers
* SSH service
* Quadlet units
* image update/reboot policy units

### How it changes from the old world

The big change is not “stop using systemd.”
It is: **systemd stays, but its ownership moves up one layer to the bootc host.**

In other words:

* old model: server systemd directly runs the workload
* new model: host systemd often runs **the container lifecycle**, while the container runs the workload

That is the correct translation.

---

# When the dev container should still feel “service-like”

There are cases where the dev container should behave like a service, but you still do **not** need in-container systemd.

Examples:

* run Jupyter Lab continuously
* run a model-serving API continuously
* run a language server or dev daemon continuously

Best translation:

* make that the **main process** of the container
* let **Quadlet/systemd on the host** manage startup and restart. ([Podman Documentation][1])

That gives you service behavior without nesting a service manager inside the container.

---

# When in-container systemd is actually justified

This should be the exception.

You might justify it only when:

* the container genuinely must supervise multiple tightly coupled long-lived processes internally
* the software stack is explicitly designed around systemd/init semantics
* you need service-style process control inside the container and cannot reasonably decompose it

Even then, I would treat it as a special case rather than the default design for a dev container.

For your current use case, I would **not** choose this as the primary model.

---

# A practical translation guide

## Put it on the bootc host with systemd when:

* it prepares the platform
* it controls the platform
* it schedules machine-level work
* it launches or supervises containers
* it depends on boot order, mounts, or hardware

## Put it in the dev container as the main command when:

* it is the primary workload of that environment
* it should start when the container starts
* it is logically one app/test/session

## Put it in a separate container when:

* it has a different lifecycle, privileges, dependencies, or restart behavior
* it is a sidecar/helper
* it is operationally separate from the dev environment

## Put multiple containers in a pod when:

* they need shared localhost/network namespace
* they should start/stop together
* they are tightly coupled services. ([Podman Documentation][5])

---

# Applying this to your specific workflow

For your design, I would model ownership like this:

## Bootc host/systemd owns

* NVIDIA driver presence
* CDI generation
* host GPU smoke check via `nvidia-smi`
* SSH into the VM/host
* Quadlet units
* automatic start of the dev container
* timers/jobs related to host testing and orchestration

## Dev container owns

* PyTorch/CUDA userspace stack
* `train_smoke.py`
* interactive development tools
* manual shell session behavior
* automatic training/inference smoke behavior when you choose to make that the startup command

## Separate containers or pods later own

* inference API
* metrics/exporter
* backup uploader
* proxy
* notebook server if you want it isolated from the dev shell
* anything that should live/restart independently from the dev container

That gives you the cleanest mapping from “traditional dev server with systemd” into “bootc host + managed containers.”

# The shortest rule to remember

Do not ask:

> “Should this be a systemd service or a container process?”

Ask:

> “Who owns this behavior: the machine, the container, or a separate cooperating service?”

Then map it like this:

* **machine owns it** → bootc host + systemd
* **container owns it** → container command
* **separate cooperating service owns it** → separate container, maybe in a pod
* **host should auto-run/manage container** → Quadlet/systemd

That is the intended operating model.

[1]: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html?utm_source=chatgpt.com "podman-systemd.unit"
[2]: https://docs.fedoraproject.org/en-US/bootc/getting-started/?utm_source=chatgpt.com "Getting Started with Bootable Containers :: Fedora Docs"
[3]: https://docs.fedoraproject.org/en-US/bootc/embedding-containers/?utm_source=chatgpt.com "Embedding Containers - Fedora Docs"
[4]: https://docs.podman.io/en/stable/Commands.html?utm_source=chatgpt.com "Commands"
[5]: https://docs.podman.io/en/stable/markdown/podman-pod.1.html?utm_source=chatgpt.com "podman-pod"

