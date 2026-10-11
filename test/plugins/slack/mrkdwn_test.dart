import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/slack/mrkdwn.dart';

/// A note as Slack reads it: the obvious Markdown in Slack's mrkdwn, Slack's three escapes, and nothing of the
/// note's front matter or of what only the app can open. A port of `src/app/plugins/slack/mrkdwn.test.ts`, case
/// for case.
void main() {
  group('Markdown as mrkdwn', () {
    test('turns bold, italics and struck words into Slack’s marks', () {
      expect(toMrkdwn('**Ship** it *today*, __not__ ~~tomorrow~~'), '*Ship* it _today_, *not* ~tomorrow~');
      expect(toMrkdwn('_already_ Slack’s'), '_already_ Slack’s');
    });

    test('makes headings bold lines, and to-dos and bullets their signs, at their indent', () {
      expect(toMrkdwn('# Plan\n## Next **steps**\n- [ ] milk\n- [x] eggs\n  - [X] flour\n* bread\n- jam'), '*Plan*\n*Next steps*\n☐ milk\n☑ eggs\n  ☑ flour\n• bread\n• jam');
    });

    test('writes links Slack’s way, and an address the app owns as its words', () {
      expect(toMrkdwn('Read [the brief](https://example.com/a?b=1&c=2) and [the notes](note/abc).'), 'Read <https://example.com/a?b=1&c=2|the brief> and the notes.');
      expect(toMrkdwn('<https://example.com>'), '<https://example.com>');
      expect(toMrkdwn('[](https://example.com/x|y)'), '<https://example.com/x%7Cy>');
    });

    test('links a picture on the web, and leaves out one on the phone', () {
      expect(toMrkdwn('![chart](https://example.com/c.png)\n![](image/a.jpg)'), '<https://example.com/c.png|chart>');
    });

    test('escapes &, < and > everywhere but its own marks', () {
      expect(toMrkdwn('Tom & Jerry <3 > all\n> a quote & more'), 'Tom &amp; Jerry &lt;3 &gt; all\n> a quote &amp; more');
    });

    test('keeps code as written, escaped and unconverted', () {
      expect(toMrkdwn('Run `a **b** <c>` now\n```\n# not a heading\n- [ ] not a box\n```'), 'Run `a **b** &lt;c&gt;` now\n```\n# not a heading\n- [ ] not a box\n```');
    });

    test('hides a redaction behind a bar and gives the other looks as their words', () {
      expect(toMrkdwn('The code is @@hunter2@@, ==remember== it ^^now^^'), 'The code is ▇▇▇▇▇▇▇, remember it now');
      expect(toMrkdwn('C++ and C++'), 'C++ and C++');
    });

    test('makes runs of blank lines one', () {
      expect(toMrkdwn('a\n\n\n\nb\n'), 'a\n\nb');
    });

    // Not cases of the page's: the rest of what the file's header promises.
    test('gives the looks drawn with emoji as their words, and a rule as a line', () {
      expect(toMrkdwn('🔥🔥too hot🔥🔥 and ❄️❄️frozen❄️❄️ and ||hidden|| and %%aside%%'), 'too hot and frozen and hidden and aside');
      expect(toMrkdwn('above\n\n---\n\nbelow'), 'above\n\n———\n\nbelow');
      expect(toMrkdwn('@@x@@ and @@a very long secret indeed@@'), '▇▇▇ and ▇▇▇▇▇▇▇▇▇▇▇▇');
      expect(toMrkdwn('```\nopen <fence>'), '```\nopen &lt;fence&gt;\n```');
    });
  });

  group('a note as a message', () {
    test('opens with its title in bold, without the title line or the front matter again', () {
      expect(noteMessage('---\nlocation: 51.5, -0.1\n---\n# Launch plan\n\nShip **Friday**.\n- [ ] tell the team'), '*Launch plan*\nShip *Friday*.\n☐ tell the team');
    });

    test('takes the front matter’s title as the title, and keeps the first line of words', () {
      expect(noteMessage('---\ntitle: Standup\n---\nWe met.'), '*Standup*\nWe met.');
    });

    test('keeps a list that opens the note, under the title it gives', () {
      expect(noteMessage('- [ ] milk\n- [ ] eggs'), '*milk*\n☐ milk\n☐ eggs');
    });

    test('is the title alone when that is all there is', () {
      expect(noteMessage('Just a thought'), '*Just a thought*');
    });

    test('cuts a note longer than Slack takes, and says so', () {
      final long = noteMessage('Long\n${'word ' * 10000}');
      expect(long.length, lessThan(40000));
      expect(long, contains('The rest is in Ghost.md'));
    });

    test('posts a summary under the note’s title', () {
      expect(summaryMessage('# Standup\n\n## Summary\nWe agreed.\n\n- [ ] Sam: ship', '## Summary\nWe agreed.\n\n- [ ] Sam: ship'), '*Standup*\n*Summary*\nWe agreed.\n\n☐ Sam: ship');
    });

    test('is "Untitled" in bold for a note with no words, and knows such a note has none', () {
      expect(noteMessage(''), '*Untitled*');
      expect(hasWords('---\nlocation: 1, 2\n---\n'), isFalse);
      expect(hasWords('---\nlocation: 1, 2\n---\nHello'), isTrue);
    });
  });
}
