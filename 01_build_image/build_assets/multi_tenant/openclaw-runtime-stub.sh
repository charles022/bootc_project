#!/usr/bin/env bash
# OpenClaw runtime stub. Identifies itself and idles. Phase-0 placeholder.
set -euo pipefail
echo "openclaw-runtime (stub) starting at $(date --iso-8601=seconds)"
echo "tenant=${OPENCLAW_TENANT:-unset}"
echo "user=$(id -un) uid=$(id -u)"
echo "this is a Phase-0 stub. real runtime is Phase 3."
exec tail -f /dev/null
