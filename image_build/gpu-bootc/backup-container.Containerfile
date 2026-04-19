# Use a small Fedora base for the backup sidecar. # backup sidecar base
FROM registry.fedoraproject.org/fedora:42 # Fedora userspace base image

# Install only the minimal tools needed for the placeholder sidecar. # backup package install
RUN dnf -y install \ # begin package install
    bash \ # provide shell
    coreutils \ # provide standard tools
    && dnf clean all # clean package metadata

# Create a workspace directory for future backup logic. # backup filesystem setup
RUN mkdir -p /workspace # workspace directory

# Copy the placeholder backup script into the image. # backup runtime file
COPY backup_stub.sh /usr/local/bin/backup_stub.sh # backup stub path

# Make the backup script executable. # backup script permissions
RUN chmod 0755 /usr/local/bin/backup_stub.sh # executable backup stub

# Start the placeholder backup script when the container starts. # backup startup command
CMD ["/usr/local/bin/backup_stub.sh"] # backup container runtime command
