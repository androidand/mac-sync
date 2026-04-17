#!/usr/bin/env bash
set -euo pipefail

# Two-way safe import from the CURRENT $HOME into this dotfiles repo.
# Additive only — never deletes anything from dotfiles/. Conflicts are
# prompted file-by-file. Designed so you can run it on EITHER Mac at any
# time: each Mac contributes its unique files; conflicts ask before changing.
#
# Workflow when both Macs have pre-existing configs:
#   Mac A:  ./pull-from-home.sh   →  git add . && git commit && git push
#   Mac B:  git pull
#           ./pull-from-home.sh   →  resolve conflicts on the few overlaps
#                                    (peer's contributions are already there)
#                                    git add . && git commit && git push
#   Mac A:  git pull              ← both Macs now have the union

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../scripts/lib/merge.sh"

if [[ ! -f "$LIB" ]]; then
	echo "Missing $LIB. Did you clone the full repo?" >&2
	exit 1
fi
# shellcheck source=../scripts/lib/merge.sh
. "$LIB"

# ----------------------------------------------------------------------------
# Stage each source into a tmp dir with the same exclusions used by the rest
# of the pipeline, then call merge_dirs.
# ----------------------------------------------------------------------------

stage="$(mktemp -d -t pull-from-home.XXXXXX)"
trap 'rm -rf "$stage"' EXIT

if [[ -d "$HOME/.claude" ]]; then
	echo "==> Staging ~/.claude (excluding ephemeral state and credentials)…"
	rsync -a \
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
		"$HOME/.claude/" "$stage/claude/"
	echo "==> Merging staged claude into dotfiles/claude (additive, prompts on conflicts)…"
	merge_dirs "$stage/claude" "$HERE/claude" claude
fi

if [[ -d "$HOME/.config/opencode" ]]; then
	echo "==> Staging ~/.config/opencode (excluding artifacts and secrets)…"
	rsync -a \
		--exclude 'auth.json' \
		--exclude 'node_modules/' \
		--exclude 'package.json' \
		--exclude 'package-lock.json' \
		--exclude 'bun.lock' \
		--exclude '.gitignore' \
		"$HOME/.config/opencode/" "$stage/opencode/"
	echo "==> Merging staged opencode into dotfiles/opencode…"
	merge_dirs "$stage/opencode" "$HERE/opencode" opencode
fi

echo "==> Staging shell dotfiles…"
mkdir -p "$stage/shell"
for f in .zshrc .zprofile .zshenv .bashrc .bash_profile .profile .aliases .exports .functions; do
	if [[ -f "$HOME/$f" ]]; then
		cp -p "$HOME/$f" "$stage/shell/$f"
	fi
done
echo "==> Merging staged shell into dotfiles/shell…"
merge_dirs "$stage/shell" "$HERE/shell" shell

echo
echo "==> Done. Review with:"
echo "    cd $HERE/.. && git status && git diff --stat"
echo "    git add . && git commit -m 'Import additions from $(scutil --get LocalHostName 2>/dev/null || hostname)' && git push"
