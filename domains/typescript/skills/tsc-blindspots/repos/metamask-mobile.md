---
repo: metamask-mobile
parent: tsc-blindspots
---

# Blind spots — metamask-mobile

**Scope of this file.** Written from measured `tsconfig.json` and `.eslintrc.js`
values. The repo was not checked out on the machine this was written on, so there
are **no verified call sites below** — every statement about actual code is an open
question with the command that settles it. Add examples on the first real review;
the extension and core overlays show the form.

## Strictness is local — the extension's audit trap does not apply

`strict: true` is set in `tsconfig.json` itself, not inherited. A reader auditing
that file sees it, which is the opposite of extension, where `strict` arrives
through `@tsconfig/node22` and is invisible locally.

Run `--showConfig` anyway, for one reason: **`noUncheckedIndexedAccess` is not part
of `strict`** and is not set here.

```bash
npx tsc -p tsconfig.json --showConfig
```

## Unchecked indexing

`record[key]` and `arr[i]` yield `T`, never `T | undefined`, everywhere the root
`tsconfig.json` governs. Under `strict: true` this is the one nullability hole left
open, and it is the one that reaches runtime — as a property access on `undefined`,
not as a type error.

Where to look, as commands rather than claims. The source root is not asserted here;
take `<src>` from the tsconfig's own `include`:

```bash
python3 -c "import json,re,sys; print(json.loads(re.sub(r'//.*','',open('tsconfig.json').read()))['include'])"
```

Then find an index expression dereferenced immediately, and a hand-written runtime
guard on an index expression sitting beside one that has none:

```bash
grep -rnE '\]\.[a-zA-Z]' <src> --include=*.ts --include=*.tsx | grep -v '\.test\.'
grep -rnE '\?\.\[|\]\?\.' <src> --include=*.ts --include=*.tsx | grep -v '\.test\.'
```

A guard the compiler did not ask for is evidence the author knew the lookup could
miss; the sibling index without one is the finding. Both core and extension carry
that exact pair on `networkConfigurationsByChainId[chainId]` followed by
`rpcEndpoints[defaultRpcEndpointIndex]`. **Open question:** whether mobile consumes
the same `NetworkController` state and whether that expression appears here — I did
not verify either. Settle both with `grep -rn "rpcEndpoints\[" <src> --include=*.ts`
and a look at the `@metamask/network-controller` dependency in `package.json`.

## No DOM lib — this changes how probes are written, not just what compiles

`lib: ["es2022"]`, with `jsx: react-native`. Nothing from `lib.dom.d.ts` is in
scope from `lib`, so a probe borrowing a DOM type fails for a reason that has
nothing to do with the claim under test — the parent skill's Step 5 failure, and
here it is the default outcome of copying a probe from an extension review.

`document`, `window`, `HTMLElement` and `Event` come from `lib.dom.d.ts` and are
therefore not supplied. `fetch`, `URL`, `AbortController` and `console` are also
`lib.dom.d.ts` members but are commonly re-declared by React Native's own type
packages or by `@types/node`. **Open question:** which of those resolve in this
repo. Settle each in one line — write it in a scratch file inside the `include`
paths and run `tsc`:

```ts
type _Probe = HTMLElement;   // TS2304 if absent
type _Probe2 = typeof fetch; // TS2304 if absent
```

Do the same before using any DOM type in a real probe. Do not infer it from the
extension or core overlays; core has `DOM` in `lib` and extension has `DOM` plus
`es2023`, so both compile things that will not compile here.

## The JS boundary — live, with one input unmeasured

`allowJs: true` puts `.js` files in the program. Whether they are **checked**
depends on `checkJs`, which was not among the measured values. The two are
different questions and only the second decides whether a type written for a JS
module is validated against anything.

**Open question, and it gates the whole class.** Settle it before writing the
review:

```bash
npx tsc -p tsconfig.json --showConfig | grep -i checkjs   # absent => off
grep -rl '@ts-check' <src> --include=*.js | wc -l           # per-file opt-ins
```

If `checkJs` is off — the default, and what extension does — then a hand-written
type for a function whose callers are all `.js` is checked against nothing and can
drift indefinitely. Size the boundary before weighting the finding, the way the
extension overlay does:

```bash
find <src> -name '*.js' | wc -l
find <src> \( -name '*.ts' -o -name '*.tsx' \) | wc -l
```

## The lint layer

`.eslintrc.js:170` sets `@typescript-eslint/no-explicit-any` to `'error'`. As in
extension, that means **you cannot find an absorbed `any` by grepping for `any`** —
writing one is a lint error, so the pressure goes into `as` instead. Use `IsAny` at
the call sites (parent §7), and read escape-hatch clusters as the search index.

`.eslintrc.js:206` turns off `@typescript-eslint/no-unsafe-enum-comparison`. That is
the lint counterpart of the parent's divergence shape 1 — a field widened from an
enum to `string` and then compared against an enum member is green in **both** `tsc`
and lint. Lint silence is not a clearance for that shape here.

**Open question:** whether `no-floating-promises` and `no-unsafe-function-type` are
on. Extension disables both; mobile was measured only for
`no-unsafe-enum-comparison`, so their state here is unknown rather than on. Settle
with `grep -n "no-floating-promises\|no-unsafe-function-type" .eslintrc.js` and, if
absent, by checking the shared config the file extends.

## Probe note

`module: commonjs` and `jsx: react-native`, against `Node16` in both extension and
core. A probe is **not** portable from those repos without rewriting its imports.
`isolatedModules: true` additionally requires `import type` / `export type` for
type-only positions — a probe that re-exports a type without `type` errors for the
wrong reason, which is the parent's Step 5 again.

## Open questions, collected

| Question | Settles it |
|---|---|
| Is `checkJs` on? | `npx tsc -p tsconfig.json --showConfig \| grep -i checkjs` |
| How big is the `.js` surface? | `find <src> -name '*.js' \| wc -l` |
| Which DOM-named globals resolve? | one-line `type _P = X;` probe per global |
| Does the `record[k]` then `arr[i]` pair appear? | `grep -rn "rpcEndpoints\[" <src> --include=*.ts` |
| Are `no-floating-promises` / `no-unsafe-function-type` on? | `grep -n` in `.eslintrc.js`, then the shared config |
| Are there per-directory tsconfigs overriding these? | `find . -name 'tsconfig*.json' -not -path '*/node_modules/*'` |
