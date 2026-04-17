#!/usr/bin/env bash
set -euo pipefail

# Runs the full merge test suite. No SSH required — uses only local fixtures.
#
# Usage:
#   ./scripts/tests/run-all.sh
#
# To also run the opencode test against your real peer's live config:
#   ./scripts/tests/test-merge-opencode.sh user@peer.local

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tests=(
	"$HERE/test-merge-line-union.sh"
	"$HERE/test-merge-text.sh"
	"$HERE/test-merge-opencode.sh"
	"$HERE/test-merge-dirs.sh"
)

total=${#tests[@]}
passed=0
failed=()

for t in "${tests[@]}"; do
	name="$(basename "$t")"
	echo
	echo "########################################"
	echo "# $name"
	echo "########################################"
	if bash "$t"; then
		passed=$((passed + 1))
	else
		failed+=("$name")
	fi
done

echo
echo "========================================"
echo "Ran $total suites: $passed passed, ${#failed[@]} failed"
if (( ${#failed[@]} > 0 )); then
	printf '  FAILED: %s\n' "${failed[@]}"
	exit 1
fi
echo "All green."
