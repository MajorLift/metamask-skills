---
repo: core
parent: tsc-blindspots
---

# Blind spots — core

What `MetaMask/core`'s configuration does **not** check. Two of the parent skill's
classes do not exist here and one exists only here, so do not carry the extension
or mobile playbook across unchanged.

## The JS boundary does not exist here — say so, do not omit it

`tsconfig.base.json` does not set `allowJs`, and it is absent from the resolved
options for a package (`npx tsc -p packages/assets-controllers/tsconfig.json
--showConfig`). Independently, `packages/*/src` contains **0** `.js` files against
**1,380** `.ts`.

So the parent skill's central premise — *"across a JavaScript boundary (`checkJs`
off) it checks nothing at all"* — has no instance in core. A review that reports
"the callers are still `.js`, so this type is validated against nothing" is wrong
here, and a `checkJs` finding copied from an extension review does not transfer.

State this explicitly in a core review rather than leaving it out. Its absence is
what makes the two classes below the ones worth spending the time on.

## Unchecked indexing — and it is not uniform across packages

`tsconfig.base.json` does not set `noUncheckedIndexedAccess`, so `record[key]` and
`arr[i]` yield `T`, never `T | undefined`. But three configs opt in:

| Config | Line |
|---|---|
| `packages/json-rpc-engine/tsconfig.json` | :9 |
| `packages/eth-json-rpc-provider/tsconfig.json` | :9 |
| `tsconfig.scripts.json` | :19 |

That is **2 of the 75 package tsconfigs**, plus the scripts config. Read the
package's own file before concluding an index expression is unchecked — the answer
differs by directory, which no other MetaMask repo here requires you to check.

The same expression appears both guarded and unguarded in two files of one package,
`packages/assets-controllers`:

```ts
// packages/assets-controllers/src/TokenBalancesController.ts:510-512  (also :526-528)
const networkConfig = networkConfigurationsByChainId[chainId];
const { networkClientId } =
  networkConfig.rpcEndpoints[networkConfig.defaultRpcEndpointIndex];

// packages/assets-controllers/src/AccountTrackerController.ts:590-596
.map((hexChainId) => {
  const networkConfig = networkConfigurationsByChainId[hexChainId];
  return networkConfig?.rpcEndpoints[
    networkConfig.defaultRpcEndpointIndex
  ]?.networkClientId;
})
.filter((id): id is NetworkClientId => id !== undefined);
```

Two index operations each, both typed non-nullable under `strict: true`. The second
site guards both with `?.` and then needs the type-predicate `.filter` to remove
the `undefined` it introduced by doing so; the first guards neither and destructures
straight through. `tsc` has no opinion about either, so consistency on this axis is
a review property in core, not a checked one.

### A package's source is checked under stricter settings than its emitted types

`packages/json-rpc-engine/tsconfig.json` sets `noUncheckedIndexedAccess` and
`exactOptionalPropertyTypes`; its `tsconfig.build.json` sets neither — it extends
`tsconfig.packages.build.json`, which does not. **0 of the build configs set
either.** So a package's source is checked under stricter settings than the `.d.ts`
consumers read is emitted under.

**Open question:** whether that asymmetry changes any emitted signature — an
inferred return type of a function returning `arr[i]` is the candidate. I did not
test it. Settle it by building the package and diffing the emitted `dist/*.d.ts`
against one emitted with the flags added to `tsconfig.build.json`.

## Bodiless ambient shims — verified `any` at live call sites

Ten files under `types/` are a single line of the form `declare module 'x';` with no
body, which types the entire module `any`. Every package includes them —
`"include": ["../../types", "./src", "../../tests"]`.

Two cases, needing different remedies:

**1. The shim overrides a package that ships its own types.**
`@metamask/metamask-eth-abis` has `"types": "dist/index.d.ts"` in its
`package.json`, and `types/@metamask/metamask-eth-abis.d.ts` shadows it. Verified
with the parent skill's substitution method, replicating a package's arrangement
(`strict`, `module`/`moduleResolution` `Node16`, `target ES2020`,
`lib ES2020 + DOM`, core's `node_modules`):

```ts
import { abiERC20 } from '@metamask/metamask-eth-abis';
import contractMap from '@metamask/contract-metadata';
type IsAny<T> = 0 extends 1 & T ? true : false;
const abiIsAny: IsAny<typeof abiERC20> = true;
const mapIsAny: IsAny<typeof contractMap> = true;
```

- With `types/**/*.d.ts` in `include`: **clean**, and flipping either to `false`
  errors `TS2322` — so both are `any`.
- With `types/` removed from `include`: `abiIsAny` errors (`Type 'true' is not
  assignable to type 'false'`) — the shipped declarations resolve and `abiERC20` is
  **not** `any`.

The shim is what makes it `any`, at these importers under
`packages/assets-controllers/src/` — `Standards/ERC20Standard.ts:6`,
`TokensController.ts:31`, `Standards/NftStandards/ERC1155/ERC1155Standard.ts:11`.
This is parent §7 false precision with a source you can delete: remove the shim.

**2. The shim stands in for a package with no types.**
`@metamask/contract-metadata` has no `types`/`typings` field; with `types/` removed
the import is `TS7016`. Hand-writing is the parent's Step 2 case 7 — correct in
principle. The defect is that the shim asserts `any` rather than a shape, so
`contractMap` is `any` at `packages/assets-controllers/src/TokensController.ts:16`
and `.../TokenDetectionController.ts:10`. `single-call-balance-checker-abi` is the
same case, at `.../AssetsContractController.ts:19`.

`@typescript-eslint/no-explicit-any` is `'error'` in `eslint.config.mjs`, in the
block commented *"Enable rules that are disabled in
`@metamask/eslint-config-typescript`"* — and it cannot see either case, because no
`any` is written anywhere. Neither can `skipLibCheck: false` (below): a bodiless
`declare module` is well-formed, so checking declarations finds nothing wrong with
it.

## Project references — two entry points that resolve differently

`composite: true` in `tsconfig.base.json`. Every package tsconfig lists its
dependencies under `references`, and every `tsconfig.build.json` references the
other packages' `tsconfig.build.json`. This is the class the other two repos do not
have, and the first thing to get right is which config you ran.

**The `paths` mapping is not inherited by every entry point.**
`tsconfig.packages.json` sets `"@metamask/*": ["../*/src"]`, commented *"we ensure
that TypeScript resolves `@metamask/*` imports to the uncompiled source code."*

| Config | Extends | Carries the `src` mapping |
|---|---|---|
| `packages/*/tsconfig.json` | `tsconfig.packages.json` | yes |
| `packages/*/tsconfig.build.json` | `tsconfig.packages.build.json` → `tsconfig.packages.json` | yes |
| `tsconfig.json` (root, `noEmit`) | `tsconfig.base.json` **directly** | **no** |

So the root config is the one whose cross-package imports fall through to normal
`Node16` resolution and the package's `types` field, and the per-package configs —
lint *and* build alike — are the ones pointed at source.

**Open question:** which file each entry point actually loads for a cross-package
import, since project references also redirect to declaration output. I did not
test it. Settle it before citing any typecheck as evidence about a cross-package
type:

```bash
npx tsc -p packages/<pkg>/tsconfig.json --explainFiles | grep -i '<dep-pkg>'
npx tsc --build tsconfig.build.json --verbose --traceResolution 2>&1 | grep -i '<dep-pkg>'
```

**Four packages are in the build graph and absent from the root config.**
`tsconfig.json` lists **71** references; `tsconfig.build.json` lists **75**. The
difference is `eip-5792-middleware`, `eip-7702-internal-rpc-middleware`,
`logging-controller` and `storage-service` — reachable transitively through other
packages' `references`, but not named at the root.

**And no script runs the root config.** The only `tsc` invocation in `package.json`
is `build:types` (`tsc --build tsconfig.build.json --verbose`); `build` is
`ts-bridge --project tsconfig.build.json`. `tsconfig.json`'s own comment says it is
*"used by the `lint` script in `package.json`, and by editors such as VSCode"*, and
`lint` runs eslint, prettier, constraints, depcheck and two scripts — no `tsc`.
**Do not cite "core typechecks clean" without naming the command you ran**, and do
not assume CI ran the config you are reading.

That is not the same as "types are never checked": eslint's type-aware rules build
a program through the parser (`eslint.config.mjs` sets `parserOptions.tsconfigRootDir`;
the `project` setting comes from `@metamask/eslint-config-typescript`, which I did
not read). Type information is loaded — but a rule set is not `tsc` reporting every
diagnostic, and a probe's `TS2322` has nothing there to surface it.

**Open question:** whether `tsc --build` here can report clean over an out-of-date
`dist/*.d.ts`. `build:types` already passes `--verbose`, which prints the
up-to-date decision per project — read that log rather than the exit code.

What holds regardless of the resolution question: **consumers outside the repo —
extension and mobile — read `dist/*.d.ts`**, and no check inside core exercises
that path from a consumer's position. A type that is correct against `src` and
stale in `dist` is invisible here and breaks there.

`skipLibCheck` is set in `tsconfig.packages.build.json` and **not** in
`tsconfig.packages.json`, so a per-package typecheck checks declaration files that
the build skips — the opposite of extension, where `skipLibCheck: true` is
inherited repo-wide.

## Probe note

`lib` is `["ES2020", "DOM"]`, so a DOM-typed probe compiles here. It does not in
mobile. `module` and `moduleResolution` are `Node16`, matching extension and not
mobile — a probe is portable between core and extension, and is not portable to
mobile without rewriting its imports.
