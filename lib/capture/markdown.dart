/// Speech, turned into a note. A port of `src/app/capture/markdown.ts`.
///
/// Local rules, run on every committed Whisper segment with no network and no delay: they catch the spoken cues the
/// guide teaches ("new paragraph", "bullet point", "heading", "check box", "bold … end bold"), the obvious to-dos ("I
/// need to..."), a spoken enumeration after a word that introduces one ("I need eggs, milk and bread"), and an
/// ordinal run ("first... second... finally..."). Nothing else decides the shape of a note: it is what was said, laid
/// out by what was said.
///
/// Deliberately heuristic and deliberately high-precision. A rule that turns a sentence into a list it was not is
/// worse than one that misses a list, because a missed list is still readable prose and a false one mangles it; so
/// the enumeration rule demands a list-introducing word before the items, and short items after it, rather than
/// trusting commas.
///
/// This library is the driver: phrases into paragraphs by pause and cue, paragraphs into sentences, and each sentence
/// through the rule families in spoken/ - inline marks (inline.dart), the marks said inside a sentence (extras.dart),
/// numbers and sums (numbers.dart), lists (lists.dart), code blocks (code_blocks.dart), and the block cues and how
/// blocks are written out (blocks.dart). What spans sentences is held here: a cue said alone, an item phrase waiting
/// for its item, a list announced, the title. Last, an item's fields said at the end of it, "due Friday", "high
/// priority", "for Sam", are written as its fields (fields.dart, docs/DESIGN.md §158).
///
/// What differs: the call. The web's `renderNote(segments, partial = '', { titled, today } = {})` has an optional
/// positional argument and then an options object, which Dart cannot write as optional positional and then named. So
/// [renderNote] keeps both positional and optional, and the options are the web's own [RenderOptions], a class:
/// `renderNote(segments, '', const RenderOptions(titled: false))`. `PARAGRAPH_GAP_MS` is [paragraphGapMs] and
/// `TRANSCRIPT_HEADING` [transcriptHeading]. `Segment` is `lib/core/note.dart`'s, passed on from here as the web
/// passes on the store's.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/days.dart';
import '../core/note.dart' show Segment;
import '../core/text.dart';
import 'spoken/blocks.dart';
import 'spoken/code_blocks.dart';
import 'spoken/extras.dart';
import 'spoken/fields.dart';
import 'spoken/inline.dart';
import 'spoken/lists.dart';
import 'spoken/stand_ins.dart';
import 'spoken/words.dart';

// A phrase with its times is the stored note's shape (core/note.dart); passed on for the recorder's libraries.
export '../core/note.dart' show Segment;

/// What [renderNote] answers (`RenderedNote`).
class RenderedNote {
  const RenderedNote({required this.markdown, required this.pendingFrom, required this.plain});

  final String markdown;

  /// Where the in-progress, uncommitted phrase begins, or null when there is none.
  final int? pendingFrom;

  /// The committed transcript, paragraphs joined by blank lines.
  final String plain;

  @override
  bool operator ==(Object other) => other is RenderedNote && other.markdown == markdown && other.pendingFrom == pendingFrom && other.plain == plain;

  @override
  int get hashCode => Object.hash(markdown, pendingFrom, plain);

  @override
  String toString() => 'RenderedNote(markdown: $markdown, pendingFrom: $pendingFrom, plain: $plain)';
}

/// A pause long enough to be a new thought, as the gap between two committed phrases (`PARAGRAPH_GAP_MS`).
///
/// Not the pause itself. The streamer (the web's src-tauri/src/whisper/stream.rs) cuts a phrase 300 ms into the quiet
/// after it and drops quiet once two seconds of it have built up, keeping 300 ms: so any pause from about 2.3 s to
/// 4 s arrives as a 1.7 s gap between the phrases, and a shorter one as none at all. At 2 s, as this once was, a
/// paragraph break by pausing could never happen on the phone. 1.5 s is a spoken pause of a little over two seconds.
///
/// The engine commits a segment on a much shorter pause, which is a breath rather than a paragraph; treating every
/// commit as a paragraph break would turn a note into a column of one-line fragments. A little over two seconds is
/// long enough that a speaker thinking mid-sentence does not trigger it. capture/voice_suite.dart `scriptHeard` times
/// the suite's phrases by the same arithmetic.
const int paragraphGapMs = 1500;

final RegExp _paragraphCue = RegExp(r'\b(?:new|next) paragraph\b[.,!?]?', caseSensitive: false);
final RegExp _pieceLead = RegExp(r'^(?:[\s.,;:?]|!(?!\[))+');
final RegExp _endsInStop = RegExp(r'[.!?]$');

// ---- paragraphs and sentences -------------------------------------------------------------------------------------

/// Committed segments, grouped into paragraphs by pause length and spoken cue.
List<String> toParagraphs(List<Segment> segments) {
  final paragraphs = <String>[];
  var current = '';
  int? lastEnd;

  void flush() {
    final text = current.trim();
    if (text.isNotEmpty) paragraphs.add(capitalise(text));
    current = '';
  }

  for (final segment in segments) {
    final text = segment.text.trim();
    if (text.isEmpty) continue;
    if (lastEnd != null && segment.startMs - lastEnd > paragraphGapMs) flush();
    lastEnd = segment.endMs;

    final pieces = text.split(_paragraphCue);
    for (var index = 0; index < pieces.length; index += 1) {
      if (index > 0) flush();
      final part = pieces[index].replaceFirst(_pieceLead, '').trim();
      // A phrase after a finished sentence starts one, whatever case Whisper gave it.
      final said = current.isNotEmpty && _endsInStop.hasMatch(current) ? capitalise(part) : part;
      if (part.isNotEmpty) current = current.isNotEmpty ? '$current $said' : said;
    }
  }
  flush();
  return paragraphs;
}

// ---- a meeting's transcript ---------------------------------------------------------------------------------------

/// The heading a meeting's transcript is written under (docs/DESIGN.md §127 section 3) (`TRANSCRIPT_HEADING`).
const String transcriptHeading = '## Transcript';

/// The heading on a line of its own, wherever it is in the body.
final RegExp _transcriptLine = RegExp(r'^## Transcript[ \t]*$', multiLine: true);

/// A meeting's transcript: its paragraphs under `## Transcript`, no cues and no title, since a meeting is recorded
/// rather than read (capture/meeting.dart). The phrase still being guessed, when there is one, ends the last
/// paragraph. The twin of the web's src-tauri/src/transcript.rs, which writes the same shape from the phone's own
/// transcription.
String renderTranscript(List<Segment> segments, [String partial = '']) {
  final paragraphs = toParagraphs(segments);
  final guess = partial.trim();
  if (guess.isNotEmpty) {
    final last = paragraphs.length - 1;
    if (last >= 0) {
      paragraphs[last] = '${paragraphs[last]} $guess';
    } else {
      paragraphs.add(guess);
    }
  }
  return '$transcriptHeading\n\n${paragraphs.join('\n\n')}';
}

/// The transcript section of a body, from its heading to the end, or null where there is none.
String? transcriptOf(String body) {
  final at = _transcriptLine.firstMatch(body)?.start;
  return at == null ? null : body.substring(at).trimRight();
}

/// The body with [transcript] (a whole section, heading and all) in place of the one it has, or on its end.
String withTranscript(String body, String transcript) {
  final section = transcript.trimRight();
  final at = _transcriptLine.firstMatch(body)?.start;
  if (at != null) return '${body.substring(0, at)}$section';
  final before = body.trimRight();
  return before.isNotEmpty ? '$before\n\n$section' : section;
}

/// The body with its transcript section taken off, for telling a transcript that arrived from an edit.
String withoutTranscript(String body) {
  final at = _transcriptLine.firstMatch(body)?.start;
  return (at == null ? body : body.substring(0, at)).trimRight();
}

/// Where one sentence ends and the next begins: a stop, then a capital. A sentence can start with inline markup
/// ("**Friday** is the deadline"), so asterisks and underscores may come before the capital, and a said line break
/// (spoken/stand_ins.dart) ends a sentence as a stop does.
final RegExp _sentenceBoundary = RegExp('(?<=[.!?*_$breakMark])\\s+(?=["\'([*_]*[A-Z0-9])');

/// The sentences of a paragraph.
///
/// Whisper punctuates and capitalises, so a terminal mark followed by a capital is a reliable boundary for speech in
/// a way it is not for typed prose (which has "e.g. Smith" and version numbers).
List<String> _sentencesOf(String paragraph) {
  final out = <String>[];
  var start = 0;
  for (final match in _sentenceBoundary.allMatches(paragraph)) {
    final end = match.start;
    final text = paragraph.substring(start, end).trim();
    if (text.isNotEmpty) out.add(text);
    start = match.end;
  }
  final tail = paragraph.substring(start).trim();
  if (tail.isNotEmpty) out.add(tail);
  return out;
}

/// The sentences of a phrase, by the same boundary: for the live reader, which takes back the last one said
/// (take_back.dart).
List<String> splitSentences(String text) => _sentencesOf(text);

// ---- the whole note -----------------------------------------------------------------------------------------------

/// How a note is rendered (`RenderOptions`).
class RenderOptions {
  const RenderOptions({this.titled = true, this.today});

  /// Whether the note may take a `# title`. False for a recording added to the end of a note that has one (a note's
  /// own Speak): its opening sentence stays a sentence, and a spoken "Title: …" becomes a `## heading` there rather
  /// than a second title mid-note.
  final bool titled;

  /// The day a spoken "due Friday" counts from (spoken/fields.dart): the person's own day, read from the clock unless
  /// a caller says otherwise, as a test does.
  final String? today;
}

/// The blocks that are list items, whose fields are said at their end: a to-do, a done one, a bullet, a step.
const Set<BlockKind> _fielded = {BlockKind.task, BlockKind.done, BlockKind.bullet, BlockKind.number};

final RegExp _andThing = RegExp(r'\s+and\s+(?=(?:the|a|an|some|two|three)\s)', caseSensitive: false);

BlockKind _blockKind(ListKind kind) => kind == ListKind.number ? BlockKind.number : BlockKind.bullet;

/// Committed segments and an optional in-progress phrase, rendered to markdown.
///
/// Pure, and cheap enough to run on every event: a note is a few hundred words and the engine emits about one event
/// a second.
/// The day a spoken "tomorrow" is counted from where a call names none (`isoDay(new Date())`): the device's own
/// today. A test held to another run's answers says the day that run was made on.
@visibleForTesting
String Function() spokenToday = _deviceToday;
String _deviceToday() => isoDay(DateTime.now());

/// The device's own today, for a test to put back.
@visibleForTesting
void resetSpokenToday() => spokenToday = _deviceToday;

RenderedNote renderNote(List<Segment> segments, [String partial = '', RenderOptions options = const RenderOptions()]) {
  final titled = options.titled;
  final today = options.today ?? spokenToday();
  final paragraphs = withCodeBlocksWhole(toParagraphs(segments));
  final plain = paragraphs.join('\n\n');

  final blocks = <Block>[];
  String? title;

  /// A cue said as its own sentence, waiting for the sentence it introduces.
  String? pendingCue;

  /// The title is decided by the first sentence with content, not by a cue before it.
  var seenContent = false;

  /// A list is open: announced, or begun by an item. Its kind, for the items that follow.
  ListKind? openList;

  /// Whether short plain sentences join the open list: only when it was announced ("here's my shopping list") or
  /// talked into being ("the next item is …"). After a cue ("bullet point, eggs") a short "Thanks." is a reply, not
  /// an item.
  var takesShortItems = false;

  /// An item phrase that stopped short ("The next item is."), waiting for its item.
  String? pendingItem;

  /// The phrase waiting was a numbered cue ("number three, the next item is"): the item is numbered.
  var pendingNumbered = false;

  /// The open list was led by "Pack these.": its items hang under that line, as a list said with a colon does.
  var ledList = false;
  final paragraphStarts = <int>{};

  /// What the spoken footnotes say, in order: written under the note.
  final footnotes = <String>[];

  /// The kind an item said as a phrase, or a short item under an announced list, takes: numbered if the list it
  /// follows is, bullets otherwise.
  ListKind listKind() {
    final last = blocks.isEmpty ? null : blocks.last;
    if (last?.kind == BlockKind.number) return ListKind.number;
    if (last?.kind == BlockKind.bullet || last?.kind == BlockKind.item) return ListKind.bullet;
    return openList ?? ListKind.bullet;
  }

  for (final paragraph in paragraphs) {
    final paragraphStart = blocks.length;
    paragraphStarts.add(paragraphStart);
    for (final piece in codeBlocksIn(paragraph)) {
      if (piece is PieceFence) {
        blocks.add(piece.block);
        pendingCue = null;
        seenContent = true;
        openList = null;
        takesShortItems = false;
        continue;
      }
      final said = liftFootnotes((piece as PieceText).text, footnotes);
      final sentences = _sentencesOf(spokenExtras(spokenInlineMarkup(inlineNumbering(said))));

      final firstOrdinal = sentences.indexWhere(ordinalStart.hasMatch);

      for (var sentenceIndex = 0; sentenceIndex < sentences.length; sentenceIndex += 1) {
        final spoken = sentences[sentenceIndex];
        final cueOnly = standaloneCue.firstMatch(spoken)?.group(1);
        if (cueOnly != null && cueOnly.isNotEmpty) {
          pendingCue = cueOnly;
          continue;
        }
        final sentence = pendingCue != null && pendingCue.isNotEmpty ? '$pendingCue: $spoken' : spoken;
        pendingCue = null;

        // The item after "the next item is", said as its own phrase. A second item phrase instead means the first was
        // just words.
        if (pendingItem != null) {
          final held = pendingItem;
          final numbered = pendingNumbered;
          pendingItem = null;
          pendingNumbered = false;
          if (!opensItem(sentence) && itemOf(sentence) == null) {
            final kind = numbered ? ListKind.number : listKind();
            blocks.add(Block(_blockKind(kind), capitalise(stripEnd(sentence))));
            openList = kind;
            takesShortItems = true;
            continue;
          }
          blocks.add(Block(BlockKind.para, held));
        }
        if (opensItem(sentence)) {
          pendingItem = sentence;
          seenContent = true;
          continue;
        }
        // "Number three, the next item is", with the item after a breath: the number waits for it too, so the list's
        // count carries on.
        final numberedOpener = numberCue.firstMatch(sentence)?.group(2);
        if (numberedOpener != null && numberedOpener.isNotEmpty && opensItem(numberedOpener)) {
          pendingItem = sentence;
          pendingNumbered = true;
          seenContent = true;
          continue;
        }

        // The very first sentence can be a spoken title, or a short opening that reads as one.
        if (!seenContent) {
          seenContent = true;
          final cue = titleCue.firstMatch(sentence)?.group(1);
          if (cue != null && cue.isNotEmpty) {
            final words = capitalise(stripEnd(cue));
            if (titled) {
              title = words;
            } else {
              blocks.add(Block(BlockKind.heading, words));
            }
            continue;
          }
          if (titled && isTitleShaped(sentence) && itemOf(sentence) == null) {
            title = stripEnd(sentence);
            openList = announcesList(sentence);
            takesShortItems = openList != null;
            continue;
          }
        }

        // A list item said as a phrase ("the next item is …"), or a short item under a list someone announced. It
        // takes the list's kind.
        final item = itemOf(sentence);
        if (item != null) {
          final kind = listKind();
          blocks.add(Block(_blockKind(kind), item));
          openList = kind;
          takesShortItems = true;
          continue;
        }

        // "Due Friday." or "High priority." a breath after an item: the item's field, not a sentence of its own.
        final before = blocks.isEmpty ? null : blocks.last;
        if (before != null && blocks.length > paragraphStart && _fielded.contains(before.kind) && onlyFields(sentence, today)) {
          blocks[blocks.length - 1] = before.withText('${before.text} ${stripEnd(sentence)}');
          continue;
        }

        final ordinalRun = firstOrdinal >= 0 && sentenceIndex >= firstOrdinal;
        final made = localBlocks(sentence, ordinalRun);
        final plainSentence = made.length == 1 && made[0].kind == BlockKind.para;
        // A short plain sentence under an open list is its next item. Only plain: a cue ("number two, …", "then …" in
        // an ordinal run) has already said what the sentence is.
        if (openList != null && takesShortItems && plainSentence && itemShaped(sentence)) {
          final kind = listKind();
          // "The stove and the lantern." is two things; "bread and butter" is one.
          final parts = stripEnd(sentence).split(_andThing);
          for (final part in parts) {
            blocks.add(Block(ledList && kind == ListKind.bullet ? BlockKind.item : _blockKind(kind), capitalise(part.trim())));
          }
          openList = kind;
          continue;
        }
        final led = plainSentence && leadsList(sentence) && announcesList(sentence) != null;
        // "Pack these." is the line a list hangs from: "Pack these:", like a list said with its colon.
        if (led) {
          blocks.add(Block(BlockKind.intro, '${stripEnd(sentence)}:'));
        } else {
          blocks.addAll(made);
        }
        ledList = led;
        final last = made.isEmpty ? null : made.last;
        final announced = announcesList(sentence);
        if (announced != null) {
          openList = announced;
          takesShortItems = true;
        } else if (last?.kind == BlockKind.number) {
          openList = ListKind.number;
        } else if (last?.kind == BlockKind.bullet) {
          openList = ListKind.bullet;
        } else {
          openList = null;
          takesShortItems = false;
        }
      }
    }
  }

  // A "the next item is" that nothing followed: it was words.
  if (pendingItem != null) blocks.add(Block(BlockKind.para, pendingItem));

  // An item's due day, priority and person, said at its end, written as its fields.
  final fielded = [for (final block in blocks) _fielded.contains(block.kind) ? block.withText(withSpokenFields(block.text, today)) : block];

  final notes = [for (var index = 0; index < footnotes.length; index += 1) '[^${index + 1}]: ${footnotes[index]}'].join('\n');
  final laidOut = renderBlocks(fielded, paragraphStarts);
  final body = finishLines(notes.isNotEmpty ? '$laidOut${laidOut.isNotEmpty ? '\n\n' : ''}$notes' : laidOut);
  var markdown = title != null && title.isNotEmpty ? '# $title${body.isNotEmpty ? '\n\n$body' : ''}' : body;

  int? pendingFrom;
  final tail = partial.trim();
  if (tail.isNotEmpty) {
    final last = blocks.isEmpty ? null : blocks.last;
    final separator = markdown.isEmpty
        ? ''
        : last?.kind == BlockKind.para
        ? ' '
        : '\n\n';
    pendingFrom = markdown.length + separator.length;
    markdown = '$markdown$separator$tail';
  }

  return RenderedNote(markdown: markdown, pendingFrom: pendingFrom, plain: plain);
}
