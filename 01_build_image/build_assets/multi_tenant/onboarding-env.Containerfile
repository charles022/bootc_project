# Onboarding env - Phase 0 stub.
# The real onboarding env hosts sshd plus an `openclaw-onboard` CLI that
# walks the tenant through credential enrollment. Phase-0 keeps it minimal:
# bash, coreutils, an idle process. SSH access is wired up later via the
# cloudflared sidecar (planned).
FROM registry.fedoraproject.org/fedora:42

RUN dnf -y install \
       bash \
       coreutils \
       openssh-server \
       sudo \
    && dnf clean all

RUN mkdir -p /workspace

COPY onboarding-env-stub.sh /usr/local/bin/onboarding-env-stub.sh
RUN chmod 0755 /usr/local/bin/onboarding-env-stub.sh

CMD ["/usr/local/bin/onboarding-env-stub.sh"]
