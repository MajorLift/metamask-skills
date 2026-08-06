#!/usr/bin/env bash
#
# Driver for the deterministic-interleaving run on MetaMask/metamask-extension#45249
# (MetaMask-planning#7523). Wrapped by capture.sh so the artifact is written by the
# tool rather than transcribed by an operator.
#
# Four arms, in order:
#   A  the two test files exactly as the PR ships them (three tests `it.skip`)
#   M  the mutation: strip `.skip`, then read the mutated lines back OFF DISK
#   B  the same test bodies with the skips removed — the intended-failure check
#   P  two probes that REPORT the observables both arms assert on, in a sequential
#      arm and an interleaved arm, so it is visible which assertions discriminate
#      interleaving and which would fail either way
#
# Arm M exists because an instrument reports the effect it had, never the instruction
# it was given: the `it(` lines are grepped back out of the files after the rewrite.
set -u

PROBES="$(cd "$(dirname "$0")" && pwd)"
FILES="shared/lib/trace.test.ts app/scripts/lib/sentry-trace-propagation.concurrency.test.ts"

echo "### target HEAD : $(git rev-parse HEAD)"
echo "### node        : $(node -v)"
echo "### probes from : $PROBES"
echo

echo "########## ARM A — as shipped (three tests are it.skip) ##########"
# shellcheck disable=SC2086
yarn jest $FILES > /tmp/armA.log 2>&1
echo "ARM A exit=$?"
tail -12 /tmp/armA.log
echo

echo "########## ARM M — mutation applied, then read back off disk ##########"
# shellcheck disable=SC2086
perl -pi -e 's/^(\s*)it\.skip\(/\1it(/' $FILES
echo "-- the three lines as they now exist on disk:"
# shellcheck disable=SC2086
grep -n '^\s*it(' $FILES \
  | grep -E 'still-pending|third concurrent|correlates an operation'
echo "-- remaining it.skip occurrences (expect 0 in both files):"
# shellcheck disable=SC2086
grep -c 'it\.skip' $FILES
echo

echo "########## ARM B — identical bodies, .skip removed ##########"
# shellcheck disable=SC2086
yarn jest $FILES > /tmp/armB.log 2>&1
echo "ARM B exit=$?"
cat /tmp/armB.log
echo

echo "########## RESTORE ##########"
# shellcheck disable=SC2086
git checkout -- $FILES
echo "-- it.skip restored (expect 2 and 1):"
# shellcheck disable=SC2086
grep -c 'it\.skip' $FILES
echo

echo "########## ARM P — discrimination probes (report, do not assert) ##########"
cp "$PROBES/trace.probe7523.test.ts" shared/lib/
cp "$PROBES/sentry-trace-propagation.probe7523.test.ts" app/scripts/lib/
yarn jest shared/lib/trace.probe7523.test.ts \
          app/scripts/lib/sentry-trace-propagation.probe7523.test.ts \
  > /tmp/probe.log 2>&1
echo "ARM P exit=$?"
grep -E 'PROBE|matches|baggage|ambient|correlated|Tests:' /tmp/probe.log
rm -f shared/lib/trace.probe7523.test.ts \
      app/scripts/lib/sentry-trace-propagation.probe7523.test.ts
echo
echo "### tracked files modified at exit (expect 0): $(git status --porcelain | grep -vc '^??')"

# A capture of a page that says only "Success" is a provenance frame, not evidence: it
# proves the run happened and discloses nothing it measured. So the finding is rendered
# as a TABLE, into a file of its own.
#
# It goes to evidence-artifacts/ rather than only to $GITHUB_STEP_SUMMARY because a
# job summary is part of the logs UI, which a fork gates behind sign-in — a signed-out
# reader sees the checkmark and none of the summary. A committed .md renders publicly
# on any GitHub blob view, so the table survives as something a reader can be shown.
# The workflow's own publish step cats evidence-artifacts/*.md into the job summary,
# so writing the file gets the summary placement for free.
SUMMARY_OUT="${GITHUB_STEP_SUMMARY:-/dev/null}"
[ -d evidence-artifacts ] && SUMMARY_OUT="evidence-artifacts/conc-7523-summary.md"
if [ "$SUMMARY_OUT" != /dev/null ]; then
  HEAD_SHA="$(git rev-parse --short HEAD)" python3 - "$SUMMARY_OUT" <<'PYEOF'
import os, re, sys

def read(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""

armA, armB, probe = read("/tmp/armA.log"), read("/tmp/armB.log"), read("/tmp/probe.log")

def tests_line(t):
    m = re.search(r"^Tests:.*$", t, re.M)
    return m.group(0).replace("Tests:", "").strip() if m else "not captured"

def parse_probe(label):
    m = re.search(rf"PROBE {re.escape(label)} \|(.*)$", probe, re.M)
    if not m:
        return {}
    return dict(kv.split("=", 1) for kv in
                (p.strip() for p in m.group(1).split("|")) if "=" in kv)

seq, inter, three = parse_probe("sequential"), parse_probe("interleaved"), parse_probe("interleaved-3 (C vs B)")

def corr(block):
    # The probe lines arrive indented inside jest's console output, so the block
    # terminator must tolerate leading whitespace. Without `\s*` the first block
    # ran to end-of-file and inherited the SECOND block's values — a well-formed
    # table reporting the exact opposite of the measurement.
    m = re.search(rf"PROBE {block}\n(.*?)(?=\n\s*PROBE |\Z)", probe, re.S)
    if not m:
        return {}
    return {k: v for k, v in re.findall(r"matches(\w+)=(\w+)", m.group(1))}

ci, cc = corr("INTERLEAVED"), corr(r"CONTROL \(B resolved first\)")
fails = re.findall(r"● (.+?)\n", armB)

out = [
    f"## Ordering guarantees — `metamask-extension#45249` @ `{os.environ.get('HEAD_SHA','?')}`",
    "",
    "### The two arms",
    "",
    "| arm | jest result |",
    "| --- | --- |",
    f"| A — three tests `it.skip`, as shipped | {tests_line(armA)} |",
    f"| B — same bodies, `.skip` removed | {tests_line(armB)} |",
    "",
    "### Does the observable discriminate interleaving?",
    "",
    "| observable | sequential | interleaved | discriminates |",
    "| --- | --- | --- | --- |",
    f"| 2nd span's `parent_span_id` | `{seq.get('parent_span_id(second)','?')}` "
    f"| `{inter.get('parent_span_id(second)','?')}` "
    f"| **yes** — and it equals the pending span's own id (`parentIsFirst={inter.get('parentIsFirst','?')}`) |",
    f"| `traceId(2nd) == traceId(1st)` | `{seq.get('traceIdsEqual','?')}` "
    f"| `{inter.get('traceIdsEqual','?')}` "
    "| **NO** — equal either way, so this assertion cannot witness concurrency |",
    f"| request-id correlates with own trace (`matchesA`) | `{cc.get('A','?')}` "
    f"| `{ci.get('A','?')}` | **yes** |",
    f"| request-id correlates with the *other* trace (`matchesB`) | `{cc.get('B','?')}` "
    f"| `{ci.get('B','?')}` | **yes** — misattribution, not loss |",
    "",
    f"Third concurrent call parents under **B**, not A "
    f"(`parentIsFirst={three.get('parentIsFirst','?')}` against B) — LIFO top-of-stack.",
    "",
    "### Arm B failures (all at the intended assertion)",
    "",
]
out += [f"- {f}" for f in fails] or ["- none captured"]
open(sys.argv[1], "a", encoding="utf-8").write("\n".join(out) + "\n")
PYEOF
fi
