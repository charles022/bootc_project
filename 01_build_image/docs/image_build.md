# Image Build Notes

The active build entrypoint is:

```bash
./build_image.sh [containers|host|test-containers|push|all]
```

The build assets live in `01_build_image/build_assets/`. `build_image.sh` keeps the image names in one place and passes the selected dev/backup image references into the bootc host image build.

Keep this layer small:

- host setup belongs in `Containerfile`
- boot-time orchestration belongs in `devpod.kube` and `devpod.yaml`
- runtime checks belong in the startup scripts
- workflow checks belong in `BUILD_TEST_REFERENCE.md`

See `BUILD_TEST_REFERENCE.md` for the current local container, local VM, and registry pull validation sequence.
