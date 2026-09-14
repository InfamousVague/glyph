import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { glyphMarkdown } from './language.ts';
import { shortLinks, shortUrl } from './links.ts';

describe('short links', () => {
  it('keeps the host, three characters, an ellipsis and three characters', () => {
    expect(shortUrl('https://www.notion.so/attackfm/Fix-the-login-bug-1a2b3c4d5e')).toBe('notion.so/att…d5e');
    expect(shortUrl('https://github.com/InfamousVague/glyph/pull/42')).toBe('github.com/Inf…/42');
    expect(shortUrl('http://example.com/path?x=12345678')).toBe('example.com/pat…678');
  });

  it('keeps short addresses whole', () => {
    expect(shortUrl('https://attack.fm')).toBe('attack.fm');
    expect(shortUrl('https://attack.fm/glyph/')).toBe('attack.fm/glyph');
  });

  it('shows the link short away from the caret and whole on its line', () => {
    const doc = 'Task: [Fix login](https://www.notion.so/attackfm/Fix-the-login-bug-1a2b3c4d5e)\n\nAnother line.';
    const parent = document.createElement('div');
    document.body.appendChild(parent);
    const view = new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown(), shortLinks()] }), parent });
    // Not focused: every link is short.
    expect(view.contentDOM.textContent).toContain('notion.so/att…d5e');
    expect(view.contentDOM.textContent).not.toContain('1a2b3c4d5e');
    view.destroy();
    parent.remove();
  });
});
