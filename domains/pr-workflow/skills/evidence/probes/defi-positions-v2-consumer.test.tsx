// Probe for `render-count.sh`, copied into the target tree by the evidence workflow at
// `ui/selectors/defi-controller-v2/__render_probe__.test.tsx`. Not part of any suite.
//
// It lives here rather than on the operator's disk so that a published count has a file
// the reader can open. The first version of this measurement cited a probe that had been
// deleted after the run, which makes the number unverifiable no matter how it was taken.
//
// Counts how many times a component consuming `getDeFiPositionsV2` re-renders while the
// DeFi slice is in its "not yet written" state and unrelated writes land on the store.
import React from 'react';
import { Provider, useSelector } from 'react-redux';
import { createStore } from 'redux';
import { render, act } from '@testing-library/react';
import { getDeFiPositionsV2 } from './positions';

type ProbeState = { metamask: { unrelated: number } };

const reducer = (
  state: ProbeState = { metamask: { unrelated: 0 } },
  action: { type: string },
): ProbeState =>
  action.type === 'unrelated/write'
    ? {
        metamask: { ...state.metamask, unrelated: state.metamask.unrelated + 1 },
      }
    : state;

let consumerRenders = 0;

function Consumer() {
  // The real consumer is `useDeFiPositionsV2`, which feeds this value straight into
  // a `useMemo` dependency array.
  useSelector(getDeFiPositionsV2 as never);
  consumerRenders += 1;
  return null;
}

describe('C4 probe — getDeFiPositionsV2 consumer renders', () => {
  it('counts consumer renders across unrelated store writes', () => {
    const PARENT_WRITES = 5;
    const store = createStore(reducer);
    consumerRenders = 0;

    render(
      <Provider store={store}>
        <Consumer />
      </Provider>,
    );

    for (let i = 0; i < PARENT_WRITES; i++) {
      act(() => {
        store.dispatch({ type: 'unrelated/write' });
      });
    }

    // eslint-disable-next-line no-console
    console.log(
      `RENDER_COUNT consumer=${consumerRenders} parentRenders=${PARENT_WRITES + 1}`,
    );
    expect(consumerRenders).toBeGreaterThan(0);
  });
});
