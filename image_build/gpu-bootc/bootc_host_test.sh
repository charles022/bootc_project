#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines. # strict bash mode
set -euo pipefail # strict execution

# Emit a clear start marker in the journal. # host test banner
echo "=== bootc_host_test.sh starting ===" # start marker

# Print a timestamp for visibility. # timestamp output
date --iso-8601=seconds # current time

# Confirm host SSH service state. # sshd state check
systemctl is-enabled sshd || true # print enabled state
systemctl is-active sshd || true # print active state

# Confirm NVIDIA CDI refresh unit state. # cdi service state check
systemctl is-enabled nvidia-cdi-refresh.path || true # print path unit enabled state
systemctl is-enabled nvidia-cdi-refresh.service || true # print service unit enabled state

# Confirm whether the runtime CDI file exists. # cdi file presence check
if [[ -f /var/run/cdi/nvidia.yaml ]]; then echo "CDI spec present: /var/run/cdi/nvidia.yaml"; else echo "CDI spec not present yet"; fi # presence message

# Run a host GPU smoke check if nvidia-smi exists. # host gpu smoke test
if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi || true; else echo "nvidia-smi not installed on host"; fi # optional gpu check

# Confirm that the pod service is known to systemd. # pod service visibility check
systemctl status devpod.service --no-pager || true # generated Quadlet service status

# Emit a clear completion marker. # host test footer
echo "=== bootc_host_test.sh completed ===" # completion marker
