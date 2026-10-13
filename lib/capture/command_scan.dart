/// Where in a finished recording a command is, if anywhere. A port of `src/app/capture/commandScan.ts` (the Tauri
/// app's voice work that followed 1.6).
///
/// "I need it to be more conversational and scan the whole text for potential command words, and then attempt to
/// reason what the intended end goal is" (Kevin). The gate used to read only the first word, so "Let's add…", "So I
/// was thinking, can you make me a list called…" and "Throw eggs on my groceries" were all saved as notes of their
/// own words.
///
/// Now every place a request could start is looked at: a verb that changes notes (add, put, make, create, start,
/// throw, stick, jot down…), optionally with the words people put in front of one ("can you", "let's", "go ahead
/// and", "I want you to"). A verb alone is not a command - "I need to make dinner" and "I want to add more tomorrow"
/// are dictation - so each one needs evidence in what follows it: a list or note word, "called/named/labeled", or the
/// title of one of the person's notes. A request someone else was given ("I told Sam to add…", or inside quotes) is
/// reported speech, not a command.
///
/// [CommandScan.anchored] says the recording starts with the command (the old gate). A command found later in the
/// recording is conversational: when it cannot be carried out, or the person declines it, the recording is kept as a
/// note rather than thrown away, because it may well have been dictation.
///
/// What differs: nothing but the shapes.
library;

import '../core/text.dart' show escapeRegExp;
import 'command.dart' show finalCommandWords, stripStopCue;

class CommandScan {
  const CommandScan({required this.words, required this.context, required this.anchored});

  /// The words from the request's verb on: what the rules read.
  final String words;

  /// The whole recording, lead-in gone: what the model reasons over.
  final String context;

  /// The recording starts with the command.
  final bool anchored;
}

/// "really", "just": words people put inside a request.
const String _filler = r'(?:(?:really|just|also|actually|quickly|please)\s+)?';
const String _request =
    r"(?:(?:(?:can|could|would|will)\s+you\s+(?:please\s+)?(?:go\s+ahead\s+and\s+)?|please\s+(?:go\s+ahead\s+and\s+)?|let'?s\s+(?:go\s+ahead\s+and\s+)?|go\s+ahead\s+and\s+|i\s+" +
    _filler +
    r"(?:want|need|would\s+like|'d\s+like)\s+(?:you\s+)?to\s+|i'?d\s+like\s+(?:you\s+)?to\s+))?" +
    _filler;
const String _verb = r'(?:add|put|append|make|create|start|throw|stick|toss|include|insert|jot(?:\s+down)?|write\s+down|save)';

/// "Can you add", "let's make", "throw": where a command could begin. The verb is group 1.
final RegExp _cue = RegExp('(?:^|[\\s,.;:!?"“”])$_request($_verb)\\b', caseSensitive: false);

/// "I need a list of…", "I want a new note called…": a request with no verb of its own.
final RegExp _need = RegExp(
  r"(?:^|[\s,.;:!?])(?:i\s+(?:(?:really|just|also|actually)\s+)?(?:need|want|would\s+like|'d\s+like)|give\s+me|can\s+i\s+(?:get|have))\s+(?:a\s+)?(?:new\s+)?(list|note|checklist|to-?\s?do\s+list)\b",
  caseSensitive: false,
);

/// Something to do with notes follows the verb.
final RegExp _noteWords = RegExp(r'\b(?:list|lists|note|notes|page|checklist|to-?\s?do(?:s|\s+list)?|called|named|titled|label(?:ed|led))\b', caseSensitive: false);

/// How far after the verb its evidence may be, in words.
const int _evidenceWords = 14;

/// Someone else was asked, or it is quoted: "I told Sam to add…".
final RegExp _reported = RegExp(r'\b(?:told|tell|tells|said|say|says|asked|ask|asks|he|she|they|him|her|them)\b|["“]', caseSensitive: false);

final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _space = RegExp(r'\s+');

/// Whether [text] names one of [titles] as whole words.
bool _namesATitle(String text, List<String> titles) {
  return titles.any((title) {
    final words = title.trim().replaceAll(_notWord, ' ').trim();
    if (words.length < 2) return false;
    return RegExp(
      r'(?:^|[^\p{L}\p{N}])' + words.split(' ').map(escapeRegExp).join(r'[\s\p{P}]+') + r'(?=$|[^\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  });
}

/// The sentence [text] is in, up to [at]: what was said just before a cue.
String _sentenceBefore(String text, int at) {
  var last = -1;
  for (final stop in const ['.', '!', '?']) {
    final found = at - 1 < 0 ? -1 : text.lastIndexOf(stop, at - 1);
    if (found > last) last = found;
  }
  return text.substring(last + 1, at);
}

/// The command in a finished recording, or null when it is dictation.
CommandScan? scanForCommand(String transcript, List<String> titles) {
  final text = stripStopCue(transcript.trim());
  final anchored = finalCommandWords(text);
  if (anchored != null) return CommandScan(words: anchored, context: anchored, anchored: true);

  final found = <({int at, String words})>[];
  for (final cue in _cue.allMatches(text)) {
    final verbAt = cue.start + cue.group(0)!.length - (cue.group(1)?.length ?? 0);
    found.add((at: cue.start, words: text.substring(verbAt)));
  }
  for (final need in _need.allMatches(text)) {
    // "I need a list of movies…" reads as "make a list of movies…".
    final nounAt = need.start + need.group(0)!.length - (need.group(1)?.length ?? 0);
    found.add((at: need.start, words: 'make a ${text.substring(nounAt)}'));
  }
  // In the order said; two at one place keep the order they were found in (`List.sort` is not stable).
  final ordered = [for (var i = 0; i < found.length; i += 1) (index: i, found: found[i])]
    ..sort((a, b) => a.found.at != b.found.at ? a.found.at.compareTo(b.found.at) : a.index.compareTo(b.index));

  for (final entry in ordered) {
    final request = entry.found;
    if (_reported.hasMatch(_sentenceBefore(text, request.at + 1))) continue;
    final head = request.words.split(_space).take(_evidenceWords).join(' ');
    if (!_noteWords.hasMatch(head) && !_namesATitle(head, titles)) continue;
    return CommandScan(words: request.words.trim(), context: text, anchored: false);
  }
  return null;
}
