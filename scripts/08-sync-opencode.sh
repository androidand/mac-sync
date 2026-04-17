#!/usr/bin/env bash
set -euo pipefail

# True two-way sync of ~/.config/opencode between this Mac and a peer.
# Additive only — never deletes from either side. Conflicts are prompted
# per file.
#
# Pipeline:
#   1. Pull peer's ~/.config/opencode into a local staging dir
#      (excludes secrets / build artifacts).
#   2. Interactive merge into THIS clone of dotfiles/opencode.
#   3. (Optional) Push merged result back to peer's ~/.config/opencode
#      with --update so we never overwrite a newer file on the peer.
#
# After the script runs, commit the local dotfiles/opencode change and push,
# so any third Mac can also pick it up via git pull.
#
# Usage:
#   ./scripts/08-sync-opencode.sh user@peer.local

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 user@peer.hostname" >&2
	exit 2
fi

PEER="$1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL="$HERE/dotfiles/opencode"
LIB="$HERE/scripts/lib/merge.sh"
STAGE="$(mktemp -d -t opencode-peer.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

# shellcheck source=lib/merge.sh
. "$LIB"

mkdir -p "$LOCAL"

echo "==> Pulling $PEER:.config/opencode into staging (excludes: secrets, node_modules, npm artifacts)"
rsync -a \
	--exclude 'auth.json' \
	--exclude 'node_modules/' \
	--exclude 'package.json' \
	--exclude 'package-lock.json' \
	--exclude 'bun.lock' \
	--exclude '.gitignore' \
	"$PEER:.config/opencode/" "$STAGE/"

echo
echo "==> Merging staged peer config into dotfiles/opencode (additive, never deletes)…"
merge_dirs "$STAGE" "$LOCAL" opencode

echo
echo "==> Local merge done. Review with: cd $HERE && git diff dotfiles/opencode"
echo

read -r -p "Push merged result back to $PEER:.config/opencode now? [y/N] " ans </dev/tty || ans=N
if [[ "$ans" =~ ^[yY]$ ]]; then
	echo "==> Pushing dotfiles/opencode → $PEER:.config/opencode (--update, no --delete)"
	# --update: skip files where the peer's mtime is newer
	# no --delete: peer-only files are LEFT INTACT
	rsync -av --update \
		--exclude 'auth.json' \
		--exclude 'node_modules/' \
		--exclude 'package.json' \
		--exclude 'package-lock.json' \
		--exclude 'bun.lock' \
		--exclude '.gitignore' \
		"$LOCAL/" "$PEER:.config/opencode/"
	echo "==> Pushed."
else
	echo "==> Skipped push. Peer keeps its current files."
fi

echo
echo "Next:"
echo "  cd $HERE"
echo "  git add dotfiles/opencode"
echo "  git commit -m 'Two-way merge opencode with $PEER'"
echo "  git push"
