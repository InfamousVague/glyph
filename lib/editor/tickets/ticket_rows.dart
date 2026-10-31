/// What a ticket's panel shows and how it says it (ticket_panel.dart, tickets.dart; docs/DESIGN.md §157): which
/// rows, which keys go under it on the quiet line, a day in words, a due day that has passed, and a link to another
/// ticket as it is written. Ports `src/app/editor/ticketRows.ts`. Pure, apart from the drawing, so each is a test
/// (test/editor/tickets/ticket_rows_test.dart).
///
/// What differs:
/// - `PanelKey`, a union of nine strings, stays a `String`: the keys are the note's own words, and a row is found by
///   its key wherever it is used.
/// - [dayLabel] is the chips' (items/field_chips.dart), which says a day the same way to the letter, in the two ways
///   of writing a date this app has a table for (core/locale_dates.dart), the phone's own once it has said which;
///   the page asked `Intl` for the device's.
/// - [linksValue] answers a `String`, a `List<String>` or null, as `withProperty` takes them.
library;

import '../../book/tickets.dart' show TicketChoice;
import '../../core/days.dart' show daysBetween;
import '../../core/properties.dart';

export '../items/field_chips.dart' show dayLabel;

/// The keys the panel always shows a row for, set or not: what a ticket is mostly asked (`ALWAYS_SHOWN`).
const List<String> alwaysShown = <String>['status', 'assignee', 'priority', 'due'];

/// The rows the panel shows past those once set, or when More is pressed (`SHOWN_WHEN_SET`). A cycle and a milestone
/// are the port's own (Matt, 2026-10-31; lib/core/planning).
const List<String> shownWhenSet = <String>['start', 'estimate', 'cycle', 'blocked-by', 'parent', 'milestone', 'labels'];

/// The rows Simple mode keeps behind More even once set (lib/core/preferences.dart `simple`): a team's planning,
/// which a person keeping their own tickets need not see.
const Set<String> advancedRows = <String>{'cycle', 'milestone'};

/// Rows the panel shows only once they are set, never offered behind More: a ticket's component (the port's own,
/// Matt, 2026-10-31), so the panel of a ticket without one is the page's to the letter.
const List<String> shownOnlyWhenSet = <String>['component'];

/// Keys the panel never names under itself: the ticket's own type, its id (the panel's heading), and how the note
/// looks; its watchers and what it duplicates, which its team's part shows (ticket_follow.dart); its component,
/// which is a row of the panel's (the port's own, 2026-10-31); and its time spent, which has a row of its own
/// (ticket_work.dart).
const Set<String> _unsaid = <String>{'type', 'id', 'look', 'watchers', 'duplicate-of', 'component', 'spent'};

/// The panel's rows for a ticket's front matter: the four always, then any of the rest that is set, or all of them
/// with [more]. In [simple] mode the advanced ones wait for More, set or not; where the host draws no planning
/// ([planned] false), they are rows only once written.
List<String> panelRows(String front, [bool more = false, bool simple = false, bool planned = true]) {
  final set = <String>{
    for (final property in propertiesOf(front))
      if (propertyList(property.value).isNotEmpty) property.key.toLowerCase(),
  };
  // `epic:` is read as the parent (lib/core/properties.dart), so its row is Parent's.
  if (set.contains('epic')) set.add('parent');
  bool shows(String key) {
    if (!planned && advancedRows.contains(key)) return set.contains(key);
    return more || (set.contains(key) && !(simple && advancedRows.contains(key)));
  }

  return <String>[...alwaysShown, ...shownWhenSet.where(shows), ...shownOnlyWhenSet.where(set.contains)];
}

/// The rows waiting behind More: the ticket keys the panel would show if they were set.
List<String> hiddenRows(String front, [bool simple = false, bool planned = true]) {
  final shown = panelRows(front, false, simple, planned).toSet();
  return <String>[...shownWhenSet.where((key) => !shown.contains(key) && (planned || !advancedRows.contains(key)))];
}

/// The keys a ticket holds that are not a ticket's, in order, as written: the quiet line under the panel.
List<String> otherKeys(String front) => <String>[
  for (final property in propertiesOf(front))
    if (!_unsaid.contains(property.key.toLowerCase()) && propertyKind(property.key) == PropertyKind.text) property.key,
];

/// Whether a due day has passed with the ticket not done (red), is today (amber), or neither: `'overdue'`,
/// `'today'` or null.
String? dueState(String? due, String today, StatusCategory category) {
  if (due == null || due.isEmpty || category == StatusCategory.done) return null;
  final between = daysBetween(today, due);
  if (between == null) return null;
  return between < 0 ? 'overdue' : (between == 0 ? 'today' : null);
}

/// How a ticket is linked from a property: by its key where it has one, else its title, as a note link.
String linkTo(TicketChoice choice) => '[[${choice.key ?? choice.title}]]';

/// What a list of links is written as: nothing for none, one link as a quoted value (`blocked-by: "[[GHO-9]]"`, the
/// way the proposal wrote it), several across as a flow list (lib/core/properties.dart `yamlList`).
Object? linksValue(List<String> links) {
  if (links.isEmpty) return null;
  return links.length == 1 ? links.first : links;
}
