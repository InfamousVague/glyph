/// What the Academy says aloud (Matt, 2026-10-28: "Add the voiceover to the academy sections and spice up the academy
/// with more colors and iconography"): a welcome as it opens on its chapters, a short hello for each chapter as it is
/// begun, and each lesson's teaching as the lesson opens.
///
/// The walkthrough's voice made the Academy's (lib/guide/narration.dart, lib/guide/narrator.dart): the same Eleven v4,
/// the same Jessica, made once at build time by tool/academy_voice.py and shipped in assets/academy/, so a person
/// hears it with no key and no network. What differs is that these words are not the page's: a lesson's teaching on
/// screen is full of the marks themselves (`**`, `- [ ]`, `>|`), which a voice cannot say, so each one here is that
/// teaching written to be heard ("two stars on each side" for `**`), a sentence or two, and the page keeps its own
/// words to read. A lesson for a plugin's mark is only offered while the mark is on, but its voice ships all the same:
/// switching the plugin on needs nothing fetched.
///
/// assets/academy/narration.json says which words made each file, and test/academy/voice_test.dart fails when an entry
/// here changes and its file is not made again, as the walkthrough's test does.
///
/// Keep each entry on one line, in single quotes, with typographic quotes and apostrophes inside (“ ” ’): that is
/// what the tool reads.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The short name each chapter's hello is kept under, `chapter-<name>`.
const Map<String, String> chapterVoiceNames = {
  'Markdown basics': 'basics',
  'More Markdown': 'more',
  'Lines that do more': 'lines',
  'Links and places': 'links',
  'Boards and to-dos': 'boards',
  'Tickets and queries': 'tickets',
  'Marks and effects': 'marks',
};

/// Every clip's words, by the name its file has: `welcome`, `chapter-<name>` ([chapterVoiceNames]), and each
/// lesson's id.
const Map<String, String> academyVoice = {
  'welcome': 'Welcome to the Ghost Academy. Each lesson is one mark: I’ll tell you what it does, then you write your own and watch the note draw it. Pick a chapter, or carry on where you left off.',
  // ---- Chapters ---------------------------------------------------------------------------------------------------
  'chapter-basics': 'Chapter one, Markdown basics. Headings, bold, lists, links and to-dos: the marks every Markdown app reads the same way.',
  'chapter-more': 'Chapter two, More Markdown. Tables, pictures, footnotes, maths, callouts and diagrams, for when a note needs a little more.',
  'chapter-lines': 'Chapter three, Lines that do more. Tags, choices, counters, sums and comments: lines whose words the note puts to work.',
  'chapter-links': 'Chapter four, Links and places. Linking to another note, leaving yourself a bookmark, and putting a place on the map.',
  'chapter-boards': 'Chapter five, Boards and to-dos. Due dates and people on a to-do, names for items, and boards built out of them.',
  'chapter-tickets': 'Chapter six, Tickets and queries. Notes as tickets, and queries that find, count and lay out what matches across all your notes.',
  'chapter-marks': 'Chapter seven, Marks and effects. Highlights, spoilers, asides, and five little effects, from the Marks plugin.',
  // ---- Markdown basics --------------------------------------------------------------------------------------------
  'title': 'A note usually starts with its name. Type one hash and a space, then the words, and that line becomes the note’s title.',
  'heading': 'Headings break a long note into parts. Two hashes and a space make a heading, and three make a smaller one inside it.',
  'bold': 'Put two stars on each side of some words to make them bold. The stars tuck themselves away once the line is written.',
  'italic': 'One underscore on each side leans the words over. It’s quieter than bold: an aside, a name, a word said with a shrug.',
  'both': 'Three stars on each side make words bold and italic at once. Save it for the one thing that mustn’t be missed.',
  'struck': 'Two tildes, the little squiggles, on each side cross the words out. Handy for a plan that changed, when you still want to see what it was.',
  'code': 'A backtick on each side sets words in a typewriter face, exactly as you typed them: a command, a file name, a code to read out.',
  'link': 'For a link, put the words people read in square brackets, then the address in round brackets right after. The note shows the words, not the address.',
  'list': 'Start a line with a dash and a space for a list. Press Enter, and the next line is a bullet too.',
  'number': 'When the order matters, start each line with a number, a dot and a space: steps to follow, one after another.',
  'todo': 'A to-do is a dash, a space, then square brackets with a space between them. Tap the box in a note to tick it off, or type an x between the brackets.',
  'quote': 'Start a line with a greater-than sign and a space to set it apart: someone else’s words, or something you want to stand out.',
  'rule': 'Three dashes on a line of their own draw a line across the note. One thing ends, and another begins.',
  'fence': 'Three backticks above and below some lines keep every one exactly as typed. Name the language after the first three, and the code is coloured too.',
  // ---- More Markdown ----------------------------------------------------------------------------------------------
  'table': 'A table is cells with upright bars between them, and a row of dashes under the first row. In a note it’s drawn as a real table; tap it to change it.',
  'picture': 'A picture is an exclamation mark, what it shows in square brackets, and where it lives in round brackets. Mostly you won’t type it: paste a picture, and the line is written for you.',
  'video': 'A video is a picture of the film’s first frame, linked to the film itself. You won’t type this one: adding a video writes the line for you.',
  'raised': 'A caret, the little upward arrow, on each side lifts part of a word above the line: the second of June, or a power in a sum.',
  'lowered': 'One tilde on each side drops part of a word below the line, the way you write water: H, two, O.',
  'footnote': 'For a footnote, put a caret and a name in square brackets after the words, then a line starting with the same mark and a colon says what it is. Tap the raised mark to read the small print.',
  'definition': 'Write a word on one line, and its meaning on the next, starting with a colon and a space. That’s how a glossary is written.',
  'maths': 'A dollar sign on each side makes a formula, drawn properly: powers, fractions, Greek letters. Two on each side, on a line of their own, set it in the middle of the page.',
  'emoji': 'Put a name between two colons and it becomes its emoji. Tada, between colons, is a party popper.',
  'callout': 'Start a quote with an exclamation mark and the word note in square brackets, and it becomes a box of its own. Tip, important, warning and caution work the same way.',
  'diagram': 'A block of code marked mermaid is drawn as the diagram it describes: boxes, and the arrows between them. Tap a drawn diagram to change its words.',
  // ---- Lines that do more -----------------------------------------------------------------------------------------
  'tag': 'A hash right against a word, with no space, tags the line. A hash and a space at the start of a line is a heading instead.',
  'choice': 'Round brackets on a list make a choice. Put an x in the one that’s picked; tap another, and it’s picked instead.',
  'counter': 'A count and a goal in square brackets, like three slash eight, makes a counter. Tap it to add one, and hold it to take one away.',
  'sum': 'Start a line with an equals sign and a space, and its answer shows after it. The answer isn’t written into the note, so it keeps up when a number changes.',
  'blank': 'Curly brackets with a question mark inside ask a question right where its answer belongs. Totals and dates are worked out at once; anything else waits for Fill, and the AI answers.',
  'hiddenLine': 'Start a quote with a bar right after the greater-than sign, and the line turns to smoke until your cursor is in it. Perfect for a riddle’s answer.',
  'progress': 'Nothing new to type here: just a heading with to-dos under it. The heading counts them, one of two, and tells you when they’re all done.',
  'comment': 'A comment lives in the note itself: a small mark after the words it’s about, and the thread in a comments block at the end. Choose Comment from the menu, and both are written for you.',
  // ---- Links and places -------------------------------------------------------------------------------------------
  'wiki': 'Two square brackets on each side of a note’s name link to that note. If there’s no note by that name yet, the link is dashed, and a tap makes it.',
  'bookmark': 'Two section signs at the end of a line are the note’s bookmark, and the note opens right there. The bookmark button moves it to the line you’re on.',
  'place': 'A link to geo, a colon, and two numbers, on its own line, is a place, with its map drawn under it. The plus beside an empty line can write one for where you are.',
  // ---- Boards and to-dos ------------------------------------------------------------------------------------------
  'fields': 'A to-do can say when it’s due, how much it matters, and who it’s for: a calendar and a date, an up arrow for high priority, and an at sign before a name. Each becomes a chip you can tap to change.',
  'anchor': 'A space, a caret and a name at the very end of a list item give it a name, so a board or a sentence can point at it.',
  'itemRef': 'To point at a named item from anywhere in the note, put a hash, a caret and its name inside double square brackets. A tap jumps to its line.',
  'board': 'A block marked board lays named items out as columns. Each line is a column: its name, a colon, and the items in it. Drag a card to move it.',
  'boardHeight': 'A board is as tall as its longest column. Drag the line under it to set a height, and the columns scroll inside. A double tap on the line takes it off again.',
  // ---- Tickets and queries ----------------------------------------------------------------------------------------
  'ticket': 'A note whose front matter says type: ticket is a ticket. Its status, who it’s for, its priority and its due day sit underneath, drawn as a card you tap to change.',
  'notebookKey': 'Give a notebook a key in its front matter, and it numbers the tickets made in it: a key of A B C gives A B C one, then A B C two, and on.',
  'query': 'A fence called query lists what matches across every note. Say where from, what has to be true, and how to show it, one line each, and it keeps up as your notes change.',
  'queryWhere': 'Where keeps only what’s true: not done yet, due before today, or for Sam, joined with and, or or. Sort puts what’s left in order.',
  'queryShow': 'Show draws the same answer another way: as a table, a list, a board, a calendar month, a timeline, or just a count.',
  'queryGroup': 'Group gives each value of a field its own heading, or its own lane on a board. Total adds a number up, under each group and at the end.',
  // ---- Marks and effects ------------------------------------------------------------------------------------------
  'spoiler': 'Two bars on each side turn the words to smoke until your cursor is in them: the end of a film, or a surprise.',
  'highlight': 'Two equals signs on each side put a wash of colour behind the words, for the line you’ll want to find again.',
  'tint': 'Put a colour’s name in round brackets right after a highlight to change its colour: blue, red, amber, green, teal, purple or gray.',
  'aside': 'Two percent signs on each side make a note to yourself inside the note: smaller, quieter, and leaning.',
  'unsure': 'Two question marks on each side draw a dotted line under a fact you want to check later.',
  'markNote': 'Words in round brackets right after a mark are a note on it, and a tap on the mark shows them. On something you’re unsure of, they say why.',
  'redact': 'Two at signs on each side put a solid bar of ink over the words. It lifts while your cursor is in them, so you can still edit them.',
  'shout': 'Two carets on each side set the words in spaced small capitals: emphasis that isn’t bold.',
  'added': 'Two plus signs on each side underline what was added. It’s the partner of struck through, for what went.',
  'heat': 'Two flames on each side make the words bold, with the air above them wavering in the heat.',
  'frost': 'Two snowflakes on each side turn the words cold, with a frost creeping over their edges.',
  'wave': 'Two waves on each side set the words bobbing along the line, a ripple passing through them.',
  'shimmer': 'Two sparkles on each side send a glint across the words every few seconds.',
  'haunt': 'Two ghosts on each side make the words fade almost away, and slowly back, like something passing.',
};

/// Where the clip called [name] is in the app's assets.
String academyVoiceAsset(String name) => 'assets/academy/$name.mp3';

/// The name of [chapter]'s hello.
String chapterVoice(String chapter) => 'chapter-${chapterVoiceNames[chapter]!}';

/// What tool/academy_voice.py wrote of each clip it made: which words, model and voice, and how long it runs, which
/// says when a lesson's teaching can follow its chapter's hello.
const String academyVoiceManifest = 'assets/academy/narration.json';

/// How long each clip runs, once [academyVoiceLengths] has read the manifest: empty until then, and a lesson begun
/// before it has is said without its chapter's hello.
Map<String, Duration> academyVoiceLengthsRead = const {};

Future<Map<String, Duration>>? _reading;

/// Reads how long each clip runs from [academyVoiceManifest], once for the app.
Future<Map<String, Duration>> academyVoiceLengths() => _reading ??= () async {
  try {
    final manifest = jsonDecode(await rootBundle.loadString(academyVoiceManifest)) as Map<String, dynamic>;
    final files = (manifest['files'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();
    academyVoiceLengthsRead = {for (final MapEntry(:key, :value) in files.entries) key: Duration(milliseconds: ((value['seconds'] as num) * 1000).round())};
  } catch (_) {
    // No manifest: each lesson is said alone.
  }
  return academyVoiceLengthsRead;
}();
