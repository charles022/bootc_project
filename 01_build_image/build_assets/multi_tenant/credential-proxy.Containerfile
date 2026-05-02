# Credential proxy sidecar - Phase 2 implementation.
# Forwards in-pod agent requests to the host openclaw-broker via a tenant-
# specific UNIX socket bind-mounted from the host. The proxy holds no master
# credentials; the broker enforces grants. See docs/concepts/credential_broker.md.
FROM registry.fedoraproject.org/fedora:42

RUN dnf -y install \
       python3 \
    && dnf clean all

COPY credential-proxy.py /usr/local/bin/credential-proxy
RUN chmod 0755 /usr/local/bin/credential-proxy

# The proxy expects /run/credential-proxy/ to be mounted from the host so that
# (a) the broker socket bind-mounted at broker.sock is reachable, and
# (b) the agent socket created at agent.sock is reachable from the other
#     pod containers via the shared /run/credential-proxy mount.
RUN mkdir -p /run/credential-proxy

CMD ["/usr/local/bin/credential-proxy"]
