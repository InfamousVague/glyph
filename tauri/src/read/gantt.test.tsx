import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { Rendered } from './Rendered.tsx';
import { daysSaid, readGantt, readTask } from './gantt.ts';

/**
 * A ```gantt fence on the shared page (gantt.ts, Rendered.tsx; docs/GANTT.md): read as lib/core/gantt/format.dart reads
 * it, and drawn as its readable list, since the reader draws no charts.
 */
const FENCE = [
  'title: Waitlist launch',
  'workdays: true',
  '',
  '## Research',
  '- Interview five users [2026-11-02 → 2026-11-04] @matt #research 100%',
  '- Read the competition [2026-11-03 +3d] @sam',
  '',
  'Build:',
  '- Design the waitlist [2026-11-05 → 2026-11-11] @matt after: Interview five users, Read the competition 60%',
  '- Build the signup page [+4d] after: Design the waitlist',
  '- ◆ Launch [2026-11-20] after: Build the signup page',
  '- [[KLN-12|Fix the login]]',
].join('\n');

describe('a gantt fence', () => {
  it('reads each task’s marks', () => {
    const task = readTask('- Design the waitlist [2026-11-05 → 2026-11-11] @matt #design after: Interview, Read 60% colour: teal')!;
    expect(task).toEqual({ name: 'Design the waitlist', milestone: false, start: '2026-11-05', end: '2026-11-11', length: null, people: ['matt'], tags: ['design'], after: ['Interview', 'Read'], progress: 60 });
    expect(readTask('- ◆ Launch [2026-11-20]')).toMatchObject({ name: 'Launch', milestone: true, start: '2026-11-20' });
    expect(readTask('- Build [+4d] after: Design')).toMatchObject({ length: '4d', after: ['Design'] });
    expect(readTask('Not a task')).toBeNull();
  });

  it('reads its title and sections, both ways', () => {
    const list = readGantt(FENCE);
    expect(list.title).toBe('Waitlist launch');
    expect(list.sections.map((s) => [s.name, s.tasks.length])).toEqual([
      ['Research', 2],
      ['Build', 4],
    ]);
    expect(list.sections[1]!.tasks[3]!.name).toBe('Fix the login');
  });

  it('says days as a reader would', () => {
    expect(daysSaid(readTask('- A [2026-11-02 → 2026-11-06]')!)).toBe('2 Nov – 6 Nov');
    expect(daysSaid(readTask('- A [2026-11-02 +5d]')!)).toBe('2 Nov, 5 days');
    expect(daysSaid(readTask('- A [+1w]')!)).toBe('1 week');
    expect(daysSaid(readTask('- A')!)).toBeNull();
  });

  it('is drawn as its list on the page, not as code', () => {
    render(<Rendered body={`# Plan\n\n\`\`\`gantt\n${FENCE}\n\`\`\`\n`} />);
    const chart = screen.getByRole('region', { name: 'Gantt chart: Waitlist launch' });
    expect(chart.textContent).toContain('Interview five users');
    expect(chart.textContent).toContain('2 Nov – 4 Nov');
    expect(chart.textContent).toContain('after Interview five users, Read the competition');
    expect(chart.textContent).toContain('60%');
    expect(chart.querySelector('li[data-milestone]')!.textContent).toContain('Launch');
    expect(chart.querySelector('li[data-done]')!.textContent).toContain('Interview five users');
    expect(document.querySelector('pre')).toBeNull();
  });
});
