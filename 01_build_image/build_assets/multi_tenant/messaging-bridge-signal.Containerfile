# Signal messaging-bridge sidecar - Phase 4.
# Wraps signal-cli in JSON-RPC daemon mode, forwards inbound messages from
# allow-listed senders to the pod-local message bus, and sends outbound for
# {"op":"reply", ...} envelopes posted by the openclaw-runtime router.
# See docs/concepts/messaging_interface.md.
FROM registry.fedoraproject.org/fedora:42

# signal-cli ships as a Java application; java-21-openjdk-headless covers the
# runtime. The signal-cli release tarball is fetched at build time and
# unpacked into /opt; the version is pinned via SIGNAL_CLI_VERSION below to
# keep host image rebuilds deterministic.
ARG SIGNAL_CLI_VERSION=0.13.10

RUN dnf -y install \
       python3 \
       java-21-openjdk-headless \
       ca-certificates \
       coreutils \
       tar \
       gzip \
       curl \
    && dnf clean all

RUN curl -L -o /tmp/signal-cli.tar.gz \
        "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}-Linux.tar.gz" \
    && tar -C /opt -xzf /tmp/signal-cli.tar.gz \
    && ln -s "/opt/signal-cli-${SIGNAL_CLI_VERSION}/bin/signal-cli" /usr/local/bin/signal-cli \
    && rm -f /tmp/signal-cli.tar.gz

COPY messaging-bridge-signal.py /usr/local/bin/messaging-bridge-signal
RUN chmod 0755 /usr/local/bin/messaging-bridge-signal

RUN mkdir -p /run/credential-proxy /run/messaging-bridge

CMD ["/usr/local/bin/messaging-bridge-signal"]
