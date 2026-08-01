#!/usr/bin/env bash
#
# selector-recompute — measure how often a reselect selector actually recomputes.
#
# Lane C4. A memoization claim ("avoids recomputation", "stops deep traversal",
# "prevents re-renders") is a claim about a COUNT. `reselect` exposes that count
# natively via `.recomputations()`, so no instrumentation and no profiler is
# needed — and no operator judgement either.
#
# Generates a throwaway probe test, runs it, captures the counter under three
# conditions, removes the probe, and writes the artifact itself.
#
#   A  identical state reference, repeated   → memoized floor (expect 1)
#   B  fresh enclosing slice, unrelated field changed → does an unrelated write cost a recompute?
#   C  a real input key perturbed            → does a relevant write cost one? (expect +1 each)
#
# B is the discriminating condition. A selector taking narrowed inputs is
# unmoved by B; one reading a whole slice recomputes on every unrelated write.
#
# Usage:
#   selector-recompute.sh --module <import path> --export <name> \
#     --fixture <json path> --slice <key> --perturb <key> [--n 5] [--label <slug>]
#
# Example:
#   selector-recompute.sh \
#     --module ui/selectors/multichain-accounts/account-tree \
#     --export getWalletsWithAccounts \
#     --fixture test/data/mock-state.json --slice metamask --perturb pinnedAccountList
set -uo pipefail

N=5; OUT_DIR="evidence-artifacts"; LABEL=""; MODULE=""; EXPORT=""; FIXTURE=""; SLICE="metamask"; PERTURB=""
die() { printf 'selector-recompute: %s\n' "$1" >&2; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --module)  MODULE="${2:-}"; shift 2 ;;
    --export)  EXPORT="${2:-}"; shift 2 ;;
    --fixture) FIXTURE="${2:-}"; shift 2 ;;
    --slice)   SLICE="${2:-}"; shift 2 ;;
    --perturb) PERTURB="${2:-}"; shift 2 ;;
    --n)       N="${2:-}"; shift 2 ;;
    --label)   LABEL="${2:-}"; shift 2 ;;
    --out)     OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$MODULE" ]  || die "--module is required (import path, no extension)"
[ -n "$EXPORT" ]  || die "--export is required (the selector's exported name)"
[ -n "$FIXTURE" ] || die "--fixture is required (a JSON state fixture)"
[ -n "$PERTURB" ] || die "--perturb is required (an input key the selector genuinely reads)"
[ -f "$FIXTURE" ] || die "fixture not found: $FIXTURE"
[ -f "$MODULE.ts" ] || [ -f "$MODULE.js" ] || die "module not found: $MODULE.{ts,js}"

LABEL="${LABEL:-recompute-$EXPORT}"
mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
STAMP="$OUT_DIR/$LABEL"
PROBE="$(dirname "$MODULE")/__recompute_probe__.test.ts"

# Relative import from the probe back to the module, and up to the fixture.
MOD_BASE="./$(basename "$MODULE")"
DEPTH="$(dirname "$MODULE" | tr -cd '/' | wc -c | tr -d ' ')"
UP=""; i=0; while [ "$i" -le "$DEPTH" ]; do UP="../$UP"; i=$((i+1)); done

cleanup() { rm -f "$PROBE"; }
trap cleanup EXIT INT TERM

cat > "$PROBE" <<PROBEEOF
import { $EXPORT } from '$MOD_BASE';
import fixture from '$UP$FIXTURE';

describe('$EXPORT recomputation probe', () => {
  it('counts recomputations across three conditions', () => {
    const base = fixture as never as { $SLICE: Record<string, unknown> };
    const call = (s: unknown) => ($EXPORT as (x: never) => unknown)(s as never);

    ($EXPORT as unknown as { resetRecomputations: () => void }).resetRecomputations();
    const count = () => ($EXPORT as unknown as { recomputations: () => number }).recomputations();

    for (let i = 0; i < $N; i++) call(base);
    const a = count();

    for (let i = 0; i < $N; i++) {
      call({ ...base, $SLICE: { ...base.$SLICE, __unrelated__: i } });
    }
    const b = count();

    for (let i = 0; i < $N; i++) {
      call({ ...base, $SLICE: { ...base.$SLICE, $PERTURB: [\`0x\${i}\`] } });
    }
    const c = count();

    // eslint-disable-next-line no-console
    console.log(\`RECOMPUTE_PROBE identical=\${a} unrelated=\${b} inputChanged=\${c} n=$N\`);
    expect(c).toBeGreaterThanOrEqual(b);
  });
});
PROBEEOF

yarn jest "$PROBE" > "$STAMP.log" 2>&1
CODE=$?
cleanup; trap - EXIT INT TERM

LINE="$(grep -o 'RECOMPUTE_PROBE .*' "$STAMP.log" | head -1)"
A="$(printf '%s' "$LINE" | sed -n 's/.*identical=\([0-9]*\).*/\1/p')"
B="$(printf '%s' "$LINE" | sed -n 's/.*unrelated=\([0-9]*\).*/\1/p')"
C="$(printf '%s' "$LINE" | sed -n 's/.*inputChanged=\([0-9]*\).*/\1/p')"

if [ -z "$A" ]; then
  VERDICT="probe-failed"
elif [ "$B" -gt "$A" ]; then
  VERDICT="recomputes on unrelated writes"
else
  VERDICT="narrowed — unrelated writes cost nothing"
fi

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')"
NODE_V="$(node -v 2>/dev/null || echo unknown)"

cat > "$STAMP.json" <<JSON
{ "selector": "$EXPORT", "module": "$MODULE", "verdict": "$VERDICT", "exit": $CODE,
  "n_calls_per_condition": $N,
  "recomputations": { "identical": ${A:-null}, "unrelated_write": ${B:-null}, "input_changed": ${C:-null} },
  "env": { "head": "$HEAD_SHA", "tracked_changes": $DIRTY, "node": "$NODE_V" },
  "log": "$STAMP.log" }
JSON

{
  echo "### C4 — \`$EXPORT\` recomputation count"
  echo
  echo "**Verdict:** $VERDICT"
  echo
  echo "| Condition | Calls | Recomputations |"
  echo "|---|---|---|"
  echo "| Identical state reference | $N | ${A:-?} |"
  echo "| Fresh \`$SLICE\` slice, unrelated field | $N | ${B:-?} |"
  echo "| \`$PERTURB\` changed (a real input) | $N | ${C:-?} |"
  echo
  echo '```console'
  echo "\$ yarn jest <generated probe>"
  echo "$LINE"
  echo '```'
  echo
  echo "<sub>Measured by \`selector-recompute.sh\` via reselect's own counter; the probe is generated, run, and deleted. head \`$HEAD_SHA\` · $DIRTY tracked changes · node \`$NODE_V\`. Log: \`$STAMP.log\`.</sub>"
} > "$STAMP.md"

printf 'selector-recompute: %s\n  %s\n  %s\n' "$VERDICT" "$STAMP.json" "$STAMP.md" >&2
[ -n "$A" ] || exit 2
exit 0
