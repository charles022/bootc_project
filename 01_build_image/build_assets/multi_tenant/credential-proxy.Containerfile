# Credential proxy sidecar - Phase 0 stub.
# The real proxy exposes a pod-local UNIX socket that talks to the host
# broker. This image just identifies itself and idles.
FROM registry.fedoraproject.org/fedora:42

RUN dnf -y install bash coreutils \
    && dnf clean all

COPY credential-proxy-stub.sh /usr/local/bin/credential-proxy-stub.sh
RUN chmod 0755 /usr/local/bin/credential-proxy-stub.sh

CMD ["/usr/local/bin/credential-proxy-stub.sh"]
