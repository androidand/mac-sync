#!/usr/bin/env bash
set -euo pipefail

# Install dotfiles as symlinks into $HOME.
# Idempotent: re-running is safe. Existing real files are backed up once.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.dotfiles-backup/$STAMP"

link() {
	local src="$1"
	local dst="$2"

	if [[ ! -e "$src" ]]; then
		echo "  skip   $dst (source $src does not exist)"
		return
	fi

	if [[ -L "$dst" ]]; then
		local current
		current="$(readlink "$dst")"
		if [[ "$current" == "$src" ]]; then
			echo "  ok     $dst -> $src"
			return
		fi
		echo "  relink $dst (was -> $current)"
		rm "$dst"
	elif [[ -e "$dst" ]]; then
		mkdir -p "$BACKUP"
		local rel="${dst#$HOME/}"
		mkdir -p "$(dirname "$BACKUP/$rel")"
		mv "$dst" "$BACKUP/$rel"
		echo "  backup $dst -> $BACKUP/$rel"
	fi

	mkdir -p "$(dirname "$dst")"
	ln -s "$src" "$dst"
	echo "  link   $dst -> $src"
}

echo "==> Symlinking Claude Code config"
link "$HERE/claude" "$HOME/.claude"

echo "==> Symlinking OpenCode config"
link "$HERE/opencode" "$HOME/.config/opencode"

echo "==> Symlinking shell dotfiles"
for f in .zshrc .zprofile .zshenv .bashrc .bash_profile .profile .aliases .exports .functions; do
	if [[ -f "$HERE/shell/$f" ]]; then
		link "$HERE/shell/$f" "$HOME/$f"
	fi
done

if [[ -d "$BACKUP" ]]; then
	echo
	echo "==> Original files backed up to: $BACKUP"
fi

echo
echo "==> Done. Reload your shell: exec \$SHELL -l"
