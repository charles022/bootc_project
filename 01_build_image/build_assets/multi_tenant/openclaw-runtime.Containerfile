# OpenClaw runtime container - Phase 0 stub.
# The real runtime hosts the agent control loop, tool dispatcher, and
# credential-proxy client. This image just identifies itself and idles.
FROM registry.fedoraproject.org/fedora:42

RUN dnf -y install bash coreutils \
    && dnf clean all

RUN mkdir -p /openclaw

COPY openclaw-runtime-stub.sh /usr/local/bin/openclaw-runtime-stub.sh
RUN chmod 0755 /usr/local/bin/openclaw-runtime-stub.sh

CMD ["/usr/local/bin/openclaw-runtime-stub.sh"]
