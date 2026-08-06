## Ordering guarantees — `metamask-extension#45249` @ `a11a6b8`

### The two arms

| arm | jest result |
| --- | --- |
| A — three tests `it.skip`, as shipped | 3 skipped, 25 passed, 28 total |
| B — same bodies, `.skip` removed | 3 failed, 25 passed, 28 total |

### Does the observable discriminate interleaving?

| observable | sequential | interleaved | discriminates |
| --- | --- | --- | --- |
| 2nd span's `parent_span_id` | `undefined` | `ab7ff663b2460f17` | **yes** — and it equals the pending span's own id (`parentIsFirst=true`) |
| `traceId(2nd) == traceId(1st)` | `true` | `true` | **NO** — equal either way, so this assertion cannot witness concurrency |
| request-id correlates with own trace (`matchesA`) | `true` | `false` | **yes** |
| request-id correlates with the *other* trace (`matchesB`) | `false` | `true` | **yes** — misattribution, not loss |

Third concurrent call parents under **B**, not A (`parentIsFirst=true` against B) — LIFO top-of-stack.

### Arm B failures (all at the intended assertion)

- concurrent trace() calls (MetaMask-planning#7523) › when a second, unrelated trace() call starts while the first is still pending › does not parent the second span under the still-pending first one
- concurrent trace() calls (MetaMask-planning#7523) › when a second, unrelated trace() call starts while the first is still pending › does not let a third concurrent call inherit an already-corrupted lineage
- getCurrentTraceId() under concurrent trace() calls (MetaMask-planning#7523) › when a second, unrelated trace() call is still pending › correlates an operation’s own outbound request with its own trace id, not a concurrently-pending unrelated operation’s
## Ordering guarantees — `metamask-extension#45249` @ `a11a6b8`

### The two arms

| arm | jest result |
| --- | --- |
| A — three tests `it.skip`, as shipped | 3 skipped, 25 passed, 28 total |
| B — same bodies, `.skip` removed | 3 failed, 25 passed, 28 total |

### Does the observable discriminate interleaving?

| observable | sequential | interleaved | discriminates |
| --- | --- | --- | --- |
| 2nd span's `parent_span_id` | `undefined` | `a05cf88636bbc481` | **yes** — and it equals the pending span's own id (`parentIsFirst=true`) |
| `traceId(2nd) == traceId(1st)` | `true` | `true` | **NO** — equal either way, so this assertion cannot witness concurrency |
| request-id correlates with own trace (`matchesA`) | `true` | `false` | **yes** |
| request-id correlates with the *other* trace (`matchesB`) | `false` | `true` | **yes** — misattribution, not loss |

Third concurrent call parents under **B**, not A (`parentIsFirst=true` against B) — LIFO top-of-stack.

### Arm B failures (all at the intended assertion)

- getCurrentTraceId() under concurrent trace() calls (MetaMask-planning#7523) › when a second, unrelated trace() call is still pending › correlates an operation’s own outbound request with its own trace id, not a concurrently-pending unrelated operation’s
- concurrent trace() calls (MetaMask-planning#7523) › when a second, unrelated trace() call starts while the first is still pending › does not parent the second span under the still-pending first one
- concurrent trace() calls (MetaMask-planning#7523) › when a second, unrelated trace() call starts while the first is still pending › does not let a third concurrent call inherit an already-corrupted lineage
