/// Marks said around words inside a sentence: "bold … end bold", "italic … end italic", "code … end code", "maths …
/// end maths", "superscript … end superscript", and a switched-on plugin's own ("spoiler … end spoiler"). A port of
/// `src/app/capture/spoken/inline.ts`.
///
/// Matched across a whole paragraph, because a speaker pauses around the words being marked and Whisper turns each
/// pause into a full stop. Both halves are required, so "a bold move" is left alone; see [spokenInlineMarkup] for
/// when "and" closes one. Pure but for the plugins' cues, which the recorder sets as it opens ([setSpokenFormats]).
///
/// What differs: nothing. The plugins' cues are this library's own state, as they are the web module's.
library;

import 'numbers.dart';
import 'stand_ins.dart';

/// A plugin's formatting said the way bold is: its cue word, and the delimiter the words it wraps are put between.
class SpokenFormat {
  const SpokenFormat({required this.word, required this.delimiter});
  final String word;
  final String delimiter;
}

/// The plugin formattings that can be said, set by the recorder from the switched-on plugins (the web's
/// plugins/types.ts `InlineFormat.cue`; the Spoiler plugin's "spoiler … end spoiler" wraps the words in `||`). Held
/// here rather than read from the registry so this file stays pure and testable. A library's own state, so whatever
/// set it last is what every later render reads: the recorder sets it once as it opens, and a test that sets it puts
/// it back.
List<SpokenFormat> _spokenFormats = const [];

final RegExp _cueWord = RegExp(r'^[a-z][a-z ]*[a-z]$', caseSensitive: false);

void setSpokenFormats(List<SpokenFormat> formats) {
  _spokenFormats = formats.where((format) => _cueWord.hasMatch(format.word.trim()) && format.delimiter.isNotEmpty).toList();
}

final RegExp _space = RegExp(r'\s+');

String _escapeWord(String word) => word.trim().replaceAll(_space, r'\s+');

/// How a cue word is heard as well as how it is spelled: "aside" comes back as "a side", "redact" as "redacted".
const Map<String, String> _saidAs = {'aside': r'a\s?side', 'unsure': '(?:un|en|in)sure|onshore', 'redact': 'redact(?:ed)?'};

RegExp _inlineMarkup(List<SpokenFormat> formats) {
  final words = [
    r'bold\s+italics?',
    'bold',
    'italics?',
    'emphasis',
    'strike(?:through)?',
    r'crossed\s+out',
    'code',
    r'super\s?script',
    r'sub\s?script',
    'maths?',
    for (final format in formats) _saidAs[format.word.trim().toLowerCase()] ?? _escapeWord(format.word),
  ];
  final any = words.join('|');
  return RegExp('\\b($any)\\b([.,:;!]?)\\s+([\\s\\S]+?)[.,;:!]?\\s+(end|and)\\s+($any)\\b([.,;:!?]?)', caseSensitive: false);
}

final RegExp _strike = RegExp(r'^strike(?:through)?$|^crossed out$');
final RegExp _italic = RegExp(r'^italics?$');
final RegExp _boldItalic = RegExp(r'^bold italics?$');
final RegExp _superscript = RegExp(r'^super ?script$');
final RegExp _subscript = RegExp(r'^sub ?script$');
final RegExp _maths = RegExp(r'^maths?$');

/// Which cue a spoken word is, however it was heard: "A side" is aside, "ensure" is unsure, "italics" is italic.
String _cueOf(String word, List<SpokenFormat> formats) {
  final heard = word.toLowerCase().replaceAll(_space, ' ').trim();
  for (final format in formats) {
    final name = format.word.trim().toLowerCase().replaceAll(_space, ' ');
    final alias = _saidAs[name];
    if (heard == name || (alias != null && RegExp('^(?:$alias)\$', caseSensitive: false).hasMatch(heard))) return name;
  }
  if (_strike.hasMatch(heard)) return 'strike';
  if (_italic.hasMatch(heard)) return 'italic';
  if (_boldItalic.hasMatch(heard)) return 'bold italic';
  if (_superscript.hasMatch(heard)) return 'superscript';
  if (_subscript.hasMatch(heard)) return 'subscript';
  if (_maths.hasMatch(heard)) return 'maths';
  return heard;
}

/// A cue word run into what follows it: "spoiler4417".
RegExp _inlineGlued(List<SpokenFormat> formats) {
  final words = ['bold', 'italic', 'strike', 'code', for (final format in formats) _escapeWord(format.word)];
  return RegExp('\\b(${words.join('|')})(\\d)', caseSensitive: false);
}

const Map<String, String> _builtInMarkers = {
  'bold italic': '***',
  'bold': '**',
  'strike': '~~',
  'code': '`',
  'superscript': '^',
  'subscript': '~',
  'maths': r'$',
};

final RegExp _italics = RegExp(r'\bitalics\b', caseSensitive: false);
final RegExp _common = RegExp(r'^(?:bold|italic|emphasis)$');
final RegExp _stopsAtEnd = RegExp(r'[.,;:!]+$');
final RegExp _glueBeforeMark = RegExp('\\s*$glue(?=[\\^~])');
final RegExp _glueBeforeCapitals = RegExp('$glue\\s+(?=[A-Z0-9]{1,2}\\b)');

/// Spoken inline markup: "bold ... end bold", "italic ... end italic", and a plugin's own ("spoiler ... end
/// spoiler", [setSpokenFormats]).
///
/// Matched across a whole paragraph rather than inside one sentence, because a speaker pauses around the words being
/// marked and Whisper turns each pause into a full stop - "the deadline is bold. Friday. End bold." - so a
/// sentence-level rule would never see both halves. Both halves are required: "a bold move" has no "end bold" and is
/// left alone. The punctuation Whisper put after "end bold" is kept, so the sentence after it still starts a new
/// sentence.
///
/// "and bold" also closes, when Whisper put a mark straight after the opening word ("Italics, maybe, and italics.")
/// or when it ends the sentence ("The deadline is bold Friday at noon and bold."). The two words sound almost the
/// same, and on synthesised speech base.en wrote "and" for "end" in most voices even with the cue vocabulary as its
/// prompt. "It was bold thinking and bold action" has neither a pause after the first "bold" nor the sentence ending
/// at the second, and is left alone.
String spokenInlineMarkup(String paragraph, [List<SpokenFormat>? formats]) {
  final said = formats ?? _spokenFormats;
  // Whisper's own spellings of the cues: "italics" for "italic", "spoiler4417" run together.
  final heard = paragraph
      .replaceAllMapped(_italics, (m) => m.group(0)!.substring(0, m.group(0)!.length - 1))
      .replaceAllMapped(_inlineGlued(said), (m) => '${m.group(1)} ${m.group(2)}');
  return heard
      .replaceAllMapped(_inlineMarkup(said), (found) {
        final match = found.group(0)!;
        final kind = found.group(1)!, paused = found.group(2)!, inner = found.group(3)!;
        final closer = found.group(4)!, closing = found.group(5)!, after = found.group(6)!;
        final cue = _cueOf(kind, said);
        // "A side … end aside" is one mark; "the gate code is spoiler … end spoiler" is not a code mark, but may hold
        // one.
        if (_cueOf(closing, said) != cue) return '$kind${spokenInlineMarkup(match.substring(kind.length), said)}';
        // "and bold" closes after a pause at the opening cue, or when it ends the sentence: "… at noon and bold."
        // Mid-sentence, "bold thinking and bold action" is prose. The other cue words are rare enough in speech that
        // "and" closes them anywhere.
        final endsSentence = after.isNotEmpty || heard.substring(found.end).trim().isEmpty;
        final common = _common.hasMatch(cue);
        // Three words or more between them is a stretch someone chose to mark: "bold thinking and bold action" is one.
        final marked = inner.trim().split(_space).length >= 3;
        if (closer.toLowerCase() == 'and' && common && paused.isEmpty && !endsSentence && !marked) return match;
        final words = inner.trim().replaceFirst(_stopsAtEnd, '');
        for (final format in said) {
          if (format.word.trim().toLowerCase().replaceAll(_space, ' ') == cue) return '${format.delimiter}$words${format.delimiter}$after';
        }
        final marker = _builtInMarkers[cue] ?? '_';
        // Code is as it was said, lower case and without the commas Whisper puts at its pauses, as a command is typed.
        final inside = cue == 'code'
            ? words.toLowerCase().replaceAll(',', '')
            : cue == 'maths'
            ? spokenMaths(words)
            : cue == 'superscript' || cue == 'subscript'
            ? spokenScript(words)
            : words;
        // Raised and lowered words hang on the word before them: the 2^nd^, H~2~O.
        final glued = cue == 'superscript' || cue == 'subscript';
        return '${glued ? glue : ''}$marker$inside$marker${glued && after.isEmpty ? glue : ''}$after';
      })
      .replaceAll(_glueBeforeMark, '')
      // After the mark, only a short capital run is part of the same word (H~2~O); "the 2^nd^ of June" keeps its space.
      .replaceAll(_glueBeforeCapitals, '')
      .replaceAll(glue, '');
}
