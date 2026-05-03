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
if [[ -f /etc/cdi/nvidia.yaml ]]; then echo "CDI spec present: /etc/cdi/nvidia.yaml"; else echo "CDI spec not present yet"; fi # presence message

# Run a host GPU smoke check if nvidia-smi exists. # host gpu smoke test
if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi || true; else echo "nvidia-smi not installed on host"; fi # optional gpu check

# Confirm that the pod service is known to systemd. # pod service visibility check
systemctl status devpod.service --no-pager || true # generated Quadlet service status

# Multi-tenant layer smoke checks. # mta smoke checks
command -v platformctl >/dev/null 2>&1 && echo "platformctl present: $(command -v platformctl)" || echo "platformctl missing" # platformctl presence
command -v openclaw-broker >/dev/null 2>&1 && echo "openclaw-broker present: $(command -v openclaw-broker)" || echo "openclaw-broker missing" # broker presence
systemctl is-enabled openclaw-broker.service || true # broker enabled state
systemctl is-active openclaw-broker.service || true # broker active state
[[ -d /var/lib/openclaw-platform/templates/quadlet ]] && echo "tenant Quadlet templates present" || echo "tenant Quadlet templates missing" # template dir presence
ls /var/lib/openclaw-platform/templates/quadlet 2>/dev/null || true # list templates
[[ -S /run/openclaw-broker/admin.sock ]] && echo "broker admin socket present" || echo "broker admin socket missing" # broker admin socket presence
python3 -c "import cryptography; print('python3-cryptography:', cryptography.__version__)" 2>/dev/null || echo "python3-cryptography missing" # crypto lib presence
command -v openclaw-provisioner >/dev/null 2>&1 && echo "openclaw-provisioner present: $(command -v openclaw-provisioner)" || echo "openclaw-provisioner missing" # provisioner presence
systemctl is-enabled openclaw-provisioner.service || true # provisioner enabled state
systemctl is-active openclaw-provisioner.service || true # provisioner active state
[[ -S /run/openclaw-provisioner/admin.sock ]] && echo "provisioner admin socket present" || echo "provisioner admin socket missing" # provisioner admin socket presence
[[ -d /var/lib/openclaw-platform/templates/agent_quadlet ]] && echo "agent Quadlet templates present" || echo "agent Quadlet templates missing" # agent template dir presence

# Emit a clear completion marker. # host test footer
echo "=== bootc_host_test.sh completed ===" # completion marker
