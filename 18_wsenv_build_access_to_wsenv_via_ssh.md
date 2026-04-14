# 18. ws-env: build access to ws-env via ssh

This document outlines the strategy and implementation for providing SSH access to the `ws-env` workstation container running on a Fedora `bootc` host. This approach ensures that the development environment is isolated from the host OS while remaining easily accessible for remote development (e.g., via VS Code Remote SSH) or terminal-based workflows.

## Strategy Overview

Following the core philosophy of this project:
1.  **Image Definition**: The `ws-env` image is defined via a `Containerfile`, including the OpenSSH server and necessary development tools.
2.  **Service Orchestration**: A Podman Quadlet (`.container` file) manages the lifecycle of the workstation container, mapping a host port to the container's SSH port.
3.  **Bootc Integration**: The Quadlet file is baked into the host's `bootc` image, ensuring the workstation environment is automatically started and managed by `systemd` upon host boot.

---

## 1. The Workstation Image (`ws-env/Containerfile`)

This image defines the environment where daily work occurs. We include `openssh-server` and configure it for secure key-based access.

```dockerfile
# File: ws-env/Containerfile
FROM fedora:40

# Install SSH server, sudo, and common dev tools
RUN dnf install -y \
    openssh-server \
    openssh-clients \
    sudo \
    git \
    vim \
    bash-completion \
    && dnf clean all

# Create the workstation user (matching host UID/GID is recommended for volume permissions)
ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME

# Setup SSH Directory
RUN mkdir -p /home/$USERNAME/.ssh && chmod 700 /home/$USERNAME/.ssh \
    && chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

# Generate host keys and configure SSH
RUN ssh-keygen -A
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Expose port 22
EXPOSE 22

# Start SSHD in the foreground
CMD ["/usr/sbin/sshd", "-D", "-e"]
```

---

## 2. The Quadlet Configuration (`ws-env.container`)

The Quadlet file tells `systemd` how to run the container. We map port `2222` on the host to port `22` in the container to avoid conflicts with the host's own SSH service.

```ini
# File: /etc/containers/systemd/ws-env.container
[Unit]
Description=Workstation Environment Container
After=network-online.target

[Container]
Image=localhost/ws-env:latest
ContainerName=ws-env

# Map host port 2222 to container port 22
PublishPort=2222:22

# Persistent storage for the workstation home directory
# This aligns with the btrfs snapshot strategy mentioned in the whitepaper
Volume=/var/lib/workstation/home:/home/developer:Z

# Ensure the container has the necessary capabilities if needed
# CapAdd=SYS_PTRACE

[Service]
# Restart the container if it fails
Restart=always

[Install]
# Start this unit when the system boots
WantedBy=multi-user.target default.target
```

---

## 3. Integrating with the Host `bootc` Image

To ensure this is part of the system build, we update the main `bootc` `Containerfile`.

```dockerfile
# Snippet to add to the main bootc Containerfile

# 1. Create the local directory for workstation persistence
RUN mkdir -p /var/lib/workstation/home

# 2. Copy the Quadlet file into the image
COPY ws-env.container /etc/containers/systemd/ws-env.container

# 3. (Optional) Pre-load or build the ws-env image during host build
# Note: In a production CI/CD, you would push ws-env to Quay and pull it here
# RUN podman pull quay.io/yourrepo/ws-env:latest
```

---

## 4. Automation: Setup Script

This script automates the generation of the authorized keys to ensure immediate access upon container start.

```bash
#!/bin/bash
# init_ws_ssh.sh

# Define paths
WS_HOME_PERSISTENT="/var/lib/workstation/home"
PUB_KEY_PATH="$HOME/.ssh/id_rsa.pub"

echo "Setting up workstation SSH access..."

# Ensure persistence directory exists
sudo mkdir -p "$WS_HOME_PERSISTENT/.ssh"

# Copy your current user's public key to the workstation's authorized_keys
if [ -f "$PUB_KEY_PATH" ]; then
    cat "$PUB_KEY_PATH" | sudo tee "$WS_HOME_PERSISTENT/.ssh/authorized_keys" > /dev/null
    sudo chmod 700 "$WS_HOME_PERSISTENT/.ssh"
    sudo chmod 600 "$WS_HOME_PERSISTENT/.ssh/authorized_keys"
    sudo chown -R 1000:1000 "$WS_HOME_PERSISTENT/.ssh"
    echo "SSH public key imported successfully."
else
    echo "Warning: Public key not found at $PUB_KEY_PATH. You will need to add it manually."
fi
```

---

## 5. Accessing the Environment

Once the `bootc` system is deployed or the Quadlet is started via `systemctl daemon-reload && systemctl start ws-env`, you can access the environment:

### From the Terminal
```bash
ssh -p 2222 developer@<host-ip>
```

### SSH Config Entry (`~/.ssh/config`)
Adding this entry allows for simple `ssh ws-env` commands and seamless integration with VS Code.

```text
Host ws-env
    HostName <host-ip>
    Port 2222
    User developer
    IdentityFile ~/.ssh/id_rsa
```

## Summary of Benefits
- **Separation of Concerns**: The host OS remains an immutable `bootc` image, while the workstation environment is a flexible container.
- **Persistence**: Using a volume for `/home/developer` ensures that code, SSH keys, and shell history survive container updates or host reboots.
- **Systemd Integration**: Quadlets allow the container to be managed using standard `systemctl` commands (`systemctl status ws-env`).
- **Security**: SSH access is restricted to key-based authentication and runs on a non-standard port.