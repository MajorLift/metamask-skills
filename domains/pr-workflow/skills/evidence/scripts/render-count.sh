#!/usr/bin/env bash
#
# render-count — lane C4, the component half.
#
# `selector-recompute` answers "how often does this selector recompute". This
# answers the other C4 question: "how many times does a consumer actually
# render". A memoization claim about context or props is a claim about that
# count, and a count of call sites is not it — 149 consumers can mean 149
# avoided renders or none.
#
# Generates a probe that mounts a provider with a counting consumer, forces the
# parent to re-render N times with the memoised value unchanged, and reports the
# consumer's render count. Arm B re-runs with the memo defeated, so the delta is
# attributable rather than assumed.
#
# Usage:
#   render-count.sh --probe <probe.test.tsx> [--defeat <file> --defeat-line <n> --defeat-with <text>]
#                   [--label <slug>] [--out <dir>]
#
# The probe is supplied rather than generated: a provider's mount requirements
# are specific to the component, and a generated one would either be wrong or
# would need every prop passed on the command line. Write it once, keep it.
# It must print a line of the form:
#
#   RENDER_COUNT consumer=<n> parentRenders=<m>
#
#   0  measured           counts captured for both arms (or arm A alone if no --defeat)
#   1  no delta           arm B identical to arm A — the memo is not doing what is claimed
#   2  probe did not emit RENDER_COUNT
#   3  usage error
set -uo pipefail

OUT_DIR="evidence-artifacts"; LABEL=""; PROBE=""; DEFEAT=""; DEFEAT_LINE=""; DEFEAT_WITH=""
die() { printf 'render-count: %s\n' "$1" >&2; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --probe)       PROBE="${2:-}"; shift 2 ;;
    --defeat)      DEFEAT="${2:-}"; shift 2 ;;
    --defeat-line) DEFEAT_LINE="${2:-}"; shift 2 ;;
    --defeat-with) DEFEAT_WITH="${2:-}"; shift 2 ;;
    --label)       LABEL="${2:-}"; shift 2 ;;
    --out)         OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help)     sed -n '2,30p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$PROBE" ] || die "--probe is required"
[ -f "$PROBE" ] || die "probe not found: $PROBE"
LABEL="${LABEL:-render-$(basename "$PROBE" | sed 's/\..*$//')}"
mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
STAMP="$OUT_DIR/$LABEL"

counts_from() { grep -o 'RENDER_COUNT .*' "$1" | head -1; }
consumer_of() { printf '%s' "$1" | sed -n 's/.*consumer=\([0-9]*\).*/\1/p'; }

yarn jest "$PROBE" > "$STAMP-armA.log" 2>&1
A_LINE="$(counts_from "$STAMP-armA.log")"
A="$(consumer_of "$A_LINE")"
[ -n "$A" ] || { printf 'render-count: probe emitted no RENDER_COUNT line\n' >&2; exit 2; }

B=""; B_LINE=""
if [ -n "$DEFEAT" ] && [ -n "$DEFEAT_LINE" ]; then
  [ -f "$DEFEAT" ] || die "defeat target not found: $DEFEAT"
  BACKUP="$(mktemp)"; cp "$DEFEAT" "$BACKUP"
  restore() { cp "$BACKUP" "$DEFEAT"; rm -f "$BACKUP"; }
  trap restore EXIT INT TERM
  awk -v n="$DEFEAT_LINE" -v r="$DEFEAT_WITH" 'NR==n{print r; next}{print}' "$DEFEAT" > "$DEFEAT.tmp" && mv "$DEFEAT.tmp" "$DEFEAT"
  yarn jest "$PROBE" > "$STAMP-armB.log" 2>&1
  B_LINE="$(counts_from "$STAMP-armB.log")"
  B="$(consumer_of "$B_LINE")"
  restore; trap - EXIT INT TERM
else
  : > "$STAMP-armB.log"
fi

if [ -n "$B" ] && [ "$B" = "$A" ]; then VERDICT="no delta — memo not attributable"; CODE=1
elif [ -n "$B" ]; then VERDICT="delta measured: $A → $B renders with the memo defeated"; CODE=0
else VERDICT="baseline only: $A consumer renders"; CODE=0; fi

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')"
NODE_V="$(node -v 2>/dev/null || echo unknown)"

cat > "$STAMP.json" <<JSON
{ "probe": "$PROBE", "verdict": "$VERDICT", "exit": $CODE,
  "consumer_renders": { "armA": ${A:-null}, "armB": ${B:-null} },
  "env": { "head": "$HEAD_SHA", "tracked_changes": $DIRTY, "node": "$NODE_V" },
  "logs": ["$STAMP-armA.log", "$STAMP-armB.log"] }
JSON

{
  echo "### C4 — consumer render count"
  echo
  echo "**Verdict:** $VERDICT"
  echo
  echo "| Arm | Change | consumer renders |"
  echo "|---|---|---|"
  echo "| A — as committed | none | ${A:-?} |"
  [ -n "$B" ] && echo "| B — memo defeated | \`$DEFEAT:$DEFEAT_LINE\` | $B |"
  echo
  echo '```console'
  echo "\$ yarn jest $PROBE"
  echo "$A_LINE"
  [ -n "$B_LINE" ] && { echo "\$ yarn jest $PROBE   # memo defeated"; echo "$B_LINE"; }
  echo '```'
  echo
  echo "This counts renders of one named consumer across a defined interaction. It is not a count"
  echo "of consumers, and a larger consumer count does not imply a larger effect."
  echo
  echo "<sub>Produced by \`render-count.sh\`; the defeat edit is reverted after the run. head \`$HEAD_SHA\` · $DIRTY tracked changes · node \`$NODE_V\`. Logs: \`$STAMP-armA.log\`, \`$STAMP-armB.log\`.</sub>"
} > "$STAMP.md"

printf 'render-count: %s\n  %s\n  %s\n' "$VERDICT" "$STAMP.json" "$STAMP.md" >&2
exit "$CODE"
