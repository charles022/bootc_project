#!/usr/bin/env bash
# platformctl - admin CLI for the OpenClaw multi-tenant layer.
# Concept: docs/concepts/multi_tenant_architecture.md
# Reference: docs/reference/platformctl.md

set -euo pipefail

PLATFORM_ROOT="${OPENCLAW_PLATFORM_ROOT:-/var/lib/openclaw-platform}"
QUADLET_DIR="${OPENCLAW_QUADLET_DIR:-/etc/containers/systemd/users}"
TEMPLATE_DIR="${OPENCLAW_TEMPLATE_DIR:-${PLATFORM_ROOT}/templates/quadlet}"
SUBID_BASE="${OPENCLAW_SUBID_BASE:-200000}"
SUBID_BLOCK="${OPENCLAW_SUBID_BLOCK:-65536}"
BROKER_ADMIN_SOCK="${OPENCLAW_BROKER_ADMIN_SOCK:-/run/openclaw-broker/admin.sock}"
PROVISIONER_ADMIN_SOCK="${OPENCLAW_PROVISIONER_ADMIN_SOCK:-/run/openclaw-provisioner/admin.sock}"
DRY_RUN="${OPENCLAW_DRY_RUN:-}"

err() { printf 'platformctl: error: %s\n' "$*" >&2; }
log() { printf 'platformctl: %s\n' "$*"; }

run() {
    if [[ -n "${DRY_RUN}" ]]; then
        printf 'DRY-RUN: %s\n' "$*"
    else
        "$@"
    fi
}

require_root() {
    if [[ $(id -u) -ne 0 ]]; then
        err "must be run as root (try: sudo platformctl ...)"
        exit 1
    fi
}

valid_tenant_name() {
    [[ "$1" =~ ^[a-z][a-z0-9-]*$ ]]
}

tenant_user()  { printf 'tenant_%s' "$1"; }
tenant_dir()   { printf '%s/tenants/%s' "${PLATFORM_ROOT}" "$1"; }

# Send one JSONL request to a UNIX socket and print the JSON reply. Returns
# 0 if ok=true, 1 otherwise. Used for both broker and provisioner.
sock_call() {
    local sock="$1" req="$2"
    if [[ ! -S "${sock}" ]]; then
        err "socket not present at ${sock}"
        return 3
    fi
    if [[ -n "${DRY_RUN}" ]]; then
        printf 'DRY-RUN: sock_call %s %s\n' "${sock}" "${req}"
        return 0
    fi
    python3 - "${sock}" "${req}" <<'PY'
import json, socket, sys
sock_path, req = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(15)
try:
    s.connect(sock_path)
    s.sendall(req.encode("utf-8") + b"\n")
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    line = buf.split(b"\n", 1)[0].decode("utf-8", errors="replace")
finally:
    s.close()

try:
    obj = json.loads(line) if line else {}
except Exception as exc:
    print(json.dumps({"ok": False, "error": f"invalid reply: {exc}", "raw": line}))
    sys.exit(1)

print(json.dumps(obj, indent=2, sort_keys=True))
sys.exit(0 if obj.get("ok") else 1)
PY
}

broker_call() {
    sock_call "${BROKER_ADMIN_SOCK}" "$1"
}

provisioner_call() {
    sock_call "${PROVISIONER_ADMIN_SOCK}" "$1"
}

# Construct a JSON request from KEY=VALUE pairs, treating numbers as numbers.
mkreq() {
    python3 - "$@" <<'PY'
import json, sys
out = {"op": sys.argv[1]}
for kv in sys.argv[2:]:
    k, _, v = kv.partition("=")
    if v.lstrip("-").isdigit():
        out[k] = int(v)
    else:
        out[k] = v
print(json.dumps(out))
PY
}

# Same as mkreq but read a single field's value from stdin so secrets never
# appear on the command line.
mkreq_with_stdin_value() {
    local op="$1" value_field="$2"; shift 2
    python3 - "${op}" "${value_field}" "$@" <<'PY'
import json, sys
op = sys.argv[1]
value_field = sys.argv[2]
out = {"op": op}
for kv in sys.argv[3:]:
    k, _, v = kv.partition("=")
    if v.lstrip("-").isdigit():
        out[k] = int(v)
    else:
        out[k] = v
out[value_field] = sys.stdin.read().rstrip("\n")
print(json.dumps(out))
PY
}

# Pick the next free subid range that does not collide with any existing
# /etc/sub{uid,gid} entry. Used as the fallback when useradd's auto-allocation
# is disabled. Without this, two tenants could end up with the same range,
# violating the "separate subuid/subgid range per tenant" rule.
next_free_subid_range() {
    local file="$1" base="${SUBID_BASE}" block="${SUBID_BLOCK}"
    local highest=$(( base - 1 ))
    if [[ -f "${file}" ]]; then
        local end
        while IFS=: read -r _ start count; do
            [[ -n "${start}" && -n "${count}" ]] || continue
            end=$(( start + count - 1 ))
            if (( end > highest )); then highest=${end}; fi
        done < "${file}"
    fi
    local start=$(( highest + 1 ))
    if (( start < base )); then start=${base}; fi
    printf '%d-%d' "${start}" $(( start + block - 1 ))
}

usage() {
    cat <<'EOF'
Usage:
  platformctl tenant create  <name>
  platformctl tenant list
  platformctl tenant inspect <name>
  platformctl tenant disable <name>
  platformctl tenant enable  <name>
  platformctl tenant delete  <name>
  platformctl tenant verify-isolation [<a> <b>]

  platformctl tunnel set-config      <tenant> [<path>]
  platformctl tunnel set-credentials <tenant> [<path>]
  platformctl tunnel show            <tenant>
  platformctl tunnel list

  platformctl credential add    <tenant> <id>     (value read from stdin)
  platformctl credential list   [<tenant>]
  platformctl credential delete <tenant> <id>
  platformctl credential rotate <tenant> <id>     (new value read from stdin)

  platformctl grant add    <tenant> <agent> <id> [<scope>]
  platformctl grant remove <tenant> <agent> <id>
  platformctl grant list   [<tenant>]

  platformctl audit tail [<n>]

  platformctl signal-link <tenant>                                  (Phase 4)

  platformctl agent  create   <tenant> --name <n> --runtime <img> --environment <img> [--credential <id> ...] [--storage <volume> ...] [--ingress <class> ...] [--messaging <transport> ...] [--is-main] [--network <profile>]
  platformctl agent  list     <tenant>
  platformctl agent  inspect  <tenant> <name>
  platformctl agent  start    <tenant> <name>
  platformctl agent  stop     <tenant> <name>
  platformctl agent  delete   <tenant> <name>
  platformctl agent  set-main <tenant> <name>

  platformctl policy show <tenant>

  platformctl backup run    <tenant>           (planned)
  platformctl backup restore <tenant> --snapshot <id>  (planned)

Environment:
  OPENCLAW_PLATFORM_ROOT          default: /var/lib/openclaw-platform
  OPENCLAW_QUADLET_DIR            default: /etc/containers/systemd/users
  OPENCLAW_TEMPLATE_DIR           default: ${OPENCLAW_PLATFORM_ROOT}/templates/quadlet
  OPENCLAW_SUBID_BASE             fallback subuid/subgid base (default 200000)
  OPENCLAW_SUBID_BLOCK            fallback subuid/subgid block size (default 65536)
  OPENCLAW_BROKER_ADMIN_SOCK      default: /run/openclaw-broker/admin.sock
  OPENCLAW_PROVISIONER_ADMIN_SOCK default: /run/openclaw-provisioner/admin.sock
  OPENCLAW_DRY_RUN                if set, print actions without executing
EOF
}

cmd_planned() {
    err "subcommand '$*' is planned, not yet implemented"
    exit 1
}

cmd_tenant_create() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then err "tenant create: missing <name>"; exit 1; fi
    if ! valid_tenant_name "${name}"; then
        err "tenant create: invalid name '${name}' (expected [a-z][a-z0-9-]*)"
        exit 1
    fi

    local user; user=$(tenant_user "${name}")
    local home; home="$(tenant_dir "${name}")/runtime"

    if getent passwd "${user}" >/dev/null; then
        err "tenant create: ${user} already exists"
        exit 2
    fi

    if [[ ! -d "${TEMPLATE_DIR}" ]]; then
        err "tenant create: template dir not found: ${TEMPLATE_DIR}"
        exit 2
    fi

    log "creating tenant '${name}' (service account ${user})"

    # Create the tenant storage subtree first so useradd's --home-dir target exists.
    run install -d -m 0755 "${PLATFORM_ROOT}/tenants"
    run install -d -m 0755 "$(tenant_dir "${name}")"
    run install -d -m 0700 "$(tenant_dir "${name}")/runtime"
    run install -d -m 0700 "$(tenant_dir "${name}")/volumes"
    run install -d -m 0750 "$(tenant_dir "${name}")/quadlet"
    run install -d -m 0750 "$(tenant_dir "${name}")/cloudflared"
    run install -d -m 0750 "$(tenant_dir "${name}")/credentials"
    run install -d -m 0755 "$(tenant_dir "${name}")/policy"
    run install -d -m 0755 "$(tenant_dir "${name}")/logs"
    run install -d -m 0750 "$(tenant_dir "${name}")/backups"

    # Create the non-login service account. Do NOT use --create-home, because the
    # home dir already exists; useradd will set ownership without copying skel.
    run useradd \
        --system \
        --home-dir "${home}" \
        --no-create-home \
        --shell /usr/sbin/nologin \
        --comment "OpenClaw tenant ${name}" \
        "${user}"

    # Lock the password (useradd --system already creates with no password,
    # but make it explicit so the account cannot be unlocked by accident).
    run passwd -l "${user}" >/dev/null

    # Verify subuid/subgid allocation; if useradd did not auto-allocate (some
    # distros disable AUTO_SUBUID_GID_RANGE), pick the next free block past the
    # highest existing range. Hardcoding a single range would make every
    # fallback-path tenant collide -- a Phase 1 isolation bug.
    if ! grep -q "^${user}:" /etc/subuid 2>/dev/null; then
        local subuid_range
        subuid_range=$(next_free_subid_range /etc/subuid)
        log "subuid not auto-allocated, assigning ${subuid_range}"
        run usermod --add-subuids "${subuid_range}" "${user}"
    fi
    if ! grep -q "^${user}:" /etc/subgid 2>/dev/null; then
        local subgid_range
        subgid_range=$(next_free_subid_range /etc/subgid)
        log "subgid not auto-allocated, assigning ${subgid_range}"
        run usermod --add-subgids "${subgid_range}" "${user}"
    fi

    # Set ownership on tenant-writable dirs.
    run chown "${user}:${user}" "$(tenant_dir "${name}")/runtime"
    run chown "${user}:${user}" "$(tenant_dir "${name}")/volumes"

    # Render the default tenant policy. The provisioner reads this file at
    # every agent_create call (see docs/concepts/agent_provisioning.md). Edit
    # by hand to relax / tighten what agents may request.
    if [[ -z "${DRY_RUN}" ]]; then
        cat > "$(tenant_dir "${name}")/policy/policy.yaml" <<EOF
# Tenant policy for ${name}. Authoritative source for agent_create validation.
# See docs/concepts/agent_provisioning.md for the schema.
tenant: ${name}
service_user: ${user}
status: active

limits:
  max_agents: 10
  max_running_agents: 5

allowed_images:
  openclaw_runtime:
    - quay.io/m0ranmcharles/fedora_init:openclaw-runtime
  environments:
    - quay.io/m0ranmcharles/fedora_init:onboarding-env

allowed_credentials:
  - codex
  - gemini
  - claude
  - email
  - signal
  - github

allowed_networks:
  - none
  - messaging-only
  - api-only
  - restricted-internet

# Messaging transports a tenant agent may attach (Phase 4). Each entry causes
# the provisioner to render the matching messaging-bridge sidecar in the agent
# pod when --messaging <transport> is passed to agent create. whatsapp ships
# as a stub container today; webhook ingress wiring is Phase 5.
allowed_messaging:
  - email
  - signal
  - whatsapp

default_network: restricted-internet

forbidden:
  privileged: true
  host_network: true
  host_pid: true
  host_ipc: true
  host_podman_socket: true
  arbitrary_host_mounts: true
EOF
        chmod 0644 "$(tenant_dir "${name}")/policy/policy.yaml"
    else
        printf 'DRY-RUN: write %s/policy/policy.yaml\n' "$(tenant_dir "${name}")"
    fi

    # Render the Quadlet templates into /etc/containers/systemd/users/<UID>/.
    local tenant_uid tenant_gid quadlet_target
    if [[ -n "${DRY_RUN}" ]] && ! id -u "${user}" >/dev/null 2>&1; then
        tenant_uid="<DRY_RUN_UID>"
        tenant_gid="<DRY_RUN_GID>"
    else
        tenant_uid=$(id -u "${user}")
        tenant_gid=$(id -g "${user}")
    fi
    quadlet_target="${QUADLET_DIR}/${tenant_uid}"
    run install -d -m 0755 "${quadlet_target}"

    local tmpl rendered
    for tmpl in "${TEMPLATE_DIR}"/*.tmpl; do
        [[ -f "${tmpl}" ]] || continue
        # Output filename: tenant-foo.pod.tmpl -> <name>-foo.pod
        rendered="${quadlet_target}/${name}-$(basename "${tmpl}" .tmpl | sed 's/^tenant-//')"
        log "render ${tmpl} -> ${rendered}"
        if [[ -z "${DRY_RUN}" ]]; then
            TENANT="${name}" \
            TENANT_UID="${tenant_uid}" \
            TENANT_GID="${tenant_gid}" \
            TENANT_HOME="${home}" \
            TENANT_VOLUMES="$(tenant_dir "${name}")/volumes" \
            TENANT_CLOUDFLARED="$(tenant_dir "${name}")/cloudflared" \
            PLATFORM_ROOT="${PLATFORM_ROOT}" \
            envsubst '${TENANT} ${TENANT_UID} ${TENANT_GID} ${TENANT_HOME} ${TENANT_VOLUMES} ${TENANT_CLOUDFLARED} ${PLATFORM_ROOT}' \
                < "${tmpl}" > "${rendered}"
            chmod 0644 "${rendered}"
        fi
    done

    # Enable lingering so user services run without an interactive login.
    run loginctl enable-linger "${user}"

    # Reload so the user-mode Quadlet generator picks up the new units.
    run systemctl daemon-reload

    # Tell the broker and the provisioner to open per-tenant sockets so the
    # credential-proxy and openclaw-runtime sidecars in this tenant's pods can
    # mount them. If either daemon is not running yet, it will pick up the
    # tenant on its next discover_tenants() at startup; warn but do not fail.
    if [[ -z "${DRY_RUN}" && -n "${tenant_uid}" && "${tenant_uid}" != "<DRY_RUN_UID>" ]]; then
        local req
        req=$(mkreq tenant_register tenant="${name}" uid="${tenant_uid}" gid="${tenant_gid}")
        if ! broker_call "${req}" >/dev/null 2>&1; then
            log "broker not reachable; tenant ${name} will be picked up on broker startup"
        else
            log "broker registered tenant ${name}"
        fi
        if ! provisioner_call "${req}" >/dev/null 2>&1; then
            log "provisioner not reachable; tenant ${name} will be picked up on provisioner startup"
        else
            log "provisioner registered tenant ${name}"
        fi
    fi

    # Start the onboarding pod under the tenant's user manager.
    if [[ -z "${DRY_RUN}" ]]; then
        # Wait briefly for the user manager to be reachable after enable-linger.
        for _ in 1 2 3 4 5; do
            if systemctl --user --machine="${user}@" daemon-reload >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        systemctl --user --machine="${user}@" start "${name}-onboard-pod.service" || {
            err "tenant create: failed to start ${name}-onboard-pod.service (see journalctl --user-unit ${name}-onboard-pod.service -M ${user}@)"
        }
    else
        printf 'DRY-RUN: systemctl --user --machine=%s@ start %s-onboard-pod.service\n' "${user}" "${name}"
    fi

    log "tenant '${name}' created (UID=${tenant_uid}, home=${home})"
}

cmd_tenant_list() {
    local users
    users=$(getent passwd | awk -F: '$1 ~ /^tenant_/ {print $1":"$3}')
    if [[ -z "${users}" ]]; then
        printf 'no tenants\n'
        return 0
    fi
    printf '%-20s %-8s %-10s %s\n' "TENANT" "UID" "STATUS" "STORAGE"
    while IFS=: read -r u uid; do
        local name="${u#tenant_}"
        local dir; dir="$(tenant_dir "${name}")"
        local status="active"
        if [[ -f "${dir}/.disabled" ]]; then status="disabled"; fi
        printf '%-20s %-8s %-10s %s\n' "${name}" "${uid}" "${status}" "${dir}"
    done <<<"${users}"
}

cmd_tenant_inspect() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then err "tenant inspect: missing <name>"; exit 1; fi
    local user; user=$(tenant_user "${name}")
    if ! getent passwd "${user}" >/dev/null; then
        err "tenant inspect: tenant '${name}' does not exist"; exit 2
    fi
    local uid gid home dir
    uid=$(id -u "${user}")
    gid=$(id -g "${user}")
    home=$(getent passwd "${user}" | cut -d: -f6)
    dir=$(tenant_dir "${name}")

    printf 'tenant:        %s\n' "${name}"
    printf 'service_user:  %s\n' "${user}"
    printf 'uid:           %s\n' "${uid}"
    printf 'gid:           %s\n' "${gid}"
    printf 'shell:         %s\n' "$(getent passwd "${user}" | cut -d: -f7)"
    printf 'home:          %s\n' "${home}"
    printf 'storage_root:  %s\n' "${dir}"
    printf 'subuid:        %s\n' "$(grep "^${user}:" /etc/subuid 2>/dev/null | head -1 || echo none)"
    printf 'subgid:        %s\n' "$(grep "^${user}:" /etc/subgid 2>/dev/null | head -1 || echo none)"
    if [[ -f "${dir}/.disabled" ]]; then printf 'status:        disabled\n'; else printf 'status:        active\n'; fi

    printf 'lingering:     '
    if loginctl show-user "${user}" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
        printf 'yes\n'
    else
        printf 'no\n'
    fi

    printf 'quadlets:      %s\n' "${QUADLET_DIR}/${uid}"
    if [[ -d "${QUADLET_DIR}/${uid}" ]]; then
        ls -1 "${QUADLET_DIR}/${uid}" | sed 's/^/  /'
    else
        printf '  (none)\n'
    fi

    printf 'tunnel:        '
    if [[ -f "${dir}/cloudflared/config.yml" ]]; then
        printf 'config.yml present'
        if compgen -G "${dir}/cloudflared/*.json" > /dev/null; then
            printf ', credentials present'
        fi
        printf '\n'
    elif [[ -f "${dir}/cloudflared/token" ]]; then
        printf 'token present\n'
    else
        printf 'unconfigured\n'
    fi

    printf 'pod_services:\n'
    if systemctl --user --machine="${user}@" list-units --no-legend --type=service 2>/dev/null \
        | awk '{print $1, $3, $4}' | grep -E "^${name}-" | sed 's/^/  /'; then
        :
    else
        printf '  (user manager not reachable; tenant may be disabled or host has not started lingering yet)\n'
    fi
}

cmd_tenant_disable() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then err "tenant disable: missing <name>"; exit 1; fi
    local user; user=$(tenant_user "${name}")
    if ! getent passwd "${user}" >/dev/null; then
        err "tenant disable: tenant '${name}' does not exist"; exit 2
    fi
    log "stopping ${name}'s onboarding pod"
    run systemctl --user --machine="${user}@" stop "${name}-onboard-pod.service" || true
    run loginctl disable-linger "${user}" || true
    run touch "$(tenant_dir "${name}")/.disabled"
    log "tenant '${name}' disabled"
}

cmd_tenant_enable() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then err "tenant enable: missing <name>"; exit 1; fi
    local user; user=$(tenant_user "${name}")
    if ! getent passwd "${user}" >/dev/null; then
        err "tenant enable: tenant '${name}' does not exist"; exit 2
    fi
    run rm -f "$(tenant_dir "${name}")/.disabled"
    run loginctl enable-linger "${user}"
    run systemctl --user --machine="${user}@" start "${name}-onboard-pod.service" || true
    log "tenant '${name}' enabled"
}

cmd_tenant_delete() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then err "tenant delete: missing <name>"; exit 1; fi
    local user; user=$(tenant_user "${name}")
    if ! getent passwd "${user}" >/dev/null; then
        err "tenant delete: tenant '${name}' does not exist"; exit 2
    fi
    local tenant_uid; tenant_uid=$(id -u "${user}")

    log "stopping ${name}'s services"
    run systemctl --user --machine="${user}@" stop "${name}-onboard-pod.service" || true
    run loginctl disable-linger "${user}" || true

    # Tell the broker and provisioner to close the per-tenant sockets. Best-effort.
    if [[ -z "${DRY_RUN}" ]]; then
        local req
        req=$(mkreq tenant_unregister tenant="${name}")
        broker_call "${req}" >/dev/null 2>&1 || true
        provisioner_call "${req}" >/dev/null 2>&1 || true
    fi

    log "removing rendered Quadlets"
    run rm -rf "${QUADLET_DIR}/${tenant_uid}"

    log "removing user account"
    run userdel "${user}" || true

    log "removing tenant data dir"
    run rm -rf "$(tenant_dir "${name}")"

    run systemctl daemon-reload
    log "tenant '${name}' deleted"
}

# Subuid/subgid range overlap check. Returns 0 when ranges overlap, 1 when not.
ranges_overlap() {
    local a_start="$1" a_count="$2" b_start="$3" b_count="$4"
    local a_end=$(( a_start + a_count - 1 ))
    local b_end=$(( b_start + b_count - 1 ))
    (( a_start <= b_end && b_start <= a_end ))
}

# Print the (start count) of a tenant's first sub{uid,gid} mapping, or empty if absent.
tenant_subid_range() {
    local file="$1" user="$2"
    grep "^${user}:" "${file}" 2>/dev/null | head -1 | awk -F: '{print $2, $3}'
}

# Per-pair isolation check. Returns 0 when isolated, 1 when a violation is found.
verify_pair_isolation() {
    local a="$1" b="$2"
    local ua; ua=$(tenant_user "${a}")
    local ub; ub=$(tenant_user "${b}")
    local da; da=$(tenant_dir "${a}")
    local db; db=$(tenant_dir "${b}")
    local violations=0

    # 1. UIDs must differ.
    local uid_a uid_b
    uid_a=$(id -u "${ua}" 2>/dev/null || echo -)
    uid_b=$(id -u "${ub}" 2>/dev/null || echo -)
    if [[ "${uid_a}" == - || "${uid_b}" == - ]]; then
        printf '  [skip ] %s vs %s: one or both tenants do not exist\n' "${a}" "${b}"
        return 0
    fi
    if [[ "${uid_a}" == "${uid_b}" ]]; then
        printf '  [FAIL ] %s vs %s: UID collision (both %s)\n' "${a}" "${b}" "${uid_a}"
        violations=$(( violations + 1 ))
    else
        printf '  [ ok  ] %s.uid (%s) != %s.uid (%s)\n' "${a}" "${uid_a}" "${b}" "${uid_b}"
    fi

    # 2. subuid / subgid ranges must not overlap.
    local f r_a r_b
    for f in /etc/subuid /etc/subgid; do
        r_a=$(tenant_subid_range "${f}" "${ua}")
        r_b=$(tenant_subid_range "${f}" "${ub}")
        if [[ -z "${r_a}" || -z "${r_b}" ]]; then
            printf '  [skip ] %s overlap check: at least one range is missing\n' "${f}"
            continue
        fi
        # shellcheck disable=SC2086
        if ranges_overlap ${r_a} ${r_b}; then
            printf '  [FAIL ] %s overlap: %s=%s vs %s=%s\n' "${f}" "${a}" "${r_a}" "${b}" "${r_b}"
            violations=$(( violations + 1 ))
        else
            printf '  [ ok  ] %s ranges disjoint (%s=%s, %s=%s)\n' "${f}" "${a}" "${r_a}" "${b}" "${r_b}"
        fi
    done

    # 3. Storage roots must be distinct, owned distinctly, and unreadable cross-tenant.
    if [[ "${da}" == "${db}" ]]; then
        printf '  [FAIL ] storage_root collision (both %s)\n' "${da}"
        violations=$(( violations + 1 ))
    else
        printf '  [ ok  ] storage roots distinct (%s, %s)\n' "${da}" "${db}"
    fi

    # 4. As tenant_a, attempt to list tenant_b's runtime dir; expect failure.
    if [[ -d "${db}/runtime" ]]; then
        if runuser -u "${ua}" -- ls "${db}/runtime" >/dev/null 2>&1; then
            printf '  [FAIL ] %s can list %s/runtime (expected EACCES)\n' "${ua}" "${db}"
            violations=$(( violations + 1 ))
        else
            printf '  [ ok  ] %s cannot list %s/runtime\n' "${ua}" "${db}"
        fi
    fi
    if [[ -d "${da}/runtime" ]]; then
        if runuser -u "${ub}" -- ls "${da}/runtime" >/dev/null 2>&1; then
            printf '  [FAIL ] %s can list %s/runtime (expected EACCES)\n' "${ub}" "${da}"
            violations=$(( violations + 1 ))
        else
            printf '  [ ok  ] %s cannot list %s/runtime\n' "${ub}" "${da}"
        fi
    fi

    # 5. Quadlet directories must be UID-segregated and root-owned.
    local qa qb
    qa="${QUADLET_DIR}/${uid_a}"
    qb="${QUADLET_DIR}/${uid_b}"
    if [[ -d "${qa}" && -d "${qb}" ]]; then
        if [[ "${qa}" == "${qb}" ]]; then
            printf '  [FAIL ] Quadlet dir collision (both %s)\n' "${qa}"
            violations=$(( violations + 1 ))
        else
            printf '  [ ok  ] Quadlet dirs distinct (%s, %s)\n' "${qa}" "${qb}"
        fi
    fi

    return $(( violations > 0 ))
}

# Per-tenant invariants check. Returns 0 when ok, 1 on any violation.
verify_tenant_invariants() {
    local name="$1"
    local user; user=$(tenant_user "${name}")
    local dir; dir=$(tenant_dir "${name}")
    local violations=0

    if ! getent passwd "${user}" >/dev/null; then
        printf '  [skip ] %s: tenant does not exist\n' "${name}"
        return 0
    fi

    local shell; shell=$(getent passwd "${user}" | cut -d: -f7)
    if [[ "${shell}" != "/usr/sbin/nologin" && "${shell}" != "/sbin/nologin" ]]; then
        printf '  [FAIL ] %s: shell is %s (expected /usr/sbin/nologin)\n' "${name}" "${shell}"
        violations=$(( violations + 1 ))
    else
        printf '  [ ok  ] %s: nologin shell\n' "${name}"
    fi

    # Locked password.
    local pwstatus; pwstatus=$(passwd -S "${user}" 2>/dev/null | awk '{print $2}')
    if [[ "${pwstatus}" != "L" && "${pwstatus}" != "LK" ]]; then
        printf '  [FAIL ] %s: password not locked (passwd -S: %s)\n' "${name}" "${pwstatus}"
        violations=$(( violations + 1 ))
    else
        printf '  [ ok  ] %s: password locked\n' "${name}"
    fi

    # Not in wheel / sudo.
    local groups
    groups=$(id -nG "${user}" 2>/dev/null || echo "")
    if echo " ${groups} " | grep -qE ' (wheel|sudo) '; then
        printf '  [FAIL ] %s: in privileged group (%s)\n' "${name}" "${groups}"
        violations=$(( violations + 1 ))
    else
        printf '  [ ok  ] %s: no privileged group membership\n' "${name}"
    fi

    # No platform-managed authorized_keys.
    local ak="${dir}/runtime/.ssh/authorized_keys"
    if [[ -f "${ak}" ]]; then
        printf '  [warn ] %s: %s exists (platform should not populate this; admin/operator may have)\n' "${name}" "${ak}"
    fi

    # Quadlet directory ownership: must be root, mode 0644 on files.
    local uid; uid=$(id -u "${user}")
    local q="${QUADLET_DIR}/${uid}"
    if [[ -d "${q}" ]]; then
        local owner
        owner=$(stat -c '%U' "${q}")
        if [[ "${owner}" != "root" ]]; then
            printf '  [FAIL ] %s: Quadlet dir %s owned by %s (expected root)\n' "${name}" "${q}" "${owner}"
            violations=$(( violations + 1 ))
        else
            printf '  [ ok  ] %s: Quadlet dir root-owned\n' "${name}"
        fi
        local f
        for f in "${q}"/*; do
            [[ -f "${f}" ]] || continue
            local fown
            fown=$(stat -c '%U' "${f}")
            if [[ "${fown}" != "root" ]]; then
                printf '  [FAIL ] %s: %s owned by %s (expected root)\n' "${name}" "${f}" "${fown}"
                violations=$(( violations + 1 ))
            fi
        done
    fi

    return $(( violations > 0 ))
}

cmd_tenant_verify_isolation() {
    require_root
    local a="${1:-}" b="${2:-}"
    local tenants
    if [[ -n "${a}" && -n "${b}" ]]; then
        tenants="${a} ${b}"
    elif [[ -z "${a}" && -z "${b}" ]]; then
        tenants=$(getent passwd | awk -F: '$1 ~ /^tenant_/ {sub("^tenant_","",$1); print $1}' | sort)
    else
        err "tenant verify-isolation: provide either no tenants (test all) or two tenant names"
        exit 1
    fi

    local count=0
    for _ in ${tenants}; do count=$(( count + 1 )); done
    if (( count < 1 )); then
        printf 'no tenants exist; nothing to verify\n'
        return 0
    fi

    local fail=0
    printf '== per-tenant invariants ==\n'
    local t
    for t in ${tenants}; do
        if ! verify_tenant_invariants "${t}"; then fail=1; fi
    done

    if (( count >= 2 )); then
        printf '== pairwise isolation ==\n'
        local arr=(${tenants})
        local i j
        for ((i=0; i<count; i++)); do
            for ((j=i+1; j<count; j++)); do
                if ! verify_pair_isolation "${arr[i]}" "${arr[j]}"; then fail=1; fi
            done
        done
    else
        printf '== pairwise isolation == (skipped, only one tenant)\n'
    fi

    if (( fail == 0 )); then
        printf '\nresult: PASS\n'
        return 0
    else
        printf '\nresult: FAIL\n'
        return 4
    fi
}

# ---- tunnel subcommands ----

# Read content from <path> if given, else stdin. Used by set-config / set-credentials.
read_content_arg_or_stdin() {
    local path="${1:-}"
    if [[ -n "${path}" ]]; then
        if [[ ! -f "${path}" ]]; then
            err "file not found: ${path}"
            return 2
        fi
        cat -- "${path}"
    else
        if [[ -t 0 ]]; then
            err "no input provided (pass a path or pipe via stdin)"
            return 1
        fi
        cat
    fi
}

cmd_tunnel_set_config() {
    require_root
    local name="${1:-}"; local path="${2:-}"
    if [[ -z "${name}" ]]; then err "tunnel set-config: missing <tenant>"; exit 1; fi
    local user; user=$(tenant_user "${name}")
    if ! getent passwd "${user}" >/dev/null; then
        err "tunnel set-config: tenant '${name}' does not exist"; exit 2
    fi
    local cfg="$(tenant_dir "${name}")/cloudflared/config.yml"
    if [[ -n "${DRY_RUN}" ]]; then
        printf 'DRY-RUN: write %s\n' "${cfg}"
        return 0
    fi
    local tmp; tmp=$(mktemp)
    trap 'rm -f "${tmp}"' RETURN
    if ! read_content_arg_or_stdin "${path}" > "${tmp}"; then exit 2; fi
    install -m 0640 -o root -g root "${tmp}" "${cfg}"
    log "wrote ${cfg}"
    log "restart the cloudflared sidecar: systemctl --user --machine=${user}@ restart ${name}-cloudflared.service"
}

cmd_tunnel_set_credentials() {
    require_root
    local name="${1:-}"; local path="${2:-}"
    if [[ -z "${name}" ]]; then err "tunnel set-credentials: missing <tenant>"; exit 1; fi
    if [[ -z "${path}" ]]; then err "tunnel set-credentials: missing <path> (a Cloudflare credentials JSON)"; exit 1; fi
    local user; user=$(tenant_user "${name}")
    if ! getent passwd "${user}" >/dev/null; then
        err "tunnel set-credentials: tenant '${name}' does not exist"; exit 2
    fi
    if [[ ! -f "${path}" ]]; then err "tunnel set-credentials: file not found: ${path}"; exit 2; fi
    # Cloudflare names credential files <tunnel-uuid>.json; preserve that.
    local base; base=$(basename "${path}")
    local dst="$(tenant_dir "${name}")/cloudflared/${base}"
    if [[ -n "${DRY_RUN}" ]]; then
        printf 'DRY-RUN: install -m 0600 -o root -g root %s %s\n' "${path}" "${dst}"
        return 0
    fi
    install -m 0600 -o root -g root "${path}" "${dst}"
    log "wrote ${dst}"
}

cmd_tunnel_show() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then err "tunnel show: missing <tenant>"; exit 1; fi
    local user; user=$(tenant_user "${name}")
    if ! getent passwd "${user}" >/dev/null; then
        err "tunnel show: tenant '${name}' does not exist"; exit 2
    fi
    local d="$(tenant_dir "${name}")/cloudflared"
    printf 'tenant:        %s\n' "${name}"
    printf 'cloudflared:   %s\n' "${d}"
    if [[ -d "${d}" ]]; then
        if [[ "$(ls -A "${d}" 2>/dev/null)" ]]; then
            ls -la "${d}" | sed 's/^/  /'
        else
            printf '  (empty)\n'
        fi
    else
        printf '  (missing)\n'
    fi
}

cmd_tunnel_list() {
    local users
    users=$(getent passwd | awk -F: '$1 ~ /^tenant_/ {print $1}')
    if [[ -z "${users}" ]]; then
        printf 'no tenants\n'
        return 0
    fi
    printf '%-20s %-12s %-12s\n' "TENANT" "CONFIG" "CREDENTIALS"
    local u name d cfg creds
    while read -r u; do
        name="${u#tenant_}"
        d="$(tenant_dir "${name}")/cloudflared"
        cfg=no; creds=no
        [[ -f "${d}/config.yml" ]] && cfg=yes
        [[ -f "${d}/token" ]] && cfg=token
        if compgen -G "${d}/*.json" > /dev/null 2>&1; then creds=yes; fi
        printf '%-20s %-12s %-12s\n' "${name}" "${cfg}" "${creds}"
    done <<<"${users}"
}

# ---- credential subcommands (Phase 2) ----

cmd_credential_add() {
    require_root
    local tenant="${1:-}" cred_id="${2:-}"
    if [[ -z "${tenant}" || -z "${cred_id}" ]]; then
        err "credential add: usage: credential add <tenant> <id>  (value read from stdin)"
        exit 1
    fi
    if ! getent passwd "$(tenant_user "${tenant}")" >/dev/null; then
        err "credential add: tenant '${tenant}' does not exist"; exit 2
    fi
    if [[ -t 0 ]]; then
        err "credential add: read value from stdin (e.g. cat secret | platformctl credential add ...)"
        exit 1
    fi
    local req
    req=$(mkreq_with_stdin_value credential_add value tenant="${tenant}" id="${cred_id}")
    broker_call "${req}"
}

cmd_credential_list() {
    local tenant="${1:-}"
    local req
    if [[ -n "${tenant}" ]]; then
        req=$(mkreq credential_list tenant="${tenant}")
    else
        req=$(mkreq credential_list)
    fi
    broker_call "${req}"
}

cmd_credential_delete() {
    require_root
    local tenant="${1:-}" cred_id="${2:-}"
    if [[ -z "${tenant}" || -z "${cred_id}" ]]; then
        err "credential delete: usage: credential delete <tenant> <id>"
        exit 1
    fi
    local req
    req=$(mkreq credential_delete tenant="${tenant}" id="${cred_id}")
    broker_call "${req}"
}

cmd_credential_rotate() {
    require_root
    local tenant="${1:-}" cred_id="${2:-}"
    if [[ -z "${tenant}" || -z "${cred_id}" ]]; then
        err "credential rotate: usage: credential rotate <tenant> <id>  (new value read from stdin)"
        exit 1
    fi
    if [[ -t 0 ]]; then
        err "credential rotate: read new value from stdin"
        exit 1
    fi
    local req
    req=$(mkreq_with_stdin_value credential_rotate value tenant="${tenant}" id="${cred_id}")
    broker_call "${req}"
}

dispatch_credential() {
    local sub="${1:-}"; shift || true
    case "${sub}" in
        add)               cmd_credential_add "$@" ;;
        list)              cmd_credential_list "$@" ;;
        delete)            cmd_credential_delete "$@" ;;
        rotate)            cmd_credential_rotate "$@" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown credential subcommand '${sub}'"; usage; exit 1 ;;
    esac
}

# ---- grant subcommands (Phase 2) ----

cmd_grant_add() {
    require_root
    local tenant="${1:-}" agent="${2:-}" cred_id="${3:-}" scope="${4:-read}"
    if [[ -z "${tenant}" || -z "${agent}" || -z "${cred_id}" ]]; then
        err "grant add: usage: grant add <tenant> <agent> <id> [<scope>]"
        exit 1
    fi
    local req
    req=$(mkreq grant_add tenant="${tenant}" agent="${agent}" id="${cred_id}" scope="${scope}")
    broker_call "${req}"
}

cmd_grant_remove() {
    require_root
    local tenant="${1:-}" agent="${2:-}" cred_id="${3:-}"
    if [[ -z "${tenant}" || -z "${agent}" || -z "${cred_id}" ]]; then
        err "grant remove: usage: grant remove <tenant> <agent> <id>"
        exit 1
    fi
    local req
    req=$(mkreq grant_remove tenant="${tenant}" agent="${agent}" id="${cred_id}")
    broker_call "${req}"
}

cmd_grant_list() {
    local tenant="${1:-}"
    local req
    if [[ -n "${tenant}" ]]; then
        req=$(mkreq grant_list tenant="${tenant}")
    else
        req=$(mkreq grant_list)
    fi
    broker_call "${req}"
}

dispatch_grant() {
    local sub="${1:-}"; shift || true
    case "${sub}" in
        add)               cmd_grant_add "$@" ;;
        remove)            cmd_grant_remove "$@" ;;
        list)              cmd_grant_list "$@" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown grant subcommand '${sub}'"; usage; exit 1 ;;
    esac
}

# ---- audit subcommand (Phase 2) ----

cmd_audit_tail() {
    local n="${1:-50}"
    if ! [[ "${n}" =~ ^[0-9]+$ ]]; then
        err "audit tail: argument must be a non-negative integer"
        exit 1
    fi
    local req
    req=$(mkreq audit_tail n="${n}")
    broker_call "${req}"
}

# ---- signal-link helper (Phase 4) ----
# Drives `signal-cli link` interactively, captures the resulting local-state
# directory, packs it as a base64-encoded tar.gz with the configured allow-list,
# and stores it as the tenant's signal/main credential in the broker.

cmd_signal_link() {
    require_root
    local tenant="${1:-}"
    if [[ -z "${tenant}" ]]; then
        err "signal-link: usage: signal-link <tenant>"
        exit 1
    fi
    if ! getent passwd "$(tenant_user "${tenant}")" >/dev/null; then
        err "signal-link: tenant '${tenant}' does not exist"; exit 2
    fi
    if ! command -v signal-cli >/dev/null 2>&1; then
        err "signal-link: signal-cli not installed on host"
        err "             ssh into a messaging-bridge-signal container or install signal-cli locally"
        exit 2
    fi

    local workdir; workdir=$(mktemp -d)
    trap 'rm -rf "${workdir}"' RETURN
    log "running signal-cli link; scan the URL below in the Signal app"
    printf 'When prompted, choose Settings -> Linked Devices -> Link New Device.\n'
    signal-cli --config "${workdir}" link -n "openclaw-${tenant}"

    local username
    username=$(ls "${workdir}/data" 2>/dev/null | head -1 || true)
    if [[ -z "${username}" ]]; then
        err "signal-link: no linked username found in ${workdir}/data"
        exit 3
    fi
    log "linked as ${username}"

    printf 'Enter comma-separated allow-listed sender numbers (e.g. +15551234567,+15557654321): '
    local allow
    read -r allow

    local archive_b64
    archive_b64=$(tar -C "${workdir}" -czf - . | base64 -w0)

    python3 - "${tenant}" "${username}" "${archive_b64}" "${allow}" <<'PY'
import json, os, socket, sys
tenant, username, archive_b64, allow = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
allow_senders = [a.strip() for a in allow.split(",") if a.strip()]
payload = {
    "username": username,
    "data_archive": archive_b64,
    "allow_senders": allow_senders,
}
sock = os.environ.get("OPENCLAW_BROKER_ADMIN_SOCK", "/run/openclaw-broker/admin.sock")
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(15)
s.connect(sock)
req = {"op": "credential_add", "tenant": tenant, "id": f"{tenant}/signal/main", "value": json.dumps(payload)}
s.sendall(json.dumps(req).encode("utf-8") + b"\n")
buf = b""
while b"\n" not in buf:
    chunk = s.recv(4096)
    if not chunk: break
    buf += chunk
print(buf.split(b"\n", 1)[0].decode("utf-8"))
PY
}

dispatch_audit() {
    local sub="${1:-}"; shift || true
    case "${sub}" in
        tail)              cmd_audit_tail "$@" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown audit subcommand '${sub}'"; usage; exit 1 ;;
    esac
}

# ---- agent subcommands (Phase 3) ----

cmd_agent_create() {
    require_root
    local tenant="${1:-}"; shift || true
    if [[ -z "${tenant}" ]]; then
        err "agent create: usage: agent create <tenant> --name <n> --runtime <img> --environment <img> [--credential <id> ...] [--storage <volume> ...] [--ingress <class> ...] [--messaging <transport> ...] [--is-main] [--network <profile>]"
        exit 1
    fi
    if ! getent passwd "$(tenant_user "${tenant}")" >/dev/null; then
        err "agent create: tenant '${tenant}' does not exist"; exit 2
    fi
    local req
    req=$(python3 - "${tenant}" "$@" <<'PY'
import json, sys
tenant = sys.argv[1]
out = {
    "op": "agent_create",
    "tenant": tenant,
    "credentials": [],
    "volumes": [],
    "ingress": [],
    "messaging": [],
}
i = 2
while i < len(sys.argv):
    flag = sys.argv[i]
    if flag in ("--name", "--runtime", "--environment", "--network"):
        if i + 1 >= len(sys.argv):
            sys.stderr.write(f"missing value for {flag}\n"); sys.exit(1)
        key = flag[2:]
        out[key] = sys.argv[i + 1]
        i += 2
    elif flag in ("--credential", "--storage", "--ingress", "--messaging"):
        if i + 1 >= len(sys.argv):
            sys.stderr.write(f"missing value for {flag}\n"); sys.exit(1)
        key = {
            "--credential": "credentials",
            "--storage": "volumes",
            "--ingress": "ingress",
            "--messaging": "messaging",
        }[flag]
        out[key].append(sys.argv[i + 1])
        i += 2
    elif flag == "--is-main":
        out["is_main"] = True
        i += 1
    else:
        sys.stderr.write(f"unknown arg {flag}\n"); sys.exit(1)
print(json.dumps(out))
PY
    ) || { err "agent create: invalid arguments"; exit 1; }
    provisioner_call "${req}"
}

cmd_agent_set_main() {
    require_root
    local tenant="${1:-}" name="${2:-}"
    if [[ -z "${tenant}" || -z "${name}" ]]; then
        err "agent set-main: usage: agent set-main <tenant> <name>"
        exit 1
    fi
    local req; req=$(mkreq agent_set_main tenant="${tenant}" name="${name}")
    provisioner_call "${req}"
}

cmd_agent_list() {
    local tenant="${1:-}"
    if [[ -z "${tenant}" ]]; then err "agent list: usage: agent list <tenant>"; exit 1; fi
    local req; req=$(mkreq agent_list tenant="${tenant}")
    provisioner_call "${req}"
}

cmd_agent_inspect() {
    local tenant="${1:-}" name="${2:-}"
    if [[ -z "${tenant}" || -z "${name}" ]]; then err "agent inspect: usage: agent inspect <tenant> <name>"; exit 1; fi
    local req; req=$(mkreq agent_inspect tenant="${tenant}" name="${name}")
    provisioner_call "${req}"
}

cmd_agent_stop() {
    require_root
    local tenant="${1:-}" name="${2:-}"
    if [[ -z "${tenant}" || -z "${name}" ]]; then err "agent stop: usage: agent stop <tenant> <name>"; exit 1; fi
    local req; req=$(mkreq agent_stop tenant="${tenant}" name="${name}")
    provisioner_call "${req}"
}

cmd_agent_start() {
    require_root
    local tenant="${1:-}" name="${2:-}"
    if [[ -z "${tenant}" || -z "${name}" ]]; then err "agent start: usage: agent start <tenant> <name>"; exit 1; fi
    local req; req=$(mkreq agent_start tenant="${tenant}" name="${name}")
    provisioner_call "${req}"
}

cmd_agent_delete() {
    require_root
    local tenant="${1:-}" name="${2:-}"
    if [[ -z "${tenant}" || -z "${name}" ]]; then err "agent delete: usage: agent delete <tenant> <name>"; exit 1; fi
    local req; req=$(mkreq agent_delete tenant="${tenant}" name="${name}")
    provisioner_call "${req}"
}

dispatch_agent() {
    local sub="${1:-}"; shift || true
    case "${sub}" in
        create)            cmd_agent_create   "$@" ;;
        list)              cmd_agent_list     "$@" ;;
        inspect)           cmd_agent_inspect  "$@" ;;
        stop)              cmd_agent_stop     "$@" ;;
        start)             cmd_agent_start    "$@" ;;
        delete)            cmd_agent_delete   "$@" ;;
        set-main)          cmd_agent_set_main "$@" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown agent subcommand '${sub}'"; usage; exit 1 ;;
    esac
}

# ---- policy subcommands (Phase 3) ----

cmd_policy_show() {
    local tenant="${1:-}"
    if [[ -z "${tenant}" ]]; then err "policy show: usage: policy show <tenant>"; exit 1; fi
    local req; req=$(mkreq policy_show tenant="${tenant}")
    provisioner_call "${req}"
}

dispatch_policy() {
    local sub="${1:-}"; shift || true
    case "${sub}" in
        show)              cmd_policy_show "$@" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown policy subcommand '${sub}'"; usage; exit 1 ;;
    esac
}

dispatch_tenant() {
    local sub="${1:-}"; shift || true
    case "${sub}" in
        create)            require_root; cmd_tenant_create  "$@" ;;
        list)              cmd_tenant_list ;;
        inspect)           cmd_tenant_inspect "$@" ;;
        disable)           require_root; cmd_tenant_disable "$@" ;;
        enable)            require_root; cmd_tenant_enable  "$@" ;;
        delete)            require_root; cmd_tenant_delete  "$@" ;;
        verify-isolation)  cmd_tenant_verify_isolation "$@" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown tenant subcommand '${sub}'"; usage; exit 1 ;;
    esac
}

dispatch_tunnel() {
    local sub="${1:-}"; shift || true
    case "${sub}" in
        set-config)      cmd_tunnel_set_config "$@" ;;
        set-credentials) cmd_tunnel_set_credentials "$@" ;;
        show)            cmd_tunnel_show "$@" ;;
        list)            cmd_tunnel_list ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown tunnel subcommand '${sub}'"; usage; exit 1 ;;
    esac
}

main() {
    local cmd="${1:-}"; shift || true
    case "${cmd}" in
        tenant)     dispatch_tenant "$@" ;;
        tunnel)     dispatch_tunnel "$@" ;;
        credential) dispatch_credential "$@" ;;
        grant)      dispatch_grant "$@" ;;
        audit)      dispatch_audit "$@" ;;
        agent)      dispatch_agent "$@" ;;
        policy)     dispatch_policy "$@" ;;
        signal-link) cmd_signal_link "$@" ;;
        backup)     cmd_planned "backup $*" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown command '${cmd}'"; usage; exit 1 ;;
    esac
}

main "$@"
