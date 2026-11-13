import 'sms.dart';

/// Reactions sent as plain texts, the way phones send them to a phone that can't take them natively:
///
/// - Google Messages: `❤️ to "message text"`, `Reacted 😂 to "…"`, `Removed ❤️ from "…"`
/// - iPhone: `Loved "…"`, `Liked "…"`, `Disliked "…"`, `Laughed at "…"`, `Emphasized "…"`, `Questioned "…"`,
///   `Reacted 🎉 to "…"`, `Removed a heart from "…"`, and `Loved an image` for a picture
///
/// The quote can be curly or straight, and a long one is cut short with "…". A reaction found here, with the
/// message it names, is drawn as a chip on that message and not as a bubble of its own ([foldReactions]).
class ParsedReaction {
  const ParsedReaction({required this.emoji, this.quote, this.media = false, this.removed = false});

  final String emoji;

  /// The text of the message reacted to, as quoted (maybe cut short). Null when it was a picture ([media]).
  final String? quote;
  final bool media;

  /// "Removed ❤️ from …": takes the sender's reaction off.
  final bool removed;
}

const _verbs = {
  'loved': '❤️',
  'liked': '👍',
  'disliked': '👎',
  'laughed at': '😂',
  'emphasized': '‼️',
  'emphasised': '‼️',
  'questioned': '❓',
};

const _removedNouns = {
  'a heart': '❤️',
  'a like': '👍',
  'a dislike': '👎',
  'a laugh': '😂',
  'an exclamation': '‼️',
  'an exclamation mark': '‼️',
  'an emphasis': '‼️',
  'a question mark': '❓',
};

const _open = '"“”„‟\'‘’';
const _close = '"“”‟\'‘’';

/// "an image", "a photo", "a video" and the like: a reaction to a picture or other attachment.
final _mediaNoun = RegExp(r'^(an? )(image|photo|picture|video|gif|attachment|movie|sticker|audio message|voice message)$', caseSensitive: false);

/// A text's quoted part: what is between the first opening quote and the last closing one, if those are its ends.
String? _quoted(String rest) {
  final s = rest.trim();
  if (s.length < 2 || !_open.contains(s[0]) || !_close.contains(s[s.length - 1])) return null;
  return s.substring(1, s.length - 1);
}

/// A run of emoji (with its joiners and variation selectors), and nothing else.
bool _isEmoji(String s) {
  if (s.isEmpty || s.runes.length > 12) return false;
  for (final r in s.runes) {
    final emojiLike = r >= 0x1F000 ||
        (r >= 0x2190 && r <= 0x2BFF) ||
        (r >= 0x2300 && r <= 0x23FF) ||
        r == 0x200D ||
        r == 0xFE0F ||
        r == 0x20E3 ||
        (r >= 0x1F1E6 && r <= 0x1F1FF) ||
        (r >= 0xE0020 && r <= 0xE007F) ||
        r == 0x00A9 ||
        r == 0x00AE ||
        r == 0x203C ||
        r == 0x2049;
    if (!emojiLike) return false;
  }
  return true;
}

/// Reads [text] as a reaction, or null when it is an ordinary message.
ParsedReaction? parseReaction(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 2000 || t.contains('\n')) return null;
  final lower = t.toLowerCase();

  ParsedReaction? target(String emoji, String rest, {bool removed = false}) {
    final q = _quoted(rest);
    if (q != null && q.trim().isNotEmpty) return ParsedReaction(emoji: emoji, quote: q, removed: removed);
    if (_mediaNoun.hasMatch(rest.trim())) return ParsedReaction(emoji: emoji, media: true, removed: removed);
    return null;
  }

  // iPhone's words: Loved "…", Laughed at an image.
  for (final e in _verbs.entries) {
    if (lower.startsWith('${e.key} ')) {
      final r = target(e.value, t.substring(e.key.length + 1));
      if (r != null) return r;
    }
  }

  // Reacted 🎉 to "…" (both phones).
  final reacted = RegExp(r'^Reacted (.+?) to (.+)$', caseSensitive: false).firstMatch(t);
  if (reacted != null && _isEmoji(reacted.group(1)!)) {
    final r = target(reacted.group(1)!, reacted.group(2)!);
    if (r != null) return r;
  }

  // Removed a heart from "…" / Removed ❤️ from "…".
  final removed = RegExp(r'^Removed (.+?) from (.+)$', caseSensitive: false).firstMatch(t);
  if (removed != null) {
    final what = removed.group(1)!;
    final emoji = _removedNouns[what.toLowerCase()] ?? (_isEmoji(what) ? what : null);
    if (emoji != null) {
      final r = target(emoji, removed.group(2)!, removed: true);
      if (r != null) return r;
    }
  }

  // Google Messages: ❤️ to "…".
  final to = RegExp(r'^(\S+) to (.+)$').firstMatch(t);
  if (to != null && _isEmoji(to.group(1)!)) {
    final r = target(to.group(1)!, to.group(2)!);
    if (r != null) return r;
  }
  return null;
}

String _norm(String s) => s
    .replaceAll(RegExp('[“”„‟]'), '"')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// Whether [body] is the message [quote] names: the same text, or its start when the quote was cut short.
bool quoteMatches(String quote, String body) {
  final q = _norm(quote);
  final b = _norm(body);
  if (q.isEmpty || b.isEmpty) return false;
  if (q == b) return true;
  for (final cut in const ['…', '...']) {
    if (q.endsWith(cut)) {
      final head = q.substring(0, q.length - cut.length).trim();
      if (head.length >= 3 && b.startsWith(head)) return true;
    }
  }
  return false;
}

/// One person's reaction on a message. [by] is their number, or '' for you.
class Reaction {
  const Reaction({required this.emoji, required this.by, required this.date});
  final String emoji;
  final String by;
  final DateTime date;
}

class Folded {
  const Folded({required this.messages, required this.reactions});

  /// The messages to draw, newest first, without the reaction texts that found their message.
  final List<Message> messages;

  /// The reactions on each message, by [Message.key], oldest first.
  final Map<String, List<Reaction>> reactions;
}

/// Takes the reaction texts out of [newestFirst] and hangs each on the message it names: the newest message before
/// it whose text matches the quote (or the newest picture, for "an image"). A reaction that names no message here
/// stays an ordinary bubble, so nothing is ever hidden that can't be shown somewhere.
///
/// One person keeps one reaction of each kind on a message; "Removed …" takes theirs off. You can react with several
/// kinds, as both phones allow.
Folded foldReactions(List<Message> newestFirst) {
  final hidden = <String>{};
  final reactions = <String, List<Reaction>>{};
  final oldestFirst = newestFirst.reversed.toList();
  for (var i = 0; i < oldestFirst.length; i++) {
    final m = oldestFirst[i];
    if (m.attachments.isNotEmpty) continue;
    final r = parseReaction(m.body);
    if (r == null) continue;
    Message? found;
    for (var j = i - 1; j >= 0 && j >= i - 400; j--) {
      final c = oldestFirst[j];
      if (hidden.contains(c.key)) continue;
      if (r.media ? c.attachments.isNotEmpty : quoteMatches(r.quote!, c.body)) {
        found = c;
        break;
      }
    }
    if (found == null) continue;
    hidden.add(m.key);
    final by = m.outgoing ? '' : m.address;
    final list = reactions.putIfAbsent(found.key, () => []);
    list.removeWhere((x) => _samePerson(x.by, by) && x.emoji == r.emoji);
    if (!r.removed) list.add(Reaction(emoji: r.emoji, by: by, date: m.date));
    if (list.isEmpty) reactions.remove(found.key);
  }
  return Folded(messages: [for (final m in newestFirst) if (!hidden.contains(m.key)) m], reactions: reactions);
}

bool _samePerson(String a, String b) {
  String d(String s) {
    final x = s.replaceAll(RegExp(r'[^0-9]'), '');
    return x.length > 10 ? x.substring(x.length - 10) : x;
  }
  if (a.isEmpty || b.isEmpty) return a == b;
  final da = d(a), db = d(b);
  return da.isNotEmpty ? da == db : a == b;
}

/// What a reaction text says in a conversation's one-line preview: "❤️ to “See you at 7”".
String? reactionSnippet(String text) {
  final r = parseReaction(text);
  if (r == null) return null;
  final what = r.media ? 'a picture' : '“${r.quote}”';
  return r.removed ? 'Removed ${r.emoji} from $what' : 'Reacted ${r.emoji} to $what';
}
