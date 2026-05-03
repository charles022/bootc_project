# Tenant agent dev environment with CUDA, cuDNN, and PyTorch.
FROM nvcr.io/nvidia/pytorch:26.03-py3

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
       bash \
       procps \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /workspace

COPY dev_container_start.sh /usr/local/bin/dev_container_start.sh
COPY dev_container_test.py /workspace/dev_container_test.py

RUN chmod 0755 /usr/local/bin/dev_container_start.sh

CMD ["/usr/local/bin/dev_container_start.sh"]
