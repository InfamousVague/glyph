/// Sending a note's list items somewhere, as the Notion and GitHub plugins do: each item becomes a thing there (a
/// task, an issue), and its words become a link to it, edited into the note so it is one undo per item and saves
/// like typing. A port of `src/app/plugins/sendItems.ts`.
///
/// - **The same words are never made twice.** What has just been sent from a note is remembered by the note, the
///   words and where they went, for five minutes, and sending them again there marks the line with what already
///   exists. The same words sent from the same note to another board or repo are a new thing there.
/// - **A made thing always gets its link.** The note can change while the service answers, so the item is found
///   again by its words after each send and, failing that, by the line it was on if that is still an item. The
///   line is not used when it now holds another item of the same send.
/// - **A failure stops the run** and is said, in the service's words, before anything else is.
///
/// What differs: the clock can be handed in ([ItemSender.now]) for the tests.
library;

import '../core/item_links.dart' show itemAt, linkedLine;
import 'details_cache.dart' show failureWords;
import 'types.dart';

/// How long a send is remembered: a second press within it marks the line rather than making another.
const Duration sentFor = Duration(minutes: 5);

/// What a send did (`Sent`).
class Sent {
  const Sent({required this.sent, required this.marked});

  /// How many were made this time.
  final int sent;

  /// How many lines were marked, whether with something made now or something made a moment ago.
  final int marked;
}

/// One item to send: its words, and the 1-based line it was on when that is known.
typedef SendItem = ({String text, int? line});

/// A sender whose links are marked `[mark](url)` (the plugin's id), with its own memory of what it sent
/// (`itemSender(mark)`).
class ItemSender {
  ItemSender(this.mark, {int Function()? now}) : now = now ?? _clock;

  final String mark;
  final int Function() now;

  static int _clock() => DateTime.now().millisecondsSinceEpoch;

  final Map<String, ({String url, int at})> _justSent = {};

  String _keyOf(String noteId, String to, String text) => '$noteId\u0000$to\u0000${text.trim().toLowerCase()}';

  String? _alreadySent(String key) {
    final known = _justSent[key];
    if (known == null) return null;
    if (now() - known.at > sentFor.inMilliseconds) {
      _justSent.remove(key);
      return null;
    }
    return known.url;
  }

  /// The item's line, marked with its link: by its words, or failing that the line it was on if that is still an
  /// item and not one of [sending] (the words of the whole send).
  bool _markItem(NoteEditing editing, SendItem item, String url, Set<String> sending) {
    String link(String text) => linkedLine(text, url, mark);
    if (editing.replaceLine((text, line) => itemAt(text, line)?.text == item.text, link)) return true;
    final was = item.line;
    if (was == null) return false;
    return editing.replaceLine((text, line) {
      final there = line == was ? itemAt(text, line) : null;
      return there != null && !sending.contains(there.text);
    }, link);
  }

  /// Sends [items] from the note on screen to [to] (the board's or the repo's id): [make] makes each and answers
  /// its address. Answers what was sent and marked, or null when a [make] failed, which has been said on the note
  /// already.
  Future<Sent?> send(List<SendItem> items, String to, NoteEditing editing, Future<String> Function(String text) make) async {
    final sending = {for (final item in items) item.text};
    var sent = 0;
    var marked = 0;
    for (final item in items) {
      final key = _keyOf(editing.noteId, to, item.text);
      // Sent a moment ago: mark the line with what already exists rather than making a second one.
      final had = _alreadySent(key);
      if (had != null && had.isNotEmpty) {
        if (_markItem(editing, item, had, sending)) marked += 1;
        continue;
      }
      try {
        final url = await make(item.text);
        _justSent[key] = (url: url, at: now());
        sent += 1;
        if (_markItem(editing, item, url, sending)) marked += 1;
      } catch (failure) {
        editing.say(failureWords(failure));
        return null;
      }
    }
    return Sent(sent: sent, marked: marked);
  }

  /// For the tests: what was sent is otherwise kept in memory for the app's life, five minutes a send.
  void forget() => _justSent.clear();
}
