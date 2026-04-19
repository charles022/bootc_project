# Use a small Fedora base for the backup sidecar.
FROM registry.fedoraproject.org/fedora:42

# Install only the minimal tools needed for the placeholder sidecar.
RUN dnf -y install \
    bash \
    coreutils \
    && dnf clean all

# Create a workspace directory for future backup logic.
RUN mkdir -p /workspace

# Copy the placeholder backup script into the image.
COPY backup_stub.sh /usr/local/bin/backup_stub.sh

# Make the backup script executable.
RUN chmod 0755 /usr/local/bin/backup_stub.sh

# Start the placeholder backup script when the container starts.
CMD ["/usr/local/bin/backup_stub.sh"]
