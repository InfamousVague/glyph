import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { NoteEditing } from '../types.ts';

/**
 * Sending a list item to GitHub as an issue: the rules Notion's sending learned first (notion/send.test.ts), which
 * GitHub's own copy never had. A second press on the same words made a second issue, and an issue whose line had
 * changed while GitHub answered was made and left unmarked, which is what makes a person press again.
 *
 * The issues module is stubbed: these are the plugin's rules, not GitHub's.
 */

const made: string[] = [];
const project = { id: 'o/r', owner: 'o', repo: 'r', url: '', branch: 'main', description: '', files: [], pack: '', packModel: null, packedAt: 0 };

vi.mock('./issues.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./issues.ts')>()),
  canWriteIssues: () => true,
  createIssue: vi.fn(async (_project: unknown, title: string) => {
    made.push(title);
    const number = made.length;
    return { owner: 'o', repo: 'r', number, url: `https://github.com/o/r/issues/${number}`, title, state: 'open', labels: [], assignees: [], updatedAt: 0, body: '' };
  }),
}));
vi.mock('./repos.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./repos.ts')>()),
  projectFor: () => project,
}));
vi.mock('../../core/haptics.ts', () => ({ fireNativeHaptic: () => undefined }));

const { githubPlugin, forgetSent } = await import('./index.tsx');

/** A note in memory, as the editor would give it: the plugin reads it and writes lines back. */
function noteOf(body: string) {
  const state = { lines: body.split('\n'), said: [] as string[] };
  const editing: NoteEditing = {
    noteId: 'note-1',
    body: () => state.lines.join('\n'),
    replaceLine(find, next) {
      for (let n = 1; n <= state.lines.length; n += 1) {
        const text = state.lines[n - 1] ?? '';
        if (find(text, n)) {
          state.lines[n - 1] = next(text);
          return true;
        }
      }
      return false;
    },
    say: (message) => state.said.push(message),
  };
  return { state, editing };
}

/** Sends `text` the way the quiet "GitHub" after the item does, through the plugin's own suggestion for that line. */
async function send(editing: NoteEditing, text: string): Promise<void> {
  const suggestion = (githubPlugin.suggest?.('note-1', editing.body()) ?? []).find((s) => editing.body().split('\n')[s.line - 1]?.includes(text));
  if (!suggestion) throw new Error(`nothing offered for ${text}`);
  await suggestion.run(editing);
}

beforeEach(() => {
  made.length = 0;
  forgetSent();
  localStorage.clear();
});

describe('sending an item to GitHub', () => {
  it('makes the issue and marks the line with it', async () => {
    const { state, editing } = noteOf('# Jobs\n\n- [ ] Fix the tab row\n- [ ] Ship it');
    await send(editing, 'Fix the tab row');
    expect(made).toEqual(['Fix the tab row']);
    expect(state.lines[2]).toBe('- [ ] Fix the tab row [github](https://github.com/o/r/issues/1)');
    expect(state.said).toEqual(['Made 1 issue in o/r.']);
  });

  it('makes one issue however often the same words are sent', async () => {
    const { state, editing } = noteOf('- [ ] Fix the tab row');
    await send(editing, 'Fix the tab row');
    // The line is marked, so a second press would not normally be possible; the words are sent again all the same.
    state.lines[0] = '- [ ] Fix the tab row';
    await send(editing, 'Fix the tab row');
    expect(made, 'the same words must not become two issues').toEqual(['Fix the tab row']);
    expect(state.lines[0]).toBe('- [ ] Fix the tab row [github](https://github.com/o/r/issues/1)');
  });

  it('marks the line it was on when the words have changed since', async () => {
    const { state, editing } = noteOf('- [ ] Fix the tab row');
    const run = send(editing, 'Fix the tab row');
    // The person keeps typing while GitHub answers.
    state.lines[0] = '- [ ] Fix the tab row on the Fold';
    await run;
    expect(made).toEqual(['Fix the tab row']);
    expect(state.lines[0]).toBe('- [ ] Fix the tab row on the Fold [github](https://github.com/o/r/issues/1)');
  });

  it('sends a whole list from the cog, each item once, and says how many', async () => {
    const { state, editing } = noteOf('- [ ] One\n- [ ] Two\n- [x] Done already');
    const action = githubPlugin.noteActions?.find((a) => a.id === 'github-send-list');
    await action!.run(editing);
    expect(made).toEqual(['One', 'Two']);
    expect(state.said).toEqual(['Made 2 issues in o/r.']);
    await action!.run(editing);
    expect(made).toEqual(['One', 'Two']);
  });

  it('says GitHub’s refusal and stops there', async () => {
    const { createIssue } = await import('./issues.ts');
    vi.mocked(createIssue).mockRejectedValueOnce(new Error('GitHub didn’t accept that token.'));
    const { state, editing } = noteOf('- [ ] One\n- [ ] Two');
    await githubPlugin.noteActions!.find((a) => a.id === 'github-send-list')!.run(editing);
    expect(state.said).toEqual(['GitHub didn’t accept that token.']);
    expect(state.lines).toEqual(['- [ ] One', '- [ ] Two']);
  });
});
