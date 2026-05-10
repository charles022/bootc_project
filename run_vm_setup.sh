#!/usr/bin/env bash

set -euo pipefail

echo "=== 1. Starting libvirt service ==="
sudo systemctl enable --now libvirtd

echo "=== 2. Adding user to libvirt group ==="
sudo usermod -aG libvirt "$USER"

echo "=== 3. Building the VM ==="
# Exporting the existing key so the scripts don't fail trying to find the default ones
export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_ed25519_7510.pub"
./02_build_vm/build_vm.sh

echo "=== 4. Running the VM ==="
export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_ed25519_7510.pub"
./02_build_vm/run_vm.sh

echo ""
echo "=== Setup Script Complete ==="
echo "Please reply to the assistant to let them know it has finished."
