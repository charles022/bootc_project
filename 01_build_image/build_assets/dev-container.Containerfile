# Use NVIDIA's PyTorch image as the dev container base.
FROM nvcr.io/nvidia/pytorch:26.03-py3

# Install only the minimum extra packages we need.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
       bash \
       procps \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /workspace /usr/local/share/dev-container

COPY dev_container_start.sh /usr/local/bin/dev_container_start.sh
COPY dev_container_test.py /usr/local/share/dev-container/dev_container_test.py

RUN chmod 0755 /usr/local/bin/dev_container_start.sh

CMD ["/usr/local/bin/dev_container_start.sh"]
