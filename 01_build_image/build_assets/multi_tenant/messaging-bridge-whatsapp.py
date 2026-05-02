#!/usr/bin/env python3
# messaging-bridge-whatsapp - PLANNED stub for Phase 4.
#
# Real implementation needs a Meta Business webhook receiver behind a
# cloudflared `messaging-webhook` ingress route exposing this container's
# HTTP listener at a stable per-tenant hostname. That ingress wiring is
# Phase 5; today the bridge ships as a placeholder so the Quadlet template
# renders without errors when an admin selects --messaging whatsapp.
#
# See docs/concepts/messaging_interface.md "WhatsApp (planned)" for the
# design notes.

import os
import sys
import time

TENANT = os.environ.get("OPENCLAW_TENANT", "")
AGENT = os.environ.get("OPENCLAW_AGENT", "")


def main():
    print("messaging-bridge-whatsapp: (planned) running as stub", flush=True)
    print(f"messaging-bridge-whatsapp: tenant={TENANT} agent={AGENT}", flush=True)
    print("messaging-bridge-whatsapp: real implementation requires Meta Business webhook ingress; see docs/concepts/messaging_interface.md", flush=True)
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
