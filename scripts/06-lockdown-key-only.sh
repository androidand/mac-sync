#!/usr/bin/env bash
set -euo pipefail

# Disable password / keyboard-interactive SSH auth. Key-only from here on.
# Run on BOTH Macs, but ONLY after 03-authorize-peer.sh has succeeded in
# BOTH directions and you've confirmed you can ssh in with just a key.
#
# Reversible: delete /etc/ssh/sshd_config.d/100-no-password.conf and reload sshd.

if [[ "$(uname)" != "Darwin" ]]; then
	echo "This script is macOS-only." >&2
	exit 1
fi

DROPIN=/etc/ssh/sshd_config.d/100-no-password.conf

echo "==> Safety check: can this host resolve its own authorized_keys?"
if [[ ! -s "$HOME/.ssh/authorized_keys" ]]; then
	echo "ERROR: $HOME/.ssh/authorized_keys is empty or missing." >&2
	echo "       Locking down now would leave you unable to SSH in." >&2
	exit 1
fi

echo "==> Verifying sshd_config reads drop-ins..."
if ! sudo grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
	echo "    Adding 'Include /etc/ssh/sshd_config.d/*.conf' to /etc/ssh/sshd_config"
	echo 'Include /etc/ssh/sshd_config.d/*.conf' | sudo tee -a /etc/ssh/sshd_config >/dev/null
fi

echo "==> Writing $DROPIN"
sudo tee "$DROPIN" >/dev/null <<'CONF'
# Managed by mac-sync/scripts/06-lockdown-key-only.sh
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
PubkeyAuthentication yes
PermitRootLogin no
CONF

echo "==> Validating sshd config..."
sudo /usr/sbin/sshd -t

echo "==> Reloading sshd..."
sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist

echo
echo "==> Done. Password SSH auth is now disabled on this Mac."
echo "    To revert: sudo rm $DROPIN && sudo launchctl kickstart -k system/com.openssh.sshd"
