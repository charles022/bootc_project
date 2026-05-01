#!/usr/bin/env bash
# Onboarding env stub. Identifies itself and idles. Phase-0 placeholder.
# sshd is installed but not started by default; the real onboarding flow
# (planned) will start sshd on a pod-local interface and run the onboard CLI.
set -euo pipefail
echo "onboarding-env (stub) starting at $(date --iso-8601=seconds)"
echo "tenant=${OPENCLAW_TENANT:-unset}"
echo "user=$(id -un) uid=$(id -u)"
echo "this is a Phase-0 stub. real onboarding flow is Phase 2."
exec tail -f /dev/null
