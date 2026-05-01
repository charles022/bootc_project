# Enroll a tenant credential

## Goal

Add a credential into a tenant's namespace, grant a specific agent access to it, and verify that the credential-proxy sidecar inside the tenant pod can fetch the value.

After completing this procedure you will know that:

- the broker has the credential (encrypted on disk)
- exactly one agent has been granted `read` access
- the proxy returns the value for the granted agent and refuses every other agent
- the audit log records every allow / deny

This corresponds to Phase 2 of the multi-tenant build (`concepts/credential_broker.md`).

## Prerequisites

- A booted host running the multi-tenant host image with `openclaw-broker.service` active.
- Admin (`root` / `sudo`) on the host.
- A tenant created via `platformctl tenant create` (`how-to/create_a_tenant.md`).
- The tenant's onboarding pod is running so its credential-proxy sidecar is reachable.

Verify the broker is up:

```bash
sudo systemctl is-active openclaw-broker.service
test -S /run/openclaw-broker/admin.sock && echo "admin socket OK"
```

## Steps

1. **Add the credential.** The plaintext value is read from stdin so it never appears on the command line or in shell history:

    ```bash
    printf '%s' 'sk-real-token-here' | sudo platformctl credential add alice alice/codex/main
    ```

    The credential id must start with `<tenant>/`; the broker rejects ids in another tenant's namespace.

2. **Verify it landed.**

    ```bash
    sudo platformctl credential list alice
    ```

    Expected: a JSON list with a single entry showing `id: alice/codex/main`, the create / update timestamps, and no plaintext.

3. **Grant a specific agent access.**

    ```bash
    sudo platformctl grant add alice alice-main alice/codex/main read
    ```

    The grant identifies the agent by the name the agent will pass in `credential_request` calls (see `concepts/agent_provisioning.md` for the agent-naming convention).

4. **Verify the grant.**

    ```bash
    sudo platformctl grant list alice
    ```

5. **Test the agent socket from inside the tenant pod.** The simplest way is to exec a shell in the openclaw-runtime container and ask the proxy:

    ```bash
    UID_=$(id -u tenant_alice)
    sudo machinectl shell tenant_alice@ /usr/bin/podman exec -i \
        $(sudo machinectl shell tenant_alice@ /usr/bin/podman ps --format '{{.Names}}' | grep openclaw-runtime) \
        python3 -c '
import socket, json, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect("/run/credential-proxy/agent.sock")
s.sendall(json.dumps({"op":"credential_request","agent":"alice-main","id":"alice/codex/main"}).encode()+b"\n")
print(s.recv(4096).decode())
'
    ```

    Expected: `{"ok": true, "value": "sk-real-token-here"}`.

6. **Confirm refusal for an ungranted agent.** Repeat step 5 but ask as a different agent name:

    ```bash
    # ... same machinectl shell + podman exec, but
    s.sendall(json.dumps({"op":"credential_request","agent":"alice-rogue","id":"alice/codex/main"}).encode()+b"\n")
    ```

    Expected: `{"ok": false, "error": "no grant for 'alice-rogue' on 'alice/codex/main'", "type": "PermissionError"}`.

7. **Check the audit log.**

    ```bash
    sudo platformctl audit tail 20
    ```

    Expected entries (newest last): `credential_add`, `grant_add`, `credential_request allowed=true`, `credential_request allowed=false reason="no grant"`.

## Verify

The full Phase-2 happy-path check that returns a single boolean:

```bash
sudo platformctl credential list alice | grep -q 'alice/codex/main' \
  && sudo platformctl grant list alice | grep -q 'alice-main' \
  && echo "enrollment: PASS" || echo "enrollment: FAIL"
```

## Common failures and what they mean

- **`broker admin socket not present`** — `openclaw-broker.service` is not running. Inspect with `sudo journalctl -xeu openclaw-broker.service`. The most common cause on a freshly-built image is the `python3-cryptography` package missing — check `python3 -c "import cryptography"` on the host.
- **`tenant 'alice' does not exist`** — `platformctl credential add` validates the tenant before calling the broker. Run `sudo platformctl tenant create alice` first (`how-to/create_a_tenant.md`).
- **`credential id 'X' must start with 'alice/'`** — the broker enforces the `<tenant>/...` namespacing rule. Rename the id.
- **`KeyError: 'alice/codex/main'`** when adding a grant — the credential was deleted or never added; `platformctl credential list alice` to confirm. (When you delete a credential, all grants for it are dropped automatically.)
- **`no grant for ... on ...` for an agent that should have access** — `sudo platformctl grant list alice` and confirm the agent name matches what the agent sends in `credential_request`. Agent names are case-sensitive.
- **Proxy returns `broker socket not present at /run/credential-proxy/broker.sock`** — the broker had not yet opened a per-tenant socket when the proxy started, *and* the broker has since not been able to discover the tenant. Check `sudo platformctl tenant inspect alice`. Restart the broker (`sudo systemctl restart openclaw-broker.service`) and the per-tenant socket will be re-opened by `discover_tenants()` at startup.

## Rotating and revoking

Rotate a credential (replace the plaintext, keep grants intact):

```bash
printf '%s' 'sk-new-token' | sudo platformctl credential rotate alice alice/codex/main
```

Revoke an agent's grant (credential stays in the store):

```bash
sudo platformctl grant remove alice alice-main alice/codex/main
```

Delete a credential (also drops every grant referencing it):

```bash
sudo platformctl credential delete alice alice/codex/main
```

Each operation appends one line to the audit log.

## See also

- `concepts/credential_broker.md`
- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `reference/platformctl.md`
- `reference/tenant_quadlets.md`
- `how-to/create_a_tenant.md`
- `how-to/verify_tenant_isolation.md`
