#!/usr/bin/env bash

set -euo pipefail

echo "=== bootc_host_test.sh starting ==="

date --iso-8601=seconds

systemctl is-enabled --quiet sshd
systemctl is-active --quiet sshd

systemctl is-enabled --quiet nvidia-cdi-refresh.path
systemctl is-enabled --quiet nvidia-cdi-refresh.service

test -s /var/run/cdi/nvidia.yaml
nvidia-smi

systemctl is-active --quiet devpod.service
podman pod exists devpod

echo "=== bootc_host_test.sh completed ==="
