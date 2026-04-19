#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines. # strict bash mode
set -euo pipefail # strict execution

# Emit a clear start marker for container logs. # dev startup banner
echo "=== dev_container_start.sh starting ===" # start marker

# Run the dev container startup test. # execute startup test
python3 /workspace/dev_container_test.py # run dev startup test

# Emit a message indicating the container will remain alive. # keepalive message
echo "=== dev container startup complete; staying alive ===" # keepalive marker

# Keep the container alive so we can enter it later with podman exec. # persistent foreground loop
tail -f /dev/null # keep container running
