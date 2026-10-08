/// The run a spoken phrasing means ("fix the spelling", "summarise it"), for the live reader to queue one said
/// mid-take for after Done (`live_route.dart` `notRoute`).
///
/// A port of `runOf`, its `RUN_RULES` and its `RUN_REST` from `src/app/ai/instruction.ts`, and nothing else of that
/// file: the rest of it belongs to `lib/ai`, which is being written elsewhere. When `lib/ai/instruction.dart` exists
/// with its own `runOf`, this file goes and `live_route.dart` imports that one.
///
/// What differs: a run's kind is the web's own word for it (`RunKind`, `src/app/ai/kinds.ts`: 'fix', 'summarize',
/// 'format', 'enhance', 'continue', 'shape') as a `String`, since the enum of kinds is `lib/ai`'s to declare.
library;

/// The runs, said in words: each rule is the phrasings that mean one kind and nothing else.
final List<(String, RegExp)> _runRules = [
  ('fix', RegExp(r'^(?:(?:fix|correct|check|clean up)(?:\s+(?:the|my|its|any))?\s+(?:spelling|grammar|typos?|punctuation|mistakes)|spell\s?check|proof\s?read)', caseSensitive: false)),
  ('summarize', RegExp(r'^(?:summari[sz]e|sum (?:it |this )?up|give me (?:a |the )?summary|tl;?dr)\b', caseSensitive: false)),
  ('format', RegExp(r'^(?:format|reformat|tidy(?: (?:it|this|up))?(?: up)?|clean (?:it |this )?up|organi[sz]e(?: it| this)?)\b(?!.*\b(?:spelling|grammar)\b)', caseSensitive: false)),
  ('enhance', RegExp(r'^(?:enhance|expand(?: on)?(?: it| this)?|flesh (?:it |this )?out|elaborate|make (?:it|this) (?:fuller|longer|richer|better))\b', caseSensitive: false)),
  ('continue', RegExp(r"^(?:continue|carry on|keep (?:going|writing)|write more|go on|what(?:'s| is) next)\b", caseSensitive: false)),
  // "Make this a list", never "make a list called…", which is a new list by name (capture/command.dart).
  (
    'shape',
    RegExp(
      r'^(?:make|turn)\s+(?:this|it|the note|these|this note|everything)\s+(?:into\s+)?(?:a\s+|an\s+)?(?:list|to-?\s?do(?: list)?|task list|tasks|check\s?list|table|numbered list|bullet(?:ed)? list|bullets)\b',
      caseSensitive: false,
    ),
  ),
];

/// What may follow a run's words and leave it the run alone: its object ("summarise it for me", "tidy this up").
final RegExp _runRest = RegExp(r'^(?:\s+(?:it|this|that|the note|this note|everything|up|please|for me|now))*\s*$', caseSensitive: false);

/// The run a phrasing means, or null. With [whole], the run and nothing more: without the keyword, "fix the spelling
/// of Kowalski on the sign" is a sentence, not a run on the note, since the rules are anchored at the front and would
/// take any sentence that opens with one of them.
String? runOf(String words, {bool whole = false}) {
  for (final (kind, rule) in _runRules) {
    final found = rule.firstMatch(words);
    if (found == null) continue;
    if (!whole || _runRest.hasMatch(words.substring(found.group(0)!.length))) return kind;
  }
  return null;
}
