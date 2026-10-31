/// Who watches a ticket (Matt, 2026-10-31, of the ticket features: "Watch" on a ticket, auto-watch for the creator,
/// the assignee and anyone who comments or is mentioned, kept as `watchers: [@matt, @sam]` in front matter). Plain
/// Markdown, as everything a ticket holds is:
///
///     ---
///     type: ticket
///     id: GHO-12
///     status: In review
///     assignee: sam
///     watchers: ["@matt", "@sam"]
///     ---
///
/// The list is written across with each handle quoted, since YAML keeps `@` for itself at the start of a value
/// (lib/core/properties.dart `yamlList`), and read with or without the at sign and the quotes, `watchers: matt, sam`
/// too. A person is the same person in any case ([handleKey]); the list keeps the case it was written in.
///
/// **Who is made a watcher** ([autoWatchers]), by a change from one text of the note to the next made on this device:
/// - the person who made it a ticket (the creator; lib/book/tickets.dart `newTicketBody` asks [ticketCreator] for a
///   ticket made outside the editor);
/// - the assignee, once one is picked or a new one is;
/// - whoever wrote a comment or a reply in its comments fence (lib/comments/format.dart);
/// - whoever is newly mentioned in its words, `@sam` (lib/mentions/mention_syntax.dart): a name still being typed,
///   `@sa` with the caret after it, waits until it is finished, so `@sa` on the way to `@sam` makes nobody a watcher.
///
/// Someone who has unwatched is not made a watcher again by the same thing standing still: only a change that adds
/// (a new assignee, a new comment, a new mention) does. Pure, so each is a test (test/book_core/ticket_watchers_test.dart).
library;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../comments/format.dart' show readComments;
import '../core/front_matter.dart' show frontMatterValue;
import '../core/item_syntax.dart' show jsTrim;
import '../core/properties.dart';
import '../mentions/mention_syntax.dart' show handleKey, mentionsInBody;

/// The front matter key the watchers are kept under.
const String watchersKey = 'watchers';

/// Who makes the tickets made on this device outside the editor: the account's handle, or null signed out, where a new
/// ticket names no watcher (lib/root/account_wiring.dart keeps it up with the account).
final ValueNotifier<String?> ticketCreator = ValueNotifier<String?>(null);

final RegExp _handle = RegExp(r'^[\p{L}\p{N}][\p{L}\p{N}_.-]*$', unicode: true);

/// [text] as a handle, its at signs and spaces off; null where it is not one (a name with a space, `Priya Shah`).
String? handleOf(String? text) {
  var word = jsTrim(text ?? '');
  while (word.startsWith('@')) {
    word = word.substring(1);
  }
  return _handle.hasMatch(word) ? word : null;
}

/// A ticket's watchers, as written, each once, without the at sign.
List<String> watchersOf(String body) {
  final seen = <String>{};
  return [
    for (final item in propertyList(frontMatterValue(body, watchersKey)))
      if (handleOf(item) case final handle? when seen.add(handleKey(handle))) handle,
  ];
}

/// Whether [handle] watches the ticket.
bool watches(String body, String? handle) {
  final want = handleOf(handle);
  return want != null && watchersOf(body).any((each) => handleKey(each) == handleKey(want));
}

/// The body with [handles] as its whole list of watchers: none takes the key off.
String withWatchersList(String body, List<String> handles) => withProperty(body, watchersKey, [for (final handle in handles) '@$handle']);

/// The body with [handle] watching ([on]) or not; the body as it was where nothing changes.
String withWatcher(String body, String handle, bool on) {
  final who = handleOf(handle);
  if (who == null) return body;
  final now = watchersOf(body);
  final has = now.any((each) => handleKey(each) == handleKey(who));
  if (has == on) return body;
  return withWatchersList(body, on ? [...now, who] : [for (final each in now) if (handleKey(each) != handleKey(who)) each]);
}

/// The body with each of [handles] watching that is not already.
String withWatchers(String body, Iterable<String> handles) {
  var next = body;
  final now = watchersOf(body);
  final added = <String>[...now];
  for (final handle in handles) {
    final who = handleOf(handle);
    if (who == null || added.any((each) => handleKey(each) == handleKey(who))) continue;
    added.add(who);
  }
  if (added.length != now.length) next = withWatchersList(body, added);
  return next;
}

Map<String, int> _counted(Iterable<String> handles) {
  final out = <String, int>{};
  for (final handle in handles) {
    out.update(handleKey(handle), (n) => n + 1, ifAbsent: () => 1);
  }
  return out;
}

/// Each comment's author in the note, counted: a thread's head and each reply.
Map<String, int> _commenters(String body) {
  if (!body.contains('comments')) return const {};
  final read = readComments(body);
  return _counted([
    for (final thread in read.threads) ...[thread.head.by, for (final reply in thread.replies) reply.by],
  ]);
}

/// Each person mentioned in the words, counted, leaving out a name the caret is at the end of: still being typed.
Map<String, int> _mentioned(String body, {int? caretLine, int? caretColumn}) => _counted([
      for (final found in mentionsInBody(body))
        if (found.mention.person && !(found.line == caretLine && found.mention.to == caretColumn)) found.mention.value,
    ]);

/// The people a change from [before] to [after] makes watchers of the ticket, as handles, in the order found, none
/// who watch it already (see the header). [me] is who made the change; [caret], where given, is the caret's offset in
/// [after], so a name being typed there is left until it is finished, and so is an assignee being typed in the front
/// matter. Nothing for a note that is not a ticket after the change.
List<String> autoWatchers(String before, String after, {required String? me, int? caret}) {
  if (before == after || !isTicket(after)) return const [];
  final out = <String>[];
  void add(String? handle) {
    final who = handleOf(handle);
    if (who != null && who != 'me' && !out.any((each) => handleKey(each) == handleKey(who))) out.add(who);
  }

  // The creator: the change that made it a ticket.
  if (!isTicket(before)) add(me);
  // The assignee, once picked: not while the caret is on its line in the front matter, being typed.
  final was = ticketOf(before)?.assignee, now = ticketOf(after)?.assignee;
  if (now != null && handleKey(now) != handleKey(was ?? '')) {
    final typing = caret != null && _onAssigneeLine(after, caret);
    if (!typing) add(now);
  }
  // Whoever wrote a comment.
  if (after.contains('comments')) {
    final had = _commenters(before);
    for (final MapEntry(key: handle, value: count) in _commenters(after).entries) {
      if (count > (had[handle] ?? 0)) add(handle);
    }
  }
  // Whoever is newly mentioned, a name finished.
  if (after.contains('@')) {
    int? line, column;
    if (caret != null) {
      final upTo = after.substring(0, caret.clamp(0, after.length));
      line = '\n'.allMatches(upTo).length + 1;
      column = upTo.length - (upTo.lastIndexOf('\n') + 1);
    }
    final had = _mentioned(before);
    for (final MapEntry(key: handle, value: count) in _mentioned(after, caretLine: line, caretColumn: column).entries) {
      if (count > (had[handle] ?? 0)) add(handle);
    }
  }
  final watching = {for (final each in watchersOf(after)) handleKey(each)};
  return [for (final each in out) if (!watching.contains(handleKey(each))) each];
}

bool _onAssigneeLine(String body, int caret) {
  final start = body.lastIndexOf('\n', caret > 0 ? caret - 1 : 0) + 1;
  final end = body.indexOf('\n', caret);
  final line = body.substring(start, end < 0 ? body.length : end);
  return line.trimLeft().toLowerCase().startsWith('assignee');
}

/// [after] with [autoWatchers] added to its watchers, or null where nobody is.
String? withAutoWatch(String before, String after, {required String? me, int? caret}) {
  final added = autoWatchers(before, after, me: me, caret: caret);
  return added.isEmpty ? null : withWatchers(after, added);
}
