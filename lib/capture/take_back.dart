/// Taking back the last thing said, as one committed phrase says it: the grammar of "scratch that", "actually, …",
/// "no wait, four" and "scratch that, add it to Groceries instead" (docs/DESIGN.md §130). A sibling of
/// `live_command.dart`: which readings a phrase has is decided here, with no notes and no clock; what is taken back,
/// and where it goes, is the live reader's (`live_route.dart`).
///
/// Matt: "Id like sentences to be able to redact." Asked what that means: redacting is what happens "when the user
/// says something like 'actually …' or 'scratch that, add it to the `<note>` instead'".
///
/// Two kinds of opener. A safe one is an order, and needs a pause after it or a send: "scratch that", "strike that",
/// "take that back", "forget that", "delete that", "never mind", "cancel that", "ignore that", and "no wait" alone;
/// "Take that back to the shop" and "Strike that pose" are words. A risky one is how people talk, and counts only
/// before a correction: "actually", "I mean", "sorry,", "or rather", "no," and "no wait" with words after it. Whether
/// the words after a risky opener correct what came before is [corrects] (the sentence said again with a change) or
/// [swapWord] (one word of a kind changed: a number, a day, a month, a name); the live reader asks, since only it
/// knows what came before. An opener stands at the start of a phrase, after a stop in any case, or after a comma
/// inside a sentence when only a drop, a send or a change follows, since Whisper writes "the meeting is at three,
/// scratch that" for a beat under 300 ms. The keyword is the opener's only when it stands right before it: before a
/// command in the head it was the command's. A rest after a stop has its first letter put down, since Whisper
/// capitalises whatever follows a stop. A send names its note as a command does, keeping "the" before "list", "note"
/// or "page", which mean the note being written to. Pure, so every phrasing is a test.
///
/// A port of `src/app/capture/takeBack.ts`.
///
/// What differs: [swapWord] answers a record `(text:, from:, to:)` where the web answers an object of those three.
/// The web's openers are sticky regular expressions (`y`) tried at one index; here each is matched as a prefix at
/// that index (`matchAsPrefix`), which is the same thing.
library;

import '../core/text.dart';
import 'command.dart';
import 'live_command.dart';
import 'markdown.dart';
import 'spoken/numbers.dart';

/// A phrase read as a take-back.
class TakeBack {
  const TakeBack({
    required this.head,
    required this.headBeforeKeyword,
    required this.opener,
    required this.said,
    required this.risky,
    required this.rest,
    required this.send,
    required this.keyed,
    required this.afterComma,
  });

  /// What came before the opener in the same phrase, as said, the keyword kept where it was: '' when nothing did.
  /// The take's own words first, a phrase of their own.
  final String head;

  /// The head came before the keyword ("The heating is fixed, hey Ghost, scratch that"): the phrase is marked
  /// `keyword`, as the live reader's `read` marks one.
  final bool headBeforeKeyword;

  /// The opener as said, for the log: "scratch that".
  final String opener;

  /// The opener and its rest as said, keyword and head off: what Undo writes as words.
  final String said;

  /// "actually", "I mean", "no,", "sorry,", "or rather", and "no wait" with a rest: ordinary words, so only a
  /// correction, a change of one word, or a send counts.
  final bool risky;

  /// What followed the opener, its separator gone, as said (lead-ins kept: these may be written): '' when nothing did.
  final String rest;

  /// The rest read as "send it to `<name>`": the name as heard, "instead" gone; null when the rest is not a send.
  final String? send;

  /// "Hey Ghost" was said before the opener.
  final bool keyed;

  /// The opener stood after a comma inside a sentence ("…at three, scratch that"): only a bare drop, a send or a
  /// change may follow it.
  final bool afterComma;

  @override
  bool operator ==(Object other) =>
      other is TakeBack &&
      other.head == head &&
      other.headBeforeKeyword == headBeforeKeyword &&
      other.opener == opener &&
      other.said == said &&
      other.risky == risky &&
      other.rest == rest &&
      other.send == send &&
      other.keyed == keyed &&
      other.afterComma == afterComma;

  @override
  int get hashCode => Object.hash(head, headBeforeKeyword, opener, said, risky, rest, send, keyed, afterComma);

  @override
  String toString() =>
      'TakeBack(head: "$head", headBeforeKeyword: $headBeforeKeyword, opener: "$opener", said: "$said", risky: $risky, rest: "$rest", send: ${send == null ? null : '"$send"'}, keyed: $keyed, afterComma: $afterComma)';
}

class _Opener {
  _Opener(String rule, {required this.safe, this.bareOnly = false}) : rule = RegExp(rule, caseSensitive: false, unicode: true);

  final RegExp rule;
  final bool safe;

  /// "no wait": safe only with nothing after it, risky with a rest.
  final bool bareOnly;
}

/// No letter or digit follows: "actually" is not "actualise", "no" is not "nobody".
const _end = r'(?![\p{L}\p{N}])';

/// The openers, each matched at one position, in the order they are tried.
final List<_Opener> _openers = [
  _Opener('scratch\\s+that$_end', safe: true),
  _Opener('strike\\s+that$_end', safe: true),
  _Opener('take\\s+that\\s+back$_end', safe: true),
  _Opener('forget\\s+that$_end', safe: true),
  _Opener('delete\\s+that$_end', safe: true),
  _Opener('never\\s+mind$_end', safe: true),
  _Opener('cancel\\s+that$_end', safe: true),
  _Opener('ignore\\s+that$_end', safe: true),
  _Opener('(?:no,?\\s+wait|wait,?\\s+no)$_end', safe: true, bareOnly: true),
  _Opener('actually$_end', safe: false),
  _Opener('i\\s+mean$_end', safe: false),
  _Opener('or\\s+rather$_end', safe: false),
  _Opener(r'sorry(?=\s*,)', safe: false),
  _Opener(r'(?:no,?\s+)*no(?=\s*,)', safe: false),
];

/// What may follow a safe opener: a pause (a comma, a stop, a colon), "and", or the end of the phrase.
final RegExp _separator = RegExp(r'^(?:[,.:;!?…]+\s*|\s+and\s+|\s*$)', caseSensitive: false);

/// A stop, or nothing: "No wait." is bare.
final RegExp _bare = RegExp(r'^[.!?…]*\s*$');

/// "Check box:" and "Bullet point:", which a command's payload (`live_route.dart` `payloadWords`) and the block cues
/// (`spoken/blocks.dart`) write, taken off what a person would quote.
final RegExp _cuePrefix = RegExp(r'^(?:check(?:ed)?\s?box|bullet\s?point|checklist(?:\s+item)?|check\s+item)[:,.]?\s*', caseSensitive: false);

/// "It" and "that" are the thing taken back; "this" is the take's own word ("move this to X" moves the recording).
final RegExp _sendVerb = RegExp(
  r'^(?:add|put|send|move|stick|file|save|drop)\s+(?:that|it|those|them|these)\s+(?:to|in|into|on|onto|under|for)\s+(?:(the|my|our)\s+)?(.+)$',
  caseSensitive: false,
);
final RegExp _sendGoes = RegExp(
  r"^(?:that|it|this)(?:['’]s|\s+(?:goes|belongs|should\s+go|should\s+be|is|was))\s+(?:in|into|on|to|for|under)\s+(?:(the|my|our)\s+)?(.+)$",
  caseSensitive: false,
);

/// A send that is starting, for a partial: the verb and its "it" or "that".
final RegExp _sendStart = RegExp(
  r"^(?:(?:add|put|send|move|stick|file|save|drop)\s+(?:that|it|those|them|these)|(?:that|it|this)(?:['’]s|\s+(?:goes|belongs|should)))(?![\p{L}\p{N}])",
  caseSensitive: false,
  unicode: true,
);

/// "The list", "my note": the note being written to, whatever it is called (`note_find.dart` `HERE`), so the article
/// stays.
final RegExp _hereNoun = RegExp(r'^(?:list|note|page)$', caseSensitive: false);

/// A risky opener at the front of a command's words, for the reader to take off: "actually, add a note to House
/// TODOs" is the command.
final RegExp _riskyStart = RegExp(r'^(?:actually|i\s+mean|or\s+rather|sorry\s*,|(?:no,?\s+)*no\s*,|no,?\s+wait|wait,?\s+no)[,:]?\s+', caseSensitive: false);

/// Words that carry nothing of a sentence, for telling one said again from a new one.
final Set<String> _stop =
    'the a an and or but so to of in on at for is are was were be it its this that i we you he she they my our your with from by as not do did does have has had will would should can could'
        .split(' ')
        .toSet();

final Set<String> _numberWords = {...numberWord.split('|'), 'half', 'quarter'};
final Set<String> _weekdays = 'monday tuesday wednesday thursday friday saturday sunday'.split(' ').toSet();
final Set<String> _months = 'january february march april may june july august september october november december'.split(' ').toSet();
final RegExp _number = RegExp(r'^\d+(?:[:.]\d+)?(?:\s?[ap]m)?$', caseSensitive: false);
final RegExp _upperFirst = RegExp(r'^\p{Lu}', unicode: true);

enum _Kind { number, weekday, month, name }

/// The kind of word [word] is, for a change of one word, or null for none: a number, a day, a month, or a capitalised
/// word.
_Kind? _kindOf(String word) {
  final lower = word.toLowerCase();
  if (_number.hasMatch(word) || _numberWords.contains(lower)) return _Kind.number;
  if (_weekdays.contains(lower)) return _Kind.weekday;
  if (_months.contains(lower)) return _Kind.month;
  if (_upperFirst.hasMatch(word)) return _Kind.name;
  return null;
}

final RegExp _insteadEnd = RegExp(r'\s+instead$', caseSensitive: false);
final RegExp _moreThanName = RegExp(r'[,;:]|\.\s');

/// A phrase's words as a send, or null: the keyword and the lead-ins off, a final "instead" and stop off, the name
/// checked.
String? _sendOf(String text) {
  final heard = findKeyword(text);
  if (heard != null && !onlyFiller(heard.before)) return null;
  final words = withoutFinalStop(commandWords(heard != null ? heard.after : text)).replaceFirst(_insteadEnd, '').trim();
  if (words.isEmpty) return null;
  final found = _sendVerb.firstMatch(words) ?? _sendGoes.firstMatch(words);
  final named = found?.group(2)?.trim();
  if (named == null || named.isEmpty) return null;
  final article = found!.group(1);
  final name = article != null && article.isNotEmpty && _hereNoun.hasMatch(named) ? '$article $named' : named;
  // A name runs to the end: with more after it, this is more than a send.
  if (_moreThanName.hasMatch(name)) return null;
  return nameable(name) == Nameable.name ? name : null;
}

typedef _Found = ({String opener, int end, bool safe, String rest});

final RegExp _leadingPause = RegExp(r'^[,:;]?\s*');
final RegExp _pauseFirst = RegExp(r'^[\s,:;]');
final RegExp _stopFirst = RegExp(r'^[.!?…]');

/// An opener at [at] in [text], and what follows it, or null when none stands there.
_Found? _openerAt(String text, int at) {
  for (final candidate in _openers) {
    final found = candidate.rule.matchAsPrefix(text, at);
    if (found == null) continue;
    final opener = found.group(0)!;
    final end = at + opener.length;
    final after = text.substring(end);
    if (candidate.bareOnly) {
      if (_bare.hasMatch(after)) return (opener: opener, end: end, safe: true, rest: '');
      // "No wait, four": how people correct one word. Words after it, with or without the comma.
      final rest = after.replaceFirst(_leadingPause, '').trim();
      return _pauseFirst.hasMatch(after) && rest.isNotEmpty ? (opener: opener, end: end, safe: false, rest: rest) : null;
    }
    if (candidate.safe) {
      final sep = _separator.firstMatch(after);
      // After a stop Whisper capitalises whatever comes next, so the rest's first letter is put down: "Scratch that.
      // Tomorrow." is never a name to swap in; a name after a comma ("scratch that, Sarah") keeps its capital.
      if (sep != null) {
        final rest = after.substring(sep.group(0)!.length).trim();
        return (opener: opener, end: end, safe: true, rest: _stopFirst.hasMatch(sep.group(0)!) ? _uncapitalise(rest) : rest);
      }
      // "scratch that add it to groceries": a send needs no pause, and never occurs in prose.
      return _sendOf(after.trim()) != null ? (opener: opener, end: end, safe: true, rest: after.trim()) : null;
    }
    // A risky opener counts only with words after it: "Actually." alone is words.
    final rest = after.replaceFirst(_leadingPause, '').trim();
    if (rest.isEmpty || !_pauseFirst.hasMatch(after)) return null;
    return (opener: opener, end: end, safe: false, rest: withoutFinalStop(rest) == '' ? '' : rest);
  }
  return null;
}

final RegExp _oneCapital = RegExp(r'^\p{Lu}(?!\p{Lu})', unicode: true);

/// The first letter down, unless the word is all capitals ("TODOs"), which is how it is written.
String _uncapitalise(String text) => _oneCapital.hasMatch(text) ? '${text[0].toLowerCase()}${text.substring(1)}' : text;

final RegExp _boundary = RegExp(r'([.!?…]["”]?|,)\s+');
final RegExp _headTail = RegExp(r'[\s,;:]+$');

/// A phrase read as a take-back: where its opener stands, what came before it, what follows it, and whether it was
/// said after the keyword. Null when the phrase is words.
TakeBack? readTakeBack(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final heard = findKeyword(text);
  final keyAt = heard != null ? heard.before.length : -1;
  // Where the phrase's own words start, its lead-ins gone; and where the command's do, after the keyword and its
  // lead-ins.
  final leadStart = text.length - commandWords(text).length;
  final keyStart = heard != null ? text.length - commandWords(heard.after).length : -1;
  // The words before the keyword, when they are words: the take's own.
  final beforeKeyword = heard != null && !onlyFiller(heard.before) ? heard.before : '';

  TakeBack make(int at, _Found found, String head, bool afterComma) {
    // Keyed only when the keyword stood right before the opener: before a command in the head ("Hey Ghost, add call
    // Sam to Work. Actually, …") the keyword was the command's, and the opener is read as it is without one.
    final keyed = heard != null && at == keyStart;
    return TakeBack(
      head: head,
      headBeforeKeyword: keyed && beforeKeyword != '',
      opener: found.opener,
      said: text.substring(at).trim(),
      risky: !found.safe,
      rest: found.rest,
      send: found.rest.isNotEmpty ? _sendOf(found.rest) : null,
      keyed: keyed,
      afterComma: afterComma,
    );
  }

  bool counts(_Found? found) => found != null && (found.safe || found.rest != '');

  // At the start, after the keyword and the lead-ins: "Okay, scratch that", "Hey Ghost, actually, …".
  if (heard != null && keyStart < text.length) {
    final first = _openerAt(text, keyStart);
    if (counts(first)) return make(keyStart, first!, beforeKeyword, false);
  }
  // Or at the phrase's own start, the keyword inside the rest: "Scratch that, hey Ghost, add it to Groceries".
  if ((heard == null || beforeKeyword.isNotEmpty) && leadStart < text.length) {
    final first = _openerAt(text, leadStart);
    if (counts(first)) return make(leadStart, first!, '', false);
  }

  // After a stop, in any case ("We need eggs. scratch that."), or after a comma inside a sentence.
  for (final boundary in _boundary.allMatches(text)) {
    final at = boundary.end;
    // Not before the phrase's own words, and not between the keyword and its command: those starts were tried above.
    if (at <= leadStart || (keyAt >= 0 && keyAt < at && at <= keyStart)) continue;
    final found = _openerAt(text, at);
    if (found == null) continue;
    final comma = boundary.group(1) == ',';
    // A head keeps its stop, and loses its comma.
    final head = text.substring(0, boundary.start + (comma ? 0 : boundary.group(1)!.length)).replaceFirst(_headTail, '');
    if (head.isEmpty) continue;
    if (!comma) {
      if (counts(found)) return make(at, found, head, false);
      continue;
    }
    // After a comma only a drop, a send, or a change of what came before: "…at three, no wait for me" is words.
    final sentences = splitSentences(head);
    final last = sentences.isEmpty ? head : sentences.last;
    final change = found.rest != '' && (_sendOf(found.rest) != null || swapWord(quoted(last), found.rest) != null || corrects(quoted(last), found.rest));
    if ((found.safe && found.rest == '') || change) return make(at, found, head, true);
  }
  return null;
}

/// The rest of a phrase read on its own as "add it to `<name>`" (keyword and lead-ins off, a final "instead" off): the
/// name, or null. For the send said in a breath of its own after "scratch that".
String? readSend(String text) => _sendOf(text.trim());

final RegExp _curlyQuote = RegExp('[’`]');
final RegExp _notEnding = RegExp(r"n't\b");
final RegExp _contraction = RegExp(r"'(?:s|re|ve|ll|d|m)\b");
final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// The words of [text] that carry its sense: the cue prefix off, contractions to their base word, lower-cased, the
/// stop words gone.
List<String> contentWords(String text) => text
    .replaceFirst(_cuePrefix, '')
    .toLowerCase()
    .replaceAll(_curlyQuote, "'")
    .replaceAll(_notEnding, '')
    .replaceAll(_contraction, '')
    .split(_notWord)
    .where((word) => word.isNotEmpty && !_stop.contains(word))
    .toList();

/// Whether [replacement] is [previous] said again with a change, by the content words they share: at least half of
/// the longer one, so the frame is shared from both sides and a one-word item is not "corrected" by a long new
/// sentence; and either two of them, or all of the previous ("eggs" | "eggs and milk"), or the same words but for one
/// in the same place ("oat milk" | "almond milk", "it's on Tuesday" | "it's on Thursday"). One word of two shared is a
/// new sentence about the same thing: "Call Sam" | "Sam is away".
bool corrects(String previous, String replacement) {
  final before = contentWords(previous);
  final after = contentWords(replacement);
  if (after.isEmpty) return false;
  final changed = before.length == after.length ? [for (var i = 0; i < before.length; i += 1) if (before[i] != after[i]) i] : <int>[];
  final kind = changed.length == 1 ? _kindOf(before[changed[0]]) : null;
  if (kind != null && kind == _kindOf(after[changed[0]])) return true;
  final had = before.toSet();
  final said = after.toSet();
  final shared = said.where(had.contains).length;
  if (shared * 2 < (had.length > said.length ? had.length : said.length)) return false;
  return shared >= 2 || shared == had.length || changed.length == 1;
}

final RegExp _token = RegExp(r"[\p{L}\p{N}](?:[\p{L}\p{N}:.'’]*[\p{L}\p{N}])?", unicode: true);
final RegExp _space = RegExp(r'\s');

/// [previous] with its one word of [fragment]'s kind (a number, a weekday, a month, a name) replaced by [fragment],
/// case and punctuation kept: "The meeting is at three." and "four" give "The meeting is at four.". Null when the
/// fragment is more than one word or of no kind, or when [previous] has two words of that kind, or none.
({String text, String from, String to})? swapWord(String previous, String fragment) {
  final word = withoutFinalStop(commandWords(fragment)).trim();
  if (word.isEmpty || _space.hasMatch(word)) return null;
  final kind = _kindOf(word);
  if (kind == null) return null;
  final prefix = _cuePrefix.firstMatch(previous)?.group(0) ?? '';
  final body = previous.substring(prefix.length);
  final tokens = _token.allMatches(body).toList();
  // A name is a capitalised word that is not the sentence's first, which Whisper capitalises whatever it is.
  final found = [
    for (var i = 0; i < tokens.length; i += 1)
      if (_kindOf(tokens[i].group(0)!) == kind && (kind != _Kind.name || i > 0)) tokens[i],
  ];
  if (found.length != 1) return null;
  final token = found.first;
  final from = token.group(0)!;
  final to = kind == _Kind.name
      ? capitalise(word)
      : _upperFirst.hasMatch(from)
      ? capitalise(word.toLowerCase())
      : _number.hasMatch(word)
      ? word
      : word.toLowerCase();
  if (from == to) return null;
  final at = prefix.length + token.start;
  return (text: '${previous.substring(0, at)}$to${previous.substring(at + from.length)}', from: from, to: to);
}

/// A segment's words as a person would quote them: "Check box:" and "Bullet point:" off, a keyword it opened with
/// off, a final stop off.
String quoted(String text) {
  final heard = findKeyword(text);
  final words = heard != null && onlyFiller(heard.before) ? commandWords(heard.after) : text;
  return withoutFinalStop(words.replaceFirst(_cuePrefix, '')).trim();
}

/// A command's words with a risky opener off their front, when a command follows it: "actually, add a note to House
/// TODOs" after the keyword is the command, said as people say it, not a correction. As said otherwise.
String commandAfterOpener(String words) {
  final plain = words.replaceFirst(_riskyStart, '').trim();
  if (plain == '' || plain == words) return words;
  return isOpener(plain) || readRoute(plain).isNotEmpty || readNameFirst(plain).isNotEmpty ? plain : words;
}

/// The cue an item was written with ("Check box: ", "Bullet point: "), or '': a replacement inherits it, so the list
/// shape holds.
String cuePrefixOf(String text) => _cuePrefix.firstMatch(text)?.group(0) ?? '';

/// The safe openers a partial can be starting, and how much of each is ordinary words that start prose too.
const List<({String opener, String ordinary})> _starts = [
  (opener: 'scratch that', ordinary: ''),
  (opener: 'strike that', ordinary: ''),
  (opener: 'take that back', ordinary: 'take that'),
  (opener: 'forget that', ordinary: 'forget'),
  (opener: 'delete that', ordinary: 'delete'),
  (opener: 'never mind', ordinary: 'never'),
  (opener: 'cancel that', ordinary: 'cancel'),
  (opener: 'ignore that', ordinary: 'ignore'),
  (opener: 'no wait', ordinary: 'no'),
  (opener: 'wait no', ordinary: 'wait'),
];

final RegExp _pauses = RegExp(r'[,.:;!?…]+');
final RegExp _spaces = RegExp(r'\s+');

/// A partial that is starting a safe opener, past any ordinary first words: for the chip, never the page. "scratch",
/// "no w" and "take that b" count; "no", "take that" and every risky opener do not, since "No parking on Sunday" and
/// "Take that to the shop" start the same way, and a partial is transient.
bool opensTakeBack(String partial) {
  final said = commandWords(partial).toLowerCase().replaceAll(_pauses, ' ').replaceAll(_spaces, ' ').trim();
  if (said.isEmpty) return false;
  return _starts.any((start) {
    if (said.startsWith(start.opener)) return true;
    if (!start.opener.startsWith(said)) return false;
    final first = start.opener.split(' ')[0];
    return start.ordinary.isNotEmpty ? said.length > start.ordinary.length + 1 : said.length >= first.length;
  });
}

final RegExp _partialBoundary = RegExp(r'(?:[.!?…]["”]?|,)\s+');

/// Where a safe opener starts in a partial: at its start, or after a stop or a comma inside it ("The meeting is at
/// three, scratch tha"), so the words before it stay on the page and the opener never lands there. -1 for none.
int takeBackAt(String partial) {
  if (opensTakeBack(partial)) return 0;
  for (final boundary in _partialBoundary.allMatches(partial)) {
    final at = boundary.end;
    if (opensTakeBack(partial.substring(at))) return at;
  }
  return -1;
}

/// A partial that is starting a send ("add it to", "that goes in"), keyword and lead-ins off: for the chip while a
/// drop waits for one.
bool opensSend(String partial) {
  final heard = findKeyword(partial);
  return _sendStart.hasMatch(commandWords(heard != null ? heard.after : partial));
}
