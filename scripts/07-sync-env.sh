#!/usr/bin/env bash
set -euo pipefail

# Interactive env-var sync between Macs.
#
# Source of truth: $HOME/.config/mac-sync/env.sh  (one "export KEY=VALUE" per line)
# Mode 600, never committed to git (it holds secrets).
#
# Usage:
#   ./07-sync-env.sh push user@peer.local   # send this Mac's env to peer
#   ./07-sync-env.sh pull user@peer.local   # fetch peer's env to here
#
# For every variable in the source file that is ALSO already populated on the
# receiving side with a different value, the script pauses and asks. Values
# are masked in prompts (first 4 chars + last 2 chars, everything in between
# shown as `…`) so secrets don't appear in your terminal scrollback.
#
# You can always choose (s)how to see the full values before answering y/N.

ENV_FILE="$HOME/.config/mac-sync/env.sh"

usage() {
	cat >&2 <<EOF
Usage: $0 (push|pull) user@peer.hostname

  push   Send this Mac's env to the peer.  Prompts about peer-populated vars.
  pull   Fetch the peer's env to this Mac. Prompts about locally-populated vars.

Env file: $ENV_FILE  (one 'export KEY=VALUE' per line)
EOF
	exit 2
}

[[ $# -eq 2 ]] || usage
DIR="$1"
PEER="$2"
case "$DIR" in push|pull) ;; *) usage ;; esac

mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

PEER_FILE="$(mktemp)"
MERGED="$(mktemp)"
TARGET_KV="$(mktemp)"
trap 'rm -f "$PEER_FILE" "$MERGED" "$TARGET_KV" "$MERGED.new" 2>/dev/null || true' EXIT

echo "==> Fetching $ENV_FILE from $PEER..."
ssh "$PEER" "mkdir -p \"\$(dirname '$ENV_FILE')\" && touch '$ENV_FILE' && chmod 600 '$ENV_FILE' && cat '$ENV_FILE'" \
	> "$PEER_FILE"

case "$DIR" in
	push) SOURCE="$ENV_FILE"; TARGET="$PEER_FILE"; TARGET_NAME="peer"  ;;
	pull) SOURCE="$PEER_FILE"; TARGET="$ENV_FILE"; TARGET_NAME="local" ;;
esac

extract() {
	awk '
		/^[[:space:]]*#/  { next }
		/^[[:space:]]*$/  { next }
		{
			sub(/^[[:space:]]*export[[:space:]]+/, "")
			p = index($0, "=")
			if (p < 2) next
			key = substr($0, 1, p - 1)
			val = substr($0, p + 1)
			sub(/[[:space:]]+$/, "", val)
			if (match(val, /^".*"$/) || match(val, /^\x27.*\x27$/)) {
				val = substr(val, 2, length(val) - 2)
			}
			print key "\t" val
		}
	' "$1"
}

mask() {
	local v="$1"
	local n=${#v}
	if (( n == 0 )); then printf '(empty)'; return; fi
	if (( n <= 8 )); then printf '********'; return; fi
	printf '%s…%s' "${v:0:4}" "${v: -2}"
}

extract "$TARGET" > "$TARGET_KV"

has_target_key()    { awk -F'\t' -v k="$1" '$1 == k { found=1; exit } END { exit !found }' "$TARGET_KV"; }
get_target_value()  { awk -F'\t' -v k="$1" 'BEGIN{OFS=FS} $1 == k { $1=""; sub(/^\t/, ""); print; exit }' "$TARGET_KV"; }

cp "$TARGET" "$MERGED"

added=0 updated=0 kept=0 unchanged=0

while IFS=$'\t' read -r key val; do
	[[ -z "$key" ]] && continue

	if ! has_target_key "$key"; then
		printf 'export %s=%q\n' "$key" "$val" >> "$MERGED"
		echo "  + $key  (added to $TARGET_NAME)"
		added=$((added + 1))
		continue
	fi

	target_val="$(get_target_value "$key")"
	if [[ "$target_val" == "$val" ]]; then
		unchanged=$((unchanged + 1))
		continue
	fi

	echo
	echo "  ? $key is populated on $TARGET_NAME with a different value"
	echo "      incoming: $(mask "$val")"
	echo "      $TARGET_NAME:     $(mask "$target_val")"
	while :; do
		printf '    Overwrite %s? [y/N/s=show full values] ' "$TARGET_NAME"
		read -r answer </dev/tty
		case "$answer" in
			y|Y)
				grep -vE "^[[:space:]]*(export[[:space:]]+)?${key}=" "$MERGED" > "${MERGED}.new"
				mv "${MERGED}.new" "$MERGED"
				printf 'export %s=%q\n' "$key" "$val" >> "$MERGED"
				updated=$((updated + 1))
				echo "      → overwrote"
				break
				;;
			s|S)
				echo "      incoming full: $val"
				echo "      $TARGET_NAME full:     $target_val"
				;;
			*)
				kept=$((kept + 1))
				echo "      → kept $TARGET_NAME value"
				break
				;;
		esac
	done
done < <(extract "$SOURCE")

echo
echo "==> Summary: added=$added  updated=$updated  kept=$kept  unchanged=$unchanged"
echo
echo "==> Diff vs current $TARGET_NAME file:"
diff -u "$TARGET" "$MERGED" || true
echo

printf 'Apply to %s? [y/N] ' "$TARGET_NAME"
read -r answer </dev/tty
if [[ ! "$answer" =~ ^[yY]$ ]]; then
	echo "Aborted. No changes written."
	exit 0
fi

case "$DIR" in
	push)
		scp -q "$MERGED" "$PEER:$ENV_FILE.new"
		ssh "$PEER" "chmod 600 '$ENV_FILE.new' && mv '$ENV_FILE.new' '$ENV_FILE'"
		echo "==> Wrote $PEER:$ENV_FILE"
		;;
	pull)
		cp "$MERGED" "$ENV_FILE"
		chmod 600 "$ENV_FILE"
		echo "==> Wrote $ENV_FILE"
		;;
esac

echo
echo "To load in the current shell:  source $ENV_FILE"
echo "To auto-load in every shell, add to ~/.zshenv:"
echo "    [ -r $ENV_FILE ] && . $ENV_FILE"
