#!/usr/bin/env bash
set -euo pipefail

# Sync ~/.ssh between Macs over rsync. Private keys stay off any git remote.
# Usage:
#   ./04-sync-ssh-folder.sh push user@peer.local     # push THIS ~/.ssh to peer
#   ./04-sync-ssh-folder.sh pull user@peer.local     # pull peer's ~/.ssh to here
#
# known_hosts is merged (both sides' entries), not overwritten, so you don't
# lose host fingerprints you've already accepted.
#
# authorized_keys is also merged rather than overwritten.

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 (push|pull) user@peer.hostname" >&2
	exit 2
fi

DIR="$1"
PEER="$2"
LOCAL="$HOME/.ssh/"

case "$DIR" in
	push)
		SRC="$LOCAL"
		DST="$PEER:~/.ssh/"
		;;
	pull)
		SRC="$PEER:~/.ssh/"
		DST="$LOCAL"
		;;
	*)
		echo "First arg must be 'push' or 'pull'." >&2
		exit 2
		;;
esac

echo "==> Syncing $SRC -> $DST"
echo "    (known_hosts and authorized_keys are merged, not replaced)"

# Stage 1: mirror everything EXCEPT the merge-sensitive files.
rsync -avh --chmod=D700,F600 \
	--exclude 'known_hosts' \
	--exclude 'known_hosts.old' \
	--exclude 'authorized_keys' \
	"$SRC" "$DST"

merge_remote() {
	local file="$1"
	case "$DIR" in
		push)
			ssh "$PEER" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/$file && chmod 600 ~/.ssh/$file"
			if [[ -f "$HOME/.ssh/$file" ]]; then
				ssh "$PEER" "tmp=\$(mktemp ~/.ssh/.${file}.XXXXXX) && cat > \"\$tmp\" && sort -u ~/.ssh/$file \"\$tmp\" -o ~/.ssh/$file && chmod 600 ~/.ssh/$file && rm -f \"\$tmp\"" \
					< "$HOME/.ssh/$file"
			fi
			;;
		pull)
			local tmp
			tmp="$(mktemp)"
			ssh "$PEER" "cat ~/.ssh/$file 2>/dev/null || true" > "$tmp"
			mkdir -p "$HOME/.ssh"
			chmod 700 "$HOME/.ssh"
			touch "$HOME/.ssh/$file"
			chmod 600 "$HOME/.ssh/$file"
			sort -u "$HOME/.ssh/$file" "$tmp" -o "$HOME/.ssh/$file"
			rm -f "$tmp"
			;;
	esac
}

echo "==> Merging known_hosts..."
merge_remote known_hosts

echo "==> Merging authorized_keys..."
merge_remote authorized_keys

echo "==> Done. Verify with: ssh -G $PEER | head"
