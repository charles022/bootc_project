#!/usr/bin/env bash
# Builder entrypoint. Runs inside an ephemeral os-builder container.
# Clones the project repo into a RAM-backed work dir, rebuilds the
# bootc host image and its sibling containers, and writes the host
# image as an oci-archive into $OUTPUT_DIR for the host to pick up.
#
# Inputs:  $SOURCE_REPO, $SOURCE_BRANCH, $OUTPUT_DIR, $SAVE_ALL
# Outputs: $OUTPUT_DIR/host.tar (always)
#          $OUTPUT_DIR/{dev,backup,os-builder}.tar  (if SAVE_ALL=1)
#
# Exit non-zero on any failure so the host orchestrator skips the
# bootc switch step and leaves the live deployment untouched.
set -euo pipefail

: "${SOURCE_REPO:?SOURCE_REPO must be set}"
: "${SOURCE_BRANCH:=main}"
: "${OUTPUT_DIR:=/output}"
: "${SAVE_ALL:=0}"

WORK_DIR=/work
ASSETS_REL="01_build_image/build_assets"

echo "[os-builder] cloning ${SOURCE_REPO}#${SOURCE_BRANCH} into ${WORK_DIR}"
mkdir -p "${WORK_DIR}"
git clone --depth 1 --branch "${SOURCE_BRANCH}" "${SOURCE_REPO}" "${WORK_DIR}"

cd "${WORK_DIR}"
ASSETS="${WORK_DIR}/${ASSETS_REL}"

build_one() {
    local tag="$1" containerfile="$2"
    echo "[os-builder] building ${tag} from ${containerfile}"
    podman build --no-cache --pull \
        -t "${tag}" \
        -f "${ASSETS}/${containerfile}" \
        "${ASSETS}"
}

build_one temp-dev        dev-container.Containerfile
build_one temp-backup     backup-container.Containerfile
build_one temp-os-builder os-builder.Containerfile
build_one temp-host       Containerfile

mkdir -p "${OUTPUT_DIR}"

echo "[os-builder] saving temp-host -> ${OUTPUT_DIR}/host.tar"
podman save --format oci-archive -o "${OUTPUT_DIR}/host.tar" temp-host

if [[ "${SAVE_ALL}" == "1" ]]; then
    echo "[os-builder] SAVE_ALL=1: also saving sibling images"
    podman save --format oci-archive -o "${OUTPUT_DIR}/dev.tar"        temp-dev
    podman save --format oci-archive -o "${OUTPUT_DIR}/backup.tar"     temp-backup
    podman save --format oci-archive -o "${OUTPUT_DIR}/os-builder.tar" temp-os-builder
fi

echo "[os-builder] done"
