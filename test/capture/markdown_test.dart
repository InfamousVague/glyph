import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart';
import 'package:ghost_md/capture/spoken/extras.dart';
import 'package:ghost_md/capture/spoken/inline.dart';
import 'package:ghost_md/capture/spoken/lists.dart';

/// What a spoken note becomes (lib/capture/markdown.dart), case for case with the web's `capture/markdown.test.ts`.
///
/// The cases fall into two groups and both matter. The first proves the rules catch what they are for. The second -
/// "does NOT become a list", "is NOT a title" - proves the precision the library's header promises, because a false
/// list mangles prose that would otherwise have read fine, and that failure is invisible until it happens to a real
/// note.

/// Segments one second long with a short breath between each.
List<Segment> spoken(List<String> texts) {
  var at = 0;
  return [
    for (final text in texts)
      () {
        final segment = Segment(text: text, startMs: at, endMs: at + 1000);
        at += 1300;
        return segment;
      }(),
  ];
}

String opening() => 'This opening sentence is long enough not to become a title.';

String md(List<String> texts, [String partial = '', RenderOptions options = const RenderOptions()]) => renderNote(spoken(texts), partial, options).markdown;

void main() {
  group('toParagraphs', () {
    test('joins segments separated by a breath into one paragraph', () {
      expect(toParagraphs(spoken(['The first thought.', 'And more of it.'])), ['The first thought. And more of it.']);
    });

    test('starts a new paragraph after a long pause', () {
      const segments = [Segment(text: 'One idea.', startMs: 0, endMs: 1000), Segment(text: 'A different one.', startMs: 4000, endMs: 5000)];
      expect(toParagraphs(segments), ['One idea.', 'A different one.']);
    });

    test('breaks on a spoken "new paragraph" and removes the cue', () {
      expect(toParagraphs(spoken(['That covers it. New paragraph. the next part.'])), ['That covers it.', 'The next part.']);
    });
  });

  group('enumeration', () {
    test('finds a list after a word that introduces one', () {
      final found = enumeration('I need eggs, milk, bread and coffee.');
      expect(found?.intro, 'I need');
      expect(found?.items, ['eggs', 'milk', 'bread', 'coffee']);
    });

    test('keeps a determiner with the first item', () {
      expect(enumeration('We should pick up some eggs, milk and bread.')?.items[0], 'some eggs');
    });

    test('accepts an Oxford comma', () {
      expect(enumeration('The team is Sarah, Tom, and Priya.')?.items, ['Sarah', 'Tom', 'Priya']);
      // "these" points at the list: it is the intro's word, not the first item.
      final found = enumeration('Pack these, the tent, the stove and the lantern.');
      expect(found?.intro, 'Pack these');
      expect(found?.items, ['the tent', 'the stove', 'the lantern']);
    });

    // The reason the rule demands an introducing word. These commas are clauses, and without the demand this sentence
    // became "We went to:" over three bullets.
    test('does NOT treat a sequence of clauses as a list', () {
      expect(enumeration('We went to the store, bought food, and came home.'), isNull);
    });

    test('does NOT make a list of long items', () {
      expect(enumeration('I need the report from last quarter, the slides we used in March, and the budget.'), isNull);
    });

    test('does NOT make a list of two items', () {
      expect(enumeration('I need eggs and milk.'), isNull);
    });
  });

  group('renderNote with local rules', () {
    test('turns a short opening into the title', () {
      expect(md(['Grocery run.', 'It has to happen before Saturday.']), '# Grocery run\n\nIt has to happen before Saturday.');
    });

    test('does NOT title a long opening', () {
      expect(md(['So I was thinking about how the launch went last week.']).startsWith('#'), false);
    });

    test('does NOT title an opening to-do', () {
      expect(md(['I need to call the bank.']), '- [ ] Call the bank');
    });

    test('honours a spoken title cue', () {
      expect(md(['Title: launch retro.', 'It went well.']), '# Launch retro\n\nIt went well.');
    });

    test('gives a recording added to a note no title of its own', () {
      const untitled = RenderOptions(titled: false);
      expect(md(['Grocery run.', 'It has to happen before Saturday.'], '', untitled), 'Grocery run. It has to happen before Saturday.');
      // A spoken title there is a section, not a second title mid-note.
      expect(md(['Title: launch retro.', 'It went well.'], '', untitled), '## Launch retro\n\nIt went well.');
      expect(md(['Title.', 'Launch retro.', 'It went well.'], '', untitled).startsWith('## '), true);
    });

    test('makes to-dos out of "need to" and "remember to"', () {
      expect(md(['Weekend plans.', 'I need to call the plumber.', "Don't forget to pay the rent."]), '# Weekend plans\n\n- [ ] Call the plumber\n- [ ] Pay the rent');
    });

    test('renders a spoken list under its intro', () {
      expect(md(['Shopping.', 'I need eggs, milk, bread and coffee.']), '# Shopping\n\nI need:\n- eggs\n- milk\n- bread\n- coffee');
    });

    test('separates a list intro from a to-do directly above it', () {
      expect(
        md(['Trip prep.', 'I need to renew my passport.', 'I need socks, shirts and a charger.']),
        '# Trip prep\n\n- [ ] Renew my passport\n\nI need:\n- socks\n- shirts\n- a charger',
      );
    });

    test('closes a spoken list before a to-do that follows it', () {
      expect(
        md(['Road trip.', 'For the drive we want snacks, water and a charger.', 'Remember to ask Sam about the dog.']),
        '# Road trip\n\nFor the drive we want:\n- snacks\n- water\n- a charger\n\n- [ ] Ask Sam about the dog',
      );
    });

    test('numbers an ordinal run once "first" has started it', () {
      expect(md(['Deploy steps.', 'First, build the app.', 'Then run the tests.', 'Finally, ship it.']), '# Deploy steps\n\n1. Build the app\n2. Run the tests\n3. Ship it');
    });

    test('does NOT number "then" without a "first"', () {
      expect(md(['It rained all morning and then it cleared up.', 'Then we went out.']), isNot(matches(RegExp(r'^\d\.', multiLine: true))));
    });

    test('honours spoken heading and bullet cues', () {
      expect(
        md(['This is a longer opening sentence about the week.', 'Heading: next steps.', 'Bullet point: book flights.']),
        'This is a longer opening sentence about the week.\n\n## Next steps\n\n- Book flights',
      );
    });

    test('emboldens a spoken "important"', () {
      expect(md(['This is a longer opening about the deadline itself.', 'Important: it moved to Friday.']), contains('**Important:** It moved to Friday.'));
    });

    // The paragraph survives rendering, not just toParagraphs: sentences of one paragraph are joined back into a
    // line, and that join must stop at a break.
    test('keeps a "new paragraph" said as its own segment', () {
      expect(
        md(['The kitchen needs work before we list it.', 'New paragraph.', 'The garden is fine as it is.']),
        'The kitchen needs work before we list it.\n\nThe garden is fine as it is.',
      );
    });

    test('keeps a "new paragraph" said mid-segment', () {
      expect(
        md(['The kitchen needs work before we list it. New paragraph. The garden is fine as it is.']),
        'The kitchen needs work before we list it.\n\nThe garden is fine as it is.',
      );
    });

    test('keeps a paragraph broken by a long pause', () {
      final markdown = renderNote(const [
        Segment(text: 'The kitchen needs work before we list it.', startMs: 0, endMs: 2000),
        Segment(text: 'The garden is fine as it is.', startMs: 5000, endMs: 7000),
      ]).markdown;
      expect(markdown, 'The kitchen needs work before we list it.\n\nThe garden is fine as it is.');
    });

    test('still joins the sentences inside one paragraph', () {
      expect(
        md(['The kitchen needs work before we list it.', 'The cupboards are the worst of it.']),
        'The kitchen needs work before we list it. The cupboards are the worst of it.',
      );
    });
  });

  group('renderNote with the in-progress phrase', () {
    test('appends the partial to the last paragraph and reports where it starts', () {
      final note = renderNote(spoken(['This is a longer opening sentence to avoid a title.']), 'and this is still');
      expect(note.markdown, 'This is a longer opening sentence to avoid a title. and this is still');
      expect(note.markdown.substring(note.pendingFrom ?? 0), 'and this is still');
    });

    test('puts the partial on its own line after a list', () {
      final note = renderNote(spoken(['I need to call the bank.']), 'and then');
      expect(note.markdown, '- [ ] Call the bank\n\nand then');
      expect(note.markdown.substring(note.pendingFrom ?? 0), 'and then');
    });

    test('keeps the partial out of the committed transcript', () {
      expect(renderNote(spoken(['Committed words.']), 'not yet').plain, 'Committed words.');
    });
  });

  // The cues the "how to talk to Glyph" guide teaches. The guide renders its own examples through renderNote, so
  // these tests are the contract it relies on: each cue does what the guide says, and each one leaves ordinary speech
  // alone.
  group('guide cues', () {
    const opening = 'This opening sentence is long enough not to become a title.';

    test('quotes', () {
      expect(md([opening, 'Quote, the best way out is always through.']), '$opening\n\n> The best way out is always through.');
    });

    test('keeps consecutive quotes in one block', () {
      expect(md([opening, 'Quote, first line.', 'Quote, second line.']), '$opening\n\n> First line.\n> Second line.');
    });

    test('numbers spoken "number one, number two"', () {
      expect(md([opening, 'Number one, book flights.', 'Number 2, pack bags.']), '$opening\n\n1. Book flights\n2. Pack bags');
    });

    test('does NOT number "number one" said as prose', () {
      expect(md([opening, 'Number one priority is sleep.']), isNot(matches(RegExp(r'^\d\.', multiLine: true))));
    });

    test('makes a check box', () {
      expect(md([opening, 'Check box, call the dentist.']), '$opening\n\n- [ ] Call the dentist');
      expect(md([opening, 'Checklist item, renew passport.']), '$opening\n\n- [ ] Renew passport');
    });

    test('does NOT make a check box of a sentence about a checklist', () {
      expect(md([opening, 'Checklist for the trip is done.']), isNot(contains('- [ ]')));
    });

    test('draws a divider behind a blank line', () {
      // Straight under text, `---` would turn that text into a heading.
      expect(md([opening, 'Divider.', 'After the break.']), '$opening\n\n---\n\nAfter the break.');
    });

    test('bolds between "bold" and "end bold", even across the pauses Whisper writes as full stops', () {
      expect(md(['$opening The deadline is bold Friday end bold.']), contains('The deadline is **Friday**.'));
      expect(md([opening, 'The deadline is bold.', 'Friday.', 'End bold.']), contains('The deadline is **Friday**.'));
    });

    test('italicises between "italic" and "end italic"', () {
      expect(md(['$opening Read italic Klara and the Sun end italic next.']), contains('_Klara and the Sun_ next'));
    });

    // What base.en writes for "end" on most voices: it sounds the same as "and".
    test('closes on "and bold" when Whisper marked a pause after the opening cue', () {
      expect(md([opening, 'Italics, maybe, and italics.']), contains('_maybe_.'));
      expect(md([opening, 'Bold. This really matters and bold.']), contains('**This really matters**.'));
    });

    test('closes on "and bold" that ends the sentence, the way Whisper writes "end bold" said plainly', () {
      expect(md(['$opening The deadline is bold Friday at noon and bold.']), contains('The deadline is **Friday at noon**.'));
      expect(md([opening, 'The deadline is italics next Friday and italics.']), contains('The deadline is _next Friday_.'));
    });

    test('does NOT close on "and bold" with no pause after the opening word', () {
      expect(md(['$opening It was bold thinking and bold action.']), isNot(contains('**')));
      expect(md(['$opening It was bold, brash thinking.']), isNot(contains('**')));
    });

    test('does NOT bold "bold" without "end bold"', () {
      expect(md(['$opening That was a bold move.']), isNot(contains('**')));
    });

    test('keeps a sentence that starts with bolded words separate from the one before', () {
      expect(md([opening, 'Heading, plan.', 'Bold Friday end bold is the day.']), contains('**Friday** is the day.'));
    });
  });

  group('a cue said as its own sentence', () {
    const opening = 'This opening sentence is long enough not to become a title.';

    // How people actually dictate a command: word, pause, content. Whisper writes the pause as a full stop, and
    // before this rule the note got the literal word "Heading."
    test('applies to the sentence after it', () {
      expect(md([opening, 'Heading.', 'Next steps.']), '$opening\n\n## Next steps');
      expect(md([opening, 'Bullet point.', 'Book flights.']), '$opening\n\n- Book flights');
      expect(md([opening, 'Quote.', 'Stay hungry.']), '$opening\n\n> Stay hungry.');
      expect(md([opening, 'To do.', 'Call mom.']), '$opening\n\n- [ ] Call mom');
      expect(md([opening, 'Number one.', 'Wake up.']), '$opening\n\n1. Wake up');
    });

    test('carries across a long pause into the next paragraph', () {
      const segments = [
        Segment(text: opening, startMs: 0, endMs: 1000),
        Segment(text: 'Heading.', startMs: 1200, endMs: 1800),
        Segment(text: 'After a long think.', startMs: 5000, endMs: 6000),
      ];
      expect(renderNote(segments).markdown, '$opening\n\n## After a long think');
    });

    test('makes a spoken title from "Title." then the words', () {
      expect(md(['Title.', 'Launch retro.', 'It went well.']), '# Launch retro\n\nIt went well.');
    });

    // The guard against prompt leakage: Whisper is prompted with the cue words, and a prompted model can echo one on
    // a quiet window. With nothing after it, the echo never reaches the note.
    test('renders nothing for a cue with nothing after it', () {
      expect(md([opening, 'Bullet point.']), opening);
      expect(md(['Heading.']), '');
    });
  });

  group('lists said the way people say them', () {
    // Matt's first real list on the Fold, 2026-09-13, as Whisper wrote it.
    const matt = [
      'Hey, this is me trying out the new app.',
      "I'd like you to add a list below.",
      'List item is weed.',
      "List item is Culver's onion ring.",
      "The next list item is Culver's cement mixer ice cream.",
      'And lastly, the final item that we need on our list is a gallon of black coffee.',
      'If you don’t order it in the head home and they will have a limited end.',
    ];

    test('makes a list of "list item is", "the next list item is" and "the final item … is"', () {
      expect(
        md(matt),
        [
          "Hey, this is me trying out the new app. I'd like you to add a list below.",
          '',
          '- Weed',
          "- Culver's onion ring",
          "- Culver's cement mixer ice cream",
          '- A gallon of black coffee',
          '',
          'If you don’t order it in the head home and they will have a limited end.',
        ].join('\n'),
      );
    });

    test('keeps a list numbered when it started with "number one"', () {
      final numbered = [...matt];
      numbered[2] = 'Number one, list item is weed.';
      numbered[3] = "Number two, list item is Culver's onion ring.";
      expect(md(numbered), contains("1. Weed\n2. Culver's onion ring\n3. Culver's cement mixer ice cream\n4. A gallon of black coffee"));
    });

    test('keeps the list whole across a long pause between items', () {
      const segments = [
        Segment(text: 'Here is my shopping list.', startMs: 0, endMs: 1500),
        Segment(text: 'The first item is oat milk.', startMs: 1800, endMs: 3000),
        Segment(text: 'Another item is eggs.', startMs: 6500, endMs: 7500),
      ];
      expect(renderNote(segments).markdown, contains('- Oat milk\n- Eggs'));
    });

    test('takes short items after a list is announced', () {
      final markdown = md([opening(), 'Here is my packing list.', 'Sunscreen.', 'Two towels.', 'The good speaker.', 'We leave at noon on Saturday if the weather holds.']);
      expect(markdown, contains('- Sunscreen\n- Two towels\n- The good speaker\n\nWe leave at noon'));
    });

    test('makes a numbered list when one is asked for', () {
      expect(md([opening(), 'Make a numbered list.', 'Preheat the oven.', 'Mix the batter.']), contains('1. Preheat the oven\n2. Mix the batter'));
    });

    test('does NOT make list items of ordinary sentences', () {
      final prose = md([opening(), 'The thing is, I am tired.', 'The item is broken again.', 'Next week is busy.', 'One is enough for now.']);
      expect(prose, isNot(matches(RegExp(r'^- ', multiLine: true))));
    });

    test('does NOT take a short reply after a cue as an item', () {
      expect(md([opening(), 'Bullet point, eggs.', 'Thanks.']), '${opening()}\n\n- Eggs\n\nThanks.');
    });

    test('does NOT take long sentences as items just because a list was mentioned', () {
      final markdown = md([opening(), 'I made a list yesterday.', 'It had everything we talked about on the phone last night.']);
      expect(markdown, isNot(matches(RegExp(r'^- ', multiLine: true))));
    });
  });

  group('"the next item is" with the item in the next phrase', () {
    test('takes the next phrase as the item when the phrase naming it stops short', () {
      final markdown = md([opening(), 'Here is my travel list.', 'The first item is the Grand Canyon.', 'The next item is.', 'Paris.', 'The next item is. Greece.']);
      expect(markdown, contains('- The Grand Canyon\n- Paris\n- Greece'));
    });

    test('keeps an item phrase with no item and nothing after it as words', () {
      expect(md([opening(), 'The next item is.']), '${opening()} The next item is.');
    });

    test('reads Whisper’s own inline numbering as a numbered list', () {
      // Matt's Fold, 2026-09-13: Whisper wrote the spoken "the next item is" as numbers.
      final markdown = md([opening(), '1. The Grand Canyon 2. Spain 3. The next item is', 'Paris.', 'The next item is. Greece.']);
      expect(markdown, contains('1. The Grand Canyon\n2. Spain\n3. Paris\n4. Greece'));
    });

    test('waits for the item after "number three, the next item is", keeping the count', () {
      // As Matt's Fold rendered it before the fix: "3. The next item is" / "Paris." / "The next item is. Greece."
      final segments = [
        Segment(text: opening(), startMs: 0, endMs: 2000),
        const Segment(text: 'Number one, the Grand Canyon.', startMs: 2300, endMs: 4000),
        const Segment(text: 'Number two, Spain.', startMs: 4300, endMs: 5500),
        const Segment(text: 'Number three, the next item is', startMs: 5800, endMs: 7200),
        const Segment(text: 'Paris.', startMs: 10000, endMs: 10800),
        const Segment(text: 'The next item is. Greece.', startMs: 14000, endMs: 16000),
      ];
      expect(renderNote(segments).markdown, contains('1. The Grand Canyon\n2. Spain\n3. Paris\n4. Greece'));
    });

    test('does NOT split ordinary numbers in a sentence', () {
      final prose = md([opening(), 'We need 2. Maybe 3 if Sam comes.', 'I was born in 1990. It was cold.']);
      expect(prose, isNot(matches(RegExp(r'^\d+\. ', multiLine: true))));
    });
  });

  group('a plugin formatting said aloud', () {
    test('wraps "spoiler … end spoiler" in the plugin\'s delimiter, and leaves bold as it was', () {
      setSpokenFormats(const [SpokenFormat(word: 'spoiler', delimiter: '||')]);
      try {
        expect(spokenInlineMarkup('The winner is spoiler. The butler. End spoiler. And bold. Friday. End bold.'), 'The winner is ||The butler||. And **Friday**.');
        expect(spokenInlineMarkup('No spoilers here, spoiler alert.'), 'No spoilers here, spoiler alert.');
      } finally {
        setSpokenFormats(const []);
      }
    });
  });

  group('spoken marks closed with "and"', () {
    test('closes a common mark mid-sentence around three words or more, and leaves a short phrase alone', () {
      expect(spokenInlineMarkup('the hot tub is italic strictly off limits and italic after ten'), 'the hot tub is _strictly off limits_ after ten');
      expect(spokenInlineMarkup('it was bold thinking and bold action'), 'it was bold thinking and bold action');
    });
  });

  group('spoken marks heard loosely', () {
    test('finds a mark inside words that start another cue, and takes any spelling of the same cue to close it', () {
      const formats = [
        SpokenFormat(word: 'spoiler', delimiter: '||'),
        SpokenFormat(word: 'aside', delimiter: '%%'),
        SpokenFormat(word: 'unsure', delimiter: '??'),
        SpokenFormat(word: 'redact', delimiter: '@@'),
      ];
      expect(spokenInlineMarkup('The gate code is spoiler four four one seven end spoiler.', formats), 'The gate code is ||four four one seven||.');
      expect(spokenInlineMarkup('A side I still prefer the other place end aside.', formats), '%%I still prefer the other place%%.');
      expect(spokenInlineMarkup('The stove is ensure gas end ensure.', formats), 'The stove is ??gas??.');
      // "Redact" is heard as "redacted" as often as not, and either end can be either.
      expect(spokenInlineMarkup('The name on the lease is redacted Sam Ortiz end redact.', formats), 'The name on the lease is @@Sam Ortiz@@.');
      expect(spokenInlineMarkup('The file was redacted before it went out.', formats), 'The file was redacted before it went out.');
      expect(spokenInlineMarkup('bold one end italic', formats), 'bold one end italic');
    });

    test('says heat as "heated … end heated", so a cooking note about heat is left as words', () {
      const formats = [SpokenFormat(word: 'heated', delimiter: '🔥🔥')];
      expect(spokenInlineMarkup('The pan was heated far too hot end heated by noon.', formats), 'The pan was 🔥🔥far too hot🔥🔥 by noon.');
      expect(spokenInlineMarkup('Heat the oven and heat the pan.', formats), 'Heat the oven and heat the pan.');
    });
  });

  group('every mark has words', () {
    /// A note opened with a sentence, so the line under test is never taken for the title.
    String said(List<String> texts) => md(['We met on the porch today.', ...texts]).replaceFirst(RegExp(r'^# We met on the porch today\n\n'), '');

    test('says the inline marks', () {
      expect(said(['This is bold italic really now end bold italic, honestly.']), 'This is ***really now***, honestly.');
      expect(said(['The meeting is on the 2 superscript nd end superscript of June.']), 'The meeting is on the 2^nd^ of June.');
      expect(said(['Water is H subscript two end subscript O.']), 'Water is H~2~O.');
      expect(said(['The rule holds when maths x squared plus two y end maths is small.']), r'The rule holds when $x^2 + 2 y$ is small.');
      expect(said(['We shipped it emoji party popper.']), 'We shipped it :tada:.');
      expect(said(['Thumbs up from Sam, emoji thumbs up.']), 'Thumbs up from Sam, :+1:.');
    });

    test('says links to pages and to lines', () {
      expect(said(['The site is link Ghost.md to attack dot fm slash glyph end link for now.']), 'The site is [Ghost.md](https://attack.fm/glyph) for now.');
      expect(said(['Read link attack.fm end link later.']), 'Read <https://attack.fm> later.');
      expect(said(['The page waits on item link ship page end link.']), 'The page waits on [[#^ship-page]].');
    });

    test('names a line at its end, once per name', () {
      expect(
        said(['Check box: ship the pricing page anchor ship page end anchor.', 'Check box: ship it again anchor ship page end anchor.']),
        '- [ ] Ship the pricing page ^ship-page\n- [ ] Ship it again ^ship-page-2',
      );
    });

    test('writes a done to-do, a definition, a footnote and a note on a mark', () {
      expect(said(['Checked box: call Sam.']), '- [ ] Call Sam');
      expect(said(['Ticked box: call Sam.']), '- [x] Call Sam');
      expect(said(['Done task, book the cabin.']), '- [x] Book the cabin');
      expect(said(['Define deposit as what you pay up front.']), 'Deposit\n: What you pay up front.');
      expect(said(['The deposit is four hundred footnote Sam said so end footnote.', 'That is fine.']), 'The deposit is four hundred[^1]. That is fine.\n\n[^1]: Sam said so.');
      setSpokenFormats(const [SpokenFormat(word: 'unsure', delimiter: '??')]);
      try {
        expect(said(['The price is unsure four hundred end unsure, note Sam said so, end note.']), 'The price is ??four hundred??(Sam said so).');
      } finally {
        setSpokenFormats(const []);
      }
    });

    test('puts the one bookmark on the last line it was said on', () {
      expect(
        said(['The deposit is four hundred, bookmark this.', 'New paragraph. The key is under the mat, bookmark here.']),
        'The deposit is four hundred.\n\nThe key is under the mat. §§',
      );
    });

    test('breaks a line and keeps a block of code whole across pauses', () {
      expect(said(['Roses are red. New line. Violets are blue.']), 'Roses are red.  \nViolets are blue.');
      final code = renderNote(const [
        Segment(text: 'We met on the porch today.', startMs: 0, endMs: 900),
        Segment(text: 'Code block in bash.', startMs: 1000, endMs: 1900),
        Segment(text: 'npm run build.', startMs: 5000, endMs: 5900),
        Segment(text: 'End code block. Then we left.', startMs: 6000, endMs: 6900),
      ]).markdown;
      expect(code, '# We met on the porch today\n\n```bash\nnpm run build\n```\n\nThen we left.');
    });

    test('leaves the same words alone in ordinary sentences', () {
      for (final sentence in [
        'They launched a new line of shoes.',
        'The link between them is weak.',
        'I sent Sam an emoji to say thanks.',
        'Define your goals as early as you can.',
        'I will bookmark this page later tonight.',
        'The code block party was loud.',
        'I checked the oven twice.',
        'Done, that was easy.',
        'The footnote was long.',
        'Maths was my best subject.',
        'The anchor held all night.',
        'Superscripts are small.',
      ]) {
        expect(said([sentence]), sentence, reason: sentence);
      }
    });
  });

  group('spoken addresses and names', () {
    test('reads an address, and nothing else', () {
      expect(spokenAddress('attack dot fm slash glyph'), 'https://attack.fm/glyph');
      expect(spokenAddress('https colon slash slash example dot com'), 'https://example.com');
      expect(spokenAddress('Ghost to attack dot fm'), isNull);
      expect(spokenAddress('the weekend'), isNull);
    });

    test('makes a line name of what was said', () {
      expect(spokenSlug('Ship Page'), 'ship-page');
      expect(spokenSlug('  the 2nd, draft '), 'the-2nd-draft');
    });
  });

  group('a to-do’s fields said at its end', () {
    /// Thursday 1 October 2026, the day the fields count from (spoken/fields.dart, docs/DESIGN.md §158).
    const on = RenderOptions(today: '2026-10-01');
    const onUntitled = RenderOptions(today: '2026-10-01', titled: false);

    test('writes a due day, a priority and a person as the item’s fields', () {
      expect(md(['I need to call the plumber due Friday.'], '', on), '- [ ] Call the plumber 📅 2026-10-02');
      expect(md(['Check box, fix the login loop, due tomorrow, high priority.'], '', on), '- [ ] Fix the login loop ⏫ 📅 2026-10-02');
      expect(md(['Bullet point, renew the passport, urgent, assigned to Matt.'], '', on), '- Renew the passport @Matt ⏫');
      expect(md(['To do: book the venue for Sam, due the third of October.'], '', on), '- [ ] Book the venue @Sam 📅 2026-10-03');
    });

    test('takes "Due next week." said a breath after an item as that item’s', () {
      expect(md(['I need to send the invoice.', 'Due next week.'], '', on), '- [ ] Send the invoice 📅 2026-10-05');
      expect(md(['Remember to back up the laptop.', 'High priority.'], '', on), '- [ ] Back up the laptop ⏫');
    });

    test('leaves prose, a "for" that is not who, and a lone cue as words', () {
      expect(md(['The rent is due on Friday.'], '', onUntitled), 'The rent is due on Friday.');
      expect(md(['I need to buy a present for Sam.'], '', on), '- [ ] Buy a present for Sam');
      expect(md(['I need to call the bank.', 'For Sam.'], '', on), '- [ ] Call the bank\n\nFor Sam.');
      expect(md(['Due Friday.', 'We should talk.'], '', onUntitled), 'Due Friday. We should talk.');
    });
  });

  group('a meeting’s transcript', () {
    /// The cases the Rust twin reads too (the web's src-tauri/src/transcript.rs), so the two cannot drift: the web's
    /// `src/app/capture/paragraphs.fixture.json`, copied.
    final fixture = (jsonDecode(File('test/capture/fixtures/paragraphs.fixture.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

    test('cuts the paragraphs as the fixture says, in every case the fixture has', () {
      expect(fixture.length, greaterThanOrEqualTo(4));
      for (final row in fixture) {
        final segments = [
          for (final segment in (row['segments'] as List).cast<Map<String, dynamic>>())
            Segment(text: segment['text'] as String, startMs: (segment['startMs'] as num).toInt(), endMs: (segment['endMs'] as num).toInt()),
        ];
        expect(toParagraphs(segments), row['paragraphs'], reason: row['name'] as String);
      }
    });

    test('is the paragraphs under their heading, no cues and no title, with the phrase still being guessed on the end', () {
      final segments = spoken(['we settled the date.', 'Sam owns the press list.']);
      expect(renderTranscript(segments), '## Transcript\n\nWe settled the date. Sam owns the press list.');
      expect(renderTranscript(segments, ' and the '), '## Transcript\n\nWe settled the date. Sam owns the press list. and the');
      expect(renderTranscript([], 'first words'), '## Transcript\n\nfirst words');
      expect(renderTranscript([]), '## Transcript\n\n');
      // A meeting is recorded, not read: a heading cue is words.
      expect(renderTranscript(spoken(['heading the launch'])), '## Transcript\n\nHeading the launch');
    });

    test('is found in a body by its heading, put in place of the one there or on the end, and taken off again', () {
      const transcript = '## Transcript\n\nWe settled the date.';
      const titled = '# Meeting, 26 Sep 14:05\n';
      expect(transcriptOf(titled), isNull);
      expect(withTranscript(titled, transcript), '# Meeting, 26 Sep 14:05\n\n$transcript');
      expect(withTranscript('', transcript), transcript);
      final body = withTranscript('# Meeting, 26 Sep 14:05\n\n## Summary\nOne line.\n\n- A point.\n', transcript);
      expect(transcriptOf(body), transcript);
      expect(withoutTranscript(body), '# Meeting, 26 Sep 14:05\n\n## Summary\nOne line.\n\n- A point.');
      // Replaced whole, whatever stands above it, and the trailing newline the editor's landing leaves is not an edit.
      expect(
        withTranscript('$body\n', '## Transcript\n\nMore was said.'),
        '# Meeting, 26 Sep 14:05\n\n## Summary\nOne line.\n\n- A point.\n\n## Transcript\n\nMore was said.',
      );
      // Only the heading on a line of its own: a line that mentions it is words.
      expect(transcriptOf('# Notes\n\nSee ## Transcript below.'), isNull);
      expect(withoutTranscript('# Notes\n\nWords.\n'), '# Notes\n\nWords.');
    });
  });
}
