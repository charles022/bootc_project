#!/usr/bin/env bash

# Exit on errors, unset vars, and failed pipelines.
set -euo pipefail

cd "$(dirname "$0")"

VM_NAME="${VM_NAME:-gpu-bootc-test}"
SSH_CONFIG="${HOME}/.ssh/config"

. "$(dirname "$0")/_detect_ssh_key.sh"
SSH_KEY_FILE="${SSH_PUB_KEY_FILE%.pub}"

DISK_DEST="/var/lib/libvirt/images/${VM_NAME}.qcow2"
if [ ! -f "${DISK_DEST}" ]; then
  echo "ERROR: Disk not found at ${DISK_DEST}" >&2
  echo "       Run ./build_vm.sh first." >&2
  exit 1
fi

# --- Tear down any existing VM of the same name ---
echo "=== Removing any existing '${VM_NAME}' VM ==="
sudo virsh destroy  "${VM_NAME}" 2>/dev/null || true
sudo virsh undefine "${VM_NAME}" --nvram 2>/dev/null || true

echo "=== Starting VM ==="

# --noautoconsole lets virt-install exit immediately after the domain starts
# so this script can continue to detect the IP and configure SSH.
# Attach manually any time with: sudo virsh console gpu-bootc-test
sudo virt-install \
  --name "${VM_NAME}" \
  --memory 16384 \
  --vcpus 8 \
  --disk path="${DISK_DEST}",format=qcow2,bus=virtio \
  --import \
  --os-variant fedora-unknown \
  --network network=default \
  --graphics none \
  --noautoconsole \
  --boot uefi

# --- Detect IP and wire up SSH alias ---
echo ""
echo "=== Detecting VM IP address ==="
VM_IP=""
for i in $(seq 1 30); do
  VM_IP=$(sudo virsh domifaddr "${VM_NAME}" 2>/dev/null \
    | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1)
  [ -n "${VM_IP}" ] && break
  echo "    waiting... (${i}/30)"
  sleep 2
done

if [ -z "${VM_IP}" ]; then
  echo ""
  echo "=== Could not detect VM IP automatically. ==="
  echo "    Run:  sudo virsh domifaddr ${VM_NAME}"
  echo "    Then: ssh root@<ip>"
  exit 0
fi

# Write/update a 'fedora-init' Host block in ~/.ssh/config so the user
# can connect with just 'ssh fedora-init' from any terminal. The block is
# replaced on every run so the IP stays current after rebuilds.
# StrictHostKeyChecking is disabled for this alias because the VM's host
# key changes on every rebuild.
touch "${SSH_CONFIG}"
chmod 600 "${SSH_CONFIG}"
sed -i '/^# BEGIN fedora-init$/,/^# END fedora-init$/d' "${SSH_CONFIG}"
cat >> "${SSH_CONFIG}" <<EOF

# BEGIN fedora-init
Host fedora-init
    HostName ${VM_IP}
    User root
    IdentityFile ${SSH_KEY_FILE}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
# END fedora-init
EOF

echo ""
echo "=== Access ==="
echo "    ssh fedora-init"
echo ""
echo "    (${VM_IP} | key: ${SSH_KEY_FILE})"
echo ""
echo "    To see the boot console:  sudo virsh console ${VM_NAME}"
echo "    To detach from console:   Ctrl+]"
