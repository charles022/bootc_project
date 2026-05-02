# OpenClaw runtime container - Phase 3.
# Hosts the agent control loop (still a stub for now: idle process) plus the
# `agentctl` CLI that talks to the host provisioner via the bind-mounted
# /run/agentctl/agentctl.sock.
#
# A real agent control loop ships later; for Phase 3 we ensure the runtime
# image is the right shape (python3 present, agentctl on PATH, locked down
# via Quadlet) so an LLM-driven loop can drop in without changing the host
# contract.
FROM registry.fedoraproject.org/fedora:42

RUN dnf -y install \
       bash \
       coreutils \
       python3 \
    && dnf clean all

RUN mkdir -p /openclaw

COPY agentctl.py /usr/local/bin/agentctl
COPY openclaw-runtime-stub.sh /usr/local/bin/openclaw-runtime-stub.sh
RUN chmod 0755 /usr/local/bin/agentctl /usr/local/bin/openclaw-runtime-stub.sh

CMD ["/usr/local/bin/openclaw-runtime-stub.sh"]
