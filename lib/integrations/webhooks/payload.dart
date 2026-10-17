/// What an outgoing webhook says (docs/INTEGRATIONS.md, §1): the JSON body, its signature, and the lines a change
/// added or changed. Pure, so every shape of change is a test.
///
/// ```json
/// { "event": "note.edited", "at": "2026-10-17T18:00:00Z",
///   "note": { "id": "...", "title": "...", "workspace": "Family", "url": "ghostmd://note/<id>",
///             "body": "<markdown>", "changed": ["- [x] Buy a crib"] } }
/// ```
///
/// `changed` is a line diff of the note as it was before the run of saves and as it is after: the lines of the new
/// body that are not among the lines both share in order (a longest common subsequence, after the shared start and
/// end are taken off). A line only moved reads as changed where it left the order; a line only taken out is in no
/// list, since the body says what is left.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../../core/note_text.dart' show listMarker, noteTitle;
import 'setup.dart';

/// The header a signed body carries.
const String signatureHeader = 'X-Ghost-Signature';

/// `sha256=<hex HMAC-SHA256 of the body>`, with [secret] as the key.
String signatureOf(String secret, List<int> body) => 'sha256=${crypto.Hmac(crypto.sha256, utf8.encode(secret)).convert(body)}';

/// A note's address in the app.
String noteLink(String id) => 'ghostmd://note/$id';

/// [at] as the body says it: UTC, to the second, `2026-10-17T18:00:00Z`.
String wireTime(DateTime at) {
  final utc = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}

/// The most lines either side of a change compared line by line; past it, a line is changed where the old body did
/// not have it at all. Typing changes a few lines, and a pasted book should not cost a second.
const int _diffCells = 4000000;

/// The lines of [after] added or changed since [before].
List<String> changedLines(String before, String after) {
  if (before == after) return const [];
  final old = before.isEmpty ? const <String>[] : before.split('\n');
  final now = after.isEmpty ? const <String>[] : after.split('\n');
  var start = 0;
  while (start < old.length && start < now.length && old[start] == now[start]) {
    start += 1;
  }
  var oldEnd = old.length, nowEnd = now.length;
  while (oldEnd > start && nowEnd > start && old[oldEnd - 1] == now[nowEnd - 1]) {
    oldEnd -= 1;
    nowEnd -= 1;
  }
  final a = old.sublist(start, oldEnd), b = now.sublist(start, nowEnd);
  final List<String> added;
  if (a.isEmpty) {
    added = b;
  } else if (a.length * b.length > _diffCells) {
    final had = a.toSet();
    added = [for (final line in b) if (!had.contains(line)) line];
  } else {
    // The longest common subsequence's table, from the end: kept[i][j] is how many of a[i..] and b[j..] it holds.
    final width = b.length + 1;
    final kept = List<int>.filled((a.length + 1) * width, 0);
    for (var i = a.length - 1; i >= 0; i -= 1) {
      for (var j = b.length - 1; j >= 0; j -= 1) {
        kept[i * width + j] = a[i] == b[j] ? kept[(i + 1) * width + j + 1] + 1 : (kept[(i + 1) * width + j] >= kept[i * width + j + 1] ? kept[(i + 1) * width + j] : kept[i * width + j + 1]);
      }
    }
    added = [];
    var i = 0, j = 0;
    while (j < b.length) {
      if (i < a.length && a[i] == b[j]) {
        i += 1;
        j += 1;
      } else if (i < a.length && kept[(i + 1) * width + j] >= kept[i * width + j + 1]) {
        i += 1;
      } else {
        added.add(b[j]);
        j += 1;
      }
    }
  }
  return [for (final line in added) if (line.trim().isNotEmpty) line];
}

final RegExp _doneItem = RegExp('^\\s*$listMarker\\s+\\[[xX]\\]\\s+(?<words>.*)\$');
final RegExp _openItem = RegExp('^\\s*$listMarker\\s+\\[ \\]\\s+(?<words>.*)\$');

/// The lines of [changed] that tick a to-do [before] had open: the same words, `[ ]` then, `[x]` now.
List<String> ticked(String before, List<String> changed) {
  final open = <String>{
    for (final line in before.split('\n'))
      if (_openItem.firstMatch(line) case final match?) match.namedGroup('words')!.trim(),
  };
  return [
    for (final line in changed)
      if (_doneItem.firstMatch(line) case final match? when open.contains(match.namedGroup('words')!.trim())) line,
  ];
}

/// What a run of saves of one note was, as a hook hears it.
class NoteChange {
  const NoteChange({required this.created, required this.changed, required this.ticked});

  /// The note was made in this run.
  final bool created;

  /// The lines added or changed ([changedLines]).
  final List<String> changed;

  /// The to-dos ticked ([ticked]).
  final List<String> ticked;
}

/// What a run of saves from [before] (null for a note made in it) to [after] was.
NoteChange changeOf(String? before, String after) {
  final changed = changedLines(before ?? '', after);
  return NoteChange(created: before == null, changed: changed, ticked: before == null ? const [] : ticked(before, changed));
}

/// Which of [hook]'s events [change] is, or null for none it asked for: a note made is `note.created`, and nothing
/// else; a to-do ticked is `todo.done` where that is asked for, else `note.edited`; any other change, `note.edited`.
WebhookEvent? eventFor(Set<WebhookEvent> events, NoteChange change) {
  if (change.created) return events.contains(WebhookEvent.created) ? WebhookEvent.created : null;
  if (change.changed.isEmpty) return null;
  if (change.ticked.isNotEmpty && events.contains(WebhookEvent.todoDone)) return WebhookEvent.todoDone;
  return events.contains(WebhookEvent.edited) ? WebhookEvent.edited : null;
}

/// The body sent: the event, when, and the note.
String payloadOf({required WebhookEvent event, required DateTime at, required String id, required String body, String? workspace, required List<String> changed}) => jsonEncode({
      'event': event.wire,
      'at': wireTime(at),
      'note': {
        'id': id,
        'title': noteTitle(body),
        'workspace': workspace,
        'url': noteLink(id),
        'body': body,
        'changed': changed,
      },
    });
