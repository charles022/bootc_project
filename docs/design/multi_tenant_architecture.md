# Full plan: per-tenant non-login service account + rootless Podman OpenClaw platform

## Executive summary

We will build a **bootc-based Fedora host** that acts as a clean, minimal, trusted control plane. The host has **one real human-accessible admin account only**. Human guests do **not** log into the host. Instead, each tenant gets a **non-login host service account** that exists only as an isolation principal for rootless Podman.

Each tenant’s actual usable environment lives inside one or more **rootless Podman pods**. Those pods contain:

OpenClaw runtime container  
guest dev environment container  
cloudflared tunnel sidecar  
credential proxy / broker sidecar  
optional messaging bridge  
optional helper/tool containers

The host owns:

tenant creation  
rootless Podman ownership  
systemd/Quadlet lifecycle  
cloudflared configuration  
credential storage  
credential grants  
agent/environment provisioning  
updates and rollback  
storage allocation  
policy enforcement

The tenant/agent owns only what the host explicitly grants inside that tenant’s environment.

The central design rule is:

Guests and agents can be powerful inside their assigned environment.  
They cannot administer the host.  
They cannot see or modify other tenants.  
They cannot arbitrarily grant themselves credentials, storage, tunnels, mounts, or host capabilities.

---

# 1. Core architecture

## 1.1 High-level shape

Hardware / VM / bare metal  
└── Fedora bootc host  
    ├── kernel + drivers  
    ├── minimal host userspace  
    ├── systemd  
    ├── Podman  
    ├── Quadlet  
    ├── host credential broker  
    ├── host provisioning service  
    ├── host policy store  
    ├── host cloudflared supervision  
    └── tenant rootless Podman runtimes

Tenant: alice  
└── non-login host service account: tenant_alice  
    └── rootless Podman  
        ├── alice-main-agent.pod  
        │   ├── cloudflared  
        │   ├── openclaw-runtime  
        │   ├── dev-env  
        │   ├── credential-proxy  
        │   └── messaging-bridge  
        │  
        ├── alice-coding-agent.pod  
        │   ├── cloudflared  
        │   ├── openclaw-runtime  
        │   ├── rust-dev-env  
        │   └── credential-proxy  
        │  
        └── alice-research-agent.pod  
            ├── openclaw-runtime  
            ├── research-env  
            └── credential-proxy

## 1.2 Host principle

The host is not a workstation for guests.

The host is a **control plane**:

trusted  
minimal  
declarative  
reproducible  
hard to mutate manually  
updated through bootc/ostree-style image updates

The host should not accumulate guest tooling, guest packages, guest Python environments, guest npm packages, guest SSH keys, or guest project files.

Guest state lives in:

tenant container storage  
tenant volumes  
tenant credential namespace  
tenant object storage/backups  
separate data drive

## 1.3 Tenant principle

A tenant is not a host login.

A tenant is a platform identity represented by:

non-login host service account  
tenant policy document  
tenant credential namespace  
tenant storage namespace  
tenant rootless Podman store  
tenant systemd/Quadlet units  
tenant cloudflared routes/tokens  
tenant OpenClaw agent objects

Example:

tenant: alice  
host service account: tenant_alice  
human host login: none  
container login: alice inside alice-dev-env

---

# 2. Why per-tenant non-login service accounts

## 2.1 What we are choosing

We are choosing:

one non-login host service account per human/tenant  
rootless Podman under that account  
host admin manages those accounts  
human users never SSH into the host

Example host users:

admin         real host admin login  
tenant_alice non-login service account  
tenant_bob   non-login service account  
tenant_cara  non-login service account

These accounts have:

locked passwords  
nologin shell  
no human SSH keys  
no sudo  
subuid/subgid mappings  
dedicated home/state directory  
rootless Podman store

## 2.2 Why this works

Rootless Podman is designed to run containers as regular users without elevated privileges. Podman’s own documentation describes rootless mode as running “most Podman commands” without additional privileges, and its user namespace model maps container users to host users/subordinate IDs rather than granting container root host-root power.

That gives us the property we need:

root inside tenant container ≠ root on host

A guest can have `sudo` inside the dev container without being allowed to `sudo` on the host.

## 2.3 What this protects

If Alice’s agent or dev environment misbehaves, its first containment layers are:

container boundary  
user namespace  
rootless Podman boundary  
tenant_alice host UID  
tenant_alice subordinate UID/GID range  
SELinux labels  
tenant-specific volumes  
tenant-specific secrets  
tenant policy

Alice should not be able to cross into:

host admin account  
host /etc  
host /usr  
host systemd control  
host cloudflared control  
host credential database  
Bob's tenant account  
Bob's Podman store  
Bob's volumes  
Bob's secrets

---

# 3. Trust and authority model

## 3.1 Trusted components

These are trusted:

bootc host image  
host admin  
host systemd  
host provisioning service  
host credential broker  
host policy engine  
host-managed Quadlet templates  
host-managed cloudflared configuration

## 3.2 Semi-trusted components

These are useful but not fully trusted:

OpenClaw agent runtime  
agent skills  
dev environment container  
messaging bridge  
guest-written scripts  
guest-installed packages

They may be controlled by LLMs, guests, or third-party packages.

## 3.3 Untrusted or high-risk inputs

These must never directly produce host-level operations:

LLM output  
agent tool call arguments  
guest shell commands  
uploaded files  
repo code  
messaging input from Signal/WhatsApp/email  
external API responses

The rule:

untrusted request → policy validation → host-controlled action

Never:

untrusted request → raw podman/systemctl/cloudflared/credential command

---

# 4. Major system components

## 4.1 bootc host image

The bootc host contains the minimal platform substrate.

Recommended host packages:

podman  
passt / pasta  
systemd  
cloudflared or cloudflared container support  
openssh-server only for admin, if needed  
policy/provisioning tools  
backup tooling  
SELinux tooling  
btrfs tooling, if using Btrfs

Podman rootless networking uses user-mode networking support; Podman’s rootless tutorial notes that a user-mode networking tool is required and that Podman uses `pasta` from `passt` for rootless networking.

The host image should not contain:

tenant project tooling  
tenant Python dependencies  
tenant npm packages  
tenant model credentials  
tenant personal SSH keys  
tenant email/Signal/WhatsApp credentials

## 4.2 systemd

systemd is the lifecycle engine.

It manages:

tenant user creation helpers  
tenant rootless Podman services  
Quadlet-generated units  
host credential broker  
host provisioner  
backup timers  
cloudflared lifecycle

Podman Quadlet integrates with systemd through a generator that reads declarative unit-like files and generates systemd service units at boot or after `daemon-reload`. It supports both system and user systemd units.

## 4.3 Quadlet

Quadlet is the declarative interface for Podman resources:

.pod  
.container  
.volume  
.network  
.image

Podman’s Quadlet documentation describes Quadlets as a way to manage containers, pods, volumes, networks, and images declaratively with systemd unit files.

We will use Quadlet for tenant workloads instead of raw ad hoc `podman run` commands.

## 4.4 rootless Podman per tenant

Each tenant service account owns its own rootless Podman environment:

tenant_alice:  
  containers  
  images  
  volumes  
  secrets  
  networks  
  systemd user units

tenant_bob:  
  separate containers  
  separate images  
  separate volumes  
  separate secrets  
  separate networks  
  separate systemd user units

Rootless Podman uses `/etc/subuid` and `/etc/subgid` mappings for additional container UIDs/GIDs. This is the mechanism that allows container users beyond the invoking host UID to be mapped into host subordinate ID ranges.

## 4.5 cloudflared sidecar per tenant pod

For each guest-facing pod, include a `cloudflared` sidecar:

tenant pod  
├── cloudflared  
├── ssh/dev-env  
├── openclaw-runtime  
└── credential-proxy

Cloudflare Tunnel’s daemon proxies traffic from Cloudflare’s network to local origins without requiring the origin to expose inbound firewall holes.

A published application route maps a public hostname to a local service behind the tunnel.

Important: the `cloudflared` container is **host/platform controlled**, not guest controlled.

The tenant/agent must not be able to edit:

tunnel token  
cloudflared config  
public hostname routing  
systemd unit  
Quadlet unit  
host Cloudflare API token

## 4.6 credential broker

The credential broker is a host-controlled service responsible for:

receiving credentials during onboarding  
encrypting/storing credentials  
issuing scoped credential grants  
rotating/revoking credentials  
injecting credentials into containers safely  
auditing credential use

Agents do not directly own master credentials.

Instead:

agent requests access  
credential proxy checks policy  
broker issues scoped secret/token or performs action

## 4.7 provisioning service

The provisioner creates and modifies tenant resources.

It owns:

tenant creation  
agent creation  
environment creation  
volume creation  
secret grants  
cloudflared route generation  
Quadlet generation  
systemd reload/restart  
backup registration  
quota enforcement

Agents may call a narrow CLI/API:

agentctl create-agent  
agentctl create-env  
agentctl attach-storage  
agentctl request-credential  
agentctl list-agents  
agentctl stop-agent

But agents may not call:

podman run arbitrary...  
systemctl arbitrary...  
cloudflared arbitrary...  
mount arbitrary...  
sudo arbitrary...

---

# 5. Identity model

## 5.1 Host identities

admin  
  real host admin  
  can SSH into host  
  can sudo  
  can update/recover host

tenant_<name>  
  non-login service account  
  no password  
  no SSH  
  no sudo  
  owns rootless Podman runtime

Example:

admin:x:1000:1000:Admin:/home/admin:/bin/bash  
tenant_alice:x:2001:2001:Tenant Alice:/var/lib/openclaw-platform/tenants/alice:/usr/sbin/nologin  
tenant_bob:x:2002:2002:Tenant Bob:/var/lib/openclaw-platform/tenants/bob:/usr/sbin/nologin

## 5.2 Container identities

Inside Alice’s dev environment container:

alice:x:1000:1000:Alice:/home/alice:/bin/bash

Inside Alice’s OpenClaw runtime container:

openclaw or agent user

Inside sidecars:

cloudflared user  
credential-proxy user

The container user may have `sudo` **inside the container**.

That is acceptable as long as:

container sudo cannot control host  
container has no host Podman socket  
container has no host systemd socket  
container has no dangerous host mounts  
container has no host cloudflared credentials  
container has no broad credential database access

---

# 6. Storage model

## 6.1 Host storage layout

Use a dedicated storage root, preferably on the separate storage drive:

/var/lib/openclaw-platform/  
├── tenants/  
│   ├── alice/  
│   │   ├── podman/  
│   │   ├── volumes/  
│   │   ├── agents/  
│   │   ├── envs/  
│   │   ├── credentials/  
│   │   ├── policies/  
│   │   ├── cloudflared/  
│   │   ├── backups/  
│   │   └── logs/  
│   │  
│   └── bob/  
│       ├── podman/  
│       ├── volumes/  
│       ├── agents/  
│       ├── envs/  
│       ├── credentials/  
│       ├── policies/  
│       ├── cloudflared/  
│       ├── backups/  
│       └── logs/  
│  
├── templates/  
│   ├── quadlet/  
│   ├── images/  
│   ├── policies/  
│   └── onboarding/  
│  
├── broker/  
├── provisioner/  
└── backups/

## 6.2 Tenant volume classes

Each tenant gets controlled volume classes:

private-agent-volume  
shared-tenant-volume  
scratch-volume  
repo-volume  
model-cache-volume  
message-archive-volume  
backup-staging-volume

Example:

alice volumes:  
  alice-shared-code  
  alice-shared-research  
  alice-agent-main-private  
  alice-agent-coding-private  
  alice-scratch  
  alice-model-cache

## 6.3 Mount policy

Allowed:

tenant-owned volume → tenant pod  
tenant-owned shared volume → selected tenant pods  
read-only template volume → tenant pod  
scratch volume → tenant pod

Forbidden:

/ → container  
/etc → container  
/var/lib/openclaw-platform → container  
/var/run/podman/podman.sock → container  
/run/systemd → container  
host cloudflared credential directory → tenant-editable mount  
host credential broker database → container  
other tenant volume → container

## 6.4 Container mutability

The dev environment may be mutable.

The OpenClaw runtime container should be as immutable as practical.

Recommended:

OpenClaw runtime:  
  mostly image-defined  
  persistent state mounted separately  
  no broad package installation

dev environment:  
  mutable  
  sudo allowed inside container  
  package installation allowed  
  project files mounted  
  can be snapshotted/rebuilt/cloned

cloudflared sidecar:  
  immutable  
  config mounted read-only  
  no guest write access

credential proxy:  
  immutable  
  narrow socket/API  
  no broad host secrets mount

---

# 7. Credential model

## 7.1 Credential ownership

Credentials are tied to the tenant, not directly to arbitrary containers.

tenant alice  
├── credential: alice/email/main  
├── credential: alice/signal/main  
├── credential: alice/codex/main  
├── credential: alice/gemini/main  
├── credential: alice/claude/main  
├── credential: alice/github/main  
└── credential: alice/cloudflare/user-route, if needed

Agent instances receive **grants**:

alice-main-agent may use:  
  alice/signal/main  
  alice/email/main read/write  
  alice/codex/main  
  alice/gemini/main

alice-coding-agent may use:  
  alice/codex/main  
  alice/github/fedora_init  
  alice/shared-code

alice-email-agent may use:  
  alice/email/main read/write  
  no shell  
  no repo volumes

## 7.2 Do not clone credential-bearing containers

Avoid:

clone authenticated OpenClaw container

Prefer:

instantiate fresh container  
attach selected state  
grant selected credentials  
attach selected volumes

Reason: cloning authenticated container state risks copying:

tokens  
cookies  
logs  
temporary sessions  
agent memory  
IPC sockets  
cached credentials  
private working files  
stale config

The cleaner model is:

base image + profile + selected grants + selected storage = new agent

## 7.3 Credential injection

Use one of these, in order of preference:

credential proxy API/socket  
short-lived token  
Podman secret mounted as file  
environment variable only when unavoidable

Avoid:

master credentials in image  
master credentials in container layer  
credentials in command-line args  
credentials in logs  
credentials in world-readable files  
credentials in agent-writable config

## 7.4 Login URL flows

For services like Codex, Gemini, Claude, GitHub, or other OAuth/browser-based tools:

onboarding tool requests login  
host broker generates or receives login URL  
URL is sent to user through SSH onboarding or existing messaging channel  
user completes login externally  
broker receives token/session  
broker stores credential under tenant namespace  
selected agents get grants

The container should not become the master credential vault. It should only receive the minimum required runtime token/session.

---

# 8. Networking model

## 8.1 Pod network

A pod is a coordination boundary, not a complete security boundary.

Containers in the same pod may share localhost/network namespace.

So only place mutually trusted cooperating components in the same pod:

good:  
  alice-openclaw  
  alice-dev-env  
  alice-cloudflared  
  alice-credential-proxy

bad:  
  alice-openclaw  
  bob-openclaw  
  shared-global-admin-api

## 8.2 Cloudflared per guest pod

Each user-facing pod can include a cloudflared sidecar:

alice-main-agent.pod  
├── cloudflared → exposes ssh/http/messaging ingress  
├── dev-env → local sshd  
├── OpenClaw → local service  
└── credential-proxy → local-only broker interface

The sidecar is platform-managed.

Cloudflare Tunnel allows the origin to remain closed while cloudflared proxies traffic outward to Cloudflare’s network.

## 8.3 Ingress classes

Define ingress types:

onboarding-ssh  
dev-ssh  
agent-web-ui  
agent-api  
messaging-webhook  
internal-only

Example:

alice-onboard.example.com → alice-onboarding-dev-env:22  
alice-dev.example.com     → alice-main-dev-env:22  
alice-agent.example.com   → alice-main-openclaw:8080

## 8.4 Egress classes

Define egress profiles:

none  
messaging-only  
api-only  
restricted-internet  
full-internet

Initial default should be conservative:

dev-env: restricted-internet or full-internet  
openclaw-runtime: api-only  
cloudflared: Cloudflare only  
credential-proxy: broker only  
messaging bridge: messaging endpoints only

---

# 9. Agent/pod composition model

## 9.1 Base pod types

### Onboarding pod

alice-onboarding.pod  
├── cloudflared  
└── onboarding-dev-env

Purpose:

initial SSH entry  
credential enrollment  
user setup  
environment selection

### Main agent pod

alice-main.pod  
├── cloudflared  
├── openclaw-runtime  
├── dev-env  
├── credential-proxy  
└── messaging-bridge

Purpose:

primary user agent  
messaging interface  
default dev environment  
agent creation requests

### Specialized agent pod

alice-rust-coding.pod  
├── openclaw-runtime  
├── rust-dev-env  
├── credential-proxy  
└── optional cloudflared

Purpose:

dedicated agent with selected environment/storage/credentials

### Headless worker agent pod

alice-worker-01.pod  
├── openclaw-runtime  
├── worker-env  
└── credential-proxy

Purpose:

no direct user ingress  
called by main agent or provisioner

## 9.2 Runtime/environment split

The OpenClaw runtime and dev environment should be separate containers where practical:

OpenClaw runtime:  
  agent brain/control loop  
  skills/tool dispatcher  
  messaging connection  
  calls dev-env through controlled interface

dev environment:  
  shell  
  compiler/toolchains  
  project files  
  sudo inside container  
  package installs

This prevents the OpenClaw runtime image from becoming a giant mutable workstation image.

## 9.3 Shared/siloed storage

Agents can use:

private storage  
shared tenant storage  
read-only reference storage  
scratch storage

Examples:

main-agent:  
  private: alice-main-private  
  shared: alice-shared-notes

coding-agent:  
  private: alice-coding-private  
  shared: alice-shared-code

email-agent:  
  private: alice-email-private  
  no shared code

---

# 10. Agent self-provisioning model

## 10.1 Allowed pattern

Agents may request:

create new agent  
create new environment  
clone environment template  
attach approved storage  
request approved credential grant  
start/stop their own tenant resources

Through:

agentctl

Example:

```bash
agentctl create-agent \
  --name alice-rust-coder \
  --runtime openclaw:stable \
  --environment fedora-rust-dev:stable \
  --storage alice-shared-code \
  --credential codex \
  --credential github:fedora_init \
  --network restricted-internet
```

## 10.2 Forbidden pattern

Agents may not execute:

podman run ...  
podman secret ...  
systemctl ...  
cloudflared tunnel ...  
mount ...  
sudo on host ...

## 10.3 Provisioning flow

agent request  
    ↓  
agentctl CLI/API  
    ↓  
tenant identity resolved  
    ↓  
policy engine validates  
    ↓  
quota engine validates  
    ↓  
credential grants checked  
    ↓  
storage grants checked  
    ↓  
template selected  
    ↓  
Quadlet generated  
    ↓  
systemd daemon-reload  
    ↓  
tenant unit started  
    ↓  
audit log written

## 10.4 Policy examples

tenant: alice

limits:  
  max_agents: 10  
  max_running_agents: 5  
  max_cpu_per_agent: 4  
  max_memory_per_agent: 8G  
  max_storage_total: 500G

allowed_images:  
  openclaw_runtime:  
    - registry.local/openclaw-runtime:stable  
  environments:  
    - registry.local/fedora-dev:stable  
    - registry.local/rust-dev:stable  
    - registry.local/python-dev:stable

allowed_credentials:  
  - codex  
  - gemini  
  - claude  
  - email  
  - signal  
  - github

default_network: restricted-internet

forbidden:  
  privileged: true  
  host_network: true  
  host_pid: true  
  host_ipc: true  
  host_podman_socket: true  
  arbitrary_host_mounts: true

---

# 11. Lifecycle sequence

## 11.1 Host installation

install bootc host  
configure admin account  
enable SELinux enforcing  
configure storage drive  
install/provision Podman + Quadlet support  
install/provision cloudflared support  
install/provision credential broker  
install/provision platform CLI  
configure backups

## 11.2 Tenant creation

Admin runs:

platformctl tenant create alice

This performs:

create non-login host service account tenant_alice  
lock password  
set shell /usr/sbin/nologin  
assign subuid/subgid range  
create tenant directories  
set ownership  
create tenant policy file  
create rootless Podman storage config  
create onboarding pod Quadlets  
create cloudflared tunnel/route  
enable tenant services  
start onboarding pod

## 11.3 User onboarding

Alice receives:

SSH target or Cloudflare Access URL  
temporary onboarding credential

Alice connects to the onboarding container:

ssh alice@alice-onboard.example.com

Inside the onboarding container:

prompt for email login  
prompt for Signal/WhatsApp setup  
prompt for Codex login URL flow  
prompt for Gemini/Claude login  
prompt for GitHub login  
optionally prompt for preferred dev image

The onboarding tool stores credentials via the broker.

## 11.4 Base agent creation

After onboarding:

provisioner creates alice-main.pod  
attaches selected credentials  
attaches default storage  
starts OpenClaw  
starts messaging bridge  
optionally stops onboarding pod

Alice then mostly interacts through:

Signal / WhatsApp / email / web UI / SSH into dev container

## 11.5 New agent creation

Alice messages main agent:

Create a new Rust coding agent with access to my shared code workspace and Codex.

Main agent calls:

agentctl create-agent ...

Host validates and creates:

alice-rust-coding.pod

## 11.6 Update flow

Host updates:

host image update  
reboot into new host image  
systemd regenerates Quadlet units  
tenant pods restart

Workload updates:

OpenClaw runtime image updated by policy  
environment images updated by policy  
tenant mutable volumes preserved  
credentials preserved

## 11.7 Rollback flow

Host rollback:

bootc rollback  
reboot  
tenant volumes unchanged  
tenant credentials unchanged  
previous host control plane restored

Agent/environment rollback:

pin previous container image  
restart pod  
restore volume snapshot if necessary

---

# 12. systemd and Quadlet plan

## 12.1 Placement strategy

Because we are using non-login service accounts, we have two workable approaches.

### Approach A: per-tenant user Quadlets

Tenant Quadlets live under the tenant service account:

/var/lib/openclaw-platform/tenants/alice/.config/containers/systemd/  
├── alice-main.pod  
├── alice-main-openclaw.container  
├── alice-main-dev.container  
├── alice-main-cloudflared.container  
└── alice-main-credential-proxy.container

Then systemd user services run for `tenant_alice`.

This generally requires user lingering so the user service manager can run without an interactive login. Enabling lingering is the standard way to allow user services to continue running after logout or without an active session.

### Approach B: admin-managed rootless user Quadlets under `/etc`

Podman supports rootless Quadlets placed by administrators in `/etc/containers/systemd/users`, including UID-specific directories where only the matching user executes the Quadlet.

Example:

/etc/containers/systemd/users/2001/  
├── alice-main.pod  
├── alice-main-openclaw.container  
└── alice-main-dev.container

This better matches a host-managed platform.

## 12.2 Recommendation

Use:

host-generated Quadlets under /etc/containers/systemd/users/<tenant_uid>/

with tenant state under:

/var/lib/openclaw-platform/tenants/<tenant>/

This keeps ownership clear:

host controls desired config  
tenant service account owns runtime state

## 12.3 Service startup

For each tenant:

enable lingering for tenant service user  
install/generated Quadlet files  
systemctl daemon-reload  
systemctl --user -M or equivalent start services for tenant

Exact implementation details may vary depending on the Fedora/systemd version and how we choose to invoke user managers. The design goal remains:

root/admin controls lifecycle  
rootless containers run as tenant service user

---

# 13. Security baseline

## 13.1 Container defaults

For most containers:

rootless  
no privileged mode  
no host network  
no host PID  
no host IPC  
no host Podman socket  
no arbitrary devices  
no broad host mounts  
SELinux enforcing  
seccomp default  
capabilities dropped unless needed  
read-only where possible  
explicit volumes only  
explicit secrets only

## 13.2 Dev environment exception

The dev environment may allow internal sudo:

container user can sudo inside container  
container can install packages  
container can run compilers  
container can run local services

But still deny:

host mounts  
host systemd  
host Podman socket  
host cloudflared credentials  
host credential database  
other tenant volumes

## 13.3 OpenClaw runtime restrictions

The OpenClaw runtime should be more restricted than the dev environment:

no sudo inside runtime if avoidable  
read-only image filesystem if possible  
only needed state mounted  
only needed APIs reachable  
only credential proxy reachable  
tool execution routed to dev-env

## 13.4 cloudflared restrictions

config read-only  
token read-only  
no tenant write access  
no shell  
no extra capabilities  
egress only to Cloudflare  
ingress only to intended local service

## 13.5 Credential proxy restrictions

local pod access only  
tenant-scoped  
agent-scoped grants  
audited  
no broad credential dump API  
no list-all-secrets for agent  
short-lived tokens preferred

---

# 14. Filesystem and ownership sketch

## 14.1 Host-level

/var/lib/openclaw-platform/  
  owner: root:root  
  mode: 0755 or stricter

/var/lib/openclaw-platform/tenants/alice/  
  owner: tenant_alice:tenant_alice for runtime subdirs  
  root-owned for policy/config subdirs where tenant must not write

Example:

/var/lib/openclaw-platform/tenants/alice/  
├── runtime/          tenant_alice writable  
├── volumes/          tenant_alice writable by controlled mounts  
├── quadlet/          root-owned generated source  
├── cloudflared/      root-owned, token readable only as needed  
├── credentials/      root-owned/broker-owned  
├── policy/           root-owned  
├── logs/             mixed, append/audit controlled  
└── backups/          root-owned or backup-service-owned

## 14.2 Tenant service account

tenant_alice:  
  home = /var/lib/openclaw-platform/tenants/alice/runtime  
  shell = /usr/sbin/nologin  
  password = locked  
  subuid/subgid = allocated

## 14.3 Container-visible layout

Inside dev container:

/home/alice  
/workspace  
/shared  
/scratch  
/agent-private

Inside OpenClaw runtime:

/openclaw/state  
/openclaw/workspace      maybe read/write selected  
/openclaw/shared         optional  
/run/credential-proxy    socket/API

---

# 15. Object model

## 15.1 Tenant

tenant:  
  id: alice  
  service_user: tenant_alice  
  uid: 2001  
  storage_root: /var/lib/openclaw-platform/tenants/alice  
  status: active

## 15.2 Credential

credential:  
  id: alice/codex/main  
  tenant: alice  
  type: codex  
  storage: broker  
  status: active  
  rotation_policy: manual

## 15.3 Environment image

environment_image:  
  id: fedora-rust-dev  
  image: registry.local/env/fedora-rust-dev:stable  
  allows_internal_sudo: true  
  allowed_mount_classes:  
    - workspace  
    - shared  
    - scratch

## 15.4 Agent

agent:  
  id: alice-rust-coding  
  tenant: alice  
  runtime_image: registry.local/openclaw/runtime:stable  
  environment_image: registry.local/env/fedora-rust-dev:stable  
  credentials:  
    - alice/codex/main  
    - alice/github/fedora_init  
  volumes:  
    - alice/shared-code  
    - alice/agent-rust-private  
  ingress:  
    - type: signal-route  
    - type: dev-ssh  
  network_profile: restricted-internet  
  status: running

## 15.5 Pod

pod:  
  id: alice-rust-coding  
  tenant: alice  
  containers:  
    - openclaw-runtime  
    - dev-env  
    - cloudflared  
    - credential-proxy  
  shared_network: true  
  volumes:  
    - shared-code  
    - private  
  secrets:  
    - tunnel-token  
    - credential-proxy-client-token

---

# 16. CLI/API surface

## 16.1 Admin CLI

platformctl tenant create alice  
platformctl tenant disable alice  
platformctl tenant delete alice  
platformctl tenant list

platformctl credential list alice  
platformctl credential revoke alice codex  
platformctl credential rotate alice codex

platformctl agent list alice  
platformctl agent create alice ...  
platformctl agent stop alice alice-rust-coding  
platformctl agent delete alice alice-rust-coding

platformctl tunnel list alice  
platformctl backup run alice  
platformctl backup restore alice --snapshot ...

## 16.2 Agent-facing CLI

agentctl create-agent ...  
agentctl create-env ...  
agentctl list-agents  
agentctl stop-agent ...  
agentctl request-credential ...  
agentctl attach-storage ...  
agentctl detach-storage ...

Agent-facing commands must be constrained by:

tenant identity  
caller agent identity  
policy  
quota  
credential grant rules  
storage grant rules  
approved templates

## 16.3 Onboarding CLI

openclaw-onboard

Capabilities:

authenticate user  
collect service credentials  
start OAuth/login URL flow  
configure preferred messaging channel  
select default environment  
trigger base agent creation

---

# 17. Build and deployment plan

## 17.1 Host image

Build a host image that includes:

Podman  
Quadlet support  
passt/pasta  
cloudflared support  
platformctl  
agentctl host endpoint  
credential broker  
provisioning service  
backup service  
systemd units  
SELinux policy additions if needed

Do not include guest tooling.

## 17.2 Container images

Maintain separate images:

openclaw-runtime:stable  
env-fedora-base:stable  
env-fedora-rust:stable  
env-fedora-python:stable  
cloudflared:stable  
credential-proxy:stable  
messaging-bridge-signal:stable  
messaging-bridge-whatsapp:stable  
onboarding-env:stable

## 17.3 Registries

At minimum:

host image registry  
runtime image registry  
environment image registry

For early development, local image tags are fine. For production, pin by digest when possible.

## 17.4 Updates

Host updates:

bootc update/switch  
reboot  
rollback available

Runtime updates:

update OpenClaw runtime image  
restart selected agents  
preserve tenant volumes

Environment updates:

new env image version  
new agents use new image  
existing mutable envs optionally migrate or stay pinned

---

# 18. Backup and restore plan

## 18.1 Back up

Back up:

tenant policies  
tenant object definitions  
tenant volumes  
tenant credential metadata  
encrypted credential store  
Quadlet generated source  
cloudflared configuration metadata  
audit logs

Do not rely on backing up only container layers.

## 18.2 Snapshot classes

host config snapshot  
tenant volume snapshot  
agent private volume snapshot  
credential-store backup  
policy backup

## 18.3 Restore

Restore sequence:

install/boot host image  
restore platform config  
restore credential broker state  
restore tenant records  
recreate non-login service users with same or remapped IDs  
restore volumes  
regenerate Quadlets  
restart tenant pods  
validate tunnels and agents

---

# 19. Failure modes and mitigations

## 19.1 Agent tries to create unsafe container

Mitigation:

agentctl accepts only declarative requests  
policy rejects privileged, host mounts, host network, broad devices  
templates generate final Quadlets

## 19.2 Tenant dev container compromised

Mitigation:

no host socket  
no host mounts  
tenant-only volumes  
rootless Podman  
tenant service UID boundary  
credential grants scoped  
cloudflared token read-only

## 19.3 OpenClaw leaks a token

Mitigation:

short-lived tokens  
credential proxy  
revocation  
audit logs  
agent-specific grants  
avoid master secrets in env vars

## 19.4 Cloudflared sidecar compromised

Mitigation:

sidecar has only its tunnel token  
token scoped to one tenant/pod route  
config read-only  
no host Cloudflare API token  
no broad local network access if possible

## 19.5 Host control plane bug

Mitigation:

small codebase  
strict input validation  
template-based generation  
audit every action  
dry-run mode  
unit tests  
VM integration tests  
no raw shell string interpolation from agent input

---

# 20. Implementation phases

## Phase 0 — minimal proof of concept

Goal:

one tenant  
one non-login service account  
one rootless pod  
one cloudflared sidecar  
one dev env  
one OpenClaw runtime  
manual credential injection

Deliverables:

platformctl tenant create alice  
alice-main.pod starts  
Alice SSHs into dev container through cloudflared  
OpenClaw container runs rootless

## Phase 1 — proper tenant isolation

Goal:

multiple tenants  
separate service users  
separate Podman stores  
separate volumes  
separate cloudflared routes

Deliverables:

alice and bob cannot see each other's files  
alice and bob rootless Podman stores separate  
host remains clean

## Phase 2 — credential broker

Goal:

onboarding stores credentials through host broker  
agents receive scoped grants

Deliverables:

credential enrollment flow  
credential proxy container  
grant/revoke flow  
audit log

## Phase 3 — agent provisioning

Goal:

OpenClaw agent can request new agents/environments safely

Deliverables:

agentctl create-agent  
policy engine  
quota engine  
Quadlet generation  
systemd restart/reload flow

## Phase 4 — messaging-first interface

Goal:

user interacts mainly through Signal/WhatsApp/email

Deliverables:

messaging bridge  
main agent routes requests  
agent creation by message  
status reporting by message

## Phase 5 — production hardening

Goal:

recoverable, auditable, maintainable platform

Deliverables:

backups  
restore tests  
host rollback tests  
tenant deletion tests  
credential revocation tests  
SELinux review  
network egress policy  
resource quotas  
logging/audit

---

# 21. First concrete target architecture

For the first real version, build this:

bootc host  
├── admin login only  
├── platformctl  
├── credential broker stub  
├── one tenant service user: tenant_alice  
└── Alice rootless pod

alice-main.pod  
├── alice-cloudflared.container  
├── alice-dev-env.container  
├── alice-openclaw.container  
└── alice-credential-proxy.container

The first version does **not** need:

many users  
many agents  
full Signal/WhatsApp automation  
full credential broker  
full policy language  
dynamic agent cloning

It needs to prove:

no human host login  
rootless tenant runtime  
container-internal sudo works  
host remains clean  
cloudflared ingress works  
OpenClaw runs in tenant pod  
tenant files live on separate storage

---

# 22. Non-negotiable design rules

## Host rules

Only admin logs into host.  
No guest SSH to host.  
No guest sudo on host.  
No guest packages on host.  
No guest project files on host except controlled volumes.  
No agent access to host Podman socket.  
No agent access to host systemd.  
No agent access to host cloudflared API/token.  
No agent access to raw credential database.

## Tenant rules

One non-login service account per tenant.  
Rootless Podman under that service account.  
Separate subuid/subgid range per tenant.  
Separate storage namespace per tenant.  
Separate credential namespace per tenant.  
Separate cloudflared route/token per tenant or pod.

## Agent rules

Agents request actions; they do not administer the host.  
Agents use agentctl; they do not run raw podman/systemctl.  
Agents receive scoped credentials; they do not own master credentials.  
Agents use selected volumes; they do not choose arbitrary host mounts.  
Agents run rootless; no privileged containers.

## Environment rules

Dev containers can allow internal sudo.  
OpenClaw runtime should be more locked down.  
cloudflared sidecar is platform-controlled.  
credential proxy is platform-controlled.

---

# 23. Final specification statement

The system will be a **single-admin Fedora bootc host** running a **multi-tenant rootless Podman platform**. Each human tenant is represented on the host by a **non-login service account** used only to own that tenant’s rootless Podman runtime, storage, secrets namespace, and systemd user services. Human users interact only with **container-level environments** exposed through **host-managed Cloudflare Tunnel sidecars**, not with the host itself.

Each tenant can have one or more OpenClaw agent pods. A pod composes an OpenClaw runtime container, a guest dev environment container, a cloudflared sidecar, a credential proxy, and optional messaging/tool containers. Guests may have broad power inside their dev containers, including internal sudo and package installation, but they cannot modify the bootc host or other tenants.

Agent creation, environment creation, credential access, tunnel routing, storage attachment, and lifecycle changes are performed only through a host-controlled provisioning layer. OpenClaw agents can request those actions through constrained tools, but the host validates every request against tenant policy, quota, allowed templates, storage grants, and credential grants before generating Quadlet/systemd units and starting rootless containers.

This gives us the desired architecture:

clean host  
no guest host logins  
per-tenant isolation  
rootless guest workloads  
container-internal sudo  
host-managed tunnels  
host-managed credentials  
OpenClaw runtime reuse  
agent/environment composition  
safe agent self-provisioning  
bootc/ostree-style host updates

The guiding principle is:

Maximum capability inside the assigned tenant environment.  
Minimum authority across the host boundary.
