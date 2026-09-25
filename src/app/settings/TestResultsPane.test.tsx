import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

// The Glacier kit reads matchMedia as it loads; jsdom has none.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
import { TestResultsPane } from './TestResultsPane.tsx';
import { sample } from '../diag/testReport.test.ts';

// Testing Library cleans up after itself only where the test globals are on, and here they are off.
afterEach(cleanup);

describe('the test results page', () => {
  it('shows the verdict, the numbers, and that the code matches', () => {
    render(<TestResultsPane report={sample()} buildSource="feedface" />);
    expect(screen.getByText('Every test passed')).toBeTruthy();
    expect(screen.getByText('The same code this build was made from.')).toBeTruthy();
    expect(screen.getByText('Page (Vitest)')).toBeTruthy();
  });

  it('warns when the report is for other code, and says what failed', () => {
    const failing = sample({
      suites: [
        {
          ...sample().suites[0]!,
          status: 'failed',
          counts: { total: 2, passed: 1, failed: 1, skipped: 0, todo: 0 },
          tests: [{ file: 'src/b.test.ts', line: 9, name: 'writes a table', status: 'failed', ms: 1, failure: 'Expected a table' }],
        },
      ],
    });
    render(<TestResultsPane report={failing} buildSource="cafebabe" />);
    expect(screen.getByText('1 test failed')).toBeTruthy();
    expect(screen.getByText(/The code changed after these tests ran/)).toBeTruthy();
    expect(screen.getByText('Expected a table')).toBeTruthy();
  });

  it('says how to make a report when the build has none', () => {
    render(<TestResultsPane report={sample({ generatedAt: null, suites: [] })} buildSource={null} />);
    expect(screen.getByText('No test report in this build.')).toBeTruthy();
  });

  it('with Only failures, keeps a failing suite’s failures and hides a suite that passed', () => {
    const passing = sample().suites[0]!;
    const report = sample({
      suites: [
        passing,
        {
          ...passing,
          id: 'cargo:app',
          title: 'App (Rust)',
          status: 'failed',
          counts: { total: 2, passed: 1, failed: 1, skipped: 0, todo: 0 },
          tests: [
            { file: 'src/store.rs', line: 4, name: 'keeps a note', status: 'passed', ms: 1, failure: null },
            { file: 'src/store.rs', line: 9, name: 'reads a note back', status: 'failed', ms: 1, failure: 'left != right' },
          ],
        },
      ],
    });
    const { container } = render(<TestResultsPane report={report} buildSource="feedface" />);
    expect(screen.getByText('Page (Vitest)')).toBeTruthy();
    fireEvent.click(screen.getByLabelText('Only failures'));
    expect(screen.queryByText('Page (Vitest)')).toBeNull();
    const names = [...container.querySelectorAll('li')].map((li) => li.textContent);
    expect(names.some((name) => name?.includes('reads a note back'))).toBe(true);
    expect(names.some((name) => name?.includes('keeps a note'))).toBe(false);
  });

  it('names the suites that did not run', () => {
    const passing = sample().suites[0]!;
    render(<TestResultsPane report={sample({ suites: [passing, { ...passing, id: 'cargo:server', title: 'Server (Rust)', status: 'notRun', counts: { total: 0, passed: 0, failed: 0, skipped: 0, todo: 0 }, tests: [] }] })} buildSource="feedface" />);
    expect(screen.getByText('Some suites did not run')).toBeTruthy();
    expect(screen.getByText('Server (Rust) did not run for this report.')).toBeTruthy();
  });
});
