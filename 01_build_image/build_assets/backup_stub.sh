#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines. # strict bash mode
set -euo pipefail # strict execution

# Emit a clear start marker for the backup sidecar logs. # backup banner
echo "=== backup_stub.sh starting ===" # start marker

# Explain that this sidecar is only a placeholder for pod validation. # placeholder note
echo "backup sidecar placeholder: no real backup logic implemented yet" # placeholder message

# Keep the sidecar alive so the pod can be inspected. # persistent foreground loop
tail -f /dev/null # keep sidecar running
