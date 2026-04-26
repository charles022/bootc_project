# /etc/profile.d/bootc-update-nudge.sh
# Notify interactive shells that a bootc deployment is staged and
# waiting for a manual reboot. Cleared automatically once the new
# deployment boots (bootc-firstboot-push.service deletes the marker).
if [ -f /var/lib/bootc-update/pending ]; then
    cat <<'EOF'
A new bootc deployment is staged and waiting for reboot.
  Reboot now:    sudo systemctl reboot
  Publish this image to Quay on its first successful boot:
    edit /etc/bootc-update/reboot.env and set push_to_quay=TRUE
EOF
fi
