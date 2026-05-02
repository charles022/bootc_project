# Messaging interface

## What

How a tenant's main agent receives messages from external transports (email, Signal, WhatsApp) and turns them into `agentctl` calls — and how it sends replies back through the same transports. Phase 4 of `design/multi_tenant_architecture.md`.

A tenant's main agent pod gets one **messaging-bridge sidecar per transport** alongside the `openclaw-runtime`, `dev-env`, `cloudflared`, and `credential-proxy` containers. Each bridge:

1. Reads its tenant credential (e.g. `alice/email/main`) at startup through the per-tenant broker socket.
2. Listens to its external transport (IMAP for email, `signal-cli` daemon for Signal, etc.).
3. For inbound messages from senders on the credential's `allow_senders` list, posts a JSONL envelope to a pod-local UNIX socket.
4. Accepts `{"op":"reply",...}` envelopes back over the same socket and sends them out through the transport.

A small **router** in the `openclaw-runtime` container subscribes to the same socket. It dispatches each inbound envelope through a hand-coded verb table — `create-agent`, `list-agents`, `stop-agent`, `status`, `help` — translating the matched verb into an `agentctl` call and posting the result back to the originating bridge as a reply envelope.

## Why

Two extremes fail:

- **SSH-only access.** Forces every guest to learn a terminal, manage SSH keys, and remember which container they're in. Defeats the goal of "user mostly interacts through Signal/WhatsApp/email" (`design/multi_tenant_architecture.md` §11.4).
- **Open natural-language control.** A free-text prompt that drives `podman` / `systemctl` / `agentctl` is exactly the LLM-prompt-injection failure mode `concepts/agent_provisioning.md` was built to prevent. One adversarial sender plus one over-eager LLM equals a privileged container.

The middle path is **bridges that only translate envelopes**, never call the provisioner directly, plus a runtime router that dispatches on a strict verb table. Bridges authenticate inbound senders against an allow-list shipped inside the credential. The runtime never hands a string to a shell.

## Implications

### Bridge ↔ runtime protocol

JSONL over **two unidirectional UNIX sockets** in the pod-shared `/run/messaging-bridge/` directory:

- `inbound.sock` — owned by the openclaw-runtime container (it listens). Each bridge opens a short-lived connection per inbound message and writes one envelope.
- `outbound-<transport>.sock` — owned by the matching bridge container (it listens). The runtime opens a short-lived connection per reply and writes one envelope.

| Direction | Socket | Shape |
|---|---|---|
| bridge → runtime | `inbound.sock` | `{"event":"message","transport":"email","bridge":"email","from":"a@b.com","subject":"...","body":"...","ts":"..."}` |
| runtime → bridge | `outbound-<transport>.sock` | `{"op":"reply","to":"a@b.com","subject":"re: ...","body":"...","transport":"email"}` |

The envelope's `bridge` field tells the runtime which `outbound-<transport>.sock` to send the reply to. When a tenant has both email and Signal bridges in the same pod, each bridge owns its own outbound socket — there is no per-bridge demultiplexing in the bridges themselves.

Two sockets instead of one because (a) it makes each direction a simple listener/connector pair, (b) it lets each bridge own and clean up its own socket without coordinating with sibling bridges, and (c) the file mode of each socket can match the corresponding side's needs.

### Verb table

The router accepts only these verbs in the message body, parsed by simple shell-style splitting (`shlex`). Anything else gets a stock reply directing the sender to `help`.

| Verb | Form | Maps to |
|---|---|---|
| `create-agent` | `create-agent <name> [<env>] [<credentials>...]` | `agentctl create-agent --name <name> --runtime <default> --environment <env> --credential <c>...` |
| `list-agents` | `list-agents` | `agentctl list-agents` |
| `stop-agent` | `stop-agent <name>` | `agentctl stop-agent <name>` |
| `status` | `status [<name>]` | `agentctl inspect-agent <name>` (or list when omitted) |
| `help` | `help` | static reply listing the verbs above |

The router has no `delete-agent` verb on purpose: agent deletion is admin-only by convention (cleanup involves recovering volumes; messages are too thin a channel for it).

### Authentication boundary

Two layers stack:

1. **Credential-defined sender allow-list.** Each transport credential carries an `allow_senders` field. The bridge drops every inbound message whose sender is not on that list **before** emitting an envelope to the runtime. This shrinks the attack surface to a fixed set of phone numbers / email addresses the admin enrolled.
2. **Runtime verb table.** Even an allow-listed sender can only invoke the verbs above. There is no string-to-shell path.

The credential proxy's per-tenant socket is not used by the bridge — bridges connect directly to the per-tenant broker socket bind-mounted from the host. The bridges issue `credential_request` ops only; the broker's grant table still gates whether the agent can read the credential. Reusing the credential-proxy's allow-listed op set on top of that would add a layer with no extra security gain (the broker already enforces the boundary).

### Why bridges don't call agentctl directly

Three reasons:

1. **Single source of dispatch.** The runtime can correlate inbound transport with reply transport, dedupe duplicate messages, and apply the verb table once. Each bridge would otherwise need its own copy of that logic.
2. **Audit clarity.** Every dispatched verb shows up in one place (`provisioner/audit.log` for the `agentctl` call; runtime stderr for the inbound match). Bridges calling `agentctl` would split that across several units.
3. **Future-proofing.** When the router gains an LLM-driven free-text mode (Phase 5+), the bridges don't need to change — they keep emitting envelopes; only the runtime's dispatch logic gets richer.

### Failure modes

| Failure | Mitigation |
|---|---|
| Sender not in `allow_senders` | bridge drops the message before emitting an envelope; logs `messaging_inbound_dropped` |
| Unknown verb | router replies `unknown command, send 'help'`; logs the verb received |
| `agentctl` denies (policy / quota / forbidden flag) | router posts the broker / provisioner error message back to the originating sender as the reply body |
| `agentctl` fails after start (Quadlet render OK, systemd start failed) | provisioner records `start_failed` in audit; router replies with the error |
| Credential rotated mid-run | bridge fails its next IMAP / Signal call, restarts, fetches the new credential — no manual intervention needed |
| Message bus socket missing (runtime not yet up) | bridge keeps polling its transport but cannot dispatch; sets a non-zero exit on first reply attempt; systemd restarts it |
| Bridge sidecar crashes | systemd `Restart=on-failure` revives it; transport state lives in the credential, not in the container |

### Files on disk

| Path | Owner | Purpose |
|---|---|---|
| `01_build_image/build_assets/multi_tenant/messaging-bridge-email.py` | repo source | email bridge daemon (IMAP poll + SMTP send) |
| `01_build_image/build_assets/multi_tenant/messaging-bridge-signal.py` | repo source | Signal bridge daemon (signal-cli daemon + `send`) |
| `01_build_image/build_assets/multi_tenant/messaging-bridge-whatsapp.py` | repo source | WhatsApp stub (planned) |
| `01_build_image/build_assets/multi_tenant/agent_quadlet/agent-messaging-bridge-<transport>.container.tmpl` | repo source | per-transport sidecar template |
| `${PLATFORM_ROOT}/tenants/<tenant>/runtime/agents/<agent>/msgbus/inbound.sock` | `tenant_<tenant>` | runtime-owned listener for inbound envelopes |
| `${PLATFORM_ROOT}/tenants/<tenant>/runtime/agents/<agent>/msgbus/outbound-<transport>.sock` | `tenant_<tenant>` | bridge-owned listener for outbound reply envelopes (one per transport) |

## See also

- `concepts/agent_provisioning.md` (the verb table calls into this)
- `concepts/credential_broker.md` (allow_senders lives in the credential payload)
- `reference/agentctl.md` (the verbs the router actually issues)
- `reference/images.md` (the bridge images)
- `reference/tenant_quadlets.md` (how the templates render into a pod)
- `how-to/enroll_messaging.md` (walkthrough)

## WhatsApp (planned)

The WhatsApp bridge ships as a stub. Real implementation requires:

- a Meta Business webhook (HTTPS POST endpoint registered with Meta for the tenant's WhatsApp Business number)
- a per-pod cloudflared `messaging-webhook` ingress route exposing the bridge's HTTP listener at a stable hostname
- per-tenant route generation on `agent set-main` (today the bridge has no exposed listener)

The cloudflared `messaging-webhook` ingress class is reserved in `policy.allowed_networks` but not yet wired into `tenant-cloudflared.container.tmpl`. Phase 5.
