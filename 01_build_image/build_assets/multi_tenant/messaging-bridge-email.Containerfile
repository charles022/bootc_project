# Email messaging-bridge sidecar - Phase 4.
# Polls IMAP for inbound messages from allow-listed senders, forwards them
# as JSONL envelopes to /run/messaging-bridge/agent.sock, and accepts
# {"op":"reply",...} envelopes that it sends as SMTP.
# See docs/concepts/messaging_interface.md.
FROM registry.fedoraproject.org/fedora:42

RUN dnf -y install \
       python3 \
       python3-pip \
       ca-certificates \
    && dnf clean all

COPY messaging-bridge-email.py /usr/local/bin/messaging-bridge-email
RUN chmod 0755 /usr/local/bin/messaging-bridge-email

# /run/credential-proxy/agent.sock is reachable from sidecars in the pod via
# the shared mount. /run/messaging-bridge is provisioned by the pod and shared
# with the openclaw-runtime container so the runtime can subscribe to events.
RUN mkdir -p /run/credential-proxy /run/messaging-bridge

CMD ["/usr/local/bin/messaging-bridge-email"]
