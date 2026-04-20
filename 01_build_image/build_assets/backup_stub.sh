#!/usr/bin/env bash

set -euo pipefail

echo "=== backup_stub.sh starting ==="

echo "backup sidecar placeholder: no real backup logic implemented yet"

if [[ "${BACKUP_ONCE:-0}" == "1" ]]; then
  exit 0
fi

tail -f /dev/null
