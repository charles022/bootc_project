#!/usr/bin/env bash
# Host-side orchestrator for the scheduled bootc update.
# Runs the os-builder container, hands off the resulting OCI archive
# to OSTree via `bootc switch --transport oci-archive`, and writes a
# pending marker the login nudge picks up.
set -euo pipefail

SOURCE_ENV=/etc/bootc-update/source.env
PENDING_MARKER=/var/lib/bootc-update/pending
OUTPUT_DIR=/run/bootc-update
ARCHIVE="${OUTPUT_DIR}/host.tar"
BUILDER_IMAGE="${BUILDER_IMAGE:-quay.io/m0ranmcharles/fedora_init:os-builder}"

if [[ -f "${SOURCE_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${SOURCE_ENV}"
fi

: "${SOURCE_REPO:?SOURCE_REPO must be set in ${SOURCE_ENV}}"
: "${SOURCE_BRANCH:=main}"

mkdir -p "$(dirname "${PENDING_MARKER}")"

echo "[bootc-update] launching builder ${BUILDER_IMAGE}"
podman run --rm --privileged --pull=missing \
    -e SOURCE_REPO="${SOURCE_REPO}" \
    -e SOURCE_BRANCH="${SOURCE_BRANCH}" \
    -e OUTPUT_DIR=/output \
    -v "${OUTPUT_DIR}:/output:Z" \
    "${BUILDER_IMAGE}"

if [[ ! -s "${ARCHIVE}" ]]; then
    echo "[bootc-update] builder produced no archive at ${ARCHIVE}; aborting" >&2
    exit 1
fi

echo "[bootc-update] staging ${ARCHIVE} via bootc switch"
bootc switch --transport oci-archive "${ARCHIVE}"

echo "[bootc-update] writing pending marker ${PENDING_MARKER}"
date --iso-8601=seconds > "${PENDING_MARKER}"

echo "[bootc-update] success"
