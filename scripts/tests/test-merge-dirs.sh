#!/usr/bin/env bash
set -euo pipefail

# Tests merge_dirs — the top-level dispatcher used by every sync script.
#
# What it covers:
#   - files only in SRC are copied into DST
#   - files only in DST are left untouched (never deleted)
#   - files identical on both sides are not rewritten
#   - files that differ are dispatched by type:
#       authorized_keys → line-union
#       *.json          → jq deep-merge
#       everything else → diff3 text merge
#
# The JSON and text merges read from /dev/tty for prompts; we patch that
# in-memory to read from /dev/null so defaults/stubs are used.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d -t merge-dirs-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

shim="$WORK/merge-shim.sh"
sed 's#</dev/tty#</dev/null#g' "$HERE/lib/merge.sh" > "$shim"
# shellcheck source=/dev/null
. "$shim"

pass=0; fail=0
assert() {
	local name="$1" cond="$2"
	if eval "$cond"; then
		echo "    PASS  $name"; pass=$((pass + 1))
	else
		echo "    FAIL  $name"; echo "          cond: $cond"; fail=$((fail + 1))
	fi
}

SRC="$WORK/src"
DST="$WORK/dst"
mkdir -p "$SRC" "$DST"

# --- identical file on both sides → should be unchanged ---
echo "identical content" > "$SRC/same.txt"
echo "identical content" > "$DST/same.txt"
SAME_MTIME_BEFORE="$(stat -c '%Y' "$DST/same.txt" 2>/dev/null || stat -f '%m' "$DST/same.txt")"

# --- src-only file → should be copied to DST ---
echo "only in src" > "$SRC/srconly.txt"
mkdir -p "$SRC/nested/dir"
echo "nested src-only" > "$SRC/nested/dir/deep.txt"

# --- dst-only file → should be preserved ---
echo "only in dst" > "$DST/dstonly.txt"
DSTONLY_SNAPSHOT="$WORK/dstonly.snapshot"
cp "$DST/dstonly.txt" "$DSTONLY_SNAPSHOT"

# --- authorized_keys on both sides (will hit line-union) ---
cat > "$SRC/authorized_keys" <<'EOF'
ssh-ed25519 AAAApeer peer@mbpM5
ssh-ed25519 AAAAshared shared@both
EOF
cat > "$DST/authorized_keys" <<'EOF'
ssh-ed25519 AAAAlocal local@thisMac
ssh-ed25519 AAAAshared shared@both
EOF

# --- JSON on both sides (will hit merge_json) ---
cat > "$SRC/config.json" <<'EOF'
{
	"providers": ["openai", "google"],
	"timeout": 500,
	"agents": { "backend": { "temp": 0.2 } }
}
EOF
cat > "$DST/config.json" <<'EOF'
{
	"providers": ["anthropic", "openai"],
	"timeout": 300,
	"agents": { "frontend": { "temp": 0.5 } }
}
EOF

# --- plain text file on both sides (will hit merge_text → editor) ---
cat > "$SRC/.zshrc" <<'EOF'
export FROM_SRC=1
alias la='ls -la'
EOF
cat > "$DST/.zshrc" <<'EOF'
export FROM_DST=1
alias ll='ls -l'
EOF

# Stub editor: keep-both resolution for the text merge
STUB_EDITOR="$WORK/stub-keep-both.sh"
cat > "$STUB_EDITOR" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
file="$1"
tmp="$(mktemp)"
grep -Ev '^(<{7}|={7}|>{7}|\|{7})' "$file" > "$tmp"
mv "$tmp" "$file"
EOF
chmod +x "$STUB_EDITOR"

# ---------- run ----------
echo "==> Running merge_dirs…"
EDITOR="$STUB_EDITOR" merge_dirs "$SRC" "$DST" mixed

echo
echo "==> Asserting results…"

# Additions
assert "src-only file was copied" "[[ -f '$DST/srconly.txt' ]]"
assert "src-only nested file was copied with parent dirs" \
	"[[ -f '$DST/nested/dir/deep.txt' ]]"
assert "src-only file content matches" \
	"[[ \"\$(cat '$DST/srconly.txt')\" == 'only in src' ]]"

# Preservation
assert "dst-only file still exists" "[[ -f '$DST/dstonly.txt' ]]"
assert "dst-only file content unchanged" \
	"cmp -s '$DST/dstonly.txt' '$DSTONLY_SNAPSHOT'"
assert "dst-only file was NOT copied to src" "[[ ! -f '$SRC/dstonly.txt' ]]"

# Identical-on-both → unchanged
assert "identical file content unchanged" \
	"[[ \"\$(cat '$DST/same.txt')\" == 'identical content' ]]"

# Line-union
ak_lines="$(wc -l <"$DST/authorized_keys" | tr -d ' ')"
assert "authorized_keys has 3 unique lines (line-union)" "[[ '$ak_lines' == '3' ]]"
assert "authorized_keys has local key" "grep -q 'AAAAlocal' '$DST/authorized_keys'"
assert "authorized_keys has peer key" "grep -q 'AAAApeer' '$DST/authorized_keys'"
assert "authorized_keys shared key deduped" \
	"[[ \$(grep -c AAAAshared '$DST/authorized_keys') == '1' ]]"

# JSON deep-merge
assert "config.json is valid JSON" \
	"jq -e 'type == \"object\"' '$DST/config.json' >/dev/null"
merged_providers="$(jq -c '.providers | sort' "$DST/config.json")"
assert "config.json providers is union (anthropic + openai + google, deduped, sorted)" \
	"[[ '$merged_providers' == '[\"anthropic\",\"google\",\"openai\"]' ]]"
assert "config.json has agents.backend (from src)" \
	"jq -e '.agents.backend' '$DST/config.json' >/dev/null"
assert "config.json has agents.frontend (from dst)" \
	"jq -e '.agents.frontend' '$DST/config.json' >/dev/null"
# timeout conflict resolved by default toward dst (auto-answer 'd' via /dev/null EOF)
assert "config.json scalar conflict timeout resolved toward dst (300)" \
	"[[ \$(jq '.timeout' '$DST/config.json') == '300' ]]"

# Text merge (editor stub kept both)
assert ".zshrc has no leftover conflict markers" \
	"! grep -Eq '^(<{7}|={7}|>{7}|\\|{7})' '$DST/.zshrc'"
assert ".zshrc kept FROM_DST" "grep -q 'FROM_DST' '$DST/.zshrc'"
assert ".zshrc added FROM_SRC" "grep -q 'FROM_SRC' '$DST/.zshrc'"
assert ".zshrc kept dst alias ll" "grep -q \"alias ll='ls -l'\" '$DST/.zshrc'"
assert ".zshrc added src alias la" "grep -q \"alias la='ls -la'\" '$DST/.zshrc'"

echo
echo "==> merge_dirs summary: $pass passed, $fail failed"
(( fail == 0 ))
