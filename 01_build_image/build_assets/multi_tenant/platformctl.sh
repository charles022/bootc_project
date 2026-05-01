#!/usr/bin/env bash
# platformctl - admin CLI for the OpenClaw multi-tenant layer.
# Concept: docs/concepts/multi_tenant_architecture.md
# Reference: docs/reference/platformctl.md

set -euo pipefail

PLATFORM_ROOT="${OPENCLAW_PLATFORM_ROOT:-/var/lib/openclaw-platform}"
QUADLET_DIR="${OPENCLAW_QUADLET_DIR:-/etc/containers/systemd/users}"
TEMPLATE_DIR="${OPENCLAW_TEMPLATE_DIR:-${PLATFORM_ROOT}/templates/quadlet}"
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

usage() {
    cat <<'EOF'
Usage:
  platformctl tenant create <name>
  platformctl tenant list
  platformctl tenant disable <name>
  platformctl tenant enable  <name>
  platformctl tenant delete  <name>

  platformctl agent      list   <tenant>           (planned)
  platformctl agent      create <tenant> ...       (planned)
  platformctl credential list   <tenant>           (planned)
  platformctl credential rotate <tenant> <id>      (planned)
  platformctl tunnel     list   <tenant>           (planned)
  platformctl backup     run    <tenant>           (planned)
  platformctl backup     restore <tenant> --snapshot <id>  (planned)

Environment:
  OPENCLAW_PLATFORM_ROOT  default: /var/lib/openclaw-platform
  OPENCLAW_QUADLET_DIR    default: /etc/containers/systemd/users
  OPENCLAW_TEMPLATE_DIR   default: ${OPENCLAW_PLATFORM_ROOT}/templates/quadlet
  OPENCLAW_DRY_RUN        if set, print actions without executing
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

    # Verify subuid/subgid allocation; fall back to explicit assignment if absent.
    if ! grep -q "^${user}:" /etc/subuid 2>/dev/null; then
        log "subuid not auto-allocated, requesting explicit range"
        run usermod --add-subuids 100000-165535 "${user}" || true
    fi
    if ! grep -q "^${user}:" /etc/subgid 2>/dev/null; then
        log "subgid not auto-allocated, requesting explicit range"
        run usermod --add-subgids 100000-165535 "${user}" || true
    fi

    # Set ownership on tenant-writable dirs.
    run chown "${user}:${user}" "$(tenant_dir "${name}")/runtime"
    run chown "${user}:${user}" "$(tenant_dir "${name}")/volumes"

    # Render a placeholder policy file (real policy engine is planned).
    if [[ -z "${DRY_RUN}" ]]; then
        cat > "$(tenant_dir "${name}")/policy/policy.yaml" <<EOF
# Placeholder tenant policy for ${name}. The policy engine itself is planned;
# see docs/concepts/agent_provisioning.md for the schema this will follow.
tenant: ${name}
service_user: ${user}
status: active
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

    log "removing rendered Quadlets"
    run rm -rf "${QUADLET_DIR}/${tenant_uid}"

    log "removing user account"
    run userdel "${user}" || true

    log "removing tenant data dir"
    run rm -rf "$(tenant_dir "${name}")"

    run systemctl daemon-reload
    log "tenant '${name}' deleted"
}

dispatch_tenant() {
    local sub="${1:-}"; shift || true
    case "${sub}" in
        create)  require_root; cmd_tenant_create  "$@" ;;
        list)    cmd_tenant_list ;;
        disable) require_root; cmd_tenant_disable "$@" ;;
        enable)  require_root; cmd_tenant_enable  "$@" ;;
        delete)  require_root; cmd_tenant_delete  "$@" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown tenant subcommand '${sub}'"; usage; exit 1 ;;
    esac
}

main() {
    local cmd="${1:-}"; shift || true
    case "${cmd}" in
        tenant)     dispatch_tenant "$@" ;;
        agent)      cmd_planned "agent $*" ;;
        credential) cmd_planned "credential $*" ;;
        tunnel)     cmd_planned "tunnel $*" ;;
        backup)     cmd_planned "backup $*" ;;
        ""|-h|--help|help) usage ;;
        *) err "unknown command '${cmd}'"; usage; exit 1 ;;
    esac
}

main "$@"
