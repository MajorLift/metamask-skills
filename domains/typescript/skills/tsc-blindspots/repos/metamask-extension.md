---
repo: metamask-extension
parent: tsc-blindspots
---

# Blind spots — metamask-extension

What this repo's configuration does **not** check, and what that means for the
parent skill's five divergence shapes. How to *run* the two-arm proof here — heap,
probe location, the authoritative-source table, the `chrome.*` caveat — is
[references/metamask-extension.md](../references/metamask-extension.md).

## `tsconfig.json` does not show you the strictness

The local file names exactly one strictness flag, `useUnknownInCatchVariables`.
Everything else arrives through `"extends": "@tsconfig/node22/tsconfig.json"`.
Resolve it before concluding anything is off:

```bash
npx tsc -p tsconfig.json --showConfig
```

That prints `strict`, `strictNullChecks`, `strictFunctionTypes`, `noImplicitAny`,
`alwaysStrict`, `strictBindCallApply`, `strictPropertyInitialization` and
`strictBuiltinIteratorReturn` all `true`, plus `target: es2022` and
`skipLibCheck: true` — none of which appear in `tsconfig.json`.

**The failure this causes is under-reporting.** An auditor greps the local file for
`strict`, finds nothing, and downgrades a real nullability divergence to "tsc
wouldn't have caught it anyway." It would: `strictNullChecks` is on, so a dropped
`| undefined` (parent shape 2) *does* surface in a probe here.

`noUncheckedIndexedAccess` is genuinely absent — checked across all three
tsconfigs in the repo (`tsconfig.json`, `development/webpack/tsconfig.webpack.json`,
`test/e2e/playwright/llm-workflow/tsconfig.json`), none of which set it.

## The JS boundary, sized

`allowJs: true` and `checkJs` unset. The parent reference explains why
`app/scripts/background.js` matters; the number is the part worth knowing:

| Under `include` (`app`, `development`, `shared`, `test`, `types`, `ui`) | Count |
|---|---|
| `.js` | 1,219 |
| `.ts` / `.tsx` | 7,245 |
| `.js` carrying `@ts-check` | **1** (`development/lib/build-type.js`) |

Roughly one included file in seven asserts nothing and is checked against nothing.
A type hand-written for a function whose callers are all in that seventh is
unfalsifiable in
the parent skill's Step 1 sense — probe it, but expect Arm B to stay silent, and
report that as *unconstrained* rather than as *cleared*.

## Unchecked indexing, in one function

`noUncheckedIndexedAccess` is off, so `record[key]` and `arr[i]` both yield `T`,
never `T | undefined`. `shared/lib/network.utils.ts:238-256` shows the whole class
in nineteen lines:

```ts
const enabledEip155Networks =
  enabledNetworkMap[KnownCaipNamespace.Eip155] ?? {};   // :243  guard the author wrote

const chainIds = Object.entries(enabledEip155Networks)
  .filter(([_chainId, isEnabled]) => isEnabled)
  .map(([chainId, _isEnabled]) => chainId) as Hex[];    // :247  escape hatch on the key type

return chainIds
  .map((chainId) => networkConfigurationsByChainId[chainId])
  .filter((config) => config !== undefined)             // :251  guard the author wrote
  .map(
    (config) =>
      config.rpcEndpoints[config.defaultRpcEndpointIndex].networkClientId,  // :254  no guard
  );
```

The record lookup at `:250` is typed `NetworkConfiguration`, so the `!== undefined`
filter at `:251` is guarding against something the compiler says cannot happen — the
author supplied it from knowledge of the data. Two lines later the array index at
`:254` is dereferenced immediately with no equivalent guard, and the compiler asked
for neither. If `defaultRpcEndpointIndex` is ever out of range the throw is at
runtime and `tsc` is green.

**For review:** a hand-written guard on an index expression is evidence the author
knew the lookup could miss. Ask why the sibling index in the same expression has
none. `shared/lib/selectors/networks.ts:88` is the same shape with the cast form —
`networkConfigurationsByChainId[chainId as Hex]` on a parameter declared `string`.

## `skipLibCheck: true` — declarations are not checked

Inherited from the base. Every `.d.ts` is exempt: the twelve files in `types/` and
every dependency's declarations.

`types/lavamoat__lavadome-core.d.ts` is a bodiless `declare module
'@lavamoat/lavadome-core';`, which types the entire module `any`. The package ships
no types (no `types`/`typings` field, no `.d.ts` in the package), so hand-writing is
the parent's Step 2 case 7 — correct in principle. The defect is that the shim
asserts `any` where it could assert a shape. I found no `.ts`/`.tsx` importer under
`app`, `shared` or `ui`; a `.js` importer would be invisible to `tsc` regardless.

## The lint layer changes what you can grep for

`.eslintrc.js:162` sets `@typescript-eslint/no-explicit-any` to `'error'`, inside the
override at `.eslintrc.js:148` scoped to `tsconfig.fileNames` filtered to `.tsx?` —
so it covers exactly the files `tsc` checks.

**Consequence for parent §7 (false precision):** you cannot find an absorbed `any`
by grepping for `any`, because writing one is a lint error. The rule pushes authors
to `as` instead, which is why the parent's "escape hatches are the tell" section is
the productive search here. Use `IsAny` at the call sites, not a grep.

`.eslintrc.js:278-296` disables a block of rules, commented *"removing changes to
our shared ESLint config made after version v9 … TODO: Remove these modifications
after the ESLint v9 update"*. Three of them matter to this skill:

| Rule | Line | What stops being reported |
|---|---|---|
| `no-floating-promises` | :284 | an unawaited promise introduced while annotating |
| `no-unsafe-enum-comparison` | :289 | parent shape 1 — `string` typed where an enum belongs, then compared to an enum member |
| `no-unsafe-function-type` | :291 | a bare `Function` standing in for a call signature |

`no-unsafe-enum-comparison` is the lint counterpart of the parent's first divergence
shape. With it off, a migration that widens an enum-valued field to `string` and
compares it to an enum member is green in **both** `tsc` and lint — so lint silence
is not a clearance here. These are marked temporary, so a finding they would have
caught is not a decision to accept the risk; say so when reporting one.

## Probe note

`incremental: true` with `tsBuildInfoFile:
node_modules/.cache/typescript/tsconfig.tsbuildinfo` means a cache persists between
Arm A and Arm B. **Open question:** whether that cache can mask a probe diagnostic
under `--noEmit`. I did not test it. If the two arms disagree in a way that does not
track the probe, delete that file and re-run before reporting anything.
