#!/usr/bin/env bash
set -euo pipefail

# Add the peer Mac's public key to this Mac's ~/.ssh/authorized_keys.
# Usage:
#   ./03-authorize-peer.sh user@peer.local
#
# This will:
#   1. Pull the peer's id_ed25519.pub over SSH (you'll be prompted for the
#      peer's macOS password ONCE, since key-only is not yet bootstrapped).
#   2. Append it to ~/.ssh/authorized_keys on THIS Mac.
#
# Run this on EACH Mac, pointing at the other one.

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 user@peer.hostname" >&2
	exit 2
fi

PEER="$1"
AUTH="$HOME/.ssh/authorized_keys"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$AUTH"
chmod 600 "$AUTH"

echo "==> Fetching public key from $PEER..."
PEER_PUB="$(ssh -o PreferredAuthentications=password,keyboard-interactive,publickey \
	"$PEER" 'cat ~/.ssh/id_ed25519.pub')"

if grep -qxF "$PEER_PUB" "$AUTH"; then
	echo "==> Peer key already authorized — nothing to do."
else
	echo "$PEER_PUB" >> "$AUTH"
	echo "==> Appended peer key to $AUTH"
fi

echo
echo "==> Test from the peer:"
echo "    ssh $USER@$(scutil --get LocalHostName 2>/dev/null || hostname).local"
