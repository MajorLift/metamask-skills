#!/usr/bin/env bash
#
# falsify-probe — prove a test is falsifying, by mutation rather than by reading.
#
# A test is evidence only if it FAILS when the mechanism it guards is removed.
# Reading the test establishes its shape; only this establishes its power.
#
# Runs two arms against the same tree:
#   Arm A  baseline — the suite as committed
#   Arm B  mutant   — one line replaced, suite re-run, source restored
#
# Emits a captured artifact (JSON + markdown) written by this script, not
# transcribed by an operator. Exit code IS the verdict, so CI can gate on it.
#
#   0  falsifying   arm A passed, arm B failed        → the test has power
#   1  vacuous      arm A passed, arm B ALSO passed   → the test proves nothing
#   2  broken       arm A failed                      → nothing to conclude
#   3  usage/env error
#
# Usage:
#   falsify-probe.sh --test <path> --source <path> --line <n> --replace <text>
#                    [--label <slug>] [--out <dir>] [--runner "<cmd>"]
#
# Example:
#   falsify-probe.sh \
#     --test ui/hooks/perps/coalesceBackgroundRequest.test.ts \
#     --source ui/hooks/perps/coalesceBackgroundRequest.ts \
#     --line 54 --replace '  const existing = undefined as Promise<TResult> | undefined;' \
#     --label coalesce-inflight
set -uo pipefail

RUNNER="yarn jest"
OUT_DIR="evidence-artifacts"
LABEL=""
TEST="" SOURCE="" LINE="" REPLACE=""

die() { printf 'falsify-probe: %s\n' "$1" >&2; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --test)    TEST="${2:-}"; shift 2 ;;
    --source)  SOURCE="${2:-}"; shift 2 ;;
    --line)    LINE="${2:-}"; shift 2 ;;
    --replace) REPLACE="${2:-}"; shift 2 ;;
    --label)   LABEL="${2:-}"; shift 2 ;;
    --out)     OUT_DIR="${2:-}"; shift 2 ;;
    --runner)  RUNNER="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$TEST" ]   || die "--test is required"
[ -n "$SOURCE" ] || die "--source is required"
[ -n "$LINE" ]   || die "--line is required"
[ -n "$REPLACE" ] || die "--replace is required (use '' only if deleting the line)"
[ -f "$TEST" ]   || die "test not found: $TEST"
[ -f "$SOURCE" ] || die "source not found: $SOURCE"
case "$LINE" in ''|*[!0-9]*) die "--line must be numeric: $LINE" ;; esac
[ "$LINE" -le "$(wc -l < "$SOURCE")" ] || die "--line $LINE is past the end of $SOURCE"

LABEL="${LABEL:-$(basename "$SOURCE" | sed 's/\.[^.]*$//')-L$LINE}"
mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
STAMP="$OUT_DIR/falsify-$LABEL"

# --- environment pin: two operators on different machines must be comparable ---
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')"
NODE_V="$(node -v 2>/dev/null || echo unknown)"
LOCK_SHA="$( { sha256sum yarn.lock 2>/dev/null || shasum -a 256 yarn.lock 2>/dev/null; } | cut -c1-16)"
ORIGINAL_LINE="$(sed -n "${LINE}p" "$SOURCE")"

BACKUP="$(mktemp)" || die "mktemp failed"
cp "$SOURCE" "$BACKUP"
restore() { cp "$BACKUP" "$SOURCE"; rm -f "$BACKUP"; }
trap restore EXIT INT TERM

run_arm() { # $1=logfile ; prints "passed|failed"
  if $RUNNER "$TEST" > "$1" 2>&1; then echo passed; else echo failed; fi
}

ARM_A="$(run_arm "$STAMP-armA.log")"

if [ "$ARM_A" != "passed" ]; then
  VERDICT="broken"; CODE=2; ARM_B="not-run"
  : > "$STAMP-armB.log"
else
  # Mutate exactly one line. `.bak` form keeps this portable across GNU/BSD sed.
  awk -v n="$LINE" -v r="$REPLACE" 'NR==n{print r; next}{print}' "$SOURCE" > "$SOURCE.tmp" \
    && mv "$SOURCE.tmp" "$SOURCE" || die "mutation failed"
  ARM_B="$(run_arm "$STAMP-armB.log")"
  restore; trap - EXIT INT TERM
  if [ "$ARM_B" = "failed" ]; then VERDICT="falsifying"; CODE=0; else VERDICT="vacuous"; CODE=1; fi
fi

summarise() { grep -E '^(Tests|Test Suites):' "$1" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g'; }
A_SUM="$(summarise "$STAMP-armA.log")"
B_SUM="$(summarise "$STAMP-armB.log")"
FAILED_NAMES="$(grep -E '^\s+●[^›]*›' "$STAMP-armB.log" 2>/dev/null | sed 's/^ *//' | head -10)"

cat > "$STAMP.json" <<JSON
{
  "verdict": "$VERDICT",
  "exit": $CODE,
  "test": "$TEST",
  "mutation": { "source": "$SOURCE", "line": $LINE,
                "from": $(printf '%s' "$ORIGINAL_LINE" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),
                "to": $(printf '%s' "$REPLACE" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))') },
  "armA": { "result": "$ARM_A", "summary": "$A_SUM", "log": "$STAMP-armA.log" },
  "armB": { "result": "$ARM_B", "summary": "$B_SUM", "log": "$STAMP-armB.log" },
  "env": { "head": "$HEAD_SHA", "tracked_changes": $DIRTY, "node": "$NODE_V", "yarn_lock_sha256_16": "$LOCK_SHA" }
}
JSON

{
  echo "### Falsification probe — \`$VERDICT\`"
  echo
  echo "| Arm | Mutation | Result |"
  echo "|---|---|---|"
  echo "| A — baseline | none | \`$A_SUM\` |"
  echo "| B — mutant | \`$SOURCE:$LINE\` replaced | \`$B_SUM\` |"
  echo
  case "$VERDICT" in
    falsifying) echo "The suite **fails when the mechanism is removed** and passes when restored. The test has power." ;;
    vacuous)    echo "The suite **passes with the mechanism removed**. It does not test what it appears to test." ;;
    broken)     echo "Arm A did not pass, so arm B was not run. No conclusion." ;;
  esac
  [ -n "$FAILED_NAMES" ] && { echo; echo "Failing under mutation:"; echo; printf '%s\n' "$FAILED_NAMES" | sed 's/^/- /'; }
  echo
  echo "<sub>Produced by \`falsify-probe.sh\` at \`$HEAD_SHA\` · node \`$NODE_V\` · yarn.lock \`$LOCK_SHA\` · $DIRTY tracked changes. Logs: \`$STAMP-armA.log\`, \`$STAMP-armB.log\`.</sub>"
} > "$STAMP.md"

printf 'falsify-probe: %s (exit %s)\n  %s\n  %s\n' "$VERDICT" "$CODE" "$STAMP.json" "$STAMP.md" >&2
exit "$CODE"
