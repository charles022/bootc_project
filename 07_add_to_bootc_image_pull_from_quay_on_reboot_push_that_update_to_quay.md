# 7. add to bootc image: pull from quay on reboot (push that update to quay)

This document describes how to configure the Fedora bootc image to autonomously check for and pull updates from Quay.io during the system's boot process. This ensures that the system always has the latest version of the OS staged and ready for the next scheduled maintenance window or weekly reboot.

## 1. Overview of the Build-Push-Pull Cycle

As outlined in the whitepaper, we are building a continuous deployment pipeline for our system OS. This process follows a specific sequence:
1.  **Build**: The pipeline builds the custom Fedora bootc image.
2.  **Push**: The pipeline pushes the new image to the Quay.io registry (Step 06).
3.  **Pull (on Reboot)**: The running system reboots and, upon startup, automatically checks Quay.io for a newer image. If an update is found, it is downloaded and staged in a new btrfs subvolume.
4.  **Final Apply**: The system remains on the current version until the *next* manual or scheduled reboot, at which point it automatically transitions into the updated environment.

## 2. Creating the Update Service

We will create a systemd "oneshot" service that triggers a `bootc upgrade` once the network is online. This command is the primary mechanism for pulling updates in a bootc system.

### File: `bootc-upgrade-on-boot.service`

```ini
[Unit]
Description=Check for bootc updates from Quay on boot
# Wait for the network to be fully up before checking the registry
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# 'bootc upgrade' fetches the update and stages it. 
# It does NOT reboot the system immediately, ensuring no unexpected downtime.
ExecStart=/usr/bin/bootc upgrade
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

## 3. Integrating into the bootc Image

To include this update mechanism in our core system, we modify the `Containerfile`. This ensures that every system deployed from this image is "self-updating" from the moment it boots.

### Updated `Containerfile` Snippet

Add the following to your core `Containerfile` (see Step 01):

```dockerfile
# ... (Previous configuration: root pass, ssh, etc.) ...

# 1. Copy the systemd service unit into the image's systemd directory
COPY bootc-upgrade-on-boot.service /usr/lib/systemd/system/bootc-upgrade-on-boot.service

# 2. Enable the service so it runs automatically on every boot
RUN systemctl enable bootc-upgrade-on-boot.service

# 3. Ensure the system is configured to track the correct Quay repository
# The 'bootc status' command will show this source as the 'Tracked' registry.
# If you are already running a bootc system, ensure it was switched to track:
# sudo bootc switch quay.io/youruser/fedora-bootc-custom:latest
```

## 4. The Trigger: Push that Update to Quay

The "Pull on Reboot" mechanism is only effective if a new image has been pushed to the registry. The following command (part of the Step 06 pipeline) is what the system will "see" when it reboots:

```bash
# In the build environment/CI pipeline:
# 1. Build the updated OS image with the new service included
podman build -t quay.io/youruser/fedora-bootc-custom:latest .

# 2. Push to Quay (The critical trigger for the system update)
podman push quay.io/youruser/fedora-bootc-custom:latest
```

## 5. Why "Pull on Reboot"?

This strategy aligns with the "Clean Workspace" philosophy and the weekly reboot schedule mentioned in the whitepaper:
- **Automation without Risk**: Unlike `bootc upgrade --apply` (which reboots immediately), the standard `bootc upgrade` only prepares the update. The user controls exactly *when* the switch happens by choosing when to reboot.
- **Alignment with Weekly Cycles**: If a new image is built and pushed every Friday, the system will pull it during its first reboot thereafter, ensuring the system is always ready for its next scheduled cycle.
- **Registry as Source of Truth**: The system becomes its own management agent, reducing the need for external push-based management tools (like Ansible) to trigger updates.

## 6. Verification and Status

Once the system has rebooted, you can verify that the update check occurred and see if a new deployment is waiting.

### Check bootc Status
```bash
bootc status
```

**Interpreting the Output:**
- **Booted**: The image currently running the system.
- **Staged**: If `bootc-upgrade-on-boot` found an update, it will be listed here. This is the version the system will run *after* the next reboot.
- **Queued for Update**: Shows the specific commit/tag being tracked on Quay.io.

### Manual Application
If you want to apply the staged update immediately (and reboot) without waiting for the next cycle:
```bash
sudo bootc upgrade --apply
```

## Summary
By adding the `bootc-upgrade-on-boot` service to the image and ensuring the pipeline correctly pushes updates to Quay, we establish a robust, hands-off maintenance cycle. The system autonomously tracks, downloads, and stages its own OS updates, requiring only a periodic reboot to stay current with the latest builds.