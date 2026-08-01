#!/usr/bin/env bash
#
# tsc-substitution — arm A/B against the type checker.
#
# A hand-written type that restates an authoritative source either agrees with it
# or does not, and `tsc` is the only thing that can settle which. Reading the two
# declarations side by side does not: TypeScript's assignability rules are not
# obvious by inspection, which is the entire reason the lane exists.
#
#   Arm A  baseline typecheck, errors recorded
#   Arm B  the substitution applied — the hand-written type replaced by the derived
#          one, or a cast removed — typecheck re-run, errors diffed
#
# The finding is the DIFF: error codes present in B and absent in A are what the
# hand-written type or the cast was concealing.
#
#   0  divergence surfaced   new errors in arm B    → the local type disagrees
#   1  no divergence         identical error sets   → substitution is silent
#   2  arm A already failing → nothing to conclude
#   3  usage/env error
#
# A silent result is NOT proof of agreement. Existing call sites may type-check
# against both shapes (indexing a `string` and a `string[]` both compile), so use
# --probe to inject a deliberately-typed sink that only one shape satisfies.
#
# Usage:
#   tsc-substitution.sh --file <path> --line <n> --replace <text>
#                       [--probe-line <n> --probe <text>] [--label <slug>]
#                       [--tsc "<command>"]
set -uo pipefail

TSC="yarn lint:tsc"; OUT_DIR="evidence-artifacts"; LABEL=""
FILE=""; LINE=""; REPLACE=""; PROBE_LINE=""; PROBE=""
die() { printf 'tsc-substitution: %s\n' "$1" >&2; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --file)       FILE="${2:-}"; shift 2 ;;
    --line)       LINE="${2:-}"; shift 2 ;;
    --replace)    REPLACE="${2:-}"; shift 2 ;;
    --probe-line) PROBE_LINE="${2:-}"; shift 2 ;;
    --probe)      PROBE="${2:-}"; shift 2 ;;
    --label)      LABEL="${2:-}"; shift 2 ;;
    --out)        OUT_DIR="${2:-}"; shift 2 ;;
    --tsc)        TSC="${2:-}"; shift 2 ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$FILE" ] || die "--file is required"
[ -f "$FILE" ] || die "file not found: $FILE"
[ -n "$LINE" ] || [ -n "$PROBE" ] || die "give --line/--replace, or --probe-line/--probe, or both"
LABEL="${LABEL:-tsc-$(basename "$FILE" | sed 's/\.[^.]*$//')}"
mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
STAMP="$OUT_DIR/$LABEL"

BACKUP="$(mktemp)" || die "mktemp failed"
cp "$FILE" "$BACKUP"
restore() { cp "$BACKUP" "$FILE"; rm -f "$BACKUP"; }
trap restore EXIT INT TERM

# tsc exits non-zero on any error, so the error SET is the signal, not the exit code.
errors_of() { grep -oE "error TS[0-9]+" "$1" 2>/dev/null | sort | uniq -c | sed 's/^ *//'; }

$TSC > "$STAMP-armA.log" 2>&1
A_ERRS="$(errors_of "$STAMP-armA.log")"
A_COUNT="$(grep -c "error TS" "$STAMP-armA.log" 2>/dev/null || echo 0)"

if [ "$A_COUNT" -gt 0 ]; then
  # Distinguish a genuinely failing repo from an incomplete local install. A baseline
  # dominated by TS2305/TS2724/TS2307 ("has no exported member" / "cannot find module")
  # means dependency types were never generated — `yarn install --mode=skip-build` does
  # exactly this — and says nothing about the code. Reporting both as "baseline failing"
  # would send the operator hunting a repo defect that is not there.
  # Report the module/export share; do not classify from it. A threshold here would be
  # a number I cannot justify — 124/280 on this repo is plainly an install artifact, yet
  # trips no majority rule, because TS2339 and TS7006 are themselves downstream of the
  # missing types. Surface the signal, leave the judgement with the operator.
  ENVISH="$(grep -coE "error TS(2305|2307|2724)" "$STAMP-armA.log" || echo 0)"
  VERDICT="baseline failing — no conclusion available"
  CODE=2; B_COUNT="not-run"; NEW_ERRS=""
  : > "$STAMP-armB.log"
else
  # Apply substitution and/or probe, highest line first so numbering holds.
  apply() { awk -v n="$1" -v r="$2" 'NR==n{print r; next}{print}' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"; }
  insert() { awk -v n="$1" -v r="$2" 'NR==n{print; print r; next}{print}' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"; }
  if [ -n "$PROBE" ] && [ -n "$PROBE_LINE" ] && [ -n "$LINE" ] && [ "$PROBE_LINE" -gt "$LINE" ]; then
    insert "$PROBE_LINE" "$PROBE"; apply "$LINE" "$REPLACE"
  else
    [ -n "$LINE" ] && apply "$LINE" "$REPLACE"
    [ -n "$PROBE" ] && [ -n "$PROBE_LINE" ] && insert "$PROBE_LINE" "$PROBE"
  fi

  $TSC > "$STAMP-armB.log" 2>&1
  B_COUNT="$(grep -c "error TS" "$STAMP-armB.log" 2>/dev/null || echo 0)"
  NEW_ERRS="$(grep -oE "error TS[0-9]+.*" "$STAMP-armB.log" 2>/dev/null | sort -u | head -12)"
  restore; trap - EXIT INT TERM
  if [ "$B_COUNT" -gt 0 ]; then VERDICT="divergence surfaced"; CODE=0; else VERDICT="substitution silent"; CODE=1; fi
fi

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')"
TS_V="$(yarn tsc --version 2>/dev/null | tail -1 || echo unknown)"

cat > "$STAMP.json" <<JSON
{ "verdict": "$VERDICT", "exit": $CODE, "file": "$FILE",
  "arm_a_errors": $A_COUNT, "arm_b_errors": ${B_COUNT:-null},
  "env": { "head": "$HEAD_SHA", "tracked_changes": $DIRTY, "typescript": "$TS_V" },
  "logs": ["$STAMP-armA.log", "$STAMP-armB.log"] }
JSON

{
  echo "### D6 — authored-vs-authoritative substitution · \`$VERDICT\`"
  echo
  echo "| Arm | Change | \`tsc\` errors |"
  echo "|---|---|---|"
  echo "| A — baseline | none | $A_COUNT |"
  echo "| B — substituted | \`$FILE\`${LINE:+:$LINE}${PROBE:+ + typed sink} | ${B_COUNT} |"
  echo
  if [ "$CODE" = "2" ] && [ "${ENVISH:-0}" -gt 0 ]; then
    echo "Arm A did not pass, so arm B was not run and **nothing about the types is established**."
    echo
    echo "\`$ENVISH\` of \`$A_COUNT\` baseline errors are module/export resolution"
    echo "(TS2305/TS2307/TS2724). Those usually mean dependency types were never generated —"
    echo "a skipped install step — rather than a defect in this repo, and other codes can be"
    echo "downstream of the same cause. Confirm the toolchain is complete before reading"
    echo "anything into this lane."
  elif [ -n "$NEW_ERRS" ]; then
    echo "Errors surfaced only under substitution:"; echo; echo '```'; printf '%s\n' "$NEW_ERRS"; echo '```'
  elif [ "$CODE" = "1" ]; then
    echo "**Silent — this is not proof of agreement.** Existing call sites may satisfy both shapes."
    echo "Re-run with \`--probe\` to inject a sink only the authoritative type accepts."
  fi
  echo
  echo "<sub>Produced by \`tsc-substitution.sh\`; source restored after the run. head \`$HEAD_SHA\` · $DIRTY tracked changes · $TS_V. Logs: \`$STAMP-armA.log\`, \`$STAMP-armB.log\`.</sub>"
} > "$STAMP.md"

printf 'tsc-substitution: %s (exit %s)\n  %s\n  %s\n' "$VERDICT" "$CODE" "$STAMP.json" "$STAMP.md" >&2
exit "$CODE"
