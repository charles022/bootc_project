#!/usr/bin/env bash
# First-boot push of a freshly-deployed bootc image.
# Reads /etc/bootc-update/reboot.env. If push_to_quay=TRUE, extracts
# the booted image from container storage and pushes it to Quay, then
# clears the flag. Always clears the pending marker on exit so the
# login nudge stops appearing.
#
# Exits 0 even on push failure so a missing podman login or transient
# network issue does not break boot. Push errors are logged at warning
# level; operator can re-publish manually via push_images.sh.
set -uo pipefail

REBOOT_ENV=/etc/bootc-update/reboot.env
PENDING_MARKER=/var/lib/bootc-update/pending
REMOTE=quay.io/m0ranmcharles/fedora_init:latest

cleanup_marker() {
    rm -f "${PENDING_MARKER}"
}

trap cleanup_marker EXIT

push_to_quay=FALSE
if [[ -f "${REBOOT_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${REBOOT_ENV}"
fi

if [[ "${push_to_quay:-FALSE}" != "TRUE" ]]; then
    echo "[bootc-firstboot-push] push_to_quay!=TRUE, no-op"
    exit 0
fi

echo "[bootc-firstboot-push] push_to_quay=TRUE, attempting push to ${REMOTE}"

# bootc stores the booted image under containers-storage; copy it out
# under the public tag, then push. skopeo handles the storage<->registry
# bridge without re-extracting the rootfs.
if ! skopeo copy \
        "containers-storage:${REMOTE}" \
        "docker://${REMOTE}" \
        --format v2s2; then
    echo "[bootc-firstboot-push] WARNING: push failed (no podman login? no network?); leaving flag set" >&2
    exit 0
fi

echo "[bootc-firstboot-push] push succeeded; clearing push_to_quay flag"
cat > "${REBOOT_ENV}" <<'EOF'
# Set push_to_quay=TRUE before rebooting into a freshly-staged image
# to publish it to Quay on its first successful boot. The push runs
# once and the flag is cleared back to FALSE automatically.
push_to_quay=FALSE
EOF
