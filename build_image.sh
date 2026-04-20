#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

ASSETS_DIR="01_build_image/build_assets"
MODE="${1:-all}"

IMAGE_REGISTRY="${IMAGE_REGISTRY:-localhost}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-bootc-dev}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

DEV_IMAGE="${DEV_IMAGE:-$IMAGE_REGISTRY/$IMAGE_NAMESPACE/dev-container:$IMAGE_TAG}"
BACKUP_IMAGE="${BACKUP_IMAGE:-$IMAGE_REGISTRY/$IMAGE_NAMESPACE/backup-container:$IMAGE_TAG}"
if [[ -z "${BOOTC_IMAGE:-}" ]]; then
  if [[ "$IMAGE_REGISTRY" == "localhost" ]]; then
    BOOTC_IMAGE="localhost/gpu-bootc-host:$IMAGE_TAG"
  else
    BOOTC_IMAGE="$IMAGE_REGISTRY/$IMAGE_NAMESPACE/gpu-bootc-host:$IMAGE_TAG"
  fi
fi

REQUIRE_CUDA="${REQUIRE_CUDA:-1}"
ALLOW_NO_SSH_KEY="${ALLOW_NO_SSH_KEY:-0}"
PODMAN_GPU_ARGS="${PODMAN_GPU_ARGS:-}"
if [[ "$REQUIRE_CUDA" != "0" && -z "$PODMAN_GPU_ARGS" ]]; then
  PODMAN_GPU_ARGS="--device nvidia.com/gpu=all"
fi

if [[ -z "${SSH_AUTHORIZED_KEY:-}" ]]; then
  for key in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    if [[ -r "$key" ]]; then
      SSH_AUTHORIZED_KEY="$(<"$key")"
      break
    fi
  done
fi

require_ssh_key() {
  if [[ -n "${SSH_AUTHORIZED_KEY:-}" ]]; then
    return
  fi

  if [[ "$ALLOW_NO_SSH_KEY" == "1" ]]; then
    echo "warning: building host image without an SSH authorized key" >&2
    return
  fi

  cat >&2 <<'EOF'
error: no SSH authorized key available for devuser

Set SSH_AUTHORIZED_KEY, add ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub, or
set ALLOW_NO_SSH_KEY=1 if an intentionally unreachable VM image is acceptable.
EOF
  exit 1
}

build_containers() {
  podman build -t "$DEV_IMAGE" -f "$ASSETS_DIR/dev-container.Containerfile" "$ASSETS_DIR"
  podman build -t "$BACKUP_IMAGE" -f "$ASSETS_DIR/backup-container.Containerfile" "$ASSETS_DIR"
}

build_host() {
  require_ssh_key

  podman build \
    --build-arg "DEV_IMAGE=$DEV_IMAGE" \
    --build-arg "BACKUP_IMAGE=$BACKUP_IMAGE" \
    --build-arg "SSH_AUTHORIZED_KEY=${SSH_AUTHORIZED_KEY:-}" \
    -t "$BOOTC_IMAGE" \
    -f "$ASSETS_DIR/Containerfile" \
    "$ASSETS_DIR"
}

test_containers() {
  podman run --rm -e BACKUP_ONCE=1 "$BACKUP_IMAGE"
  # shellcheck disable=SC2086
  podman run --rm $PODMAN_GPU_ARGS -e DEV_ONCE=1 -e "REQUIRE_CUDA=$REQUIRE_CUDA" "$DEV_IMAGE"
}

push_images() {
  podman push "$DEV_IMAGE"
  podman push "$BACKUP_IMAGE"
  podman push "$BOOTC_IMAGE"
}

case "$MODE" in
  containers) build_containers ;;
  host) build_host ;;
  test-containers) test_containers ;;
  push) push_images ;;
  all) build_containers; build_host ;;
  *)
    echo "usage: $0 [containers|host|test-containers|push|all]" >&2
    exit 2
    ;;
esac

echo "dev image:    $DEV_IMAGE"
echo "backup image: $BACKUP_IMAGE"
echo "bootc image:  $BOOTC_IMAGE"
