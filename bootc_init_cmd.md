The short answer is **no, not in the traditional container way.** When you build a Fedora `bootc` image, the standard container instructions like `CMD` or `ENTRYPOINT` are **completely ignored** when the image is booted as an actual operating system. 

Here is why that happens, and how you achieve your goal instead.

### The "Why": Container Runtime vs. OS Boot
In a traditional container environment (like Docker or Podman), the container runtime is responsible for starting your environment and executing the `CMD` or `ENTRYPOINT` you defined.

However, when you deploy a `bootc` image to bare metal or a VM, there is no container runtime wrapping it. The system boots using a standard bootloader (like GRUB) and the Linux kernel, which immediately hands control over to **`systemd`** as PID 1. Because `systemd` is running the show, it doesn't look at OCI image metadata like `CMD`. 

*(Note: `CMD` and `ENTRYPOINT` will still work if you `podman run` your bootc image to test it locally, but they will do nothing on a real boot).*

### The "How": Using systemd
To run a command when a `bootc` image starts, you need to do it the traditional Linux way: **create a systemd service.** You can define this service directly in your `Containerfile` and enable it during the build process.

**1. Create a systemd service file (e.g., `my-startup-script.service`)**
```ini
[Unit]
Description=Run custom command on boot
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/my-script.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**2. Update your `Containerfile`**
You will need to copy your script and the service file into the image, and then use `systemctl enable` so it is ready to go on boot.

```dockerfile
FROM quay.io/fedora/fedora-bootc:42

# Copy your script
COPY my-script.sh /usr/local/bin/my-script.sh
RUN chmod +x /usr/local/bin/my-script.sh

# Copy the systemd service file
COPY my-startup-script.service /etc/systemd/system/my-startup-script.service

# Enable the service so systemd starts it on boot
RUN systemctl enable my-startup-script.service
```

### Pro-Tip: Every Boot vs. First Boot Only
If you are coming from traditional containers, you might be trying to replicate an initialization script (like setting up SSH keys, generating machine IDs, or fetching metadata). 

* **If it needs to run every time the machine turns on:** The standard systemd setup above works perfectly.
* **If it only needs to run on the very first boot:** Add `ConditionFirstBoot=yes` under the `[Unit]` section of your systemd service file. This ensures `systemd` only executes your script once, keeping subsequent reboots clean and fast.
Here is exactly how you would set that up. 

While the `Containerfile` structure remains mostly the same, the magic happens in the systemd service file. By adding `ConditionFirstBoot=yes`, systemd will check if this is the machine's initial boot (typically determined by whether `/etc/machine-id` is uninitialized) and only run the service if it is.

### 1. The First-Boot systemd Service (`my-first-boot.service`)

Create your service file and add the `ConditionFirstBoot=yes` directive to the `[Unit]` section:

```ini
[Unit]
Description=One-time initialization script on first boot
After=network-online.target
# This is the magic line that tells systemd to only run this once
ConditionFirstBoot=yes

[Service]
Type=oneshot
ExecStart=/usr/local/bin/first-boot-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

### 2. The Setup Script (`first-boot-setup.sh`)

Create the script that you want to execute. For example, maybe you need to fetch some cloud-init style metadata or set a unique identifier:

```bash
#!/bin/bash
# /usr/local/bin/first-boot-setup.sh

echo "Running first-boot initialization..."
# Add your custom logic here (e.g., fetching SSH keys, configuring hardware)

echo "Initialization complete."
```

### 3. The Updated Containerfile

Now, copy both files into your image and enable the service just like before:

```dockerfile
FROM quay.io/fedora/fedora-bootc:42

# 1. Copy the initialization script and make it executable
COPY first-boot-setup.sh /usr/local/bin/first-boot-setup.sh
RUN chmod +x /usr/local/bin/first-boot-setup.sh

# 2. Copy the systemd service file
COPY my-first-boot.service /etc/systemd/system/my-first-boot.service

# 3. Enable the service
# systemd will queue it to run on boot, but ConditionFirstBoot ensures 
# it actually executes only on the very first boot of the deployed OS.
RUN systemctl enable my-first-boot.service
```

When you build and deploy this image to bare metal or a VM, the script will run immediately upon the first boot. If you reboot that machine later, systemd will see the unit is enabled, evaluate the `ConditionFirstBoot=yes` rule, see that the machine has already been booted previously, and quietly skip executing the script.
Yes — but only a **small** amount.

## What you need in the bootc host `Containerfile`

You do **not** need special logic to make the host “search for” Quadlets. Quadlet’s systemd generator already reads system Quadlet files at boot and on `systemctl daemon-reload`. So the host just needs the files present in the right location. ([Podman Documentation][1])

In practice, that means your bootc host image build should do these things:

### 1) Install the host-side software that will run them

At minimum, the host image needs Podman, since Quadlet is part of the Podman/systemd integration. If this is a GPU-capable host image, it also needs the NVIDIA host-side pieces you already planned, such as the toolkit used to generate CDI and the driver path. ([Podman Documentation][1])

### 2) Copy the Quadlet and Pod YAML into the image

For image-provided system workloads, place them in the system Quadlet directory, for example:

* `/usr/share/containers/systemd/devpod.kube`
* `/usr/share/containers/systemd/devpod.yaml`

Quadlet reads these system files during boot and generates the corresponding `.service` units automatically. ([Podman Documentation][1])

### 3) Add an `[Install]` section to the Quadlet if you want auto-start

If you want the container to start automatically when the bootc system boots, the Quadlet needs an `[Install]` section such as:

```ini
[Install]
WantedBy=multi-user.target
```

That is the key step for “start this container automatically on boot.” Podman’s Quadlet docs explicitly call out the `[Install]` section for starting on boot. ([Podman Documentation][2])

## What you do **not** need

You do **not** need to add some separate “watcher” or explicit “look here for Quadlets” command in the `Containerfile`. Once Podman/Quadlet is present and the files are in the expected directory, systemd + the Quadlet generator handle discovery. ([Podman Documentation][1])

You also do **not** need a boot-image-style `CMD` or `ENTRYPOINT` to launch the container. For a bootc host, automatic startup is handled by systemd through Quadlet, not by a Docker-style host entrypoint. ([Podman Documentation][1])

## Minimal `Containerfile` shape

So the host image `Containerfile` should look conceptually like this:

```dockerfile
FROM quay.io/fedora/fedora-bootc:42

RUN dnf -y install \
      podman \
      nvidia-open \
      nvidia-container-toolkit \
    && dnf clean all

COPY nvidia-cdi-refresh.service /usr/lib/systemd/system/nvidia-cdi-refresh.service
COPY devpod.kube /usr/share/containers/systemd/devpod.kube
COPY devpod.yaml /usr/share/containers/systemd/devpod.yaml

RUN systemctl enable nvidia-cdi-refresh.service
```

And then `devpod.kube` contains:

```ini
[Unit]
Description=GPU development container
After=network-online.target nvidia-cdi-refresh.service
Wants=network-online.target
Requires=nvidia-cdi-refresh.service

[Kube]
Yaml=/usr/share/containers/systemd/devpod.yaml

[Install]
WantedBy=multi-user.target
```

## Short answer

So the answer is:

* **Yes**, the bootc host image build needs to **include** the Quadlet file and Pod YAML in the proper system directory.
* **No**, you do not need extra logic to make the host “look for” them.
* **Yes**, if you want automatic startup, the Quadlet should include an `[Install]` section like `WantedBy=multi-user.target`. ([Podman Documentation][1])

The next useful addition would be to separate this into two explicit cases in your docs:

1. files present but **not** auto-started
2. files present **and** auto-started via `[Install]`

[1]: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html?utm_source=chatgpt.com "podman-systemd.unit"
[2]: https://docs.podman.io/en/v5.0.1/markdown/podman-systemd.unit.5.html?utm_source=chatgpt.com "podman-systemd.unit"

The recommended way is:

## Use a Quadlet, managed by host systemd

For a **bootc image**, the normal pattern is:

1. **Bake a Quadlet file into the bootc image**
2. Place it in one of the system Quadlet directories, typically:

   * `/usr/share/containers/systemd/` for image-provided units
   * `/etc/containers/systemd/` for mutable local units
3. Let **systemd** start it at boot via the Quadlet-generated service
4. Add an `[Install]` section like:

   ```ini
   [Install]
   WantedBy=multi-user.target
   ```

That is the clean, host-native way for a bootc system to automatically start a container when the OS boots. It matches the pattern we already settled on: **host boot behavior is handled by systemd; container lifecycle on the host is handled by Quadlet; container internal behavior is handled by the container command.** Podman documents Quadlet as a systemd generator for containers and related workloads, and Fedora bootc documentation explicitly recommends using Quadlet/systemd units for containers that should run on the image.

## In your case

For your design, that means:

* the **bootc image** includes:

  * the `.kube` Quadlet file
  * the referenced Pod YAML
  * any supporting systemd units like `nvidia-cdi-refresh.service`
* the Quadlet gets an `[Install]` section
* the image either:

  * enables the generated service at build time when appropriate, or
  * you enable it once in the VM during testing

So the host boots, systemd comes up, Quadlet generates the service, and that service launches the container automatically.

## Why this is the recommended approach

Because it keeps the layers clean:

* **bootc host image**: installs and configures the OS and host services
* **Quadlet/systemd**: decides whether the container starts automatically
* **Pod YAML / container command**: decides what the container does after it starts

That is more maintainable and more aligned with the documented model than trying to make the bootc host “run a container automatically” through a Docker-style host entrypoint idea. The host is an OS, so the correct startup controller is systemd; Quadlet is the container-facing bridge for that.

## Minimal example

```ini
# /usr/share/containers/systemd/devpod.kube
[Unit]
Description=GPU development container
After=network-online.target nvidia-cdi-refresh.service
Wants=network-online.target
Requires=nvidia-cdi-refresh.service

[Kube]
Yaml=/usr/share/containers/systemd/devpod.yaml

[Install]
WantedBy=multi-user.target
```

That is the recommended pattern for “bootc image automatically starts and runs a container.”

## Short version

If you want a bootc image to automatically start a container, the recommended way is:

* **do not** try to do it with a boot-image “initial command”
* **do** use **Quadlet + systemd**
* for your GPU path, keep using **`.kube` Quadlets + Pod YAML**

That is the most defensible approach we’ve identified so far.

