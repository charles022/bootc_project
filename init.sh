cd /home/chuck/code/bootc_project/02_build_vm
SSH_PUB_KEY_FILE="$HOME/.ssh/id_ed25519_7510.pub" ./build_vm.sh
SSH_PUB_KEY_FILE="$HOME/.ssh/id_ed25519_7510.pub" ./run_vm.sh

# After that, the intended smoke checks are:

ssh fedora-init 'systemctl is-active sshd cloud-init.target nvidia-cdi-refresh.service; bootc status'
ssh fedora-init 'bash /usr/local/bin/bootc_host_test.sh'

