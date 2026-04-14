# 2. run bootc image as container

While Fedora `bootc` images are primarily designed to be deployed as the host operating system, running them as containers is a critical step for development, validation, and hosting specific services via Podman Quadlets. This approach allows you to verify that your configurations, packages, and scripts are working correctly before committing to a bare-metal or VM deployment.

In alignment with our strategy, we will focus on running these images using **Podman Quadlets** to ensure they are managed as standard systemd services.

---

## 1. Prerequisites
- A built bootc image (e.g., `localhost/fedora-bootc:latest`).
- Podman installed and configured on the host.
- Understanding that running a bootc image as a container requires systemd to be functional within the container.

---

## 2. Manual Execution (for Testing)
Before automating with Quadlets, you can run the image manually to ensure it initializes correctly. Because bootc images are designed to be full operating systems, they require specific flags to allow `systemd` to run as PID 1.

```bash
podman run -d \
  --name bootc-test \
  --privileged \
  --cap-add=SYS_ADMIN \
  --security-opt label=disable \
  localhost/fedora-bootc:latest /sbin/init
```

**Key Flags:**
- `--privileged`: Grants necessary permissions for systemd to manage cgroups and devices.
- `--cap-add=SYS_ADMIN`: Specifically required for many systemd operations.
- `/sbin/init`: Explicitly calls the systemd init process.

---

## 3. Quadlet Implementation
To integrate this into our automated pipeline and ensure persistence across reboots, we use a Podman Quadlet (`.container` file). This file will reside in `/etc/containers/systemd/` (for system-wide services) or `~/.config/containers/systemd/` (for rootless/user services).

### `bootc-workstation.container`
This Quadlet defines the workstation environment mentioned in the whitepaper.

```ini
[Unit]
Description=Bootc Workstation Container
After=network-online.target

[Container]
Image=localhost/fedora-bootc:latest
ContainerName=workstation-service
# We use privileged mode to allow systemd inside the container to manage resources
Privileged=true
# Mount the BTRFS work directories as defined in the strategy
Volume=/mnt/data/workstation_home:/home/user:Z
Volume=/mnt/data/backups:/mnt/backups:Z
# Ensure systemd is the entrypoint
Exec=/sbin/init
# Standard networking for workstation access
Network=bridge

[Install]
# Start this unit when the system boots
WantedBy=multi-user.target
```

---

## 4. Deploying the Quadlet
Once the `.container` file is created, follow these steps to activate the service:

1. **Reload systemd daemon:**
   ```bash
   systemctl daemon-reload
   ```
   *This triggers the Quadlet generator to create a standard systemd service file from your `.container` file.*

2. **Start and Enable the service:**
   ```bash
   systemctl enable --now bootc-workstation.service
   ```

3. **Verify the status:**
   ```bash
   systemctl status bootc-workstation.service
   podman ps
   ```

---

## 5. Interacting with the Bootc Container
To enter the workstation environment and perform development tasks:

```bash
podman exec -it workstation-service /bin/bash
```

Or, if you need a login shell to simulate a full terminal session:

```bash
podman exec -it workstation-service login -f root
```

---

## 6. Alignment with BTRFS Snapshot Strategy
As per the whitepaper, the workstation container uses persistent volumes. Because these volumes (`/mnt/data/workstation_home`) are stored on a BTRFS partition on the host, you can perform snapshots of the container's data without stopping the container:

```bash
# Example BTRFS snapshot command on the host
btrfs subvolume snapshot -r /mnt/data/workstation_home /mnt/data/backups/workstation_$(date +%Y%m%d)
```

This ensures that while the bootc image remains immutable and is refreshed weekly, your user data and development work remain persistent and backed up via the host's BTRFS capabilities.