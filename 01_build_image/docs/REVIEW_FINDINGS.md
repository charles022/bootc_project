# Review Findings

Current status after the build asset cleanup:

- Image names are now controlled by `build_image.sh` and passed into the bootc image build.
- The default pod image names are local development names, not placeholder registry names.
- The dev and backup containers share `/var/lib/devpod/workspace` through the pod manifest.
- Startup tests now fail when required host, pod, or GPU checks fail.
- The host image creates `devuser`; host builds fail unless `SSH_AUTHORIZED_KEY` or a default public key is available, except when `ALLOW_NO_SSH_KEY=1` is explicitly set.
- `nvidia.com/gpu=all: 1` is documented by Podman 5.8.1 `podman-kube-play(1)` for CDI device selection. Recheck this on the final target Podman version.

See `BUILD_TEST_REFERENCE.md` for the active build and validation path.
