/// One recording, several requests: "add to the elements list gold carbon and then add to the posters list genes, and
/// can you make a new note called elements and add magnesium". A port of `src/app/capture/compound.ts` (the voice
/// work that followed the Tauri app's 1.6).
///
/// Read as one, the second request ends up inside the first one's items or inside a note's name. This finds where
/// each request starts, so each can be read on its own.
///
/// What differs: nothing but the shapes.
library;

const String _verb = r'(?:add|put|append|make|create|start)';

/// What comes before a verb that starts a request: a sentence end or "and"/"then", and the words people put in front.
final RegExp _leadBefore = RegExp(
  r'(?:^|[.?!;,]\s*|\b(?:and|then)\s+)(?:(?:(?:can|could|would)\s+you\s+|please\s+|also\s+|and\s+|then\s+|okay\s+|ok\s+|so\s+|go\s+ahead\s+and\s+)[\s,]*)*$',
  caseSensitive: false,
);

/// A request that is plainly about notes: it names a new list or note, or an existing one ("add to the posters list").
final RegExp _newNote = RegExp(r'^(?:make|create|start)\s+(?:(?:me|us)\s+)?(?:a|another|one)\s+(?:new\s+)?(?:list|note|checklist)\b', caseSensitive: false);
final RegExp _addTo = RegExp(
  r"^(?:add|put|append)\s+(?:(?:these|this|them|it)\s+)?(?:to|in|into|on)\s+(?:the|my|our)\s+([\p{L}\p{N}'’-]+(?:\s+[\p{L}\p{N}'’-]+){0,4}?)\s+(?:list|note)\b",
  caseSensitive: false,
  unicode: true,
);

final RegExp _inTheNote = RegExp(r'\b(?:in|inside|into)\s+(?:the|that|this)\s+(?:new\s+)?note[\s,.;:]*(?:(?:and|then|can\s+you|please)[\s,]*)*$', caseSensitive: false);

final RegExp _notLetters = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String _norm(String text) => text.toLowerCase().replaceAll(_notLetters, ' ').trim();

/// The requests in [words], each from its own verb on. A recording with one request comes back as it was. "Add to
/// the games list" straight after making a list called games is the same request going on, not a new one.
List<String> splitCommands(String words) {
  final starts = <({int cut, int verb})>[];
  for (final match in RegExp('\\b$_verb\\b', caseSensitive: false).allMatches(words)) {
    final verb = match.start;
    if (verb == 0) continue;
    final lead = _leadBefore.firstMatch(words.substring(0, verb));
    if (lead == null) continue;
    // "make a note called X and in the note, make a list": one request, a list inside the note.
    if (_inTheNote.hasMatch(words.substring(0, verb))) continue;
    final request = words.substring(verb);
    final cut = verb - lead.group(0)!.length;
    final named = _addTo.firstMatch(request)?.group(1);
    if (!_newNote.hasMatch(request) && named == null) continue;
    final before = words.substring(starts.isEmpty ? 0 : starts.last.verb, cut);
    if (named != null &&
        RegExp(
          '\\b(?:called|named|titled|label(?:ed|led)(?:\\s+of)?)\\s+${_norm(named).split(' ').join(r'[\s\p{P}]+')}\\b',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(before)) {
      continue;
    }
    starts.add((cut: cut, verb: verb));
  }
  if (starts.isEmpty) return [words];
  final out = <String>[];
  var from = 0;
  for (final start in starts) {
    out.add(words.substring(from, start.cut).trim());
    from = start.verb;
  }
  out.add(words.substring(from).trim());
  return [
    for (final part in out)
      if (part.isNotEmpty) part,
  ];
}
