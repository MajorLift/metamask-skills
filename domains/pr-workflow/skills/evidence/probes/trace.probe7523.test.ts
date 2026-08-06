/**
 * PROBE for MetaMask-planning#7523 / PR #45249 — drop into shared/lib/ and run:
 *   yarn jest shared/lib/trace.probe7523.test.ts
 *
 * Reports (rather than asserts) the two observables the PR's skipped
 * span-parenting tests assert on, in BOTH a sequential and an interleaved arm,
 * so it can be seen which of them actually discriminates interleaving.
 */
import * as Sentry from '@sentry/browser';
import { trace, TraceName } from './trace';

const NAME_MOCK = TraceName.Transaction;

function deferred<Value = void>() {
  let resolve!: (value: Value) => void;
  const promise = new Promise<Value>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

function initRealSentryClient(): void {
  const client = new Sentry.BrowserClient({
    dsn: 'https://public@example.ingest.sentry.io/1',
    transport: () => ({
      send: () => Promise.resolve({}),
      flush: () => Promise.resolve(true),
    }),
    stackParser: Sentry.defaultStackParser,
    integrations: [],
    tracesSampleRate: 1,
  });
  Sentry.getCurrentScope().setClient(client);
  client.init();
  globalThis.sentry = { ...Sentry } as typeof globalThis.sentry;
}

async function tick(times = 1) {
  for (let i = 0; i < times; i += 1) {
    await Promise.resolve();
  }
}

function report(label: string, a?: Sentry.Span | null, b?: Sentry.Span | null) {
  const parent = b ? Sentry.spanToJSON(b).parent_span_id : '<no span>';
  const traceA = a?.spanContext().traceId;
  const traceB = b?.spanContext().traceId;
  const spanIdA = a?.spanContext().spanId;
  // eslint-disable-next-line no-console
  console.log(
    `PROBE ${label} | parent_span_id(second)=${parent ?? 'undefined'} | ` +
      `spanId(first)=${spanIdA} | parentIsFirst=${String(parent === spanIdA)} | ` +
      `traceId(first)=${traceA} | traceId(second)=${traceB} | ` +
      `traceIdsEqual=${String(traceA === traceB)}`,
  );
}

describe('PROBE 7523: which assertions discriminate interleaving?', () => {
  beforeEach(() => {
    initRealSentryClient();
  });
  afterEach(() => {
    Sentry.getCurrentScope().clear();
    Sentry.getIsolationScope().clear();
  });

  it('ARM SEQUENTIAL: A fully resolves before B starts', async () => {
    const spanA = await trace({ name: NAME_MOCK, id: 'A-seq' }, async () =>
      Sentry.getActiveSpan(),
    );
    const spanB = await trace({ name: NAME_MOCK, id: 'B-seq' }, async () =>
      Sentry.getActiveSpan(),
    );
    report('sequential', spanA, spanB);
  });

  it('ARM INTERLEAVED: B starts while A is still pending', async () => {
    const aGate = deferred<void>();
    let spanA: Sentry.Span | null | undefined;
    const aPromise = trace({ name: NAME_MOCK, id: 'A-pending' }, async () => {
      spanA = Sentry.getActiveSpan();
      await aGate.promise;
      return spanA;
    });

    let spanB: Sentry.Span | null | undefined;
    const bPromise = trace(
      { name: NAME_MOCK, id: 'B-concurrent-unrelated' },
      () => {
        spanB = Sentry.getActiveSpan();
        return spanB;
      },
    );
    await tick(3);
    report('interleaved', spanA, spanB);
    await bPromise;
    aGate.resolve();
    await aPromise;
  });

  it('ARM INTERLEAVED-3: C starts while both A and B are pending', async () => {
    const aGate = deferred<void>();
    const bGate = deferred<void>();
    let spanA: Sentry.Span | null | undefined;
    let spanB: Sentry.Span | null | undefined;
    let spanC: Sentry.Span | null | undefined;

    const aPromise = trace({ name: NAME_MOCK, id: 'A-pending-2' }, async () => {
      spanA = Sentry.getActiveSpan();
      await aGate.promise;
      return spanA;
    });
    const bPromise = trace({ name: NAME_MOCK, id: 'B-pending-2' }, async () => {
      spanB = Sentry.getActiveSpan();
      await bGate.promise;
      return spanB;
    });
    const cPromise = trace({ name: NAME_MOCK, id: 'C-concurrent-2' }, () => {
      spanC = Sentry.getActiveSpan();
      return spanC;
    });
    await tick(3);
    report('interleaved-3 (C vs B)', spanB, spanC);
    report('interleaved-3 (C vs A)', spanA, spanC);
    await cPromise;
    bGate.resolve();
    await bPromise;
    aGate.resolve();
    await aPromise;
  });
});
