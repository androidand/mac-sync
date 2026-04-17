#!/usr/bin/env bash
set -euo pipefail

# True two-way sync of ~/.ssh between this Mac and a peer.
# Additive only — never deletes from either side. Private/public keys
# (id_*) are per-machine identities and are NEVER synced.
#
# Pipeline:
#   1. Pull peer's ~/.ssh into a local staging dir (excludes id_* and
#      per-machine state).
#   2. Interactive, type-aware merge into THIS Mac's ~/.ssh:
#        - authorized_keys, known_hosts  → line-union (sort -u)
#        - config                        → diff3 3-way merge, editor on conflict
#        - anything else                 → additive + prompt on conflict
#   3. (Optional) Push merged result back to peer so they also get the union.
#        - authorized_keys, known_hosts  → pushed unconditionally (supersets)
#        - everything else               → rsync --update, never --delete
#
# Usage:
#   ./scripts/04-sync-ssh-folder.sh user@peer.hostname

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 user@peer.hostname" >&2
	exit 2
fi

PEER="$1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/lib/merge.sh"
LOCAL="$HOME/.ssh"
STAGE="$(mktemp -d -t ssh-peer.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

# shellcheck source=lib/merge.sh
. "$LIB"

mkdir -p "$LOCAL"
chmod 700 "$LOCAL"

EXCLUDES=(
	--exclude 'id_*'
	--exclude '*.pub'
	--exclude 'known_hosts.old'
	--exclude 'agent.sock'
	--exclude 'ssh-agent.sock'
	--exclude '.DS_Store'
)

echo "==> Pulling $PEER:~/.ssh into staging (excludes: id_*, *.pub, sockets)"
rsync -a --chmod=D700,F600 "${EXCLUDES[@]}" \
	"$PEER:.ssh/" "$STAGE/"

echo
echo "==> Merging staged peer ~/.ssh into local ~/.ssh (additive, prompts on conflict)…"
merge_dirs "$STAGE" "$LOCAL" ssh

# Tighten perms after merge — merge_dirs doesn't re-apply them.
chmod 700 "$LOCAL"
find "$LOCAL" -maxdepth 1 -type f -exec chmod 600 {} \;

echo
echo "==> Local merge done."
echo

read -r -p "Push merged result back to $PEER:~/.ssh now? [y/N] " ans </dev/tty || ans=N
if [[ ! "$ans" =~ ^[yY]$ ]]; then
	echo "==> Skipped push. Peer keeps its current files."
	echo "    (Run this script from the peer too, with THIS host as argument,"
	echo "     to converge both sides.)"
	exit 0
fi

# authorized_keys and known_hosts on local are now guaranteed supersets of
# what the peer had. Push them unconditionally so peer gets the union.
for f in authorized_keys known_hosts; do
	if [[ -f "$LOCAL/$f" ]]; then
		echo "==> Pushing merged $f → $PEER:~/.ssh/$f (superset, unconditional)"
		rsync -a --chmod=D700,F600 "$LOCAL/$f" "$PEER:.ssh/$f"
	fi
done

# Everything else: push with --update so we never clobber a file the peer
# touched more recently than us.
echo "==> Pushing other ~/.ssh files → $PEER:~/.ssh (--update, no --delete, excludes id_*)"
rsync -a --update --chmod=D700,F600 "${EXCLUDES[@]}" \
	--exclude 'authorized_keys' \
	--exclude 'known_hosts' \
	"$LOCAL/" "$PEER:.ssh/"

echo
echo "==> Done. Private keys were not touched on either side."
echo "    Verify with: ssh -G $PEER | head"
