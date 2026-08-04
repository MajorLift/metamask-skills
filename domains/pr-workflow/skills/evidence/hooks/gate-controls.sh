#!/usr/bin/env bash
#
# Control matrix for the emit-time gate. Run it from anywhere; it copies the hook to a
# directory with no sibling scripts/ so `_find_gate()` resolves the way it does in
# production rather than the way it does in a checkout.
#
# It exists because three copies of this hook were on one machine, the oldest was the one
# wired into settings, and it had no `gh api` matcher — so every publish through that path
# went ungated for weeks while two newer copies sat unused. Nothing noticed, because a gate
# that blocks nothing is indistinguishable from a gate with nothing to block.
#
# Positives must block (exit 2). Negatives must pass (exit 0). Both halves matter: a gate
# that blocks everything is as broken as one that blocks nothing, and only the negative
# arm catches it.
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")" && pwd)/pr-evidence-gate.py}"
[ -f "$HOOK" ] || { echo "usage: gate-controls.sh [path/to/pr-evidence-gate.py]" >&2; exit 2; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$HOOK" "$tmp/hook.py"

printf '<!-- LAVAMOAT_DILIGENCE_START -->\n**LavaMoat grants — x**\n\n```\n$ yarn build\n  exit 0\n```\n<!-- LAVAMOAT_DILIGENCE_END -->\n' > "$tmp/bad.md"
printf 'Addressed: see the linked run.\n' > "$tmp/reply.md"
# The enrichment rule needs the REPORT shape, not report vocabulary: three or more
# paragraphs, a cited link, and no reply-template opener. A one-line probe passes it for
# the wrong reason, which is how a mis-specified positive arm reads as a working rule.
cat > "$tmp/finding.md" <<'BODY'
The migration path is ground-truthed against the fixture set and rules out the ordering hazard.

Two of the three cases resolve through the same upstream guard, so the remaining exposure is
the un-guarded third: https://github.com/o/r/blob/abc123/src/migrate.ts#L40

That leaves the rollback lane unaccounted for, which is worth its own pass before this lands.
BODY

probe() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")"; }

fails=0
check() { # name expected command
  local name="$1" want="$2" cmd="$3" got
  probe "$cmd" | python3 "$tmp/hook.py" >/dev/null 2>&1; got=$?
  if [ "$got" = "$want" ]; then printf '  ok    %-34s exit=%s\n' "$name" "$got"
  else printf '  FAIL  %-34s exit=%s want=%s\n' "$name" "$got" "$want"; fails=$((fails+1)); fi
}

echo "gate-controls: $HOOK"
check "positive: gh api body write"   2 "gh api repos/o/r/issues/comments/1 -X PATCH -F body=@$tmp/bad.md"
check "positive: gh pr comment"       2 "gh pr comment 1 --repo o/r --body-file $tmp/bad.md"
check "positive: finding via comment" 2 "gh issue comment 1 --repo o/r --body-file $tmp/finding.md"
check "negative: unrelated command"   0 "ls -la"
check "negative: gh read, no body"    0 "gh pr view 1 --repo o/r"
check "negative: a reply is a reply"  0 "gh issue comment 1 --repo o/r --body-file $tmp/reply.md"

echo
[ "$fails" -eq 0 ] && { echo "gate-controls: all arms behave"; exit 0; }
echo "gate-controls: $fails arm(s) wrong — the gate is not doing what it claims"; exit 1
