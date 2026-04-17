#!/usr/bin/env bash
set -euo pipefail

# Enable Remote Login (sshd) on macOS.
# LEAVES password auth enabled on purpose — needed to bootstrap key exchange.
# Password auth is disabled later by 06-lockdown-key-only.sh, once keys are
# authorized on both Macs.
#
# Run on BOTH Macs. Requires sudo.

if [[ "$(uname)" != "Darwin" ]]; then
	echo "This script is macOS-only." >&2
	exit 1
fi

echo "==> Enabling Remote Login (sshd)..."
sudo systemsetup -setremotelogin on

echo "==> Starting sshd (launchd)..."
sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true

echo
echo "==> SSH is enabled with default auth (password + key). Connection details:"
echo "    hostname : $(scutil --get LocalHostName 2>/dev/null || hostname).local"
echo "    user     : $USER"
echo "    LAN IPs  :"
ipconfig getifaddr en0 2>/dev/null | sed 's/^/      en0 /' || true
ipconfig getifaddr en1 2>/dev/null | sed 's/^/      en1 /' || true

echo
echo "Next: run 02-generate-key.sh on each Mac, then 03-authorize-peer.sh."
echo "Do NOT run 06-lockdown-key-only.sh until you've confirmed key login works."
