#!/usr/bin/env bash
#
# capture — turn any analysis command into a contract-compliant evidence artifact.
#
# The analysis scripts in this repo (retention-scan.py, policy-audit.py, a jest
# probe, a selector recomputation counter) all print to stdout. Printing to stdout
# means the operator is the capture device: they read it, retype some of it into a
# comment, and the result carries their provenance rather than the measurement's.
#
# This wraps any command so the ARTIFACT is written by the tool. Nothing is retyped.
#
#   capture.sh --label <slug> --lane <id> --claim "<under test>" [--verdict <word>] -- <cmd...>
#
# --verdict is stated by the caller, never inferred from the exit code: a wrapped
# tool's exit convention is its own, and guessing prints "pass" over real findings.
#
# Emits, under --out (default evidence-artifacts/):
#   <label>.log    raw stdout+stderr of the command, unmodified
#   <label>.json   machine-readable: verdict, exit code, env pin, claim
#   <label>.md     the block to attach, quoting the log rather than summarising it
#
# Exit code is the wrapped command's own, so CI gates on it unchanged.
#
# Example:
#   capture.sh --label defi-retention --lane C9 \
#     --claim "every retention primitive this diff introduces is released" \
#     -- python3 retention-scan.py ui/store/background-connection.ts pr.patch
set -uo pipefail

OUT_DIR="evidence-artifacts"; LABEL=""; LANE=""; CLAIM=""; MAXLOG=120; VERDICT=""
die() { printf 'capture: %s\n' "$1" >&2; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="${2:-}"; shift 2 ;;
    --lane)  LANE="${2:-}"; shift 2 ;;
    --claim) CLAIM="${2:-}"; shift 2 ;;
    --verdict) VERDICT="${2:-}"; shift 2 ;;
    --out)   OUT_DIR="${2:-}"; shift 2 ;;
    --max-log-lines) MAXLOG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    --) shift; break ;;
    *) die "unknown argument: $1 (did you forget -- before the command?)" ;;
  esac
done

[ -n "$LABEL" ] || die "--label is required"
[ -n "$CLAIM" ] || die "--claim is required: name the falsifiable thing under test"
[ $# -gt 0 ]    || die "no command given after --"

mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
STAMP="$OUT_DIR/$LABEL"

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')"
NODE_V="$(node -v 2>/dev/null || echo n/a)"
PY_V="$(python3 -V 2>&1 || echo n/a)"
LOCK_SHA="$( { sha256sum yarn.lock 2>/dev/null || shasum -a 256 yarn.lock 2>/dev/null; } | cut -c1-16)"
[ -n "$LOCK_SHA" ] || LOCK_SHA="n/a"
CMD_STR="$*"

# Run it. Never interpret the output — capture it verbatim.
"$@" > "$STAMP.log" 2>&1
CODE=$?

LINES="$(wc -l < "$STAMP.log" | tr -d ' ')"
# No verdict is inferred from the exit code. A wrapped tool's convention is its own —
# policy-audit.py exits 0 while listing sixteen new capability grants, so guessing here
# would print "pass" over a page of findings. The caller states the verdict or none is claimed.
[ -n "$VERDICT" ] || VERDICT="completed"

jstr() { printf '%s' "${1-}" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'; }

cat > "$STAMP.json" <<JSON
{
  "label": $(jstr "$LABEL"),
  "lane": $(jstr "$LANE"),
  "claim": $(jstr "$CLAIM"),
  "command": $(jstr "$CMD_STR"),
  "verdict": "$VERDICT",
  "exit": $CODE,
  "log": "$STAMP.log",
  "log_lines": $LINES,
  "env": { "head": "$HEAD_SHA", "tracked_changes": $DIRTY,
           "node": "$NODE_V", "python": "$PY_V", "yarn_lock_sha256_16": "$LOCK_SHA" }
}
JSON

{
  if [ "$VERDICT" = "completed" ]; then
    echo "### ${LANE:+$LANE — }ran to completion (exit $CODE) — read the output, no verdict asserted"
  else
    echo "### ${LANE:+$LANE — }\`$VERDICT\` (exit $CODE)"
  fi
  echo
  echo "**Claim under test:** $CLAIM"
  echo
  echo '```console'
  echo "\$ $CMD_STR"
  if [ "$LINES" -gt "$MAXLOG" ]; then
    head -n "$MAXLOG" "$STAMP.log"
    echo "… $((LINES - MAXLOG)) further lines in $STAMP.log"
  else
    cat "$STAMP.log"
  fi
  echo '```'
  echo
  echo "<sub>Produced by \`capture.sh\`, not transcribed. head \`$HEAD_SHA\` · $DIRTY tracked changes · node \`$NODE_V\` · \`$PY_V\` · yarn.lock \`$LOCK_SHA\`. Raw log: \`$STAMP.log\`.</sub>"
} > "$STAMP.md"

printf 'capture: %s (exit %s)\n  %s\n  %s\n  %s\n' "$VERDICT" "$CODE" "$STAMP.log" "$STAMP.json" "$STAMP.md" >&2
exit "$CODE"
