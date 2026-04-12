
This is the whitepaper for our project. The document ostree_notes.md contains some recommendations about the project, and all other documents should be a dedicated document for each piece of the Checklist/Plan section of this document.


## goal, purpose
- current process:
    - we maintain a set of scripts (fedora_init) to setup our system from scratch. we
      periodically will save all files as a compressed backup to a separate location,
      put the latest Fedora Server OS on a USB, then wipe the drive while installing
      the OS.  We then run the scripts to recreate our system environment, minus any
      transient files, which we can reference as needed if we need to. this keeps the
      workspace clean, all software up to date, and removes any software that we have
      not intentionally saved to our setup scripts. our process is, we will develop on
      the system, update system configurations and build components, and as they
      become functional, we save the scripts necessary to recreate them to fedora_init
      for the next time we wipe and reinstall the system.
- process we are building:
    - going forward we will be using bootc images of fedora to manage system component
      builds, updates, and component development. Broadly, we will be building a bootc
      image for the core system os, as well as software installation and
      configuration. We will use podman quadlets and podman pods via quadlets to build
      the systemd services where we can and where the added complexity is offset by
      the meaningful benefit of separation from the core bootc image build. The
      mindset is: setup goes directly into the bootc image Containerfile, while the
      actions that the system takes after it has been set up are put into quadlets,
      particulaly those that should be run as systemd services. We will create a
      pipeline that runs weekly to rebuild the image (which will pull the latest
      version of all software during the build, including the latest quadlets and
      container images), push the newly built image to quay, then refresh the system
      with that latest image. We will then, manually or through an automated schedule,
      reboot to the latest image on a weekly basis. One of the quadlets we will
      incorporate will be a workstation image and container for using the system in
      day to day operation. We will be using btrfs send to save snapshots of our work,
      while allowing all but a couple specific directories to be kept clean. We will
      keep the container persistent so that installed software is kept, but we also
      have the option to save the containers in their state, back them up,
      then redeploy as freshly built containers, potentially after placing some of
      those changes into the next workstation image build. We'll be creating
      scheduled cron jobs or systemd timers to backup snapshots of the workstation
      directories to our separate larger drive on the same system. Those btrfs
      backups will remain untouched. We will periodically compress and encrypt
      these backups then push them to the cloud at longer intervals. 


Checklist/Plan:
---
# base
    1. build bootc image (no enhancements)
    2. run bootc image as container
    3. choose vm software
    4. build bootc image as iso
    5. run bootc image as vm
    6. push to quay
    7. add to bootc image: pull from quay on reboot (push that update to quay)
# flash system
    8. compress + encrypt files, push as backup to GDrive
    9. build v1.0 image, push to quay
    10. pull v1.0 image, build as ISO (w/ anaconda)
    11. flash image to USB, wipe + install to system
# base image build structure
    12. build Containerfile (simple git install) (add to image build, test as container + vm)
    13. build Quadlet (simple ws-env, no integration) (add to image build, test as container + vm)
# enhance testing
    14. test GPU passthrough w/ standard vm
    15. test GPU passthrough w/ bootc image
    16. test GPU passthrough w/ bootc image + nvidia container
    17. write as automated CI/CD for image testing
        (add to image_build + fedora_init, push to quay + github, reboot)
# system wipe/build/use/backup/recovery
    18. ws-env: build access to ws-env via ssh
    19. ws-env: map persistent memory location /etc
    20. create system btrfs backup on D:/var/
    21. automate backup: ws-env -> sys-btrfs
    22. automate recovery: sys-btrfs -> ws-env directory
    23. automate backup: system btrfs backup compress/encrypt -> cloud
    24. automate recovery: cloud -> sys-btrfs


## open questions / things to finish conceptualizing
-- in the bootc image build, we can provide --fs ext4 (or ideally btrfs). can/should we provide btrfs so that we can use as a true sys admin/root?
** can we build w/o root?
** for the initial iso that we flash to a drive and boot to, we SHOULD work out all
details ahead of time, then use the bare ISO rather than use the gui installer, purely
for reproducability. If there are other benefits to the anaconda installer, then maybe
we will keep the anaconda installer. we want to discuss this and work out an intended
approach.
** more thoroughly document the process for adding Category1-4 (outlined in "process
for wiping system post-bootc) + workstation container into the bootc image (probably
through the containerfile).
** how to wipe /etc and potentially /var? use a dedicated script? when to do either?
we want the periodic updates of the bootc image to go through regularly so that we can
keep the software and kernels and kernel modules up to date. We also want to be able
to leave the workstation container at the drop of the hat and come back to it without
fear that our work will be lost. So we should have a set pipeline script to create a
clean and complete btrfs backup, then to do a full wipe and boot back with the latest
image and a completely clean system.

## process for wiping system post-bootc
- on bootc update
    - /usr is replaced
    - /etc remains
    - bootc image needs additional separate pods, quads, containers (workspace container)
    - on wipe, bootc image loads (like with bootc update)
        - bootc update would be a separate process from wipe
        - btrfs send (backup, periodically regardless of wipe)
            - could keep the backup structure and send structure in place
            - btrfs would treat these as new blocks
            - allow us to easily roll back between different wipes
            - ** could we do compression on btrfs backups between wipes? part of the CI/CD
    Category 1: write from workstation, wipe on reentry
        - anything not in specific directories
        - could still include these in the btrfs backups just in case
    Category 2: persist workstation container reboots
        - anything in $HOME/code, $HOME/notes
        - ** map to /etc or /var?
    Category 3: persist system wipes
        - anything in D:/
        - mainly: btrfs backups (uncompressed, unencrypted)
            - periodically compress, encrypt, push to cloud
        - + selective, large content (machine learning models)
    Category 4: cloud: compressed encrypted backups of Category 3 btrfs backups



- `/usr/share/containers/systemd/` — replaced wholesale by the new image. Any local edits are gone.
- `/etc/containers/systemd/` — 3-way merged. Your local edits are preserved unless the new image also changed the same lines, in which case you get a merge conflict to resolve (same as `/etc/ssh/sshd_config`).



Surface:
- bootc image:
    - kernel relevant build (nvidia-akmods, dnf update)
    - items w/ large/complex setup + minimal runtime surface
        - ssh configuration, backup process
        - systemd processes
        - can still access/modify these by logging into the server itself
            - updates maintained between reboots as layers in /etc
            - realtime changes should be worked into the bootc image build for the next build
- quadlets + pods + containers:
    - user workstation container (ws-env)
        - maps specific directories to /etc or /var to persist across reboots
        - all other files and software installs are transient until baked into ws-env image build
        - all files, including transient ones, are backed up with btrfs to /D:/var/backup
    - all will share resources and visibility as needed
    - ** future: nvidia container for building and running models
        - ** shared access w/ workstation-container to persistent directories
        - ** allows workstation-container to function w/ latest and reliable software
    - ** future: openclaw container: specific and limited access
    - ** future: containers may include things like ssh, cloudflared, btrfs-backup, etc
        - ** would allow these to be built and tested separately from core bootc image


### Workflow:
- cron job weekly
    - rebuilds bootc image w/ latest image, kernels, software
    - push image to quay
- manual reboots
    - pull the latest (by default) available image from quay
    - boots to that latest image
        - ** can we integrate automated new images/kernels/software updates without reboot? for minor updates ('dnf update ...'-esk updates) w/o shutting down the server?
- enhancements
    - pull latest image from quay
    - build locally
    - light test: run as container
    - full test:
        - wrap as VM ISO
        - run in VM
    - add new content to the image build script + ContainerFile


### bootc image breakdown
    - Containerfile (install, configure), Quadlets (run as service)
    - quadlet container images
        - services to run at startup
        - workstation container, nvidia container
    - pod quadlets
        - quadlet services w/ shared resources
        - system level, store in /etc
## 1. image Containerfile
- software installation + configuration

```dockerfile
FROM quay.io/fedora/fedora-bootc:41
RUN dnf install -y openssh-server && \
    systemctl enable sshd
COPY sshd_config_baseline /etc/ssh/sshd_config.d/99-custom.conf
```

## 2. podman quadlets (baked into the bootc image)
- pull/run containers on boot
- Fedora endorsed
- process:
    - image build includes the quadlet (a .container, .pod, .network, .volume file)
    - quadlet defines what container images to pull/build/run on boot
    - systemd-generator converts the container + quadlet definition into a systemd unit
- update container images separately from the bootc image
- latest container images are pulled and run on reboot
- sytem-wide quadlet location:
    - read-only, from your bootc image: `/usr/share/containers/systemd/`
    - mutable, for runtime additions: '/etc/containers/systemd/`

```quadlet
# /usr/share/containers/systemd/workstation.container
[Unit]
Description=Workstation container
After=network-online.target

[Container]
Image=ghcr.io/yourname/workstation:latest
AutoUpdate=registry
Volume=/var/workstation-home:/home/user:Z
Network=host          # or a named network
Exec=/usr/bin/sleep infinity

[Install]
WantedBy=multi-user.target
```

### Future: 3. Podman pods via Quadlets
- potential for system services (backup CI/CD, logger, ssh)
- where services need shared resources
- would allow us to test and deploy components separately from base functional bootc
  image
- Best for tightly coupled services that need shared network/IPC namespace
- think...
    - service + its sidecar proxy
    - database + its exporter
- howto:
    - define a `.pod` Quadlet +  `.container` Quadlets that reference it
- benefit:
    - shared-namespace in pods
    - processes talk over localhost or share IPC without network overhead

```
# workstation.pod
[Pod]
PodName=workstation

# app.container
[Container]
Pod=workstation.pod
Image=ghcr.io/yourname/workstation:latest

# proxy.container  
[Container]
Pod=workstation.pod
Image=ghcr.io/yourname/nginx-proxy:latest
```



# workflow
- one time setup
    - push image to quay
    - build image as ISO, reboot to image (future pulls from quay)
- build, deploy
    - cron to build the latest images with updated kernels etc, push to quay
    - reboots always pull latest bootc image + quadlet containers
- enchance
    - pull image + quadlets from quay
    - light test as a container
    - full test: build as ISO, test as VM


