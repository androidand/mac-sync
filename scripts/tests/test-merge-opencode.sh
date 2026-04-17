#!/usr/bin/env bash
set -euo pipefail

# End-to-end test for merge_json against realistic opencode.json fixtures.
#
# What it does:
#   1. Generates two fixtures inspired by the two Macs' opencode.json:
#        a) thisMac.json  — baseline, mirrors dotfiles/opencode/opencode.json
#        b) peer.json     — synthetic mbpM5 variant with additions + overlaps
#      If a peer host is supplied, step (b) is replaced by rsync'ing the
#      peer's real ~/.config/opencode/opencode.json over SSH.
#   2. Runs merge_json (the same function the sync scripts use).
#   3. Asserts the merged result is the expected additive union with
#      conflicts resolved in favor of "dst" (the default when Enter is
#      pressed at the prompt).
#
# Usage:
#   ./scripts/tests/test-merge-opencode.sh                     # synthetic peer
#   ./scripts/tests/test-merge-opencode.sh user@mbpm5.local    # real peer

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$HERE/lib/merge.sh"
REPO="$(cd "$HERE/.." && pwd)"
PEER="${1:-}"

# shellcheck source=../lib/merge.sh
. "$LIB"

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

WORK="$(mktemp -d -t merge-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

THIS="$WORK/thisMac.json"
PEER_FILE="$WORK/peer.json"
MERGED="$WORK/merged.json"

# ---------------------------------------------------------------------------
# Fixture A: thisMac — seeded from the repo's current baseline
# ---------------------------------------------------------------------------
if [[ -f "$REPO/dotfiles/opencode/opencode.json" ]]; then
	# strip trailing commas / comments if any, then ensure it's valid JSON
	jq '.' "$REPO/dotfiles/opencode/opencode.json" > "$THIS"
	echo "==> thisMac fixture: seeded from dotfiles/opencode/opencode.json"
else
	cat > "$THIS" <<'EOF'
{
	"$schema": "https://opencode.ai/config.json",
	"model": "anthropic/claude-sonnet-4-5",
	"small_model": "anthropic/claude-haiku-4-5",
	"enabled_providers": ["anthropic", "azure", "openrouter"],
	"permission": {
		"edit": "allow",
		"bash": { "*": "ask", "pwd": "allow" }
	},
	"agent": {
		"swarm-orchestrator": {
			"model": "anthropic/claude-sonnet-4-5",
			"temperature": 0.2
		},
		"backend-engineer": {
			"model": "anthropic/claude-sonnet-4-5",
			"temperature": 0.25
		}
	},
	"mcp": {
		"context7": { "type": "remote", "enabled": true }
	}
}
EOF
	echo "==> thisMac fixture: synthetic (repo baseline not found)"
fi

# ---------------------------------------------------------------------------
# Fixture B: peer — either SSH-pulled from real peer, or synthetic
# ---------------------------------------------------------------------------
if [[ -n "$PEER" ]]; then
	echo "==> Fetching peer opencode.json from $PEER via rsync/ssh…"
	rsync -a "$PEER:.config/opencode/opencode.json" "$PEER_FILE"
	echo "    got $(wc -c <"$PEER_FILE") bytes from $PEER"
else
	# A plausible mbpM5 variant: different small_model, extra provider,
	# extra agent, extra command, extra MCP, different bash rule scalar.
	cat > "$PEER_FILE" <<'EOF'
{
	"$schema": "https://opencode.ai/config.json",
	"model": "anthropic/claude-sonnet-4-5",
	"small_model": "anthropic/claude-haiku-4-5-20251001",
	"enabled_providers": ["anthropic", "azure", "openrouter", "google"],
	"permission": {
		"edit": "ask",
		"bash": { "*": "ask", "pwd": "allow", "git *": "allow" }
	},
	"agent": {
		"swarm-orchestrator": {
			"model": "anthropic/claude-opus-4-6",
			"temperature": 0.3
		},
		"data-scientist": {
			"model": "anthropic/claude-sonnet-4-5",
			"temperature": 0.1
		}
	},
	"mcp": {
		"context7": { "type": "remote", "enabled": true },
		"playwright": { "type": "local", "enabled": true }
	}
}
EOF
	echo "==> peer fixture: synthetic mbpM5 variant"
fi

echo
echo "==> thisMac JSON:"
jq -c 'keys' "$THIS"
echo "==> peer JSON:"
jq -c 'keys' "$PEER_FILE"

# ---------------------------------------------------------------------------
# Run the merge: treat thisMac as DST (the side that persists), peer as SRC.
# Feed 'd' (keep dst) to every conflict prompt so the test is deterministic.
# ---------------------------------------------------------------------------
cp "$THIS" "$MERGED"

# merge_json reads prompts from /dev/tty, so we redirect /dev/tty to a pipe
# that auto-answers 'd' for every prompt.
echo
echo "==> Running merge_json (auto-answering 'd' = keep thisMac for every conflict)…"
# 256 lines of 'd' is plenty; awk doesn't SIGPIPE and plays nice with pipefail
awk 'BEGIN { for (i = 0; i < 256; i++) print "d" }' > "$WORK/answers"

# Bash can't easily replace /dev/tty mid-function, so wrap the invocation in
# a subshell that uses 'script' where available, or a FIFO trick. Simplest
# portable approach: temporarily redefine /dev/tty via a bind-mount-free
# alternative — we use a small shim that re-reads the function with stdin
# as the tty source.
merge_json_autod() {
	local src="$1" dst="$2"
	# Re-run merge_json body but source /dev/tty from stdin instead.
	# We patch by copying merge.sh, swapping </dev/tty with </dev/stdin.
	local shim
	shim="$(mktemp)"
	sed 's#</dev/tty#</dev/stdin#g' "$LIB" > "$shim"
	# shellcheck source=/dev/null
	( . "$shim"; merge_json "$src" "$dst"; )
	rm -f "$shim"
}

merge_json_autod "$PEER_FILE" "$MERGED" < "$WORK/answers"

echo
echo "==> Merged result keys:"
jq -c 'keys' "$MERGED"

# ---------------------------------------------------------------------------
# Assertions — these are what "correct" looks like for an additive union
# ---------------------------------------------------------------------------
pass=0
fail=0
assert() {
	local name="$1" cond="$2"
	if eval "$cond"; then
		echo "    PASS  $name"
		pass=$((pass + 1))
	else
		echo "    FAIL  $name"
		echo "          cond: $cond"
		fail=$((fail + 1))
	fi
}

echo
echo "==> Assertions:"

# enabled_providers must contain the UNION of both sides, deduped
this_providers="$(jq -c '.enabled_providers // [] | sort' "$THIS")"
peer_providers="$(jq -c '.enabled_providers // [] | sort' "$PEER_FILE")"
merged_providers="$(jq -c '.enabled_providers // [] | sort' "$MERGED")"
expected_providers="$(jq -cn --argjson a "$this_providers" --argjson b "$peer_providers" '$a + $b | unique')"
assert "enabled_providers is union" "[[ '$merged_providers' == '$expected_providers' ]]"

# Agents: every agent key from BOTH sides must exist in merged
for side in "$THIS" "$PEER_FILE"; do
	for k in $(jq -r '.agent // {} | keys[]' "$side"); do
		assert "agent.$k survives merge (from $(basename "$side"))" \
			"jq -e '.agent.\"$k\"' '$MERGED' >/dev/null"
	done
done

# MCP servers: every mcp key from BOTH sides must exist in merged
for side in "$THIS" "$PEER_FILE"; do
	for k in $(jq -r '.mcp // {} | keys[]' "$side"); do
		assert "mcp.$k survives merge (from $(basename "$side"))" \
			"jq -e '.mcp.\"$k\"' '$MERGED' >/dev/null"
	done
done

# Scalar conflicts resolved toward DST (thisMac) when we answered 'd'
if jq -e '.small_model' "$THIS" >/dev/null && jq -e '.small_model' "$PEER_FILE" >/dev/null; then
	this_sm="$(jq -r '.small_model' "$THIS")"
	peer_sm="$(jq -r '.small_model' "$PEER_FILE")"
	if [[ "$this_sm" != "$peer_sm" ]]; then
		merged_sm="$(jq -r '.small_model' "$MERGED")"
		assert "scalar conflict small_model kept thisMac value" \
			"[[ '$merged_sm' == '$this_sm' ]]"
	fi
fi

# Nested scalar conflict: swarm-orchestrator.model
if jq -e '.agent."swarm-orchestrator".model' "$THIS" >/dev/null 2>&1 \
	&& jq -e '.agent."swarm-orchestrator".model' "$PEER_FILE" >/dev/null 2>&1; then
	this_so="$(jq -r '.agent."swarm-orchestrator".model' "$THIS")"
	peer_so="$(jq -r '.agent."swarm-orchestrator".model' "$PEER_FILE")"
	if [[ "$this_so" != "$peer_so" ]]; then
		merged_so="$(jq -r '.agent."swarm-orchestrator".model' "$MERGED")"
		assert "nested scalar conflict (swarm-orchestrator.model) kept thisMac" \
			"[[ '$merged_so' == '$this_so' ]]"
	fi
fi

# Merged object key count must be >= max of each side's key count at top level
this_n="$(jq '. | keys | length' "$THIS")"
peer_n="$(jq '. | keys | length' "$PEER_FILE")"
merged_n="$(jq '. | keys | length' "$MERGED")"
assert "merged top-level key count is additive (>= max of sides)" \
	"(( merged_n >= this_n && merged_n >= peer_n ))"

# Merged JSON must be valid
assert "merged JSON parses as valid" "jq -e 'type == \"object\"' '$MERGED' >/dev/null"

echo
echo "==> Summary: $pass passed, $fail failed"
echo "    thisMac:  $THIS"
echo "    peer:     $PEER_FILE"
echo "    merged:   $MERGED"
echo
if (( fail > 0 )); then
	echo "==> DIFFS for debugging:"
	echo "--- thisMac vs merged ---"
	diff <(jq -S . "$THIS") <(jq -S . "$MERGED") || true
	echo "--- peer vs merged ---"
	diff <(jq -S . "$PEER_FILE") <(jq -S . "$MERGED") || true
	exit 1
fi

echo "==> All assertions passed."
