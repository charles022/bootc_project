# Review Findings

These findings remain after fixing parser-breaking comment placement.

## Pod Images Are Placeholder Registry References

`build_images.sh` builds the dev and backup images as:

```text
ghcr.io/YOURORG/dev-container:latest
ghcr.io/YOURORG/backup-container:latest
```

`devpod.yaml` uses those same image names. A booted VM will need to pull those
images from GHCR unless they are preloaded into the VM's container storage. The
`YOURORG` placeholder should be replaced with a real registry namespace and the
images should be pushed, or the bootc host image should be changed to include or
otherwise preload the container images it starts at boot.

## GPU Resource Declaration Needs Validation

`devpod.yaml` currently declares:

```yaml
resources:
  limits:
    nvidia.com/gpu=all: 1
```

That key is not standard Kubernetes extended-resource syntax. Before relying on
Quadlet/Podman to start the GPU pod, validate the supported CDI/GPU request form
for the target Podman and NVIDIA Container Toolkit versions, then update the pod
manifest accordingly.
