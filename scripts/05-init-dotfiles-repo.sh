#!/usr/bin/env bash
set -euo pipefail

# Initialize the dotfiles/ folder as a git repo and stage an initial commit.
# Does NOT push anywhere — you point it at your own remote afterwards.
#
# Run this on the Mac you consider the initial source of truth.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE/dotfiles"

if [[ ! -d .git ]]; then
	git init -b main
fi

git add .
git commit -m "Initial dotfiles import" || echo "==> Nothing to commit."

echo
echo "==> Next steps:"
echo "  1. Create a PRIVATE repo on GitHub / your git host (e.g. 'dotfiles')."
echo "  2. git remote add origin git@github.com:<you>/dotfiles.git"
echo "  3. git push -u origin main"
echo
echo "On the OTHER Mac:"
echo "  git clone git@github.com:<you>/dotfiles.git ~/dotfiles"
echo "  cd ~/dotfiles && ./bootstrap.sh"
