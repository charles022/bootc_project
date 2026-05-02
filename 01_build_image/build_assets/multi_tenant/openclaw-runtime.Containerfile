# OpenClaw runtime container - Phase 3 + Phase 4 router.
# Hosts the agent control loop (Phase 4: a strict verb-table message router
# at openclaw-runtime-router.py) plus the `agentctl` CLI that talks to the
# host provisioner via the bind-mounted /run/agentctl/agentctl.sock and the
# pod-local /run/messaging-bridge/agent.sock written by the messaging-bridge
# sidecars.
#
# A real LLM-driven loop drops in later (Phase 5+) without changing the host
# contract; the router today dispatches a small, hand-coded verb table.
FROM registry.fedoraproject.org/fedora:42

RUN dnf -y install \
       bash \
       coreutils \
       python3 \
    && dnf clean all

RUN mkdir -p /openclaw /run/messaging-bridge

COPY agentctl.py /usr/local/bin/agentctl
COPY openclaw-runtime-router.py /usr/local/bin/openclaw-runtime-router
COPY openclaw-runtime-stub.sh /usr/local/bin/openclaw-runtime-stub.sh
RUN chmod 0755 /usr/local/bin/agentctl /usr/local/bin/openclaw-runtime-router /usr/local/bin/openclaw-runtime-stub.sh

CMD ["/usr/local/bin/openclaw-runtime-router"]

