# Use NVIDIA's PyTorch image as the dev container base. # dev container base
FROM nvcr.io/nvidia/pytorch:26.03-py3 # GPU-capable PyTorch base image

# Install only the minimum extra packages we need. # dev package install
RUN apt-get update \ # refresh apt metadata
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \ # install packages without prompts
       bash \ # provide shell for interactive use
       procps \ # provide ps and related tools
    && rm -rf /var/lib/apt/lists/* # clean apt metadata

# Create the working directory used by the dev container. # dev filesystem setup
RUN mkdir -p /workspace # workspace directory

# Copy the dev startup wrapper and startup test into the image. # dev runtime files
COPY dev_container_start.sh /usr/local/bin/dev_container_start.sh # startup wrapper
COPY dev_container_test.py /workspace/dev_container_test.py # startup test script

# Make the startup wrapper executable. # dev script permissions
RUN chmod 0755 /usr/local/bin/dev_container_start.sh # executable startup wrapper

# Start the wrapper when the container starts. # dev startup command
CMD ["/usr/local/bin/dev_container_start.sh"] # container runtime command
