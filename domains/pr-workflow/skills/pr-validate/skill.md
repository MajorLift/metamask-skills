---
name: pr-validate
description: Validate a MetaMask PR with objective evidence — primarily the Autonomous Engineering Platform (AEP) harness (visual_validation for visible UI behavior, perf_validation for non-visible perf behavior), backed by complementary evidence (Sentry query links, screenshots, screen recordings→GIF, DevTools/CDP output, bundle-size, web-vitals, test/CI results). Drives the AEP local stack end to end: preflight (postgres + temporal + worker + control-plane) → submit POST /v1/tasks → poll GET /v1/runs/:id → fetch artifacts → assemble an evidence bundle → publish to the PR body (re-hosting images to a public repo, scrubbing local paths). Match evidence to the PR's specific falsifiable claim, not a fixed checklist. Triggers on /pr-validate, /pr-validate visual, /pr-validate perf, /pr-validate preflight, /pr-validate status, /pr-validate evidence, /pr-validate plan, or when the user mentions validating/proving a PR, AEP / visual validation / perf validation, capturing evidence for a PR, before/after screenshots, a screen recording or GIF for a PR, attaching Sentry links or DevTools output as proof, or publishing an evidence bundle to a PR body.
maturity: experimental
---

# /pr-validate

Prove a PR does what it claims with **objective, reviewer-grade evidence**. The primary engine is the **Autonomous Engineering Platform (AEP)** harness run locally — `visual_validation` for visible UI behavior, `perf_validation` for non-visible perf behavior — augmented by whatever complementary evidence the claim demands (Sentry query links, screenshots, screen recordings, DevTools/CDP output, bundle/web-vitals/test results).

This skill **executes**: it brings up the local stack, runs the harness, captures artifacts, assembles the bundle, and — **only with confirmation** — publishes to the public PR body. The platform decides what passes; the model does not declare victory. See the AEP creed: *"Tests prove the code compiles. Screenshots prove the user actually sees the fix."*

> **Hard rule — demonstrate, don't claim.** Every verdict must *demonstrate that the **ticket objective** is achieved* with an inspectable artifact (link / screenshot / screen recording / run / Sentry query / CDP capture) — never explain or claim in prose that it is achieved. Anchor to the linked issue's objective, not just the PR body's self-description. An unbacked "objective achieved" narrative is a vacuous pass → report **⚠️ inconclusive** and name what's missing; never upgrade prose to **✅ proven**.

## Principles

Twenty rules the rest of this skill implements. When a situation isn't covered below, decide by these.

**What you may claim**
- **Falsifiability** — name the observation that would disprove the claim, then go looking for it. A review that cannot fail is not a review.
- **Falsifier coverage is not exhaustive — human intervention point.** There is no fixed checklist, so there is no completeness guarantee: the falsifiers found are bounded by claim-extraction quality and by what the reviewer thought to test. "No falsifier fired" is not "no falsifier exists." A human judges whether the falsifier chosen matches the claim's actual risk, and whether a mixed or high-stakes claim needed more than one — this skill closes the falsifiers it finds, it does not attest that it found all of them.
- **Diff-anchored** — the claim is what the code *can* do, not what the PR body promises. Drift between them is a finding, not a claim.
- **Surface-specific, and a surface need not be a screen** — a job graph, a build artifact, a policy file, or a telemetry shape are all legitimate surfaces with their own falsifiers.

**What counts as evidence**
- **Demonstrate, don't claim** — a verdict shows the objective met with an inspectable artifact. Prose asserting it is a vacuous pass.
- **In situ** — present output on the tool's own surface (the run page, the Discover view, the trace waterfall, the console). Retyping output into the report launders evidence into claim: verbatim text proves nothing about provenance, and a transcription is a place to be selective without noticing you are being selective.
- **Reproducibility of assertions** — the bar is not that the reader *can* re-run it (a working link is the floor) but that they *needn't*: the exhibit is complete enough — the numbers, the window, the method, the control — that reading it makes the result near-certain. The re-issuable link/query is a backstop for the skeptic, offered second, never the headline.

**Why believe it**
- **No vacuous passes** — green is not proof. Assert non-empty artifacts; ask whether the assertion *could* have failed and whether the test exercises the changed code.
- **Check the instrument, not just the result** — measurement design can manufacture a finding. Verify the treatment is actually delivered in each arm before interpreting any delta.
- **Removing a bias is not establishing validity** — correcting a flaw you found licenses only that correction. A trust gate names how the evidence could *still* be vacuous; if the sentence describes work you did rather than risk that remains, it is not a gate.
- **A null states its power** — when the spread exceeds the effect under test, report *not resolvable at this n* and name the smallest detectable effect. Never let it read as "no effect".
- **Premises are claims** — probe the *because* ("unavailable", "access-limited", "can't be done here") as hard as the verdict. A false premise silently justifies the wrong method, and "unavailable" is the highest-suspicion premise because it licenses weaker evidence.
- **Recompute stated counts** against the source before publishing. A number true of an earlier draft's scope is the commonest stale fact.

**When to stop**
- **Stop at the falsifier** — match the bar to the claim's risk; evidence past the closed falsifier is noise.
- **Defer to CI** where CI already covers it, unless the coverage is itself the point.
- **State what was not covered** — steps that could not be automated are recorded as open, with the reason. A report listing only successes reads the same as one where nothing was checked.

**How it is handled**
- **Refutation is a successful validation** — report it, localize it, hand back the repro. Don't fix, and don't publish a failure to someone else's PR unprompted.
- **Publish surface follows ownership** — the PR body when you authored it; a comment when validating someone else's.
- **Scrub before publishing, confirm before any public write** — local paths and usernames leak through failure summaries; one PR's approval does not carry to the next.
- **Isolate concurrent runs** — colliding ports, artifact dirs, or upload paths cross-contaminate evidence *silently*. That is an integrity failure, not flakiness.

## The core move: match evidence to the claim

A PR makes a **falsifiable claim** ("privacy mode now hides the Perps balance"; "hovering the asset row preloads the chart with no double-fetch"; "this cuts startup http.client time"). Validation = pick the evidence that would **falsify that claim if it were false**, then run it. Do not run a fixed checklist.

**Step 1 — extract the claim.** Read the PR (`gh pr view`, `gh pr diff`) *and the linked issue*, then write a **Claim Card** — the linchpin; every lane is only as good as the claim. Full rubric, anti-patterns, and special cases (refactor/no-op, bug-fix, perf, migration, flag-gated): **[references/claim-extraction.md](references/claim-extraction.md).**

```
Claim:     Given <precondition>, when <action>, then <observable>.
Surface:   <screen / API / metric>  (reachable? seed / flag / fallback: …)
Type:      <visible | perf | telemetry | state | build | behavior>  → lanes <…>
Falsifier: <observation that would disprove the claim>
Baseline:  <base ref | fails-on-main test | before-window>
```

A claim must be falsifiable, surface-specific, **anchored to the diff** (if the body promises X but the diff can't deliver it, flag the drift — that's a finding, not a claim), bounded, and quantified where it's a perf claim. Decompose a mixed PR into one card per claim.

**Step 2 — match each claim to lanes** from the [evidence catalog](references/evidence-catalog.md):

| Claim shape | Primary lane | Complementary |
|---|---|---|
| Visible UI change (layout, copy, show/hide, theme) | **A1 `visual_validation`** / B1 mm-CLI — before/after screenshots | recording→GIF for motion; B5 a11y |
| A bug fix (any kind) | **⭐ B3 falsifying test** — fails on `main`, passes on the branch | A1/B1 if visible; E1 if it errored |
| Non-visible perf (preload, no-double-fetch, lazy-load, chunk) | **A2 `perf_validation`** — falsifiable assertions | C6 CDP netlog, D2 chunk membership |
| Render / over-render | **C4 WDYR + `devtools:react`** | C1 startup traces |
| Interaction responsiveness / startup timing | **C2 INP · C3 TBT · C5 benchmark (paired A/B)** | C1 phase traces, C6 profile |
| Telemetry / error-rate / latency in prod | **E1 Sentry links** (before/after) | E2 Tempo; span-volume → `/sentry-quota` |
| Bundle / build output | **D1 size · D2 chunk membership** | — |
| A dependency change is safe | **D3 LavaMoat policy + D4 manifest diff** | D1 size |
| Runtime containment still holds | **F8 SES lockdown / scuttling, on the shipped variant** | D3 policy |
| Persisted-state change | **⭐ F1 migration** (`changedKeys`, old→new state) | F2 vault round-trip |
| Tx / dapp / flag / snap / i18n behavior | **F3 sim · F4 provider · F5 flag matrix · F6 snaps · F7 i18n** | B2 e2e trace |
| Behavior with no UI | **B3 test + G4 repro** | G1 CI checks |

Lane IDs (A1, B3, …) index [references/evidence-catalog.md](references/evidence-catalog.md) — the full menu with verified capture commands and the complete matching guide. When a PR mixes claims (a UI fix that also shifts a metric), run more than one lane and assemble them into one bundle.

## When to use

- **Prove a PR** before requesting review or merge — produce the before/after a reviewer expects.
- **Re-validate** after a force-push or a requested change.
- **Back a perf/telemetry claim** with numbers and links, not prose.
- **Assemble + publish** an evidence bundle from a run you already have (`evidence` subcommand).

Not for code-correctness review (use `/review`, `/code-review`) or span-quota review (use `/sentry-quota`). This skill proves *behavior*, not code quality.

## Subcommands

| Invocation | Behavior |
|---|---|
| `/pr-validate <pr>` | **Flagship.** Read the PR → state the claim → pick lanes → [preflight](#preflight) → run AEP lane(s) + gather complementary evidence → assemble bundle → **propose** the PR-body section and confirm before publishing. |
| `/pr-validate plan <pr>` | Dry run: read the PR, state the claim, recommend lanes + targeting hints. No stack, no run. Cheap first step when unsure. |
| `/pr-validate visual <pr>` | AEP `visual_validation` only. |
| `/pr-validate perf <pr>` | AEP `perf_validation` only — check the graph is present first, see [caveat](#perf_validation-caveat). |
| `/pr-validate preflight` | Health-check the local stack; bring up what's down. No run. |
| `/pr-validate status <run-id>` | Poll `GET /v1/runs/:id`; print stage timeline + `evidenceBundle.artifactRefs`. |
| `/pr-validate evidence <pr> [--run <id>]` | Assemble + publish a bundle from an existing run and/or complementary sources (Sentry/screens/devtools). No new AEP run. |
| `/pr-validate lane <id> <pr>` | Run a single [catalog](references/evidence-catalog.md) lane by id (e.g. `lane F1`, `lane C3`, `lane D3`) — for the non-AEP lanes where you know the claim type. |
| `/pr-validate compare <pr>` | Paired A/B for a perf or refactor claim: build base + head, capture the lane on both, diff. Avoids the stale-baseline trap (catalog C5). **Per-arm treatment check first:** verify the mechanism under test is actually active in each arm (chunk split present, span emitted, flag evaluated) before interpreting deltas — a null arm without delivered treatment is a no-op, not a control (2026-07-22, #42795 bisect lesson). |

`<pr>` is a number or URL on `MetaMask/metamask-extension` unless another repo is given. Every variant runs Step 1 (extract the Claim Card) first — the claim decides the lane, even when you named one.

## Preflight

The AEP harness runs as a local stack: postgres, a temporal server, a worker, and a control plane. Bring-up steps, required Node version, registry auth, and environment are documented in the [AEP repository](https://github.com/MetaMask/metamask-autonomous-engineering-platform) itself — follow its README rather than a copy here, which drifts. Health-check first and bring up only what is down.

Fast checks:

```bash
curl -fsS localhost:3000/health >/dev/null && echo "control-plane up"   || echo "control-plane DOWN"
curl -fsS localhost:8233 >/dev/null && echo "temporal UI up"            || echo "temporal DOWN"
docker ps --format '{{.Names}}' | grep -E 'aep-postgres|aep-temporal'
```

If the control plane answers on `localhost:3000/health`, the stack is ready and you can skip to *Run mechanics*.

## Teardown

The stack is the heaviest thing this skill starts — postgres + temporal + a Node worker + control-plane — and the worker holds a live Claude session while the autonomous run itself spends tokens. It is **on-demand, not resident**: bring it up for the validation window, **tear it down when the run(s) finish**. Left up, it's the single largest reclaimable footprint on a shared host and quietly keeps a Claude seat warm.

- **If your host wraps the stack in a service manager**, use its own down command — it stops the services and removes the `--rm` postgres/temporal containers, so state resets on the next bring-up (fine, each run is fresh anyway).
- **Otherwise:** stop the `yarn dev:*` processes and remove the postgres/temporal containers.
- **Tear down on every exit path** — pass, refutation, *or* abort. A failed or abandoned run leaves the stack up exactly as much as a passing one; the usual leak is walking away after a refutation without stopping it.

## Run mechanics (submit → poll → fetch)

The control-plane is a thin REST shell. Submit a PR-validation task, poll the run, pull artifacts from the evidence bundle.

```bash
CP=localhost:3000
PR="https://github.com/MetaMask/metamask-extension/pull/<n>"

# Submit (publishEvidence:false ALWAYS for local runs — the platform otherwise
# writes to the public PR body even on failure, leaking local paths/usernames)
RUN_ID=$(curl -fsS -X POST "$CP/v1/tasks" -H 'content-type: application/json' -d '{
  "repo": "MetaMask/metamask-extension",
  "title": "Visual validation — PR #<n>",
  "taskClass": "visual_validation",
  "externalRef": "'"$PR"'",
  "payload": { "prUrl": "'"$PR"'", "description": "<targeting hint>", "publishEvidence": false }
}' | node -e 'process.stdin.on("data",d=>console.log(JSON.parse(d).runId||JSON.parse(d).id))')

# Poll
curl -fsS "$CP/v1/runs/$RUN_ID" | node -e 'const r=JSON.parse(require("fs").readFileSync(0));console.log(r.status); (r.evidenceBundle?.artifactRefs||[]).forEach(a=>console.log(a.name,a.mediaType))'

# Fetch an artifact
curl -fsS "$CP/v1/runs/$RUN_ID/artifacts/<artifactName>" -o /tmp/<artifactName>
```

- `taskClass`: `visual_validation` or `perf_validation`. The worker auto-enriches the payload from `prUrl` (pulls headSha, base, diff, files, linked issues via the GitHub app) — you only supply `prUrl` + a `description` targeting hint.
- The **targeting hint** (`payload.description`) is how you steer the agent to the surface under test. Be specific: which screen, which control, what to toggle. For hard-to-reach surfaces, name the reachable fallback (e.g. the Shield entry modal stands in for the Perps tutorial modal, which is gated in the default fixture).
- Artifact regex allows **png/jpg/log/txt only** — no video. Screen recordings need the side-channel recipe (catalog + publishing reference).

### Concurrent runs (multiple agents / parallel lanes)

Five shared resources need per-run isolation on one machine — collisions cross-contaminate evidence *silently* (wrong session's logs attributed to a run), which is an integrity failure, not flakiness: **(1)** CDP debug ports — derive per run, never hardcode; **(2)** e2e harness service ports (anvil/proxy/fixture/mocha) — one e2e run at a time per worktree, one worktree per agent, and never rebuild `dist/` in a worktree with an active run; **(3)** artifact dirs — per-run namespaces; `test-artifacts/` is per-worktree shared state, harvest failure artifacts before the next run overwrites the same test-title dir; **(4)** evidence-repo uploads — run-scoped paths (`pr-<n>/<run-id>/`), retry-with-fresh-sha on 409, never overwrite another run's published files; **(5)** commit-pinning — pin only after your own final upload lands, verifying your files exist at that sha. Safe to share: registry auth, a read-only `dist/`, the AEP stack itself.

### Trust the evidence (anti-reward-hacking)

A green result is not proof. The vacuous-pass trap is the floor: if `promptCrafter` errors, the chain "passes" via skip with **zero artifacts** — a pass is only real if `evidenceBundle.artifactRefs` is non-empty with the expected media. Beyond that, every lane must clear a trustworthiness gate before you believe or publish it: **does the artifact show the *claimed* surface** (not a spinner/wrong screen), **does the test exercise the *changed* code** (fails on `main`), **does the signal exceed noise**, **could the assertion have failed**? The Claim Card's Falsifier is the anchor. Full gate + per-lane traps: **[references/evidence-trustworthiness.md](references/evidence-trustworthiness.md).**

### perf_validation caveat

The `perf-validation/` graph writes falsifiable network/static/smoke assertions and gives the tester deterministic `.aep/` helpers (CDP netlog, phase segmentation, source-map chunk membership). Two constraints worth knowing before a perf run:

- It requires a `yarn webpack --test` build first — the browserify `build:test` has no code splitting, so `import()` never hits the network there.
- Temporal caps activity results at ~2MB, so artifact refs must be content-free; only `evidenceBundle` carries base64.

**Check the graph is present in your AEP checkout before relying on it.** It is newer than the visual-validation graph and may not be in every version — if it isn't registered, perf runs silently won't dispatch, and the fallback is manual DevTools/CDP capture (see the catalog).

## Complementary evidence

AEP is primary but rarely sufficient alone. Pull whatever the claim needs — **and proactively suggest evidence the PR author likely didn't think of**. The catalog is grouped into 7 families; full menu with verified capture commands and "what it proves": **[references/evidence-catalog.md](references/evidence-catalog.md).** Families:

- **A. AEP** — `visual_validation` / `perf_validation` / bundle byproducts (primary autonomous engine).
- **B. Behavior & flow** — mm-CLI visual, E2E trace+video, **⭐ falsifying regression test** (fails on main, passes on branch — the strongest bug proof), Storybook/component, a11y, flaky-stability rerun.
- **C. Performance & render** — startup/custom traces, web-vitals (**INP/FCP/LCP/CLS** via `stateHooks`), long-task **TBT** (separate observer), React render/selector (WDYR), benchmark A/B (paired), DevTools/CDP profiling, memory-over-flow, **same-window app+DevTools capture** (C8 — UI + console evidence in one frame, OS-level region recording).
- **D. Build output** — bundle-size, chunk membership, **LavaMoat policy diff**, manifest permissions diff, build-variant matrix.
  (Runtime containment — SES lockdown, scuttling, Snow — is **F8**, not D: D is what the build *permits*, F8 is what the running artifact *enforces*.)
- **E. Production telemetry** — Sentry links (span-volume → `/sentry-quota`), Tempo traces, error-event shape.
- **F. Extension integrity** — **⭐ state migration**, vault/keyring, tx simulation, provider/dapp, feature-flag matrix, snaps, i18n.
- **G. CI/review/process** — check links, coverage delta, reviewer bot, manual repro.

Screen recordings (motion a still can't prove): `mm` + a Playwright `recordVideo` preload → `ffmpeg` two-pass palette GIF (webm/mp4 don't render inline). See [references/evidence-publishing.md](references/evidence-publishing.md).

## Sufficiency — how much is enough

Match the bar to the claim; stop when the claim's falsifier is closed. Don't over-instrument a copy fix; don't under-prove a high-stakes claim.

- **One lead lane that closes the falsifier** is enough for low-risk, single-claim PRs (a copy fix → one screenshot; a bug fix → the falsifying test).
- **Weigh AEP's cost before reaching for it.** A `visual_validation`/`perf_validation` run spins the full stack *and* burns autonomous-agent tokens — by far the most expensive lane. Use it when the claim genuinely needs autonomous capture of a reachable surface; when a lighter lane closes the same falsifier (a single `mm` screenshot, a falsifying test, a CDP capture, an artifact CI already produced), prefer it and skip the stack. Whenever you do start it, tear it down after (see [Teardown](#teardown)).
- **Lead + one corroborator** for perf/telemetry (a number *and* its source) and for anything user-facing that also moves a metric. **For a perf-targeting PR the lead lane is the measured impact itself** — a paired A/B benchmark at the current head (C5) or equivalent — never mechanism evidence alone (chunk membership, netlog exclusion prove the improvement is *possible*, not that it *happened*). A perf PR also always carries correctness + non-regression lanes: changed-surface tests green at head, affected flows exercised, neutral profile within noise. (2026-07-22, #42795 lesson.)
- **Lead + integrity lane** for high-stakes surfaces regardless of size: persisted-state (migration + vault), money (tx simulation), permissions (LavaMoat + manifest), runtime containment (SES lockdown / scuttling), security/keyring. Size-S doesn't lower the bar here.
- **Per-claim** for mixed PRs — each Claim Card needs its own closed falsifier; a strong UI proof doesn't cover the metric it also shifts.
- **Rely on CI for routine coverage — don't re-collect what CI already establishes.** Lint, build, typecheck, the full test suite, changelog validation: CI is the authoritative source; **cite the check result** (e.g. "423 pass / 0 fail at head") instead of re-running it locally. Spend independent evidence only on (a) the claim's load-bearing falsifier, (b) specifically important/noteworthy areas (security, money, permissions, the exact changed surface), or (c) where the trust-gate warns a green result could be vacuous/misattributed. This is the economy counterpart to *"don't trust green blindly"*: that gate polices the **claim-critical** lane; this rule spares the **routine** coverage — re-collecting what CI covers is bundle noise. (#9628: cited CI's pass matrix for build/test, ran independent evidence only for the load-bearing homogeneity + resolution lanes.)

Stop when each claim has one trustworthy artifact that would have shown its falsifier. More evidence past that is noise.

## Publishing the evidence bundle

**Public, outward-facing action — always confirm the rendered section with the user before writing the PR body.** Match AEP's own format so the section is idempotent and reviewer-familiar. Full recipe (markers, image re-hosting, recordings, the `### After` injection, privacy scrub): **[references/evidence-publishing.md](references/evidence-publishing.md).** Essentials:

- **Canonical header — every validation output leads with the exact literal `## 🧪 Validation Run`.** Same string in a PR comment and in the PR-body section, never reworded or demoted — the constancy is what makes it scannable/Ctrl-F-able, like Copilot's fixed `## Pull request overview`. Line 2 is the meta line: `**Verdict:** ✅ proven — **Claim:** <one-liner>` then `head \`<sha>\` · <date> · lanes: <list>`. Enforced mechanically by `hooks/pr-evidence-gate.py` (a validation/verification/evidence heading or AEP marker without the literal blocks the `gh` write).
- **Post complete, once — and know which regime the surface is in.** Comments are **push** (audience notified once at post time; edits are silent): hold until every planned lane is present or consciously dropped, and put substantive additions or changed verdicts in a **new comment referencing the original**, never a silent edit. The PR **body** is **pull** (consulted at review time): the idempotent marker upsert on re-validation at a new head is correct there. Typo-level comment edits are fine.
- **Falsifier-forward.** After the meta line, foreground **what would have falsified the claim and how each falsifier is closed** — the falsifier is the load-bearing content, not a footnote. Structure the body as "what would make this false → the evidence that rules it out," not a lane inventory with a `falsifiers closed` line buried at the bottom. The reviewer should see the disproof attempt first.
- **Don't restate CI results.** Lint/build/typecheck/test/changelog outcomes are already on the PR's Checks tab — the reviewer sees them. Cite a CI result in the comment only to **highlight something specific** they'd otherwise miss; otherwise reference "green in Checks" or omit it. Restating "423 pass / 0 fail" is bundle noise (the display-side counterpart to the catalog's *rely on CI* collection rule).
- **Re-host images first.** Control-plane artifact URLs are `localhost` and won't render on GitHub. Re-host each artifact somewhere **your readers can reach unauthenticated**, then link the hosted URL — see [evidence-publishing.md](references/evidence-publishing.md) for the host choice and the mandatory unauthenticated `curl` check. A personal repo or a private bucket fails this for every reader but you.
- **Use idempotency markers** so a re-run replaces in place: wrap the whole section in `<!-- VALIDATION_RUN_START -->` … `<!-- VALIDATION_RUN_END -->`; inside it, AEP's own `<!-- AEP_VISUAL_VALIDATION_START/END -->` for the status block and `<!-- AEP_SCREENSHOTS_START/END -->` for images, injected into the PR template's `### **After**` section (replacing the `<!-- [screenshots/recordings] -->` placeholder) when present.
- **Verdict-first, lanes nested:** under the canonical header, hand-assembled AEP blocks demote to `### AEP Visual Validation` (leave AEP's own service-published `##` blocks untouched) with `**✅ Passed**` / `**❌ Failed**` / `ℹ️`, the long narrative in `<details><summary>Validation details</summary>`, a meta line `Run \`<id>\` · [LangSmith trace](…)`.
- **Scrub** local paths and your username from any narrative before publishing — failure summaries leak them.

## Validation output format

When reporting back (before publishing), lead with the verdict and the claim it tests:

```
PR #<n> — <title>
Claim: <the falsifiable behavior under test>
Verdict: ✅ proven / ❌ refuted / ⚠️ inconclusive (vacuous pass — 0 artifacts)
Evidence:
  - visual_validation run <id> — N screenshots (before/after <surface>)
  - perf_validation run <id> — M/M assertions proven
  - Sentry: <before/after link>
Artifacts: <local paths or re-hosted URLs>
Next: publish to PR body? (y/N)
```

If a lane comes back inconclusive, say so and name what's missing — never upgrade a vacuous pass to "proven".

### When validation refutes the claim (❌)

A refutation is a *successful* validation — the skill did its job. Report it constructively, do **not** publish a public "Failed" section to the author's PR unprompted:

- **Lead with the falsifier you hit:** "Claim refuted — under privacy mode the Perps balance is still visible (screenshot)." Show the evidence that disproves it.
- **Localize:** which lane, which surface, the exact observation vs the expected. Tie it to the diff if you can see why.
- **Separate refuted from inconclusive:** refuted = evidence shows the claim is false; inconclusive = evidence couldn't be captured / was untrustworthy (trust-gate fail). Don't conflate.
- **Hand back, don't fix:** this skill proves behavior; fixing is the author's loop (or a `bug_fix`/`pr_feedback` run). Offer the repro, not a patch.
- Surface privately first; only post to the PR if the author asks or it's your own PR.

## Safety & privacy

- **`publishEvidence: false` on every local submit.** Publish manually, only after a real pass, only with confirmation.
- **Re-host before linking** — never put a `localhost` URL or a local file path in a public PR body.
- **Scrub** usernames/paths from narratives. Failure summaries are the usual leak.
- **Don't trust green blindly** — assert non-empty `artifactRefs` (vacuous-pass trap).
- **Confirm before any PR-body write.** One PR's approval doesn't carry to the next.

## Worked example

PR claims privacy mode now hides the Perps balance (the demo bug #42683):
1. `gh pr view` → claim = "with privacy mode on, the Perps tab balance is masked like everywhere else."
2. Lane = `visual_validation` (visible). Preflight stack.
3. Submit with `description: "Onboard, enable privacy mode in Settings, open the Perps tab, confirm the balance is masked. If the Perps tutorial modal blocks, use the Shield entry modal as the reachable surface."` + `publishEvidence:false`.
4. Poll to completion; assert `artifactRefs` has the before/after pair (not a vacuous skip).
5. Fetch the two PNGs; re-host them to your configured evidence host; assemble the `AEP_VISUAL_VALIDATION` section with the hosted URLs injected into the template's `### After`.
6. Show the rendered section; on confirm, upsert the PR body.

End-to-end examples for **non-visual** claims (perf, migration, flag-gated, refactor/no-op): **[references/worked-examples.md](references/worked-examples.md).**

## Positioning: AEP vs recipes vs pr-validate

Three adjacent things; keep the boundary clear so they compose instead of collide:

- **AEP** — governed *fleet orchestration*: sandboxes, Temporal, autonomous runs at scale. The heavy engine.
- **ADR-0058 recipes** ([decisions#173](https://github.com/MetaMask/decisions/pull/173)) — a *dev-machine inner-loop* proof artifact: a declarative per-PR recipe run against the live app over CDP, emitting `summary.json`/`trace.json`/manifest.
- **pr-validate** (this skill) — the *claim→evidence methodology + taxonomy* both draw on. The Claim Card is the bridge from a PR's claim to the right proof target; the [evidence catalog](references/evidence-catalog.md) is the lane vocabulary; [lane-assertions.md](references/lane-assertions.md) maps each lane to a recipe assertion (and flags the out-of-band, non-UI lanes — the gap raised in review on decisions#173).

pr-validate is the one a human drives; it can dispatch an AEP run or author a recipe as its capture step.

## Workflow integration

Where pr-validate sits in the PR lifecycle (see the public `pr-workflow` siblings):

- **After `create-pr`, before `pr-review-queue`:** validate the claim, attach the bundle, *then* request review — reviewers get the before/after up front.
- **On force-push / requested-change:** re-run the affected lane(s); re-validation keeps a stale evidence section honest.
- **`/triage` push items:** a `push`-state PR isn't done until its claim is proven; pr-validate produces the evidence that lets it move.
- **Not a CI gate** (same scope line as ADR-0058) — it's the author's inner loop, complementing unit/e2e, not replacing them.

## Boundaries

- **Executes, with a confirmation gate on publish.** It runs the harness and captures evidence autonomously; it does not write to the public PR body without showing you the section first.
- **Local-only AEP.** No hosted instance. The skill drives the local stack.
- **Proves behavior, not code.** Pair with `/review` / `/code-review` for correctness and `/sentry-quota` for span-volume risk.
- **No persisted state.** Each run is fresh. To keep a validation record, ask — nothing is written by default.

## Related

- [references/claim-extraction.md](references/claim-extraction.md) — Step 1: turn a PR into a falsifiable Claim Card.
- [references/evidence-catalog.md](references/evidence-catalog.md) — the full menu of evidence kinds, verified capture commands, and what each proves.
- [references/evidence-trustworthiness.md](references/evidence-trustworthiness.md) — the anti-reward-hacking gate before believing/publishing a lane.
- [references/evidence-publishing.md](references/evidence-publishing.md) — PR-body format, non-visual/multi-lane rendering, image re-hosting, recordings→GIF, privacy scrub, ADR-0058 artifact contract.
- [references/worked-examples.md](references/worked-examples.md) — end-to-end runs for perf / migration / flag-gated / refactor claims.
- [references/lane-assertions.md](references/lane-assertions.md) — lane → declarative recipe-assertion mapping (ADR-0058 bridge).
- [MetaMask/metamask-autonomous-engineering-platform](https://github.com/MetaMask/metamask-autonomous-engineering-platform) — the AEP repo: stack bring-up in its README, plus `docs/demo-runbook.md`, `packages/agent-chain/src/graphs/{visual,perf}-validation/`, and `packages/github/src/pr-body-builder.ts` (the canonical PR-body format this skill mirrors).
- `MetaMask/decisions#173` — ADR-0058 Recipe-Based Verification (the adjacent inner-loop proof system).
- `/sentry-quota` — sibling skill for span-volume PR review; `/review`, `/code-review` — code correctness.
- `/memory-leak-hunt` — the engine behind the **memory leak** evidence category (C9). pr-validate delegates retention analysis to it and packages the verdict; it also runs standalone.
- [[reference_aep_local_run]] — the source memory this skill encodes.
- [[reference_sentry_project_topology]] — Sentry project mapping for the telemetry-evidence lane.
