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
