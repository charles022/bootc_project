# Ephemeral build environment for the bootc host image and its sibling
# containers. Pulled by the host's bootc-update.service on a timer; the
# scheduled-update pipeline runs an --rm instance of this image, has it
# clone the upstream repo into RAM, builds all four Containerfiles, and
# emits the host image as an OCI archive into a tmpfs mount supplied by
# the host. Carries no credentials and no project-specific state.
FROM quay.io/fedora/fedora:42

RUN dnf -y install \
        podman \
        buildah \
        skopeo \
        git \
        ca-certificates \
        bash \
        coreutils \
    && dnf clean all

ENV SOURCE_REPO=https://github.com/charles022/bootc_project.git \
    SOURCE_BRANCH=main \
    OUTPUT_DIR=/output \
    SAVE_ALL=0

COPY os-builder.sh /usr/local/bin/os-builder.sh
RUN chmod 0755 /usr/local/bin/os-builder.sh

ENTRYPOINT ["/usr/local/bin/os-builder.sh"]
