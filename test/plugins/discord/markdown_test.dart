import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/discord/markdown.dart';

/// A note as Discord reads it (lib/plugins/discord/markdown.dart; Matt, 2026-10-26): Markdown left as Discord reads
/// it, turned where Discord reads it otherwise or not at all, and one message, cut at a line with a link to the rest.
void main() {
  group('Markdown as Discord’s', () {
    test('keeps what Discord reads as Markdown does, and makes __bold__ bold, not underlined', () {
      expect(toDiscordMarkdown('**Ship** it *today* or _soon_, __not__ ~~tomorrow~~'), '**Ship** it *today* or _soon_, **not** ~~tomorrow~~');
      expect(toDiscordMarkdown('snake__case__words stay'), 'snake__case__words stay');
    });

    test('makes the note’s headings Discord’s third size, deeper ones bold lines', () {
      expect(toDiscordMarkdown('# Plan\n## Next **steps**\n### Later\n#### Much later'), '### Plan\n### Next steps\n**Later**\n**Much later**');
    });

    test('draws to-dos as boxes and every bullet as a dash, at their indent', () {
      expect(toDiscordMarkdown('- [ ] milk\n- [x] eggs\n  - [X] flour\n* bread\n+ jam\n1. first'), '- ☐ milk\n- ☑ eggs\n  - ☑ flour\n- bread\n- jam\n1. first');
    });

    test('keeps web links as Discord’s, and an address the app owns as its words', () {
      expect(toDiscordMarkdown('Read [the **brief**](https://example.com/a?b=1&c=2) and [the notes](note/abc).'), 'Read [the brief](https://example.com/a?b=1&c=2) and the notes.');
      expect(toDiscordMarkdown('<https://example.com>'), '<https://example.com>');
      expect(toDiscordMarkdown('[](https://example.com/x)'), '<https://example.com/x>');
      // An address the message writes itself has its brackets encoded, so it cannot end the link early.
      expect(discordLinkUrl('https://en.wikipedia.org/wiki/Foo_(bar)'), 'https://en.wikipedia.org/wiki/Foo_%28bar%29');
    });

    test('links a picture on the web, and leaves out one on the phone', () {
      expect(toDiscordMarkdown('![chart](https://example.com/c.png)\n![](image/a.jpg)'), '[chart](https://example.com/c.png)');
    });

    test('keeps code as written, and a ~~~ fence as a ``` one with its language', () {
      expect(toDiscordMarkdown('Run `a __b__ ||c||` now\n~~~dart\n# not a heading\n- [ ] not a box\n~~~'), 'Run `a __b__ ||c||` now\n```dart\n# not a heading\n- [ ] not a box\n```');
      expect(toDiscordMarkdown('```\nopen fence'), '```\nopen fence\n```');
    });

    test('hides a redaction behind a bar, not a spoiler, and gives the other looks as their words', () {
      expect(toDiscordMarkdown('The code is @@hunter2@@, ==remember== it ^^now^^ ||or else||'), 'The code is ▇▇▇▇▇▇▇, remember it now or else');
      expect(toDiscordMarkdown('🔥🔥too hot🔥🔥 and %%aside%%'), 'too hot and aside');
    });

    test('draws a rule as a line, a table in a code block, and escapes Discord’s small print', () {
      expect(toDiscordMarkdown('above\n\n---\n\nbelow'), 'above\n\n———\n\nbelow');
      expect(toDiscordMarkdown('Prices:\n| Item | £ |\n|---|---:|\n| Tea | 2 |\nAfter'), 'Prices:\n```\n| Item | £ |\n|---|---:|\n| Tea | 2 |\n```\nAfter');
      expect(toDiscordMarkdown('-# not small'), r'\-# not small');
      expect(toDiscordMarkdown('> a quote **too**'), '> a quote **too**');
    });

    test('makes runs of blank lines one', () {
      expect(toDiscordMarkdown('a\n\n\n\nb\n'), 'a\n\nb');
    });
  });

  group('a note as a message', () {
    test('opens with its title as a heading, without the title line or the front matter again', () {
      expect(discordNoteMessage('---\nlocation: 51.5, -0.1\n---\n# Launch plan\n\nShip __Friday__.\n- [ ] tell the team'), '## Launch plan\nShip **Friday**.\n- ☐ tell the team');
    });

    test('takes the front matter’s title, keeps a list that opens the note, and is "Untitled" with no words', () {
      expect(discordNoteMessage('---\ntitle: Standup\n---\nWe met.'), '## Standup\nWe met.');
      expect(discordNoteMessage('- [ ] milk\n- [ ] eggs'), '## milk\n- ☐ milk\n- ☐ eggs');
      expect(discordNoteMessage(''), '## Untitled');
      expect(discordHasWords('---\nlocation: 1, 2\n---\n'), isFalse);
      expect(discordHasWords('---\nlocation: 1, 2\n---\nHello'), isTrue);
    });

    test('posts a summary under the note’s title', () {
      const section = '## Summary\nWe agreed.\n\n- [ ] Sam: ship';
      expect(discordSummaryMessage('# Standup\n\n$section', section), '## Standup\n### Summary\nWe agreed.\n\n- ☐ Sam: ship');
    });

    test('fits a note of 2000 characters whole, and cuts a longer one at a line with its share link', () {
      final exactly = 'T\n${'x' * (2000 - 5)}';
      expect(discordNoteMessage(exactly), '## T\n${'x' * 1995}');
      expect(discordNoteMessage(exactly).length, 2000);

      final long = 'Long\n${[for (var i = 0; i < 300; i++) 'Line $i of the note.'].join('\n')}';
      expect(discordTooLong(discordNoteText(long)), isTrue);
      final cut = discordNoteMessage(long, rest: 'https://ghostmarkdown.com/read.html#abc.def');
      expect(cut.length, lessThanOrEqualTo(2000));
      expect(cut, startsWith('## Long\nLine 0 of the note.\n'));
      expect(cut, endsWith('\n…\n**[Read the rest in Ghost.md](https://ghostmarkdown.com/read.html#abc.def)**'));
      // Cut at a line: the last line kept is whole.
      final kept = cut.split('\n…\n').first.split('\n').last;
      expect(kept, matches(RegExp(r'^Line \d+ of the note\.$')));
    });

    test('says the rest is in Ghost.md where there is no link, and closes a fence it cuts', () {
      final code = '# Code\n```\n${'print(1);\n' * 400}```';
      final cut = discordNoteMessage(code);
      expect(cut.length, lessThanOrEqualTo(2000));
      expect(cut, endsWith('\n```\n…\n*The rest is in Ghost.md: it is longer than one Discord message.*'));
      expect(RegExp('^```', multiLine: true).allMatches(cut).length.isEven, isTrue);
    });

    test('never splits a pair of UTF-16 units, and counts in them', () {
      final emoji = 'E\n${'😀' * 1500}';
      final cut = discordNoteMessage(emoji);
      expect(cut.length, lessThanOrEqualTo(2000));
      final before = cut.split('\n…\n').first;
      expect(before.runes.every((r) => r < 0xD800 || r > 0xDFFF), isTrue);
    });

    test('escapes Discord’s marks in plain words, and strips a line of them for a mark of the message’s own', () {
      expect(discordEscaped('Hello_Trade *Co* <3 #1 [x] |y| ~z~ `q`'), r'Hello\_Trade \*Co\* \<3 \#1 \[x\] \|y\| \~z\~ \`q\`');
      expect(discordPlain('A call about the **launch** and *more*'), 'A call about the launch and more');
    });
  });
}
