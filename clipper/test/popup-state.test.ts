import { describe, expect, it } from 'vitest';
import type { Extract, Peek } from '../src/core/page.ts';
import { canSave, draftOf, initial, reduce, startingMode, type Event, type State } from '../src/popup/state.ts';

/** The popup's state machine (src/popup/state.ts): every way through it, without a browser. */

const page: Peek = { url: 'https://field.example/a', title: 'The Quiet Garden | Field Notes', selected: false, readable: true };
const article: Extract = { mode: 'article', url: page.url, title: 'The Quiet Garden', markdown: 'Words.\n', pictures: [{ url: 'https://field.example/p.png', alt: 'p' }] };

const run = (events: Event[], from: State = initial()) => events.reduce(reduce, from);
const ready = () => run([{ type: 'signedIn', handle: 'matt' }, { type: 'peeked', page }, { type: 'read', extract: article }]);

describe('signing in', () => {
  it('starts signed out when nothing is kept, and asks for both before it sends', () => {
    let s = run([{ type: 'signedOut' }]);
    expect(s.phase).toBe('signedOut');
    s = reduce(s, { type: 'signIn' });
    expect(s).toMatchObject({ phase: 'signedOut', error: 'Type your handle and password.' });
    s = run([{ type: 'type', field: 'handle', value: 'matt' }, { type: 'type', field: 'password', value: 'correct horse' }, { type: 'stay', value: true }, { type: 'signIn' }], s);
    expect(s).toMatchObject({ phase: 'signingIn', handle: 'matt', password: 'correct horse', stay: true, error: null });
  });

  it('says a refusal and empties the password, keeping the handle', () => {
    const s = run([{ type: 'signedOut' }, { type: 'type', field: 'handle', value: 'matt' }, { type: 'type', field: 'password', value: 'nope' }, { type: 'signIn' }, { type: 'signInFailed', error: 'Wrong handle or password.' }]);
    expect(s).toMatchObject({ phase: 'signedOut', handle: 'matt', password: '', error: 'Wrong handle or password.' });
  });

  it('forgets the password once signed in, and goes on to read the page', () => {
    const s = run([{ type: 'signedOut' }, { type: 'type', field: 'handle', value: 'matt' }, { type: 'type', field: 'password', value: 'correct horse' }, { type: 'signIn' }, { type: 'signedIn', handle: 'matt' }]);
    expect(s).toMatchObject({ phase: 'reading', password: '' });
  });

  it('ignores typing once it is not asking', () => {
    const s = ready();
    expect(reduce(s, { type: 'type', field: 'password', value: 'x' })).toBe(s);
  });
});

describe('clipping', () => {
  it('opens on Selection when something is selected, else Article', () => {
    expect(startingMode(page)).toBe('article');
    expect(startingMode({ ...page, selected: true })).toBe('selection');
    expect(run([{ type: 'signedIn', handle: 'matt' }, { type: 'peeked', page: { ...page, selected: true } }]).mode).toBe('selection');
  });

  it('takes the page’s title, until the person writes their own, which a new mode keeps', () => {
    let s = ready();
    expect(s.form.title).toBe('The Quiet Garden');
    s = run([{ type: 'edit', field: 'title', value: 'Winter beds' }, { type: 'mode', mode: 'bookmark' }, { type: 'read', extract: { ...article, mode: 'bookmark', title: 'Something else' } }], s);
    expect(s.form.title).toBe('Winter beds');
    expect(s.mode).toBe('bookmark');
  });

  it('drops an answer for a mode the person has left', () => {
    const s = run([{ type: 'mode', mode: 'screenshot' }, { type: 'read', extract: { ...article, mode: 'page' } }], ready());
    expect(s).toMatchObject({ phase: 'reading', mode: 'screenshot' });
  });

  it('takes the whole page for an article that was not there, and says why', () => {
    const s = run([{ type: 'signedIn', handle: 'matt' }, { type: 'peeked', page }, { type: 'read', extract: { ...article, mode: 'page', notice: 'no-article' } }]);
    expect(s).toMatchObject({ phase: 'ready', mode: 'article' });
    expect(s.extract?.notice).toBe('no-article');
    expect(draftOf(s).mode).toBe('page');
  });

  it('says why a page could not be read, and cannot save it', () => {
    const s = run([{ type: 'signedIn', handle: 'matt' }, { type: 'peeked', page }, { type: 'readFailed', error: 'This page can’t be clipped.' }]);
    expect(s).toMatchObject({ phase: 'ready', extract: null, error: 'This page can’t be clipped.' });
    expect(canSave(s)).toBe(false);
    expect(reduce(s, { type: 'save' }).phase).toBe('ready');
  });

  it('will not save a note with no title, and says so', () => {
    const s = run([{ type: 'edit', field: 'title', value: '   ' }, { type: 'save' }], ready());
    expect(s).toMatchObject({ phase: 'ready', error: 'Give the note a title.' });
  });

  it('drops a workspace or notebook that is no longer the account’s', () => {
    let s = run([{ type: 'choices', choices: { workspaces: [{ id: 'w1', name: 'Garden' }], notebooks: [{ id: 'b1', title: 'Reading' }] } }, { type: 'edit', field: 'workspace', value: 'w1' }, { type: 'edit', field: 'notebook', value: 'b1' }], ready());
    expect(s.form).toMatchObject({ workspace: 'w1', notebook: 'b1' });
    s = reduce(s, { type: 'choices', choices: { workspaces: [], notebooks: [{ id: 'b1', title: 'Reading' }] } });
    expect(s.form).toMatchObject({ workspace: null, notebook: 'b1' });
    expect(reduce(s, { type: 'edit', field: 'notebook', value: '' }).form.notebook).toBeNull();
  });
});

describe('saving', () => {
  it('sends what the person chose with what the page answered', () => {
    const s = run([{ type: 'edit', field: 'tags', value: '#reading, garden' }, { type: 'edit', field: 'comment', value: 'For spring.' }, { type: 'edit', field: 'workspace', value: 'w1' }, { type: 'save' }], ready());
    expect(s.phase).toBe('saving');
    expect(draftOf(s)).toEqual({ mode: 'article', url: page.url, title: 'The Quiet Garden', markdown: 'Words.\n', pictures: article.pictures, tags: ['reading', 'garden'], comment: 'For spring.', workspace: 'w1', notebook: null });
  });

  it('is saved, and can clip again', () => {
    let s = run([{ type: 'save' }, { type: 'saved', saved: { id: 'n1', title: 'The Quiet Garden', stored: 1, linked: [] } }], ready());
    expect(s.phase).toBe('saved');
    s = reduce(s, { type: 'again' });
    expect(s).toMatchObject({ phase: 'ready', saved: null });
  });

  it('says a failure and stays ready to try again', () => {
    const s = run([{ type: 'save' }, { type: 'saveFailed', error: 'The sync service could not be reached.' }], ready());
    expect(s).toMatchObject({ phase: 'ready', error: 'The sync service could not be reached.' });
    expect(canSave(s)).toBe(true);
  });

  it('goes back to signing in when the session has ended, with the handle kept', () => {
    const s = run([{ type: 'save' }, { type: 'saveFailed', error: 'Your session has ended. Sign in again.', signedOut: true }], ready());
    expect(s).toMatchObject({ phase: 'signedOut', handle: 'matt', extract: null, error: 'Your session has ended. Sign in again.' });
  });

  it('ignores a second Save while one is on its way', () => {
    const s = run([{ type: 'save' }], ready());
    expect(reduce(s, { type: 'save' })).toBe(s);
    expect(reduce(s, { type: 'mode', mode: 'page' })).toBe(s);
  });
});
