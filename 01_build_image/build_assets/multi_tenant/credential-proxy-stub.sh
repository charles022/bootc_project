#!/usr/bin/env bash
# Credential proxy stub. Identifies itself and idles. Phase-0 placeholder.
set -euo pipefail
echo "credential-proxy (stub) starting at $(date --iso-8601=seconds)"
echo "tenant=${OPENCLAW_TENANT:-unset}"
echo "this is a Phase-0 stub. real proxy is Phase 2."
exec tail -f /dev/null
