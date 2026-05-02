# Enroll a messaging transport

## Goal

Add an email or Signal messaging-bridge sidecar to a tenant's main agent so the human user can drive `agentctl` verbs (`create-agent`, `list-agents`, `stop-agent`, `status`, `help`) by sending messages from a known address or device.

## Prerequisites

- The tenant exists (`platformctl tenant create alice` has been run).
- The tenant's onboarding pod is up.
- A target main agent exists, or you intend to create one as part of this walkthrough.
- `concepts/messaging_interface.md` is the design rationale; this how-to is the procedural recipe.

## Steps — email

### 1. Build a credential JSON

The bridge expects a JSON object with these fields:

```json
{
  "imap_host": "imap.example.com",
  "imap_port": 993,
  "smtp_host": "smtp.example.com",
  "smtp_port": 465,
  "username": "alice@example.com",
  "password": "app-specific-password",
  "from_addr": "alice@example.com",
  "allow_senders": ["alice.personal@gmail.com", "alice.work@example.org"]
}
```

`allow_senders` is the **only** thing keeping a random sender from triggering `agentctl` calls. Treat it as the auth boundary: be precise.

### 2. Enroll the credential

```bash
cat alice-email.json \
    | sudo platformctl credential add alice alice/email/main
```

The plaintext is read from stdin so it never appears on the command line. The broker encrypts it (Fernet) and writes the entry to its store. Verify:

```bash
sudo platformctl credential list alice
```

### 3. Grant the main agent

```bash
sudo platformctl grant add alice main alice/email/main read
```

`read` is the only scope the bridge needs.

### 4. Create or update the main agent

If `main` does not exist yet:

```bash
sudo platformctl agent create alice \
    --name main \
    --runtime quay.io/m0ranmcharles/fedora_init:openclaw-runtime \
    --environment quay.io/m0ranmcharles/fedora_init:onboarding-env \
    --is-main \
    --messaging email \
    --credential email
```

If it already exists, recreate it (the messaging field is set at create time):

```bash
sudo platformctl agent stop alice main
sudo platformctl agent delete alice main
sudo platformctl agent create alice --name main --is-main --messaging email \
     --runtime ... --environment ... --credential email
```

### 5. Verify the bridge is up

```bash
sudo systemctl --user --machine=tenant_alice@ status alice-main-pod.service
sudo journalctl --user --machine=tenant_alice@ -u alice-main-messaging-bridge-email.service
```

The bridge logs `resolved credential id=email for alice@example.com` once it has fetched and parsed the credential.

### 6. End-to-end test

From an allow-listed address, send a message with body `help` to `alice@example.com`. Within the IMAP poll interval (default 30 seconds), the bridge emits an envelope; the runtime router sees the verb, replies with the static help text, and the bridge sends the reply via SMTP. You should receive the help message in the same allow-listed mailbox.

## Steps — Signal

Signal uses a linked-device flow rather than a username/password. Once linked, the credential carries the Signal local-state directory which `signal-cli` uses to authenticate as that device.

### 1. Link a device

The platform ships a helper that runs `signal-cli link` and stores the resulting state under the broker:

```bash
sudo platformctl signal-link alice
```

The command prints a `tsdevice://...` URL. Open Signal on the user's primary phone, choose **Settings → Linked Devices → Link New Device**, scan the URL or paste it. After confirmation, the helper packs the device state, sender allow-list (collected interactively), and stores it under `alice/signal/main`.

### 2. Grant + create

Same shape as the email flow:

```bash
sudo platformctl grant add alice main alice/signal/main read
sudo platformctl agent create alice --name main --is-main \
     --messaging email --messaging signal \
     --runtime ... --environment ... \
     --credential email --credential signal
```

If `main` already exists with the email bridge attached, recreate it with both transports.

### 3. End-to-end test

From the linked Signal device, send a message with body `help` to the linked number. The Signal bridge receives it (typically within a few seconds), the runtime dispatches `help`, and the reply comes back through Signal.

## Verify

```bash
# Confirm the agent record carries the messaging field
sudo platformctl agent inspect alice main | grep messaging

# Confirm the bridge sidecars are running
sudo systemctl --user --machine=tenant_alice@ list-units --no-legend --type=service \
    | grep messaging-bridge

# Confirm the audit log captured a successful round-trip
sudo platformctl audit tail 50 | grep -E 'messaging_inbound|messaging_outbound|agent_create'
```

## Troubleshooting

- **Bridge logs "broker denied alice/email/main"**: no grant. Run `platformctl grant add alice main alice/email/main read`.
- **Bridge logs "rejecting message from non-allow-listed sender"**: the sender's normalized address is not in the credential's `allow_senders` list. `credential rotate` to install a corrected payload.
- **No reply to `help`**: check `journalctl --user --machine=tenant_alice@ -u alice-main-openclaw-runtime.service` — the runtime logs every dispatched verb. If the runtime never sees the envelope, the bridge cannot connect to `/run/messaging-bridge/agent.sock`; check the per-agent msgbus dir owner is `tenant_alice` and mode `0770`.
- **`signal-cli` JVM warnings on startup**: these are normal; the bridge ignores them. A real failure shows as `signal-cli daemon exited` in the journal.
