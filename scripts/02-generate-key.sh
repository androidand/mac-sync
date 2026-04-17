#!/usr/bin/env bash
set -euo pipefail

# Generate an ed25519 SSH keypair if one does not already exist.
# Run on both Macs. Safe to re-run: will not overwrite.

KEY="$HOME/.ssh/id_ed25519"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$KEY" ]]; then
	echo "==> Key already exists at $KEY — skipping generation."
else
	echo "==> Generating ed25519 keypair at $KEY"
	ssh-keygen -t ed25519 -a 100 -f "$KEY" -C "$USER@$(scutil --get LocalHostName 2>/dev/null || hostname)"
fi

echo
echo "==> Public key (copy this to the other Mac's authorized_keys):"
echo
cat "${KEY}.pub"
