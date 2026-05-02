# WhatsApp messaging-bridge sidecar - PLANNED Phase-5 stub.
# Ships so --messaging whatsapp renders a valid Quadlet today; produces no
# real traffic. Real implementation needs a Meta Business webhook receiver
# behind a cloudflared `messaging-webhook` ingress route (Phase 5).
# See docs/concepts/messaging_interface.md "WhatsApp (planned)".
FROM registry.fedoraproject.org/fedora:42

RUN dnf -y install python3 \
    && dnf clean all

COPY messaging-bridge-whatsapp.py /usr/local/bin/messaging-bridge-whatsapp
RUN chmod 0755 /usr/local/bin/messaging-bridge-whatsapp

CMD ["/usr/local/bin/messaging-bridge-whatsapp"]
