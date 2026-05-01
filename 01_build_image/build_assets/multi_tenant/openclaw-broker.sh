#!/usr/bin/env bash
# openclaw-broker (stub) - placeholder for the host credential broker.
# The real broker is Phase 2 of the multi-tenant build; see
# docs/concepts/credential_broker.md.
#
# This stub:
#   - ensures /var/lib/openclaw-platform/broker exists
#   - writes a state marker recording that the broker has run
#   - exits 0
#
# It exists today purely so the systemd dependency graph and the broker state
# directory are in place. It does NOT issue credentials or grants.

set -euo pipefail

BROKER_DIR="${OPENCLAW_PLATFORM_ROOT:-/var/lib/openclaw-platform}/broker"

install -d -m 0750 "${BROKER_DIR}"

cat > "${BROKER_DIR}/STATE" <<EOF
state=stub
phase=0
note=The credential broker is a stub. See docs/concepts/credential_broker.md.
last_run=$(date --iso-8601=seconds)
EOF
chmod 0640 "${BROKER_DIR}/STATE"

echo "openclaw-broker (stub): state recorded at ${BROKER_DIR}/STATE"
