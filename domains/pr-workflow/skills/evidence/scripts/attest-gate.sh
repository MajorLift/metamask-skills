#!/usr/bin/env bash
#
# attest-gate — phase 0 of /attest. Mechanical, no model, hard fails only.
#
# Everything checkable is checked before anything is asked of a model, because a
# model asked "is this good evidence?" answers from inside the frame that produced
# the text. These are greppable, so they are not a matter of judgement.
#
# Usage: attest-gate.sh <artifact.md> [--reference <showcase.html>]
#
#   0  all checks pass       → proceed to the dispatched passes
#   1  one or more failed    → BLOCKED, do not publish
#   2  usage error
set -uo pipefail

FILE="${1:-}"; REF=""
[ $# -ge 2 ] && [ "${2:-}" = "--reference" ] && REF="${3:-}"
[ -n "$FILE" ] || { echo "usage: attest-gate.sh <artifact.md> [--reference <file>]" >&2; exit 2; }
[ -f "$FILE" ] || { echo "attest-gate: not found: $FILE" >&2; exit 2; }

FAILED=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n       %s\n' "$1" "$2"; FAILED=$((FAILED+1)); }
has()  { grep -qF "$1" "$FILE"; }
hasre(){ grep -qE "$1" "$FILE"; }
hasi() { grep -qiE "$1" "$FILE"; }   # case-insensitive; a separate function because
                                     # `hasre -i '<pat>'` silently greps for "-i".

echo "attest-gate: $FILE"
echo

has 'VALIDATION_RUN_START' && has 'VALIDATION_RUN_END' \
  && pass "1 marker pair" \
  || fail "1 marker pair" "no VALIDATION_RUN_START/_END — a re-run appends a duplicate instead of replacing"

has '## 🧪 Validation Run' \
  && pass "2 canonical header" \
  || fail "2 canonical header" "missing '## 🧪 Validation Run'"

hasre '^\*\*Verdict:\*\*.*\*\*Claim:\*\*' \
  && pass "3 verdict line" \
  || fail "3 verdict line" "no '**Verdict:** … — **Claim:** …' — valence is not legible at a glance"

# A run outside the repo's toolchain pins a different thing. A browser-memory lane
# names "Firefox 153.0"; a repo lane names a head SHA and a lockfile hash. Both are
# pins, and a check that only knows the second one fails every run of the first —
# telling an author their pinned environment is unpinned.
hasre 'head `[0-9a-f]{7,}|sha256|node `v|yarn\.lock `|[Ff]irefox [0-9]+\.[0-9]|[Cc]hrom(e|ium) [0-9]+\.|[Ss]afari [0-9]+\.|[Nn]ode v?[0-9]+\.[0-9]' \
  && pass "4 environment pinned" \
  || fail "4 environment pinned" "no head SHA, lockfile hash, or pinned toolchain/browser version"

# 5 — the one that matters. A tool-written log, a run link, or an image; not typed prose.
if hasre '!\[|<img|data:image|actions/runs|/gist\.|evidence-artifacts/|Produced by '; then
  pass "5 captured artifact"
else
  fail "5 captured artifact" "every block appears operator-typed; no tool-written log, run link, or image referenced"
fi

if hasi 'what would close it|what would prove it|closing it requires'; then
  fail "6 no prescriptions" "contains a 'what would close it' section — that is an unfinished run, formatted to look finished"
elif hasre '^\s*(Run|Switch|Assert|Scroll|Compare) '; then
  fail "6 no prescriptions" "imperative-mood instructions to the reader — the artifact does not exist"
else
  pass "6 no prescriptions"
fi

if hasi "I originally|correction to my earlier|filed by me|hard to calibrate|I withdraw|my earlier comment"; then
  fail "7 no process narration" "contains first-person process commentary — the reader did not see the earlier draft, and the byline may not be yours"
else
  pass "7 no process narration"
fi

if hasi '\*\*Verdict:\*\*.*proven' && ! hasre 'Produced by |actions/runs|evidence-artifacts/'; then
  fail "8 verdict is earned" "claims 'proven' with no execution artifact — reading yields 'unverified'"
else
  pass "8 verdict is earned"
fi

# 9 — the wrapper's verdict must not contradict the artifact it embeds. A comment is
# assembled by hand around machine output, and the hand-written header is exactly where
# a "vacuous" result acquires a "proven" label.
HDR="$(grep -m1 '^\*\*Verdict:\*\*' "$FILE" | tr 'A-Z' 'a-z')"
BODY="$(grep -ioE 'vacuous|value unstable|no delta|nothing falsified|broke the module|substitution silent|probe-failed' "$FILE" | head -1 | tr 'A-Z' 'a-z')"
if printf '%s' "$HDR" | grep -q 'proven' && [ -n "$BODY" ]; then
  fail "9 verdict matches artifact" "header claims 'proven' while the embedded artifact reports '$BODY'"
else
  pass "9 verdict matches artifact"
fi

# 10 — the positive counterpart to check 6. A run succeeds by putting concerns in front
# of a reviewer, so an artifact that floats nothing has reported only what it happened to
# measure and called that the whole picture. This is NOT satisfied by a "what would close
# it" section, which check 6 rejects: that hands the reader the run's own unfinished work,
# whereas this names a limit or a question the run is right to leave open.
#
# The vocabulary is a fixed list because this phase asks no model anything. That makes
# it blind to a limit phrased outside the list — a real run stated its limit as "what it
# does not establish" and the check called it absent. Add phrases when that happens;
# judging whether the stated limit is substantive is the dispatched passes' job.
if hasi 'open for review|raise with a human|falsifier|worth a look|left unmeasured|not covered by this run|no verdict offered|does not establish|what it does not|cannot attribute'; then
  pass "10 floats something for review"
else
  fail "10 floats something for review" "no limit, open question, or falsifier named — an artifact that floats nothing implies its measurement was the whole surface"
fi

if [ -n "$REF" ] && [ -f "$REF" ]; then
  r=$(grep -coE '!\[|<img|data:image' "$REF"); c=$(grep -coE '!\[|<img|data:image|evidence-artifacts/|Produced by' "$FILE")
  echo
  printf '  ratio  reference captures: %s | this artifact: %s\n' "$r" "$c"
  [ "$c" -eq 0 ] && [ "$r" -gt 0 ] && printf '         reference is capture-led and this is prose-only — see check 5\n'
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "attest-gate: phase 0 clean — proceed to /outframe ‖ /missing ‖ /press"
  exit 0
fi
echo "attest-gate: BLOCKED — $FAILED check(s) failed. Do not publish."
exit 1
