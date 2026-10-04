import { describe, expect, it } from 'vitest';
import { noteMessage, summaryMessage, toMrkdwn } from './mrkdwn.ts';

/**
 * A note as Slack reads it: the obvious Markdown in Slack's mrkdwn, Slack's three escapes, and nothing of the note's
 * front matter or of what only the app can open.
 */

describe('Markdown as mrkdwn', () => {
  it('turns bold, italics and struck words into Slack’s marks', () => {
    expect(toMrkdwn('**Ship** it *today*, __not__ ~~tomorrow~~')).toBe('*Ship* it _today_, *not* ~tomorrow~');
    expect(toMrkdwn('_already_ Slack’s')).toBe('_already_ Slack’s');
  });

  it('makes headings bold lines, and to-dos and bullets their signs, at their indent', () => {
    expect(toMrkdwn('# Plan\n## Next **steps**\n- [ ] milk\n- [x] eggs\n  - [X] flour\n* bread\n- jam')).toBe('*Plan*\n*Next steps*\n☐ milk\n☑ eggs\n  ☑ flour\n• bread\n• jam');
  });

  it('writes links Slack’s way, and an address the app owns as its words', () => {
    expect(toMrkdwn('Read [the brief](https://example.com/a?b=1&c=2) and [the notes](note/abc).')).toBe('Read <https://example.com/a?b=1&c=2|the brief> and the notes.');
    expect(toMrkdwn('<https://example.com>')).toBe('<https://example.com>');
    expect(toMrkdwn('[](https://example.com/x|y)')).toBe('<https://example.com/x%7Cy>');
  });

  it('links a picture on the web, and leaves out one on the phone', () => {
    expect(toMrkdwn('![chart](https://example.com/c.png)\n![](image/a.jpg)')).toBe('<https://example.com/c.png|chart>');
  });

  it('escapes &, < and > everywhere but its own marks', () => {
    expect(toMrkdwn('Tom & Jerry <3 > all\n> a quote & more')).toBe('Tom &amp; Jerry &lt;3 &gt; all\n> a quote &amp; more');
  });

  it('keeps code as written, escaped and unconverted', () => {
    expect(toMrkdwn('Run `a **b** <c>` now\n```\n# not a heading\n- [ ] not a box\n```')).toBe('Run `a **b** &lt;c&gt;` now\n```\n# not a heading\n- [ ] not a box\n```');
  });

  it('hides a redaction behind a bar and gives the other looks as their words', () => {
    expect(toMrkdwn('The code is @@hunter2@@, ==remember== it ^^now^^')).toBe('The code is ▇▇▇▇▇▇▇, remember it now');
    expect(toMrkdwn('C++ and C++')).toBe('C++ and C++');
  });

  it('makes runs of blank lines one', () => {
    expect(toMrkdwn('a\n\n\n\nb\n')).toBe('a\n\nb');
  });
});

describe('a note as a message', () => {
  it('opens with its title in bold, without the title line or the front matter again', () => {
    expect(noteMessage('---\nlocation: 51.5, -0.1\n---\n# Launch plan\n\nShip **Friday**.\n- [ ] tell the team')).toBe('*Launch plan*\nShip *Friday*.\n☐ tell the team');
  });

  it('takes the front matter’s title as the title, and keeps the first line of words', () => {
    expect(noteMessage('---\ntitle: Standup\n---\nWe met.')).toBe('*Standup*\nWe met.');
  });

  it('keeps a list that opens the note, under the title it gives', () => {
    expect(noteMessage('- [ ] milk\n- [ ] eggs')).toBe('*milk*\n☐ milk\n☐ eggs');
  });

  it('is the title alone when that is all there is', () => {
    expect(noteMessage('Just a thought')).toBe('*Just a thought*');
  });

  it('cuts a note longer than Slack takes, and says so', () => {
    const long = noteMessage(`Long\n${'word '.repeat(10_000)}`);
    expect(long.length).toBeLessThan(40_000);
    expect(long).toContain('The rest is in Ghost.md');
  });

  it('posts a summary under the note’s title', () => {
    expect(summaryMessage('# Standup\n\n## Summary\nWe agreed.\n\n- [ ] Sam: ship', '## Summary\nWe agreed.\n\n- [ ] Sam: ship')).toBe('*Standup*\n*Summary*\nWe agreed.\n\n☐ Sam: ship');
  });
});
