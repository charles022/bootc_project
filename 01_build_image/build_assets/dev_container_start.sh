#!/usr/bin/env bash

set -euo pipefail

echo "=== dev_container_start.sh starting ==="

python3 /usr/local/share/dev-container/dev_container_test.py

if [[ "${DEV_ONCE:-0}" == "1" ]]; then
  exit 0
fi

echo "=== dev container startup complete; staying alive ==="
tail -f /dev/null
