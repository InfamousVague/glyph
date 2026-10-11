/// What the recorder suggests saying: the spoken cues that shape a note, the routing commands, and the asks the AI
/// takes. A port of `src/app/capture/tips.ts`.
///
/// Two shapes. Before the first word, a card of them ([starters]): a couple of each kind, so the whole of what can
/// be said is on the page while the microphone waits. Then, in a pause ([tips]), one line at a time, never the same
/// one twice in a row, gone when talking resumes. The list follows the cues `markdown.dart` actually understands and
/// the commands the live reader carries out as they are said (live_route.dart), so a tip is always something that
/// works: words for a note you name, moving the recording, a new note. The routing tip names one of your own notes,
/// which teaches the command better than a made-up title. Tables, books and voice memos are not taught: a recording
/// does not make them. Nor, yet, is "Hey Ghost, add … to Doing" said on a board's own Speak, which the live reader
/// does carry out into that lane: it is the one command the tips could teach and do not, and a heading or lane of
/// the note being written to needs the keyword.
///
/// A command needs no keyword, so every tip says it bare, in a form the bare gate takes (live_command.dart): "Add …
/// to Groceries" when the title says the note is a list, else "Add a note to Work, …", since "a note" said is its
/// own evidence; "New item for Groceries, …" with the item in the same breath, which the middle of a recording
/// needs. The note a tip names is one the gate can name bare: never a book, and never a title that starts with a
/// verb ("Call log", "Book club"), which is read as what to do. Each is held to the reader by a test.
///
/// The asks the AI takes ([asks]) are on the card alone, and only when the recording is a note's own Speak: an ask
/// is the named runs, which the reader at Done reads without the keyword when they are the whole phrase, said first
/// into a note that exists, not a cue for a pause.
///
/// What differs: the one object each function takes is named parameters; a note [tipInPause] is told of is a
/// [TipNote], the three things the web reads of it (its id, its title and its body); `target` is the body of the
/// note being continued, or null. The plugins' tips stay a parameter (`pluginTips`), as on the web. `ASKS` is
/// [asks] and `TIP_AFTER_MS` [tipAfterMs].
library;

import '../core/book.dart' show isBookBody;
import 'live_command.dart' show Nameable, nameable;
import 'note_find.dart' show titleKind;

/// One thing to say.
class Tip {
  const Tip({required this.say, required this.does});

  /// The words to say, shown in quotes.
  final String say;

  /// What saying them does, read after the words: Say “Check box” to make a to-do.
  final String does;

  @override
  bool operator ==(Object other) => other is Tip && other.say == say && other.does == does;

  @override
  int get hashCode => Object.hash(say, does);

  @override
  String toString() => 'Tip(say: $say, does: $does)';
}

const List<Tip> _cues = [
  Tip(say: 'Bullet point', does: 'to start a list'),
  Tip(say: 'The next item is …', does: 'to add to a list'),
  Tip(say: 'Heading', does: 'and then its words to start a section'),
  Tip(say: 'Check box', does: 'to make a to-do'),
  Tip(say: 'New paragraph', does: 'to break the text'),
  Tip(say: 'Scratch that', does: 'to take back the last thing you said'),
  Tip(say: 'Title', does: 'first to name the note'),
  Tip(say: 'Bold … end bold', does: 'around words to make them stand out'),
  Tip(say: 'Quote', does: 'for something someone said'),
  Tip(say: 'Number one', does: 'to start a numbered list'),
  Tip(say: 'Divider', does: 'to draw a line'),
  Tip(say: 'Subheading', does: 'for a section inside a section'),
  Tip(say: 'Option', does: 'for each choice, and “picked option” for the one you chose'),
  Tip(say: 'Info box', does: 'to set a line apart in a box'),
  Tip(say: 'Hidden line', does: 'to keep a line in smoke until it is tapped'),
  Tip(say: 'Calculate', does: 'and then a sum, to see its answer'),
  Tip(say: 'Hashtag', does: 'and a word to tag a line'),
  Tip(say: 'Counter zero of eight', does: 'after an item to count it off'),
  Tip(say: 'Italic … end italic', does: 'around words to lean them'),
  Tip(say: 'Strike … end strike', does: 'to cross words out'),
  Tip(say: 'Code … end code', does: 'around a command'),
  Tip(say: 'Done task', does: 'for a to-do that is already done'),
  Tip(say: 'Link … to … end link', does: 'with words and an address, “attack dot fm”'),
  Tip(say: 'Note link … end link', does: 'around a note’s name to link to it'),
  Tip(say: 'Footnote … end footnote', does: 'for small print under the note'),
  Tip(say: 'Bookmark this', does: 'at the end of a line to open the note there'),
  Tip(say: 'Define … as …', does: 'to write a term and its meaning'),
  Tip(say: 'Emoji', does: 'and its name, like “emoji party popper”'),
  Tip(say: 'New line', does: 'between two pauses to break a line'),
  Tip(say: 'Code block … end code block', does: 'for lines of code, one a sentence'),
  Tip(say: 'Maths … end maths', does: 'around a formula, “x squared plus y”'),
  Tip(say: 'Superscript … end superscript', does: 'to raise words, and “subscript” to lower them'),
  Tip(say: 'Anchor … end anchor', does: 'to name an item, and “item link … end link” to point at it'),
];

/// The asks the AI takes, said first into a note's own Speak (`ASKS`): the words are read as an instruction rather
/// than written into the note, the take is let go, and the run lands in the note as it opens, every change marked
/// until kept or reverted. Each is held to the reader's rules by a test.
const List<Tip> asks = [
  Tip(say: 'Fix the spelling', does: 'and the note is checked as it opens, every change marked'),
  Tip(say: 'Summarise this', does: 'for the point of the note in far fewer words'),
  Tip(say: 'Make this a list', does: 'to shape the note into tasks, a list or a table'),
  Tip(say: 'Tidy this up', does: 'to format the note, keeping every word that matters'),
  Tip(say: 'Carry on', does: 'and the AI writes on from the last line in the note’s own voice'),
];

/// The tip that sends words to a note, said in a form that works without the keyword: "Add … to Groceries" routes
/// bare because the title says it is a list; for a note whose title does not, "a note" said is the evidence.
String _addTo(String title) => titleKind(title) != null ? 'Add … to $title' : 'Add a note to $title, …';

/// Whether a tip can name this title bare: not a verb's ("Call log" is "call log", a thing to do), not "a …" or
/// "the top".
bool _nameableTitle(String? title) => title != null && title.isNotEmpty && nameable(title) == Nameable.name;

/// The tips, in the order they come round. [noteTitle] is a recent note's title for the routing tip; [continuing]
/// says a note is already being added to, which is when "new note" is worth knowing.
List<Tip> tips({String? noteTitle, required bool continuing}) {
  final title = _nameableTitle(noteTitle) ? noteTitle : null;
  final route = <Tip>[];
  if (title != null) route.add(Tip(say: _addTo(title), does: 'to put it there, into its list if it has one'));
  if (title != null) route.add(Tip(say: 'New item for $title, …', does: 'with the item after it, to add to its list'));
  if (continuing) route.add(const Tip(say: 'New note', does: 'to start a fresh one'));
  if (title != null) route.add(Tip(say: 'Move this to $title', does: 'to send this recording there'));
  // Routing first and then every few cues, since it is the least discoverable; a routing line the cues leave no slot
  // for comes round after them rather than never.
  final out = <Tip>[];
  for (var i = 0; i < _cues.length; i += 1) {
    if (i % 3 == 0 && i ~/ 3 < route.length) out.add(route[i ~/ 3]);
    out.add(_cues[i]);
  }
  final after = (_cues.length / 3).ceil();
  if (after < route.length) out.addAll(route.sublist(after));
  return out;
}

/// A note a command can name, as the tip for a pause reads it.
class TipNote {
  const TipNote({required this.id, required this.title, required this.body});

  final String id;
  final String title;

  /// The note's text (the web's `note.body`).
  final String body;
}

/// The tip for this pause (the capture screen shows it until words come again): the [turn]th of the tips, round and
/// round, then the switched-on plugins' own, as the plugin wrote them. The routing tip names the most recent note
/// that is not the one being written to and that a tip can name bare: not a book, not a title that starts with a
/// verb.
///
/// [notes] are the notes a command can name, most recent first; [own] is the id of the note being written to, which
/// no tip sends words to; [target] is the body of the note being continued, or null for a new one; [pluginTips] is
/// the switched-on plugins' tips for the routing tip's note; [turn] is how many tips have been shown this recording.
Tip? tipInPause({
  required List<TipNote> notes,
  required String own,
  required String? target,
  required List<Tip> Function(String? recent) pluginTips,
  required int turn,
}) {
  String? recent;
  for (final c in notes) {
    if (c.id != own && !isBookBody(c.body) && _nameableTitle(c.title)) {
      recent = c.title;
      break;
    }
  }
  final list = [...tips(noteTitle: recent, continuing: target != null), ...pluginTips(recent)];
  return list.isEmpty ? null : list[turn % list.length];
}

/// What the card before the first word shows, and in what order.
class Starters {
  const Starters({required this.shape, required this.send, required this.ask});

  /// How to shape the note: the first few cues.
  final List<Tip> shape;

  /// Where to send it: adding to a note by name, and moving the recording.
  final List<Tip> send;

  /// What to ask the AI to do with the note; empty where an ask cannot run.
  final List<Tip> ask;
}

/// How many of each the card holds: enough to show the shape of each kind, few enough to fit above the buttons on a
/// phone (`EACH`).
const int _each = 2;

/// The card's suggestions, a couple of each kind. The sending pair names a note of theirs when there is one to name:
/// words for it, which go into it as they are said, and moving the recording there. With nothing to name, or a title
/// the gate would read as what to do ("Call log"), the one way to make something new, so a first recording still
/// sees that a recording can go somewhere. The asks are there only when [asking]: the recording is a note's own
/// Speak, not over the lock screen, which is the one case an ask said first is run; a new recording is given none
/// rather than a line that would end as a note of the command's words.
Starters starters({String? noteTitle, bool asking = false}) {
  final title = _nameableTitle(noteTitle) ? noteTitle : null;
  final send = title != null
      ? [
          Tip(say: _addTo(title), does: 'to put it there, into its list if it has one'),
          Tip(say: 'Move this to $title', does: 'to send this recording there'),
        ]
      : const [Tip(say: 'Make a list called … with …', does: 'for a new list: its name, and after “with” its items')];
  return Starters(
    shape: _cues.sublist(0, _each),
    send: send.length > _each ? send.sublist(0, _each) : send,
    ask: asking ? asks.sublist(0, _each) : const [],
  );
}

/// How long a pause has to be before a tip shows. Longer than a breath, shorter than giving up (`TIP_AFTER_MS`).
const int tipAfterMs = 2500;
