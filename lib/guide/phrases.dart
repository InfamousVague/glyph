/// What to SAY to get Markdown: the spoken examples behind what the guide promises about talking. A port of
/// `src/app/guide/phrases.ts` (`PHRASES`, `CUE_ALONE`, `renderExample`, `COMMAND`, `NOTE_COMMAND`, `ASK`).
///
/// The guide once drew these as a page of its own; that page went on 2026-10-02 and the promises are the cheat
/// sheet's now, the "say" line beside each mark (marks.dart). The examples stay as what test/guide/guide_test.dart
/// runs through the recorder's own rules ([renderNote]), so a rule that regresses fails a test instead of the sheet
/// quietly teaching something that no longer works. Only cues lib/capture/markdown.dart implements belong here.
///
/// What differs: the three constants at the foot are records where the page has `as const` objects.
library;

import '../capture/markdown.dart';

/// One spoken example (`Example`).
class Example {
  const Example({required this.say, required this.expect});

  /// What to say, one phrase per pause, the way Whisper commits it.
  final List<String> say;

  /// A marker the rendered Markdown must contain.
  final String expect;
}

/// A cue, the mark it writes and its example (`PhraseGroup`).
class PhraseGroup {
  const PhraseGroup({required this.title, required this.symbol, required this.lead, required this.cues, required this.example});
  final String title;

  /// The mark the cue writes, as the guide shows it beside the words: "#", "- [ ]". Empty for a blank line.
  final String symbol;

  /// One line on when to use it.
  final String lead;

  /// The words that trigger it, as a person would read them.
  final List<String> cues;
  final Example example;
}

/// `PHRASES`.
const List<PhraseGroup> phrases = <PhraseGroup>[
  PhraseGroup(
    title: 'Name the note',
    symbol: '#',
    lead: 'Say it first. A short first sentence becomes the title anyway.',
    cues: <String>['“Title”', '“Call this note”'],
    example: Example(say: <String>['Title: weekend trip.', 'We leave on Friday after work.'], expect: '# Weekend trip'),
  ),
  PhraseGroup(
    title: 'Start a section',
    symbol: '##',
    lead: 'Say it at the start of a sentence, then pause.',
    cues: <String>['“Heading”', '“New section”'],
    example: Example(say: <String>['Notes from the call with Sam about the house.', 'Heading: the budget.', 'We agreed on four thousand.'], expect: '## The budget'),
  ),
  PhraseGroup(
    title: 'New paragraph',
    symbol: '',
    lead: 'Or just stop talking for two seconds.',
    cues: <String>['“New paragraph”'],
    example: Example(say: <String>['The kitchen needs work before we list it.', 'New paragraph.', 'The garden is fine as it is.'], expect: 'list it.\n\nThe garden'),
  ),
  PhraseGroup(
    title: 'Bullet points',
    symbol: '-',
    lead: 'One point per sentence.',
    cues: <String>['“Bullet point”', '“Next point”'],
    example: Example(say: <String>['Things to check at the cabin.', 'Bullet point: the heating.', 'Next point: the water pressure.'], expect: '- The heating'),
  ),
  PhraseGroup(
    title: 'A list in one breath',
    symbol: '-',
    lead: 'Three or more short things after a word like need, buy or bring.',
    cues: <String>['“I need eggs, milk and bread”'],
    example: Example(say: <String>['For the drive we need snacks, water, a charger and the good playlist.'], expect: 'For the drive we need:\n- snacks'),
  ),
  PhraseGroup(
    title: 'Numbers, out loud',
    symbol: '1.',
    lead: 'Use it when the order matters.',
    cues: <String>['“Number one”', '“Number two”'],
    example: Example(say: <String>['Packing order.', 'Number one: passports.', 'Number two: chargers.'], expect: '2. Chargers'),
  ),
  PhraseGroup(
    title: 'Steps in order',
    symbol: '1.',
    lead: 'Start with “first”. Then say second, then, or finally.',
    cues: <String>['“First”', '“Second”', '“Finally”'],
    example: Example(say: <String>['How to reset the router.', 'First, unplug it.', 'Second, wait thirty seconds.', 'Finally, plug it back in.'], expect: '3. Plug it back in'),
  ),
  PhraseGroup(
    title: 'To-dos',
    symbol: '- [ ]',
    lead: 'Say it like you’d say it to yourself.',
    cues: <String>['“Remember to”', '“I need to”', '“Check box”'],
    example: Example(say: <String>['Before Saturday.', 'Remember to book the cabin.', 'Check box: call the plumber.'], expect: '- [ ] Call the plumber'),
  ),
  PhraseGroup(
    title: 'Quote someone',
    symbol: '>',
    lead: 'Keeps their words apart from yours.',
    cues: <String>['“Quote”'],
    example: Example(say: <String>['What the landlord said at the end.', 'Quote: the deposit comes back in full.'], expect: '> The deposit comes back in full.'),
  ),
  PhraseGroup(
    title: 'Make it stand out',
    symbol: '**',
    lead: 'Pause after the word so it gets a colon.',
    cues: <String>['“Important”', '“Key point”'],
    example: Example(say: <String>['Thoughts on the offer.', 'Important: they need an answer by Monday.'], expect: '**Important:**'),
  ),
  PhraseGroup(
    title: 'Bold and italic, anywhere',
    symbol: '** _',
    lead: 'Say where it starts and where it ends, mid-sentence if you like.',
    cues: <String>['“Bold” then “end bold”', '“Italic” then “end italic”'],
    example: Example(say: <String>['The deadline is bold Friday at noon end bold, not Monday.'], expect: '**Friday at noon**'),
  ),
  PhraseGroup(
    title: 'A smaller section',
    symbol: '###',
    lead: 'A section inside a section.',
    cues: <String>['“Subheading”'],
    example: Example(say: <String>['Heading: packing.', 'Subheading: the kitchen.', 'Pots and pans.'], expect: '### The kitchen'),
  ),
  PhraseGroup(
    title: 'A callout',
    symbol: '> [!NOTE]',
    lead: 'A boxed note. Say “tip”, “warning” or “important” before it for those.',
    cues: <String>['“Info box”', '“Callout”', '“Warning callout”'],
    example: Example(say: <String>['Before you arrive, please read this.', 'Info box: the gate sticks, so lift it first.'], expect: '> [!NOTE]\n> The gate sticks'),
  ),
  PhraseGroup(
    title: 'A hidden line',
    symbol: '>|',
    lead: 'Kept in smoke until it is tapped.',
    cues: <String>['“Hidden line”'],
    example: Example(say: <String>['The answer to the riddle from the party.', 'Hidden line: it was the butler.'], expect: '>| It was the butler.'),
  ),
  PhraseGroup(
    title: 'Choices',
    symbol: '- ( )',
    lead: 'Things to pick from; say “picked option” for the one you chose.',
    cues: <String>['“Option”', '“Picked option”'],
    example: Example(say: <String>['Where should we stay?', 'Option: tent.', 'Picked option: cabin.'], expect: '- (x) Cabin'),
  ),
  PhraseGroup(
    title: 'A sum',
    symbol: '=',
    lead: 'Say the numbers and plus, minus, times or divided by. The answer shows beside it.',
    cues: <String>['“Calculate”'],
    example: Example(say: <String>['The trip adds up like this.', 'Calculate: four hundred plus one hundred twenty.'], expect: '= 400 + 120'),
  ),
  PhraseGroup(
    title: 'Tags, counters and links',
    symbol: '# [ / ] [[ ]]',
    lead: 'Mid-sentence: “hashtag” and a word, “counter three of eight”, or “note link” and a note’s name, then “end link”.',
    cues: <String>['“Hashtag travel”', '“Counter zero of eight”', '“Note link … end link”'],
    example: Example(say: <String>['Daily goals below.', 'Bullet point: drink water, counter zero of eight hashtag health.'], expect: '- Drink water [0/8] #health'),
  ),
  PhraseGroup(
    title: 'Struck through and code',
    symbol: '~~ `',
    lead: 'Said like bold: where it starts and where it ends.',
    cues: <String>['“Strike” then “end strike”', '“Code” then “end code”'],
    example: Example(say: <String>['The meeting moved from strike Tuesday end strike to Wednesday.'], expect: '~~Tuesday~~'),
  ),
  PhraseGroup(
    title: 'A dividing line',
    symbol: '---',
    lead: 'Say it on its own, between two parts of a note.',
    cues: <String>['“Divider”', '“Horizontal line”'],
    example: Example(say: <String>['That covers the morning.', 'Divider.', 'The afternoon is free.'], expect: '\n---\n'),
  ),
];

/// A cue said on its own, "Bullet point." then a pause, applies to what comes next (`CUE_ALONE`).
const Example cueAlone = Example(say: <String>['Shopping.', 'Bullet point.', 'Oat milk.'], expect: '- Oat milk');

/// The same shape the capture tests use: a second per phrase with a breath between (`toSegments`).
List<Segment> _toSegments(List<String> say) {
  var at = 0;
  final segments = <Segment>[];
  for (final text in say) {
    segments.add(Segment(text: text, startMs: at, endMs: at + 1000));
    at += 1300;
  }
  return segments;
}

/// An example as the recorder would write it (`renderExample`).
String renderExample(Example example) => renderNote(_toSegments(example.say)).markdown;

/// What the habits page taught to say first, with or without "Hey Ghost" first (`COMMAND`): a command, which puts
/// words in a note by its name. test/guide/guide_test.dart holds it to the live reader and to the reader at Done.
const ({String say, String note, String words}) command = (say: 'Add bread to Groceries', note: 'Groceries', words: 'bread');

/// The same for a note whose title does not say it is a list (`NOTE_COMMAND`): "a note" said is the gate's evidence,
/// and the words follow a comma.
const ({String say, String note, String words}) noteCommand = (say: 'Add a note to Work, call Sam', note: 'Work', words: 'Call Sam.');

/// An ask, which runs the AI on the note whose mic it is said into (`ASK`).
const ({String say, String run}) ask = (say: 'Fix the spelling', run: 'fix');
