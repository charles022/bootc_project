# Use NVIDIA's PyTorch image as the dev container base.
FROM nvcr.io/nvidia/pytorch:26.03-py3

# Install only the minimum extra packages we need.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
       bash \
       procps \
    && rm -rf /var/lib/apt/lists/*

# Create the working directory used by the dev container.
RUN mkdir -p /workspace

# Copy the dev startup wrapper and startup test into the image.
COPY dev_container_start.sh /usr/local/bin/dev_container_start.sh
COPY dev_container_test.py /workspace/dev_container_test.py

# Make the startup wrapper executable.
RUN chmod 0755 /usr/local/bin/dev_container_start.sh

# Start the wrapper when the container starts.
CMD ["/usr/local/bin/dev_container_start.sh"]
