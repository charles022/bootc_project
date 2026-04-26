# Write a systemd unit for the host

## Goal
Add a service that runs at boot on the deployed host image.

## Background
A bootc host boots via GRUB → kernel → systemd as PID 1. The OCI image's `CMD` or `ENTRYPOINT` are container-runtime concepts and are **ignored** at boot. To run something at boot, write a systemd unit and bake it into the host image. While `CMD` and `ENTRYPOINT` still execute when running the image locally with `./run_container.sh`, they have no effect on the actual host boot process.

## Steps

1.  **Write the unit.** Drop a service file in `01_build_image/build_assets/`, e.g., `my-startup.service`:
    ```ini
    [Unit]
    Description=Run my custom startup script
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/my-startup.sh
    RemainAfterExit=yes
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    ```

2.  **Write the script.** Drop the executable in `01_build_image/build_assets/`, e.g., `my-startup.sh`. Make sure it is executable (`chmod +x`).

3.  **Wire it into the host `Containerfile`.** Edit `01_build_image/build_assets/Containerfile` to copy and enable the unit:
    ```dockerfile
    COPY my-startup.sh /usr/local/bin/my-startup.sh
    COPY my-startup.service /usr/lib/systemd/system/my-startup.service
    RUN chmod 0755 /usr/local/bin/my-startup.sh
    RUN systemctl enable my-startup.service
    ```
    *See the file in the repo for the authoritative version of the host image definition.*

4.  **Rebuild and redeploy.** Run `./build_image.sh` and then re-run the VM as described in `how-to/build_and_run_vm.md`. If the image is already published, use `bootc upgrade` on the host.

## Verify
On the booted host, check the status and logs:
```bash
systemctl status my-startup.service
journalctl -u my-startup.service --no-pager
```

## Variations

### Every boot (default)
The example above runs every time the system boots.

### First boot only
Add `ConditionFirstBoot=yes` to the `[Unit]` section. systemd evaluates this against the machine ID state; once the host has booted once and initialized the machine ID, the unit is skipped on subsequent reboots:
```ini
[Unit]
ConditionFirstBoot=yes
```
This pattern is used by `bootc-firstboot-push.service`. See `reference/systemd_units.md` for details.

### Triggered by a path appearing
For "wait until file/device X exists, then run," use a `.path` unit to activate the service. In this project, `nvidia-cdi-refresh.path` activates `nvidia-cdi-refresh.service` when `/dev/nvidiactl` appears. See `reference/systemd_units.md`.

### Triggered by a timer
To run on a schedule, use a `.timer` unit. For example, `bootc-update.timer` fires `bootc-update.service` weekly. See `reference/systemd_units.md`.

## Where files go in the host image (placement rules)

- `/usr/lib/systemd/system/` — Preferred location for image-provided units baked into the host.
- `/etc/systemd/system/` — Mutable local units (subject to ostree's `/etc` 3-way merge on upgrade).
- `/usr/share/containers/systemd/` — Location for Quadlet files (see `reference/quadlets.md`).
- `~/.config/containers/systemd/` — User-scoped Quadlets (not used by this project).

## What this doc is NOT
- Not a Quadlet primer (see `reference/quadlets.md` and `concepts/ownership_model.md`).
- Not an exhaustive systemd reference (see `man systemd.service` and `man systemd.unit`).

## Sources
- `bootc_init_cmd.md` — Rationale for why `CMD`/`ENTRYPOINT` don't apply.
- `01_build_image/build_assets/Containerfile` — Standard pattern for COPY and enable.
- `concepts/ownership_model.md` — General project separation of concerns.
