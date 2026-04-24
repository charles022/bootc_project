# Sourced by build_vm.sh and run_vm.sh.
# Sets SSH_PUB_KEY_FILE to the first existing candidate, or exits nonzero.

SSH_PUB_KEY_FILE="${SSH_PUB_KEY_FILE:-}"
if [ -z "${SSH_PUB_KEY_FILE}" ]; then
  for candidate in "${HOME}/.ssh/id_ed25519.pub" "${HOME}/.ssh/id_rsa.pub"; do
    if [ -f "${candidate}" ]; then
      SSH_PUB_KEY_FILE="${candidate}"
      break
    fi
  done
fi

if [ -z "${SSH_PUB_KEY_FILE}" ] || [ ! -f "${SSH_PUB_KEY_FILE}" ]; then
  echo "ERROR: No SSH public key found." >&2
  echo "       Tried ~/.ssh/id_ed25519.pub and ~/.ssh/id_rsa.pub." >&2
  echo "       Generate one with: ssh-keygen -t ed25519" >&2
  echo "       Or set SSH_PUB_KEY_FILE=/path/to/key.pub and re-run." >&2
  exit 1
fi
