#!/usr/bin/env bash
#
# Summoned — the verification gate. One command, two stages:
#
#   1. Parse/compile every .gd in the project.
#   2. Run the headless test suite.
#
# Run it before every commit; CI runs the same script (.github/workflows/verify.yml),
# so a green local run means a green CI run. See the "Verification recipe" section of
# the Roadmap HQ page in Notion for the full four-stage recipe — stages 3 (live
# in-engine) and 4 (eyes/ears-on) need the editor and a human, so they are not here.
#
# Deliberately keys on OUTPUT, not exit codes: `godot --check-only` exits 0 even on a
# parse error, and the test scene can exit non-zero on a clean run. Trusting $? here
# would report success on genuinely broken code.
#
# Uses plain Godot CLI only — no editor, no MCP bridge, no GodotIQ addon.
#
# Usage:  ./verify.sh            (auto-detects Godot)
#         GODOT=/path/to/godot ./verify.sh
set -uo pipefail

cd "$(dirname "$0")"

# --- locate Godot -------------------------------------------------------------
if [[ -z "${GODOT:-}" ]]; then
	for candidate in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$(command -v godot 2>/dev/null || true)" \
		"$(command -v godot4 2>/dev/null || true)"
	do
		if [[ -n "$candidate" && -x "$candidate" ]]; then
			GODOT="$candidate"
			break
		fi
	done
fi
if [[ -z "${GODOT:-}" || ! -x "$GODOT" ]]; then
	echo "FAIL: Godot binary not found. Set GODOT=/path/to/godot" >&2
	exit 1
fi

echo "Godot: $("$GODOT" --version 2>/dev/null | tail -1)"
echo

# Import assets first so a cold checkout (CI has no .godot/ cache — it is gitignored)
# does not surface import chatter as script errors.
if [[ ! -d ".godot" ]]; then
	echo "No .godot cache — importing assets first (cold checkout)..."
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
	echo
fi

failures=0

# --- stage 1: parse/compile every script --------------------------------------
# Runs inside a scene (scripts/compile_check.gd) rather than via `--check-only`:
# --check-only compiles without the project's autoloads registered, so all 16 scripts
# that reference GameState report "Identifier not found" — false failures.
echo "=== 1/2  Compiling scripts ==="
compile_out="$("$GODOT" --headless --path . --quit-after 600 res://scenes/compile_check.tscn 2>&1)"
compile_line="$(grep -E "^COMPILE CHECK:" <<<"$compile_out" | tail -1)"

if [[ -z "$compile_line" ]]; then
	echo "  FAIL  compile check produced no result line (crash, or it never finished)"
	tail -20 <<<"$compile_out" | sed 's/^/        /'
	failures=$((failures + 1))
else
	echo "  $compile_line"
	grep -E "^\s+FAILED" <<<"$compile_out" | sed 's/^/    /' || true
	if ! grep -qE "\b0 failed\b" <<<"$compile_line"; then
		failures=$((failures + 1))
	fi
fi
echo

# --- stage 2: headless test suite ---------------------------------------------
# --quit-after is REQUIRED: the test scene does not quit itself and will hang forever.
echo "=== 2/2  Test suite ==="
suite_out="$("$GODOT" --headless --path . --quit-after 300 res://scenes/test.tscn 2>&1)"
result_line="$(grep -E "^[0-9]+ passed" <<<"$suite_out" | tail -1)"

if [[ -z "$result_line" ]]; then
	echo "  FAIL  suite produced no result line (crash, or it never reached the end)"
	tail -20 <<<"$suite_out" | sed 's/^/        /'
	failures=$((failures + 1))
else
	echo "  $result_line"
	grep -E "^\s+FAIL" <<<"$suite_out" | sed 's/^/      /' || true
	# "0 failed" is the only acceptable outcome; skips are reported but allowed.
	if ! grep -qE "\b0 failed\b" <<<"$result_line"; then
		failures=$((failures + 1))
	fi
fi
echo

# --- verdict ------------------------------------------------------------------
if [[ $failures -eq 0 ]]; then
	echo "PASS — safe to commit."
	exit 0
fi
echo "FAIL — $failures stage(s) failed. Do not commit; see the Roadmap HQ commit protocol." >&2
exit 1
