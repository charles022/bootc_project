# Verify tenant isolation

## Goal

Prove that the tenants on a running multi-tenant host are actually isolated from each other. This is the central deliverable of Phase 1 of the multi-tenant build (`concepts/multi_tenant_architecture.md`).

After completing this procedure you will know whether:

- every tenant has a non-login service account with a locked password and no privileged-group membership
- every tenant has its own non-overlapping `/etc/subuid` and `/etc/subgid` ranges
- one tenant's service account cannot read another tenant's runtime directory
- the rendered Quadlet directories are root-owned and per-UID segregated

## Prerequisites

- A booted host running the multi-tenant host image.
- Admin (`root` / `sudo`) on the host.
- At least one tenant created via `platformctl tenant create` (`how-to/create_a_tenant.md`). Pairwise checks are skipped automatically when only one tenant exists.

## Steps

1. **Create two tenants for a meaningful pairwise check.** Skip if you already have at least two tenants.

    ```bash
    sudo platformctl tenant create alice
    sudo platformctl tenant create bob
    ```

2. **Run the full check across every tenant on the host.**

    ```bash
    sudo platformctl tenant verify-isolation
    ```

    Expected (abbreviated):

    ```text
    == per-tenant invariants ==
      [ ok  ] alice: nologin shell
      [ ok  ] alice: password locked
      [ ok  ] alice: no privileged group membership
      [ ok  ] alice: Quadlet dir root-owned
      [ ok  ] bob:   nologin shell
      [ ok  ] bob:   password locked
      [ ok  ] bob:   no privileged group membership
      [ ok  ] bob:   Quadlet dir root-owned
    == pairwise isolation ==
      [ ok  ] alice.uid (994) != bob.uid (993)
      [ ok  ] /etc/subuid ranges disjoint (alice=296608 65536, bob=362144 65536)
      [ ok  ] /etc/subgid ranges disjoint (alice=296608 65536, bob=362144 65536)
      [ ok  ] storage roots distinct (/var/lib/openclaw-platform/tenants/alice, /var/lib/openclaw-platform/tenants/bob)
      [ ok  ] tenant_alice cannot list /var/lib/openclaw-platform/tenants/bob/runtime
      [ ok  ] tenant_bob   cannot list /var/lib/openclaw-platform/tenants/alice/runtime
      [ ok  ] Quadlet dirs distinct (/etc/containers/systemd/users/994, /etc/containers/systemd/users/993)

    result: PASS
    ```

3. **Run a focused two-tenant check.**

    ```bash
    sudo platformctl tenant verify-isolation alice bob
    ```

    Same per-tenant and pairwise sections, but limited to alice and bob.

4. **Inspect a single tenant for context.**

    ```bash
    sudo platformctl tenant inspect alice
    ```

    Prints UID, GID, shell, home, storage root, subuid/subgid range, status, lingering, the Quadlet directory listing, the tunnel state, and the user-mode pod-services state.

## Verify

The command exits `0` on PASS and `4` on any FAIL — so a CI or smoke-test script can treat it as a single boolean signal:

```bash
if sudo platformctl tenant verify-isolation > /tmp/iso.log; then
    echo "isolation: PASS"
else
    echo "isolation: FAIL"; cat /tmp/iso.log
fi
```

## Common failures and what they mean

- **`subuid range overlap`** — two tenants have overlapping subuid blocks. Usually means `useradd`'s auto-allocation was disabled in `/etc/login.defs` *and* the older Phase-0 hardcoded fallback was used. Phase 1 replaces that fallback (`reference/platformctl.md`); upgrade the host image, then `platformctl tenant delete` and re-create the affected tenants.
- **`tenant_X can list /var/lib/openclaw-platform/tenants/Y/runtime`** — directory permissions on the runtime dir were widened by hand. Reset with `sudo chmod 0700 /var/lib/openclaw-platform/tenants/<Y>/runtime`.
- **`shell is /bin/bash`** — the account was edited by hand. Reset with `sudo usermod -s /usr/sbin/nologin tenant_<name>`.
- **`password not locked`** — same. Reset with `sudo passwd -l tenant_<name>`.
- **`in privileged group (... wheel ...)`** — the account was added to `wheel` or `sudo` by hand. Remove with `sudo gpasswd -d tenant_<name> wheel`.
- **`Quadlet dir … owned by <user>`** — the rendered Quadlet directory was chowned. Reset with `sudo chown -R root:root /etc/containers/systemd/users/<UID>`.

If you see one of the warnings rather than a hard failure (for example `runtime/.ssh/authorized_keys exists`), the platform itself did not create that file — an admin or an in-tenant process did. Investigate before clearing.

## See also

- `reference/platformctl.md`
- `concepts/multi_tenant_architecture.md`
- `concepts/tenant_identity_model.md`
- `concepts/tenant_storage_layout.md`
- `how-to/create_a_tenant.md`
