#!/usr/bin/env bash
# Install a sudoers.d entry that lets the iphonebridge user daemon set the
# adapter CoD without prompting for a password — but only for that one
# specific btmgmt invocation.
#
# Run as root: sudo bash systemd/install-cod-sudoers.sh
set -euo pipefail

DST=/etc/sudoers.d/iphonebridge-cod

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2; exit 1
fi

USER_TO_GRANT="${SUDO_USER:-}"
if [[ -z "$USER_TO_GRANT" || "$USER_TO_GRANT" == "root" ]]; then
    echo "Could not determine non-root user to grant. Run via sudo." >&2
    exit 1
fi
if ! id "$USER_TO_GRANT" >/dev/null 2>&1; then
    echo "User does not exist: $USER_TO_GRANT" >&2
    exit 1
fi

BTMGMT="$(command -v btmgmt || true)"
if [[ -z "$BTMGMT" ]]; then
    echo "btmgmt not found. Install the bluez package first." >&2
    exit 1
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
# Allow the iphonebridge user daemon to set the adapter CoD without a
# password prompt. No other btmgmt invocation is permitted by this rule.
$USER_TO_GRANT ALL=(root) NOPASSWD: $BTMGMT class 4 8
EOF

# Validate before installing — bad sudoers files can lock you out.
if ! visudo -cf "$TMP" >/dev/null; then
    echo "FATAL: generated sudoers entry failed validation. Not installing." >&2
    exit 1
fi

install -m 440 -o root -g root "$TMP" "$DST"
echo "[+] Installed $DST for $USER_TO_GRANT"

# Quick verification
if visudo -cf "$DST" >/dev/null; then
    echo "[+] visudo says $DST is valid"
else
    echo "[!] $DST failed validation post-install — removing"
    rm -f "$DST"
    exit 1
fi

cat <<EOF

[+] The iphonebridge user daemon can now run 'btmgmt class 4 8' without
    a password. On each daemon start (e.g. boot, login), it will set
    the adapter to A/V Hands-Free CoD automatically.

    Verify by restarting the daemon:
      systemctl --user restart iphonebridge

    Then check journalctl --user -u iphonebridge for a 'CoD set ok' line.

    Uninstall:
      sudo rm $DST
EOF
