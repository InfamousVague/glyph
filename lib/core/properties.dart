/// A ticket's vocabulary as a list reads it: `type: ticket` in a note's front matter, its key and its status, and
/// where that status stands in its notebook's workflow. The part of `src/app/core/properties.ts` a ticket's mark
/// draws from (`notes/TicketMark.tsx`): [propertyList], [isTicket], [statusesOf], [statusCategory], [issueKeyOf],
/// [ticketIdOf], [ticketOf].
///
/// What differs: [Ticket] carries the id, the status, its category and the assignee. The rest of the web's `Ticket`
/// (priority, due, start, estimate, blocked-by, parent, labels) and every writer come with the ticket's own panel.
library;

import 'package:flutter/foundation.dart';
import 'front_matter.dart';

final RegExp _linksOnly = RegExp(r'^\[\[[^\]\n]*\]\](?:\s*,\s*\[\[[^\]\n]*\]\])*$');

/// [text] cut at its commas, but not at one inside quotes that open an item, or inside brackets.
List<String> _cutAtCommas(String text) {
  final parts = <String>[];
  var start = 0;
  var depth = 0;
  String? quote;
  for (var at = 0; at < text.length; at += 1) {
    final char = text[at];
    if (quote != null) {
      if (char == r'\' && quote == '"') {
        at += 1;
      } else if (char == quote && quote == "'" && at + 1 < text.length && text[at + 1] == "'") {
        at += 1;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if ((char == '"' || char == "'") && text.substring(start, at).trim().isEmpty) {
      quote = char;
    } else if (char == '[') {
      depth += 1;
    } else if (char == ']') {
      depth = depth > 0 ? depth - 1 : 0;
    } else if (char == ',' && depth == 0) {
      parts.add(text.substring(start, at));
      start = at + 1;
    }
  }
  parts.add(text.substring(start));
  return parts;
}

/// A value as a list: a flow list, `[bug, ui]`, or names with commas, `Matt, Claude`. Each item with its quotes off
/// and trimmed, empty ones dropped. A value of note links alone, `[[GHO-9]]`, is that link, not a list inside a list.
List<String> propertyList(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return const [];
  final flow = text.startsWith('[') && text.endsWith(']') && !_linksOnly.hasMatch(text);
  return _cutAtCommas(flow ? text.substring(1, text.length - 1) : text).map((item) => unquoted(item.trim()).trim()).where((item) => item.isNotEmpty).toList();
}

/// The `type:` that makes a note a ticket (`TICKET_TYPE`).
const String ticketType = 'ticket';

/// Whether a note is a ticket: its front matter says `type: ticket`, in any case.
bool isTicket(String body) => frontMatterValue(body, 'type')?.trim().toLowerCase() == ticketType;

/// The workflow a ticket moves through when its notebook names none (`DEFAULT_STATUSES`).
const List<String> defaultStatuses = ['Backlog', 'To do', 'In progress', 'In review', 'Done'];

/// A notebook's own workflow, its `statuses:` list, each once; the default where it names none or there is no notebook.
List<String> statusesOf(String? notebook) {
  final seen = <String>{};
  final own = propertyList(notebook == null || notebook.isEmpty ? null : frontMatterValue(notebook, 'statuses')).where((status) => seen.add(status.toLowerCase())).toList();
  return own.isNotEmpty ? own : [...defaultStatuses];
}

/// Where a status stands, as Jira groups them: not started, under way, or finished with (`StatusCategory`).
enum StatusCategory { todo, doing, done }

/// A status as its words are compared: lower case, no apostrophes, a space between words. "Won't do" is "wont do".
String _statusWords(String status) =>
    status.toLowerCase().replaceAll(RegExp("['’]"), '').replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

const Set<String> _done = {
  'done', 'closed', 'resolved', 'complete', 'completed', 'finished', 'shipped', 'released', 'merged', 'fixed', 'cancelled', 'canceled', 'duplicate', 'rejected',
  'declined', 'abandoned', 'obsolete', 'archived', 'wont do', 'wont fix', //
};
const Set<String> _todo = {'backlog', 'to do', 'todo', 'open', 'new', 'ready', 'planned', 'triage', 'icebox', 'inbox', 'next', 'later', 'not started'};
const Set<String> _doing = {'doing', 'review', 'reviewing', 'testing', 'qa', 'started', 'active', 'blocked', 'wip', 'ongoing', 'working', 'building'};

/// Whether a board's column is its Done lane: a name that starts or ends with the word (core/itemSyntax.ts `isDoneName`).
bool isDoneName(String name) => RegExp(r'^done\b|\bdone$', caseSensitive: false).hasMatch(name.trim());

/// Where a status stands, by its words and in any case. A name none of the lists know is placed by the workflow it is
/// in, where one is given: its first status not started, its last done, any between under way.
StatusCategory statusCategory(String? status, [List<String>? workflow]) {
  final words = _statusWords(status ?? '');
  if (words.isEmpty) return StatusCategory.todo;
  if (_done.contains(words) || isDoneName(words)) return StatusCategory.done;
  if (_todo.contains(words)) return StatusCategory.todo;
  if (_doing.contains(words) || words.startsWith('in ')) return StatusCategory.doing;
  final at = workflow?.indexWhere((each) => _statusWords(each) == words) ?? -1;
  if (workflow == null || at < 0) return StatusCategory.todo;
  if (at == workflow.length - 1 && at > 0) return StatusCategory.done;
  return at == 0 ? StatusCategory.todo : StatusCategory.doing;
}

final RegExp _issueKey = RegExp(r'^[A-Z][A-Z0-9]{1,9}-[1-9]\d{0,5}$');

/// [text] as an issue key, trimmed and upper-cased (`gho-12` is `GHO-12`), or null.
String? issueKeyOf(String? text) {
  final key = (text ?? '').trim().toUpperCase();
  return _issueKey.hasMatch(key) ? key : null;
}

/// A ticket's id, its `id:` as an issue key; null where it has none or it is not one.
String? ticketIdOf(String body) => issueKeyOf(frontMatterValue(body, 'id'));

/// A ticket's properties as its mark shows them (`Ticket`, in part).
@immutable
class Ticket {
  const Ticket({required this.id, required this.status, required this.category, required this.assignee});
  final String? id;

  /// As written; null where it has none.
  final String? status;

  /// Where the status stands, in the workflow given.
  final StatusCategory category;

  /// As written, without an at sign.
  final String? assignee;
}

/// A ticket's properties, or null where the note is not one. [statuses] is its notebook's workflow ([statusesOf]).
Ticket? ticketOf(String body, [List<String>? statuses]) {
  if (!isTicket(body)) return null;
  String? said(String key) {
    final value = frontMatterValue(body, key)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final status = said('status');
  final assignee = said('assignee')?.replaceFirst(RegExp(r'^@+'), '').trim();
  return Ticket(id: ticketIdOf(body), status: status, category: statusCategory(status, statuses), assignee: assignee == null || assignee.isEmpty ? null : assignee);
}
