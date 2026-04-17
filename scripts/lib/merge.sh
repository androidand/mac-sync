#!/usr/bin/env bash
# Type-aware, additive, two-way merge primitives.
#
# merge_dirs SRC DST [LABEL]
#   For every file under SRC+DST:
#     - only in SRC → copy to DST
#     - only in DST → leave alone
#     - in both, identical → no-op
#     - in both, differ → dispatched on path/ext:
#         *.json                  → merge_json (deep-merge via jq)
#         authorized_keys|known_hosts → merge_line_union (sort -u)
#         anything else           → merge_text (editor with conflict markers)
#
# Never deletes. All conflicts produce a single merged file.
# Prompts read from /dev/tty.

_need() {
	command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; return 1; }
}

merge_line_union() {
	local src="$1" dst="$2"
	local tmp
	tmp="$(mktemp)"
	# union, sorted, dedup, preserves comments and blanks stripped only if duplicate
	sort -u "$src" "$dst" > "$tmp"
	mv "$tmp" "$dst"
}

merge_json() {
	local src="$1" dst="$2"
	_need jq || return 1

	# Recursive deep merge:
	#   - objects: recurse, union keys
	#   - arrays: union, dedup (order preserved by appearance)
	#   - scalars: if equal → keep; if not → collect conflict
	# We implement this with a jq program that emits BOTH a merged value
	# and a list of conflict paths. On conflicts, we prompt once per path.

	local prog='
		def deepmerge($a; $b; $path):
			if ($a | type) == "object" and ($b | type) == "object" then
				( ($a | keys) + ($b | keys) | unique ) as $ks
				| reduce $ks[] as $k (
					{merged: {}, conflicts: []};
					(deepmerge($a[$k] // null; $b[$k] // null; $path + [$k])) as $r
					| .merged[$k] = $r.merged
					| .conflicts += $r.conflicts
				)
			elif ($a | type) == "array" and ($b | type) == "array" then
				{ merged: ($a + $b | unique), conflicts: [] }
			elif $a == null then
				{ merged: $b, conflicts: [] }
			elif $b == null then
				{ merged: $a, conflicts: [] }
			elif $a == $b then
				{ merged: $a, conflicts: [] }
			else
				{ merged: $b, conflicts: [{path: $path, a: $a, b: $b}] }
			end;
		deepmerge($a[0]; $b[0]; [])
	'

	local merged_json
	merged_json="$(jq -n --slurpfile a "$dst" --slurpfile b "$src" "$prog" \
		| jq -c '.' 2>/dev/null)" || { echo "    jq deep-merge failed"; return 1; }

	# Extract merged tree and conflicts
	local merged_tree conflicts_json
	merged_tree="$(printf '%s' "$merged_json" | jq '.merged')"
	conflicts_json="$(printf '%s' "$merged_json" | jq -c '.conflicts')"

	local nconflicts
	nconflicts="$(printf '%s' "$conflicts_json" | jq 'length')"

	if (( nconflicts > 0 )); then
		echo "    $nconflicts leaf value conflict(s) in this JSON:"
		local i
		for ((i=0; i<nconflicts; i++)); do
			local path a b
			path="$(printf '%s' "$conflicts_json" | jq -r ".[$i].path | map(if type==\"number\" then \"[\\(.)]\" else \".\\(.)\" end) | join(\"\")")"
			path=".${path#.}"
			a="$(printf '%s' "$conflicts_json" | jq -c ".[$i].a")"
			b="$(printf '%s' "$conflicts_json" | jq -c ".[$i].b")"
			echo "      $path"
			echo "        dst: $a"
			echo "        src: $b"
			local ans
			printf '      Take (d)st / (s)rc [d] ' >&2
			read -r ans </dev/tty || ans=d
			case "$ans" in
				s|S)
					merged_tree="$(printf '%s' "$merged_tree" | jq --argjson v "$b" "setpath($(printf '%s' "$conflicts_json" | jq ".[$i].path"); \$v)")"
					;;
				*) # keep dst: overwrite merged value (currently holds src by default)
					merged_tree="$(printf '%s' "$merged_tree" | jq --argjson v "$a" "setpath($(printf '%s' "$conflicts_json" | jq ".[$i].path"); \$v)")"
					;;
			esac
		done
	fi

	printf '%s' "$merged_tree" | jq '.' > "$dst"
}

merge_text() {
	local src="$1" dst="$2"
	# Show a merged file with conflict markers, let the user resolve once,
	# then write the result back to dst.
	local tmp base
	tmp="$(mktemp)"
	base="$(mktemp)"  # empty common ancestor
	: > "$base"
	# diff3 writes the merged result with <<<<<<<, =======, >>>>>>> markers
	# when there are conflicts. Exit code 1 = conflicts, 0 = clean merge.
	if diff3 -m -L dst -L common -L src "$dst" "$base" "$src" > "$tmp"; then
		mv "$tmp" "$dst"
		echo "    clean 3-way merge (no conflicts)"
	else
		echo "    conflict markers in place. Opening \$EDITOR to resolve…"
		${EDITOR:-${VISUAL:-vi}} "$tmp" </dev/tty
		# quick sanity check: any leftover markers?
		if grep -Eq '^(<{7}|={7}|>{7})' "$tmp"; then
			echo "    WARNING: merge markers still present in the result. Keeping DST unchanged."
			rm -f "$tmp"
		else
			mv "$tmp" "$dst"
			echo "    saved resolved merge"
		fi
	fi
	rm -f "$base"
}

_dispatch_merge() {
	local rel="$1" src="$2" dst="$3"
	local name
	name="$(basename "$rel")"

	case "$name" in
		authorized_keys|known_hosts)
			merge_line_union "$src" "$dst"
			echo "    line-union"
			;;
		*.json)
			if merge_json "$src" "$dst"; then
				echo "    json deep-merge"
			else
				echo "    json merge failed → falling back to text merge"
				merge_text "$src" "$dst"
			fi
			;;
		*)
			merge_text "$src" "$dst"
			;;
	esac
}

merge_dirs() {
	local src="$1" dst="$2"
	local label="${3:-merge}"

	if [[ ! -d "$src" ]]; then
		echo "  (skip $label: source $src does not exist)"
		return 0
	fi

	mkdir -p "$dst"

	local added=0 merged_count=0 same=0
	local rel src_f dst_f

	while IFS= read -r -d '' src_f; do
		rel="${src_f#"$src"/}"
		dst_f="$dst/$rel"

		if [[ ! -e "$dst_f" ]]; then
			mkdir -p "$(dirname "$dst_f")"
			cp -p "$src_f" "$dst_f"
			echo "  + $label/$rel  (added from src)"
			added=$((added + 1))
			continue
		fi

		if cmp -s "$src_f" "$dst_f"; then
			same=$((same + 1))
			continue
		fi

		echo
		echo "  ~ $label/$rel  (differs — merging)"
		_dispatch_merge "$rel" "$src_f" "$dst_f"
		merged_count=$((merged_count + 1))
	done < <(find "$src" -type f -print0)

	echo "  $label summary: added=$added merged=$merged_count unchanged=$same"
}
