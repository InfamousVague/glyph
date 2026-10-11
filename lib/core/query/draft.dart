/// What a ticket made from a lane of a query's board must say for the query to list it in that lane (Matt: "add the
/// ability to add new tickets to query boards from the board like we can on the standard board"). A port of
/// `src/app/core/query/draft.ts`: the lane's value in the field the board groups by, the notebook `from:` names (its
/// pages are what `[[A notebook]]` lists), the labels its `#tag`s ask for, the person its `@name` does, and every
/// `field = value` its `where:` insists on. Only what every record listed must have is taken: a source or a test
/// under `or` or `not` names one of several ways in, so it is left to the person. A ticket made from what is taken
/// may still miss a `<` or a `contains`; the board's lane is the one thing it is sure to match.
///
/// Tickets only: a query of to-dos has no one note a new line belongs in, and a query of notes no workflow its lanes
/// come from. Pure; the screen makes the note.
///
/// What differs: a draft's fields are a list of `(field, value)` records, the web's pairs.
library;

import 'read.dart';

class TicketDraft extends QueryData {
  const TicketDraft({required this.link, required this.fields, required this.labels});

  /// The note `from: [[…]]` names first: the notebook the ticket goes in, or a note it links to; null for neither.
  final String? link;

  /// Front-matter properties to set, in order, the lane's last so nothing in `where:` overrides it.
  final List<(String field, String value)> fields;

  /// The `#tag`s `from:` asks for, as the ticket's labels.
  final List<String> labels;

  @override
  Object? toJson() => {
        'link': link,
        'fields': [for (final (field, value) in fields) [field, value]],
        'labels': labels,
      };
}

/// Fields a ticket's maker sets or the library reads from elsewhere, never copied from a test.
const Set<String> _made = {'title', 'id', 'key', 'type', 'note', 'created', 'updated', 'done', 'checked', 'tags', 'labels', 'text'};

/// Whether a board drawn from [query] can make its tickets from a lane.
bool draftsTickets(Query query) => query.kind == QueryKind.tickets;

final RegExp _hash = RegExp('^#');

/// The ticket a lane of [query]'s board makes: [group] is the field the board is grouped by as it ran (a board left
/// ungrouped is a ticket's status, run.dart), and [lane] the lane's value in it, or null for a board of one lane.
TicketDraft? ticketDraft(Query query, String? group, String? lane) {
  if (!draftsTickets(query)) return null;
  final sources = _required(query.from);
  String? link;
  String? person;
  final labels = <String>[];
  for (final source in sources) {
    switch (source) {
      case LinkSource(:final title):
        link ??= title;
      case TagSource(:final tag):
        labels.add(tag.replaceFirst(_hash, ''));
      case PersonSource(:final name):
        person ??= name;
      default:
    }
  }
  final fields = <String, String>{};
  if (person != null && person.isNotEmpty) fields['assignee'] = person;
  for (final test in _insisted(query.where)) {
    final field = test.field.toLowerCase();
    if (_made.contains(field)) continue;
    final value = _literalText(test.value);
    if (value != null) fields[field] = value;
  }
  final grouped = group?.toLowerCase();
  if (grouped != null && grouped.isNotEmpty) {
    fields.remove(grouped);
    if (lane != null) fields[grouped] = lane;
  }
  return TicketDraft(link: link, fields: [for (final MapEntry(:key, :value) in fields.entries) (key, value)], labels: labels);
}

/// The sources every record must come from: `from:`'s own, or each side of an `and`, never one under `or` or `not`.
List<Source> _required(Source? from) => switch (from) {
      null => const [],
      AndSource(:final all) => [for (final each in all) ..._required(each)],
      OrSource() || NotSource() => const [],
      _ => [from],
    };

/// The `field = value` tests every record must pass: `where:`'s own, or each side of an `and`.
List<Compare> _insisted(Condition? where) => switch (where) {
      null => const [],
      AndCondition(:final all) => [for (final each in all) ..._insisted(each)],
      Compare(op: Op.eq) => [where],
      _ => const [],
    };

/// A value as a front-matter property writes it; null for `empty` or a day counted from today, which says no one
/// day.
String? _literalText(Literal value) => switch (value) {
      WordsLiteral(:final text) || NumberLiteral(:final text) => text,
      DateLiteral(:final day) => day,
      _ => null,
    };
