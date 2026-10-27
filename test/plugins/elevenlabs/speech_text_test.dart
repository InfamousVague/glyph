// A note made into words to read aloud, and cut into reads (lib/plugins/elevenlabs/speech_text.dart): what a person
// reads on the page, never the Markdown under it; and reads that keep every word, in order, none past its limit.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/elevenlabs/speech_text.dart';

void main() {
  group('speechText', () {
    test('the front matter, code, pictures, memos, files and rules are not read; a heading and items are phrases of their own', () {
      const body = '''---
title: Trip
banner: image/b.png
---
# Trip to Lisbon

![a tram](image/tram.png)
We land on **Friday** and take the _tram_ to `Alfama`.

- [ ] Book the hotel
- [x] Pack the ~~big~~ small bag
1. Pastéis de nata

> Bring a jacket

```dart
print('not read');
```

[Lease 2026.pdf](file/5f0c2e9a-1b2c-4d3e-8f40-0a1b2c3d4e5f.pdf "2.4 MB")
[Voice-over, Elara.mp3](file/aaaa.mp3 "1.0 MB")
![voice 0:12](tape:12000-19500@k3f9x2)

---
Thanks!''';
      expect(speechText(body), '''Trip to Lisbon.

We land on Friday and take the tram to Alfama.

Book the hotel.

Pack the big small bag.

Pastéis de nata.

Bring a jacket

Thanks!''');
    });

    test('a link is its words, a wiki link its title or alias, and footnotes, cues, HTML and bare addresses go', () {
      const body = 'See [the plan](https://example.com/plan) and [[Budget 2027]] or [[Q3 notes|the notes]].[^c1] {image: a red chair} <b>Now</b> https://ghostmarkdown.com #travel\n\n[^c1]: A comment.';
      expect(speechText(body), 'See the plan and Budget 2027 or the notes. Now travel');
    });

    test('a table is read a row at a time, each cell after its heading', () {
      const body = '''| Name | Role |
| --- | :-: |
| Ada | lead |
| Grace |  |''';
      expect(speechText(body), 'Name: Ada, Role: lead. Name: Grace.');
    });

    test('an unclosed fence takes the rest of the note with it; nothing to read is empty', () {
      expect(speechText('Before\n```\ncode\nmore'), 'Before');
      expect(speechText('---\na: b\n---\n\n![x](image/x.png)\n'), '');
    });

    test('lines of one paragraph are read as one', () {
      expect(speechText('One line\nand the next'), 'One line and the next');
    });
  });

  group('speechChunks', () {
    String words(List<String> chunks) => chunks.join(' ').split(RegExp(r'\s+')).join(' ');

    test('short words are one read', () {
      expect(speechChunks('Hello.\n\nAgain.', most: 100), ['Hello.\n\nAgain.']);
    });

    test('cut at paragraphs, then sentences, then spaces; none past the limit, every word kept in order', () {
      final paragraph = List.generate(12, (i) => 'Sentence number $i is here.').join(' ');
      final text = [paragraph, 'Short one.', paragraph].join('\n\n');
      final chunks = speechChunks(text, most: 120);
      expect(chunks.every((c) => c.length <= 120), isTrue);
      expect(words(chunks), text.split(RegExp(r'\s+')).join(' '));
      // A sentence is never cut in the middle where it fits.
      for (final chunk in chunks) {
        expect(chunk.trimRight(), endsWith('.'));
      }
    });

    test('a word longer than the limit is cut where it must be', () {
      final chunks = speechChunks('a ${'x' * 25} b', most: 10);
      expect(chunks.every((c) => c.length <= 10), isTrue);
      expect(chunks.join().replaceAll(' ', ''), 'a${'x' * 25}b');
    });
  });
}
