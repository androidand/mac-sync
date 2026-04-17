#!/usr/bin/env bash
set -euo pipefail

# Tests merge_text — used for any file that isn't JSON or a known line-union
# file (e.g. .zshrc, ~/.ssh/config, arbitrary dotfiles).
#
# diff3 with an empty common ancestor ALWAYS produces conflict markers when
# the two sides differ at all. That means every real text merge goes through
# the $EDITOR resolution path. We stub $EDITOR with a script that simulates
# a user resolving the conflict, then verify the written DST.
#
# Two cases:
#   1. EDITOR resolves all markers → DST updated with the resolved content.
#   2. EDITOR leaves markers intact → DST left unchanged (safety fallback).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/merge.sh
. "$HERE/lib/merge.sh"

WORK="$(mktemp -d -t text-test.XXXXXX)"
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

# merge_text reads from /dev/tty for the editor invocation. In tests we
# can't connect a real tty, so we patch the lib in-memory to read from
# /dev/null (the editor we'll use doesn't need stdin anyway).
shim="$WORK/merge-shim.sh"
sed 's#</dev/tty#</dev/null#g' "$HERE/lib/merge.sh" > "$shim"
# shellcheck source=/dev/null
. "$shim"

# ---------- Case 1: editor resolves by keeping BOTH sides (union) ----------
DST="$WORK/case1/.zshrc"
SRC="$WORK/case1/src/.zshrc"
mkdir -p "$(dirname "$DST")" "$(dirname "$SRC")"

cat > "$DST" <<'EOF'
export PATH=$PATH:/usr/local/bin
alias ll='ls -la'
eval "$(starship init zsh)"
EOF

cat > "$SRC" <<'EOF'
export PATH=$PATH:/opt/homebrew/bin
alias ll='ls -la'
eval "$(zoxide init zsh)"
EOF

# Stub editor: drops diff3 markers, keeps every line that wasn't a marker.
# This simulates a user who reads the conflict and picks "keep both".
STUB_EDITOR="$WORK/stub-editor-keep-both.sh"
cat > "$STUB_EDITOR" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
file="$1"
tmp="$(mktemp)"
grep -Ev '^(<{7}|={7}|>{7}|\|{7})' "$file" > "$tmp"
mv "$tmp" "$file"
EOF
chmod +x "$STUB_EDITOR"

EDITOR="$STUB_EDITOR" merge_text "$SRC" "$DST"

echo "==> Case 1 (keep-both) merged DST:"
cat "$DST"
echo

assert "case 1: DST has no leftover conflict markers" \
	"! grep -Eq '^(<{7}|={7}|>{7}|\\|{7})' '$DST'"
assert "case 1: DST kept starship (from original dst)" "grep -q 'starship' '$DST'"
assert "case 1: DST added zoxide (from src)" "grep -q 'zoxide' '$DST'"
assert "case 1: DST kept /usr/local/bin (dst PATH)" "grep -q '/usr/local/bin' '$DST'"
assert "case 1: DST added /opt/homebrew/bin (src PATH)" "grep -q '/opt/homebrew/bin' '$DST'"

# ---------- Case 2: editor leaves markers → safety fallback keeps DST unchanged ----------
DST2="$WORK/case2/.zshrc"
SRC2="$WORK/case2/src/.zshrc"
mkdir -p "$(dirname "$DST2")" "$(dirname "$SRC2")"

cat > "$DST2" <<'EOF'
ORIGINAL_DST_CONTENT=1
export ONLY_IN_DST=true
EOF
cat > "$SRC2" <<'EOF'
ORIGINAL_SRC_CONTENT=1
export ONLY_IN_SRC=true
EOF

DST2_SNAPSHOT="$WORK/case2.dst.snapshot"
cp "$DST2" "$DST2_SNAPSHOT"

# "true" is a real binary that does nothing → leaves the tmp file untouched
# → conflict markers remain → merge_text refuses to write DST.
EDITOR="true" merge_text "$SRC2" "$DST2"

echo "==> Case 2 (unresolved) DST after merge_text:"
cat "$DST2"
echo

assert "case 2: unresolved merge leaves DST byte-identical to snapshot" \
	"cmp -s '$DST2' '$DST2_SNAPSHOT'"
assert "case 2: DST still contains ONLY_IN_DST" "grep -q 'ONLY_IN_DST' '$DST2'"
assert "case 2: DST does NOT contain ONLY_IN_SRC (src never won)" \
	"! grep -q 'ONLY_IN_SRC' '$DST2'"

# ---------- Case 3: user picks dst only (drops all markers and src-side lines) ----------
DST3="$WORK/case3/.zshrc"
SRC3="$WORK/case3/src/.zshrc"
mkdir -p "$(dirname "$DST3")" "$(dirname "$SRC3")"

cat > "$DST3" <<'EOF'
DST_LINE_A=1
DST_LINE_B=2
EOF
cat > "$SRC3" <<'EOF'
SRC_LINE_X=1
SRC_LINE_Y=2
EOF

# Stub editor: between >>>>>>> and end of src block, delete those lines.
# Simulates "reject src, keep dst".
STUB_KEEP_DST="$WORK/stub-editor-keep-dst.sh"
cat > "$STUB_KEEP_DST" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
file="$1"
awk '
	/^<<<<<<< / { in_dst = 1; next }
	/^\|\|\|\|\|\|\| / { in_dst = 0; in_base = 1; next }
	/^======= / { in_base = 0; in_src = 1; next }
	/^>>>>>>> / { in_src = 0; next }
	in_src || in_base { next }
	{ print }
' "$file" > "$file.tmp"
mv "$file.tmp" "$file"
EOF
chmod +x "$STUB_KEEP_DST"

EDITOR="$STUB_KEEP_DST" merge_text "$SRC3" "$DST3"

echo "==> Case 3 (keep-dst-only) merged DST:"
cat "$DST3"
echo

assert "case 3: DST has no leftover markers" \
	"! grep -Eq '^(<{7}|={7}|>{7}|\\|{7})' '$DST3'"
assert "case 3: DST kept DST_LINE_A" "grep -q 'DST_LINE_A' '$DST3'"
assert "case 3: DST kept DST_LINE_B" "grep -q 'DST_LINE_B' '$DST3'"
assert "case 3: DST rejected SRC_LINE_X" "! grep -q 'SRC_LINE_X' '$DST3'"
assert "case 3: DST rejected SRC_LINE_Y" "! grep -q 'SRC_LINE_Y' '$DST3'"

echo
echo "==> text-merge summary: $pass passed, $fail failed"
(( fail == 0 ))
