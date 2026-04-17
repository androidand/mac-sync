#!/usr/bin/env bash
set -euo pipefail

# Import configs from the CURRENT $HOME into this dotfiles repo.
# Run this ONCE on the Mac that has the canonical configs, review the diff,
# then commit + push.
#
# Uses rsync with --exclude patterns that mirror .gitignore so secrets and
# ephemeral state are left behind.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() { echo "+ $*"; "$@"; }

if [[ -d "$HOME/.claude" ]]; then
	echo "==> Importing ~/.claude -> claude/"
	run rsync -a --delete \
		--exclude 'projects/' \
		--exclude 'todos/' \
		--exclude 'shell-snapshots/' \
		--exclude 'statsig/' \
		--exclude 'ide/' \
		--exclude 'history.jsonl' \
		--exclude 'logs/' \
		--exclude 'caches/' \
		--exclude '__store.db*' \
		--exclude '.credentials.json' \
		--exclude 'credentials.json' \
		--exclude '*.token' \
		--exclude '*.key' \
		"$HOME/.claude/" "$HERE/claude/"
fi

if [[ -d "$HOME/.config/opencode" ]]; then
	echo "==> Importing ~/.config/opencode -> opencode/"
	run rsync -a --delete \
		--exclude 'auth.json' \
		"$HOME/.config/opencode/" "$HERE/opencode/"
fi

echo "==> Importing shell dotfiles -> shell/"
mkdir -p "$HERE/shell"
for f in .zshrc .zprofile .zshenv .bashrc .bash_profile .profile .aliases .exports .functions; do
	if [[ -f "$HOME/$f" ]]; then
		run cp "$HOME/$f" "$HERE/shell/$f"
	fi
done

echo
echo "==> Done. Review with:"
echo "    cd $HERE/.. && git status && git diff --stat"
