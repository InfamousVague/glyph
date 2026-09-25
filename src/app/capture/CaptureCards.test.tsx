import { describe, expect, it, vi } from 'vitest';
import { button, press, show } from '../../test/render.tsx';
import type { Note } from '../core/store.ts';
import { ListLanding, TableCard } from './CaptureCards.tsx';
import type { TableDraft } from './takeHost.ts';

/** The recorder's cards (capture/CaptureCards.tsx): the table asked for a piece at a time, and items landing in a list. */

const draft = (over: Partial<TableDraft<Note>> = {}): TableDraft<Note> => ({ note: null, title: 'AttackFM', columns: [], rows: [], lastAt: 0, ...over });

describe('the table card', () => {
  it('asks for the labels first, with how to say them, and offers no "That’s all" until there are some', () => {
    const card = show(<TableCard draft={draft()} heard="" onDone={vi.fn()} onCancel={vi.fn()} />);
    expect(card.textContent).toContain('Table for AttackFM');
    expect(card.textContent).toContain('What will the column labels be?');
    expect(card.textContent).toContain('Say them with commas, like “bug, owner, status”.');
    expect(card.querySelector('table')).toBeNull();
    expect(() => button('That’s all', card)).toThrow();
  });

  it('asks for the first row, then the next, showing the table as it grows', () => {
    const first = show(<TableCard draft={draft({ columns: ['Bug', 'Owner'] })} heard="" onDone={vi.fn()} onCancel={vi.fn()} />);
    expect(first.textContent).toContain('What goes in the first row?');
    expect(first.textContent).toContain('In order: Bug, Owner.');
    const next = show(<TableCard draft={draft({ columns: ['Bug', 'Owner'], rows: [['Seek bar drift']] })} heard="" onDone={vi.fn()} onCancel={vi.fn()} />);
    expect(next.textContent).toContain('Next row? Or say “done”.');
    expect([...next.querySelectorAll('td')].map((cell) => cell.textContent)).toEqual(['Seek bar drift', '']);
  });

  it('shows the words being heard for the piece it asked for, without the keyword', () => {
    const card = show(<TableCard draft={draft({ columns: ['Bug'] })} heard="Hey Ghost, downloads stuck" onDone={vi.fn()} onCancel={vi.fn()} />);
    expect(card.textContent).toContain('“downloads stuck”');
    expect(card.textContent).not.toContain('In order');
  });

  it('answers its two buttons', () => {
    const onDone = vi.fn();
    const onCancel = vi.fn();
    const card = show(<TableCard draft={draft({ columns: ['Bug'] })} heard="" onDone={onDone} onCancel={onCancel} />);
    press(button('That’s all', card));
    press(button('Cancel', card));
    expect(onDone).toHaveBeenCalledOnce();
    expect(onCancel).toHaveBeenCalledOnce();
  });
});

describe('items landing in another note', () => {
  it('shows the list’s last lines as they were, then the new ones, all without their marks', () => {
    const body = '# Shopping\n\n- Eggs\n- Bread\n- [ ] Milk\n\n- Oat milk\n- Bin bags';
    const landing = show(<ListLanding title="Shopping" body={body} added={['- Oat milk', '- Bin bags']} />);
    const lines = [...landing.querySelectorAll('p')].map((line) => line.textContent);
    expect(lines).toEqual(['Shopping', 'Milk', 'Oat milk', 'Bin bags']);
  });
});
