#!/usr/bin/env bash
set -euo pipefail

# Tests merge_line_union — used for authorized_keys and known_hosts.
#
# Semantics under test:
#   - Every line present on either side is kept.
#   - Duplicates are collapsed (sort -u).
#   - Output is written to DST; SRC is not touched.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/merge.sh
. "$HERE/lib/merge.sh"

WORK="$(mktemp -d -t line-union-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
assert() {
	local name="$1" cond="$2"
	if eval "$cond"; then
		echo "    PASS  $name"; pass=$((pass + 1))
	else
		echo "    FAIL  $name"; echo "          cond: $cond"; fail=$((fail + 1))
	fi
}

# ---------- Fixture 1: authorized_keys ----------
DST="$WORK/authorized_keys.dst"
SRC="$WORK/authorized_keys.src"
SRC_SNAPSHOT="$WORK/authorized_keys.src.snapshot"

cat > "$DST" <<'EOF'
ssh-ed25519 AAAAlocal1 local@thisMac
ssh-ed25519 AAAAshared shared@both
EOF
cat > "$SRC" <<'EOF'
ssh-ed25519 AAAAmbpM5 peer@mbpM5
ssh-ed25519 AAAAshared shared@both
EOF
cp "$SRC" "$SRC_SNAPSHOT"

merge_line_union "$SRC" "$DST"

echo "==> authorized_keys merged DST:"
cat "$DST"
echo

lines_dst="$(wc -l <"$DST" | tr -d ' ')"
assert "authorized_keys has exactly 3 unique lines" "[[ '$lines_dst' == '3' ]]"
assert "authorized_keys contains local key" "grep -q 'AAAAlocal1' '$DST'"
assert "authorized_keys contains peer key" "grep -q 'AAAAmbpM5' '$DST'"
assert "authorized_keys contains shared key" "grep -q 'AAAAshared' '$DST'"
assert "authorized_keys shared key deduped (appears once)" \
	"[[ \$(grep -c 'AAAAshared' '$DST') == '1' ]]"
assert "merge_line_union did not touch SRC" "cmp -s '$SRC' '$SRC_SNAPSHOT'"

# ---------- Fixture 2: known_hosts with overlapping host + unique entries ----------
DST2="$WORK/known_hosts.dst"
SRC2="$WORK/known_hosts.src"
cat > "$DST2" <<'EOF'
github.com ssh-rsa AAAAghRSA
gitlab.com ssh-rsa AAAAglRSA
EOF
cat > "$SRC2" <<'EOF'
github.com ssh-rsa AAAAghRSA
mbpm5.local ssh-ed25519 AAAAmbpM5ED
EOF

merge_line_union "$SRC2" "$DST2"

echo "==> known_hosts merged DST:"
cat "$DST2"
echo

assert "known_hosts has exactly 3 unique lines" \
	"[[ \$(wc -l <'$DST2' | tr -d ' ') == '3' ]]"
assert "known_hosts keeps github (identical on both)" "grep -q 'AAAAghRSA' '$DST2'"
assert "known_hosts keeps gitlab (only in dst)" "grep -q 'AAAAglRSA' '$DST2'"
assert "known_hosts adds mbpm5 (only in src)" "grep -q 'AAAAmbpM5ED' '$DST2'"

# ---------- Fixture 3: empty SRC should be a no-op ----------
DST3="$WORK/empty_src.dst"
SRC3="$WORK/empty_src.src"
printf 'line1\nline2\n' > "$DST3"
: > "$SRC3"
merge_line_union "$SRC3" "$DST3"
assert "empty SRC leaves DST content intact" \
	"[[ \$(wc -l <'$DST3' | tr -d ' ') == '2' ]]"

# ---------- Fixture 4: empty DST gets populated from SRC ----------
DST4="$WORK/empty_dst.dst"
SRC4="$WORK/empty_dst.src"
: > "$DST4"
printf 'ssh-ed25519 AAAAX x@host\n' > "$SRC4"
merge_line_union "$SRC4" "$DST4"
assert "empty DST populated from SRC" "grep -q 'AAAAX' '$DST4'"

echo
echo "==> line-union summary: $pass passed, $fail failed"
(( fail == 0 ))
