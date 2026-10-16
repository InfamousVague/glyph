/// The fields on a list item's words: when it is due, how much it matters, who it is for, and anything else a query
/// may ask of it (Matt asked what Notion- and Jira-like features custom Markdown could give the app, "like tickets
/// and such", and picked this one first: docs/DESIGN.md §156). A port of `src/app/core/taskFields.ts`, one to one.
///
///     - [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03 ^login-loop
///
///     `@sam`            a person, the item's assignee
///     `⏫`              a priority: 🔺 highest, ⏫ high, 🔼 medium, 🔽 low, ⏬ lowest
///     `📅 2026-10-03`   a date: 📅 due, 🛫 start, ⏳ scheduled, ✅ done, ➕ created, ❌ cancelled
///     `🔁 every week`   a recurrence, its rule in words up to the next field
///     `[effort:: 3]`    any other field, by name
///
/// The signs are Obsidian Tasks' own, so a to-do written here is a task with a due date in Obsidian, and Dataview
/// reads the dates and the `[key:: value]` fields wherever they are in the words: the guiding rule, plain Markdown
/// that still reads in another app (docs/MARKDOWN.md). Tasks also writes 🆔 an id, ⛔ the ids it waits on and 🏁
/// what to do when it is done; they are read here and kept where they are, so they are never taken for words,
/// though nothing in the app acts on them yet. The `@sam` is ours: nothing else gives a person to a line of
/// Markdown, and an at sign before a name is what every chat and tracker already writes. So is `⏰ 2026-10-03 09:00`,
/// a reminder (lib/reminders, docs/FEATURES_2_1.md), in the form the Obsidian Reminder plugin reads beside Tasks: read
/// here as one of Tasks' others (key `reminder`), and written where a named field goes, before the run of Tasks'
/// fields, so Tasks still reads the dates after it ([withWrittenField]).
///
/// Where a field goes. Tasks reads its fields from the end of the line, a block link (`^login-loop`) aside and tags
/// among them, and stops at the first thing that is not one. So the writer here keeps them in a run at the end of
/// the words, in the order Tasks writes them ([tasksOrder]), and puts a person or a named field before that run,
/// never inside it, where Tasks would stop and lose the date: the proposal's `📅 2026-10-03 ⏫ @sam #bug` reads
/// here, but Tasks sees only words in it, so the app writes `@sam #bug ⏫ 📅 2026-10-03`. All of it goes before the
/// item's tail - the bookmark, the mark, a counter, the anchor - which is item_syntax.dart's to say, so `wordsEnd`
/// still finds the words' end, a board's anchor still names the item and a Notion mark is still the mark. (An item
/// with a mark or a counter after its fields is words in Tasks' eyes; it still reads.)
///
/// Where a field is found. Anywhere in a text, as a tag is (tags.dart) and as Dataview finds them, but not in quiet
/// words: code, an address, a note link's title, maths, HTML (blanks_syntax.dart `quietRanges`), or a redaction's
/// `@@…@@`, whose words are hidden and are no one's to list as an assignee. The editor asks its own parser too.
///
/// One grammar, in one module, as item_syntax.dart says why: the chips, the voice's "due Friday", a board card's
/// words, a title sent to Notion or GitHub and a query's table all read a field here and nowhere else. Pure, so
/// every shape of line is a test (test/core/task_fields_test.dart).
///
/// What differs: the names and the shapes. The web's `PRIORITIES`, `NO_PRIORITY_RANK`, `DATE_KEYS`, `TASKS_ORDER`
/// and `FIELD_EMOJI` are [priorities], [noPriorityRank], [dateKeys], [tasksOrder] and [fieldEmoji]. Its string
/// unions are plain strings here (`PriorityName`, `DateKey`, `TasksKey`, `FieldKey`), held to their lists by
/// [isDateKey] and [isTasksKey]; `FieldKind` is an enum whose names are the web's strings; `Priority`, `FieldSpan`
/// and `TaskFields` are classes, the first two with value equality. Where two spans start and end together the
/// web's sort keeps the readers' order, so the sort here is made stable by hand.
library;

import 'blanks_syntax.dart' show quietRanges;
import 'days.dart' show isIsoDay;
import 'item_syntax.dart' show jsTrim, listLead, wordsEnd;
import 'tags.dart' show tagsIn;

// ---- priorities ---------------------------------------------------------------------------------------------------

/// One priority (`Priority`).
class Priority {
  const Priority({required this.name, required this.label, required this.emoji, required this.rank});

  /// How a ticket's `priority:` and a query's `where:` write it, lower case: `highest`, `high`, `medium`, `low` or
  /// `lowest` (`PriorityName`).
  final String name;

  /// How it is shown.
  final String label;

  /// How an item's words write it (Obsidian Tasks').
  final String emoji;

  /// Its place when sorted, the most urgent first: 0 for highest. An item with none sits at [noPriorityRank].
  final int rank;

  @override
  bool operator ==(Object other) => other is Priority && other.name == name && other.label == label && other.emoji == emoji && other.rank == rank;

  @override
  int get hashCode => Object.hash(name, label, emoji, rank);

  @override
  String toString() => 'Priority($name)';
}

/// The priorities, the most urgent first: Tasks' five and Jira's, the same names (`PRIORITIES`).
const List<Priority> priorities = [
  Priority(name: 'highest', label: 'Highest', emoji: '🔺', rank: 0),
  Priority(name: 'high', label: 'High', emoji: '⏫', rank: 1),
  Priority(name: 'medium', label: 'Medium', emoji: '🔼', rank: 2),
  Priority(name: 'low', label: 'Low', emoji: '🔽', rank: 4),
  Priority(name: 'lowest', label: 'Lowest', emoji: '⏬', rank: 5),
];

/// Where an item with no priority sorts: between medium and low, as Tasks sorts it, since an item nobody has ranked
/// is an ordinary one, not the least of them (`NO_PRIORITY_RANK`).
const int noPriorityRank = 3;

/// The emoji's variation selector, which a keyboard may put after any of them.
const String _vs = '️';

/// A priority from what was said or written: its name in any case ("High", "highest"), or its emoji, with or
/// without the variation selector. Null for anything else, "normal" and "none" included: no priority is no field.
Priority? priorityOf(String? said) {
  final clean = jsTrim(said ?? '').replaceFirst(_vs, '').toLowerCase();
  for (final p in priorities) {
    if (p.name == clean || p.emoji == clean) return p;
  }
  return null;
}

/// A priority's place when sorted, the most urgent first; an item with none between medium and low.
int priorityRank(String? name) {
  for (final p in priorities) {
    if (p.name == name) return p.rank;
  }
  return noPriorityRank;
}

// ---- the fields' names --------------------------------------------------------------------------------------------

/// The dates an item may carry, in the order Tasks writes them (`DATE_KEYS`).
const List<String> dateKeys = ['created', 'start', 'scheduled', 'due', 'cancelled', 'done'];

/// Tasks' fields in the order Tasks writes them after an item's words: the order the writer keeps (`TASKS_ORDER`).
const List<String> tasksOrder = ['id', 'dependsOn', 'priority', 'recurs', 'onCompletion', 'created', 'start', 'scheduled', 'due', 'cancelled', 'done'];

/// Each emoji field's sign as the app writes it; a priority's is its own ([priorities]) (`FIELD_EMOJI`).
const Map<String, String> fieldEmoji = {
  'id': '🆔',
  'dependsOn': '⛔',
  'recurs': '🔁',
  'onCompletion': '🏁',
  'created': '➕',
  'start': '🛫',
  'scheduled': '⏳',
  'due': '📅',
  'cancelled': '❌',
  'done': '✅',
};

/// The other signs Tasks reads for a field, read here too and never written.
const Map<String, List<String>> _alsoRead = {
  'scheduled': ['⌛'],
  'due': ['📆', '🗓'],
};

/// Whether [key] is one of the dates an item may carry.
bool isDateKey(String key) => dateKeys.contains(key);

/// Whether [key] is one of the fields Obsidian Tasks writes as an emoji.
bool isTasksKey(String key) => tasksOrder.contains(key);

final RegExp _spaces = RegExp(r'\s+');

/// A named field's key as it is compared and kept: trimmed, lower case, each run of spaces a dash, as Dataview reads
/// one, so `[Due Date:: …]` and `[due-date:: …]` are one field.
String fieldKey(String key) => jsTrim(key).toLowerCase().replaceAll(_spaces, '-');

// ---- people -------------------------------------------------------------------------------------------------------

/// A person as written: an at sign after the line's start, a space or an opening bracket, then a letter, then
/// letters, digits, `_`, `.` or `-`. So `sam@example.com` is an address, `@@redacted@@` is a redaction, `@ 2pm` and
/// `@2pm` are a time, and a lone `@` is a word. A trailing `.` or `-` is punctuation: "Ask @sam." is Sam.
final RegExp _person = RegExp(r'(^|[\s([{])@(\p{L}[\p{L}\p{N}_.-]*)', unicode: true);

final RegExp _leadingAts = RegExp(r'^@+');
final RegExp _notHandle = RegExp(r'[^\p{L}\p{N}_.-]', unicode: true);
final RegExp _leadingNotLetter = RegExp(r'^[^\p{L}]+', unicode: true);
final RegExp _trailingStops = RegExp(r'[.-]+$');

/// A name as an item writes it after its at sign, or null where nothing of it can be: "Sam" is `Sam`, "Sam Ortiz" is
/// `Sam-Ortiz`, "@sam" is `sam`. What a spoken "for Sam" and a person picker write.
String? personHandle(String name) {
  final handle = jsTrim(name)
      .replaceFirst(_leadingAts, '')
      .replaceAll(_spaces, '-')
      .replaceAll(_notHandle, '')
      .replaceFirst(_leadingNotLetter, '')
      .replaceFirst(_trailingStops, '');
  return handle.isNotEmpty ? handle : null;
}

/// A person as two mentions of them are compared: the handle, lower case. So `@sam`, "Sam" and a ticket's
/// `assignee: Sam` are one person, and so are `@sam-ortiz` and "Sam Ortiz".
String personKey(String name) => (personHandle(name) ?? jsTrim(name)).toLowerCase();

/// Whether two mentions name one person.
bool samePerson(String one, String two) {
  final key = personKey(one);
  return key != '' && key == personKey(two);
}

// ---- reading ------------------------------------------------------------------------------------------------------

/// What kind of field a span is: a date, a priority, a recurrence, a person, a named `[key:: value]` field, or one
/// of Tasks' others (🆔, ⛔, 🏁), read and kept (`FieldKind`).
enum FieldKind { date, priority, recurs, person, inline, tasks }

/// One field in a text, as `tagsIn` gives a tag (tags.dart): where it is, and what it says (`FieldSpan`).
class FieldSpan {
  const FieldSpan({required this.kind, required this.from, required this.to, required this.key, required this.value});

  final FieldKind kind;

  /// The sign or the bracket that opens it, counted from the offset given.
  final int from;

  /// The end of its value.
  final int to;

  /// What it is: a date's key for a date; `priority`, `recurs`, `assignee`; `id`, `dependsOn` or `onCompletion` for
  /// Tasks' others; a named field's key as [fieldKey] keeps it.
  final String key;

  /// What it says: the day (`2026-10-03`, as written), the priority's name, the rule's words, the person's name
  /// without the at sign (as written), or the value as written, trimmed.
  final String value;

  @override
  bool operator ==(Object other) => other is FieldSpan && other.kind == kind && other.from == from && other.to == to && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(kind, from, to, key, value);

  @override
  String toString() => 'FieldSpan(${kind.name} $key=$value, $from, $to)';
}

/// What a reader makes of one match: the field, where it opens and how long it is.
typedef _Read = ({FieldKind kind, String key, String value, int at, int length});

/// One grammar of fields: a pattern, and what a match of it is.
class _Reader {
  const _Reader(this.pattern, this.read, {this.person = false});

  final RegExp pattern;
  final _Read Function(RegExpMatch found) read;

  /// Whether this is the reader of people, whose match is checked for an address after it.
  final bool person;
}

/// Any of the signs given, and the variation selector after it, as a pattern: each sign its own alternative.
String _signs(List<String> all) => '(?:${all.join('|')})$_vs?';
String _signOf(String key) => _signs([fieldEmoji[key]!, ...?_alsoRead[key]]);

/// The spaces Tasks allows between a sign and its value: any, on the line.
const String _gap = r'[ \t]*';

/// A recurrence's rule: words, numbers, commas and `!`, as Tasks reads one, to the next thing that is not.
const String _rule = r'[\p{L}\p{N}][\p{L}\p{N}, !]*';

/// Tasks' ids: letters, digits, `_` and `-`.
const String _taskId = '[A-Za-z0-9_-]+';

/// A named field, `[key:: value]`: the key a letter or a digit and then words, the value any words and note links.
/// Not a link's words (`[a:: b](…)`), and not inside a note link or after a picture's `!`.
const String _inline = r'(?<![[!])\[([\p{L}\p{N}][\p{L}\p{N} _./-]*?)[ \t]*::[ \t]*((?:\[\[[^\]\n]*\]\]|[^[\]\n])*?)[ \t]*\](?!\()';

final RegExp _ruleTail = RegExp(r'[\s,]+$');

final List<_Reader> _readers = [
  for (final key in dateKeys)
    _Reader(
      RegExp('${_signOf(key)}$_gap(\\d{4}-\\d{2}-\\d{2})(?!\\d)', unicode: true),
      (found) => (kind: FieldKind.date, key: key, value: found.group(1) ?? '', at: found.start, length: found.end - found.start),
    ),
  _Reader(
    RegExp('(${priorities.map((p) => p.emoji).join('|')})$_vs?', unicode: true),
    (found) => (kind: FieldKind.priority, key: 'priority', value: priorityOf(found.group(1))?.name ?? '', at: found.start, length: found.end - found.start),
  ),
  _Reader(RegExp('${_signOf('recurs')}$_gap($_rule)', unicode: true), (found) {
    // The rule ends at its last word: the spaces and commas after it are the gap before what comes next.
    final all = found.group(1) ?? '';
    final rule = all.replaceFirst(_ruleTail, '');
    final length = found.end - found.start - (all.length - rule.length);
    return (kind: FieldKind.recurs, key: 'recurs', value: rule, at: found.start, length: length);
  }),
  _Reader(
    RegExp('${_signOf('id')}$_gap($_taskId)', unicode: true),
    (found) => (kind: FieldKind.tasks, key: 'id', value: found.group(1) ?? '', at: found.start, length: found.end - found.start),
  ),
  _Reader(
    RegExp('${_signOf('dependsOn')}$_gap($_taskId(?:[ \\t]*,[ \\t]*$_taskId)*)', unicode: true),
    (found) => (kind: FieldKind.tasks, key: 'dependsOn', value: found.group(1) ?? '', at: found.start, length: found.end - found.start),
  ),
  _Reader(
    RegExp('${_signOf('onCompletion')}$_gap([A-Za-z]+)', unicode: true),
    (found) => (kind: FieldKind.tasks, key: 'onCompletion', value: found.group(1) ?? '', at: found.start, length: found.end - found.start),
  ),
  // A reminder: `⏰ 2026-10-03 09:00`, a day and a time on the clock, its value kept as `2026-10-03 09:00`.
  _Reader(
    RegExp('⏰$_vs?$_gap(\\d{4}-\\d{2}-\\d{2})[ \\t]+([01]?\\d|2[0-3]):([0-5]\\d)(?!\\d)', unicode: true),
    (found) => (kind: FieldKind.tasks, key: 'reminder', value: '${found.group(1)} ${found.group(2)!.padLeft(2, '0')}:${found.group(3)}', at: found.start, length: found.end - found.start),
  ),
  _Reader(_person, (found) {
    final lead = (found.group(1) ?? '').length;
    final name = (found.group(2) ?? '').replaceFirst(_trailingStops, '');
    return (kind: FieldKind.person, key: 'assignee', value: name, at: found.start + lead, length: name.length + 1);
  }, person: true),
  _Reader(
    RegExp(_inline, unicode: true),
    (found) => (kind: FieldKind.inline, key: fieldKey(found.group(1) ?? ''), value: jsTrim(found.group(2) ?? ''), at: found.start, length: found.end - found.start),
  ),
];

/// A redaction, `@@…@@`: its words are hidden, so nothing in them is a field.
final RegExp _redaction = RegExp(r'@@[^\s@](?:[^\n@]|@(?!@))*?@@');

/// Every field in [text], in order, counting positions from [offset]: anywhere in it but quiet words and a
/// redaction. Where two would overlap - a person in a named field's value, `[owner:: @sam]` - the one that starts
/// first is the field, and the other is its words.
List<FieldSpan> fieldsIn(String text, [int offset = 0]) {
  if (text.isEmpty) return [];
  final quiet = quietRanges(text);
  for (final found in _redaction.allMatches(text)) {
    quiet.add((from: found.start, to: found.end));
  }
  final all = <FieldSpan>[];
  for (final reader in _readers) {
    for (final found in reader.pattern.allMatches(text)) {
      // A name run on into an at sign (`@sam@mastodon.social`) is an address, not a person.
      if (reader.person && found.end < text.length && text[found.end] == '@') continue;
      final field = reader.read(found);
      if (quiet.any((q) => field.at >= q.from && field.at < q.to)) continue;
      all.add(FieldSpan(kind: field.kind, key: field.key, value: field.value, from: field.at, to: field.at + field.length));
    }
  }
  // The earliest first, the longer of two that start together first; a stable sort, as JavaScript's is.
  final order = [for (var n = 0; n < all.length; n += 1) n];
  order.sort((a, b) {
    final byFrom = all[a].from - all[b].from;
    if (byFrom != 0) return byFrom;
    final byTo = all[b].to - all[a].to;
    return byTo != 0 ? byTo : a - b;
  });
  final kept = <FieldSpan>[];
  for (final n in order) {
    final span = all[n];
    if (kept.isEmpty || span.from >= kept.last.to) kept.add(span);
  }
  return [for (final span in kept) FieldSpan(kind: span.kind, key: span.key, value: span.value, from: span.from + offset, to: span.to + offset)];
}

/// What an item's fields say, read together (`TaskFields`).
class TaskFields {
  const TaskFields({
    required this.due,
    required this.start,
    required this.scheduled,
    required this.done,
    required this.created,
    required this.cancelled,
    required this.recurs,
    required this.priority,
    required this.assignees,
    required this.id,
    required this.dependsOn,
    required this.onCompletion,
    required this.fields,
  });

  final String? due;
  final String? start;
  final String? scheduled;
  final String? done;
  final String? created;
  final String? cancelled;

  /// The recurrence's rule in words, "every week on Monday"; kept, not yet acted on.
  final String? recurs;

  /// The priority's name: `highest`, `high`, `medium`, `low` or `lowest`.
  final String? priority;

  /// The people, as written without their at signs, each once, in order.
  final List<String> assignees;

  /// Tasks' own id (🆔), the ids it waits on (⛔) and what to do when it is done (🏁): read and kept, not yet acted
  /// on.
  final String? id;
  final List<String> dependsOn;
  final String? onCompletion;

  /// Every named field, by its key as [fieldKey] keeps it, the first of a repeated one winning.
  final Map<String, String> fields;

  /// The date under one of [dateKeys], as the web's `fields[key]` reads it; null for a date not set or a key that is
  /// not a date.
  String? date(String key) => switch (key) {
    'due' => due,
    'start' => start,
    'scheduled' => scheduled,
    'done' => done,
    'created' => created,
    'cancelled' => cancelled,
    _ => null,
  };
}

/// Dataview's own names for a task's dates, and a priority by name: what an item written for Dataview says in
/// `[due:: 2026-10-03]`. Read as the emoji's where the item has no emoji for it, as Dataview reads them both.
const Map<String, String> _dataviewNames = {
  'due': 'due',
  'start': 'start',
  'scheduled': 'scheduled',
  'created': 'created',
  'completion': 'done',
  'cancelled': 'cancelled',
  'priority': 'priority',
};

/// What [text]'s fields say: an item's line or its words, as [fieldsIn] finds them. The first of a repeated field
/// wins, as a reader of the line in another app would take it. A date is as written; a named `[due:: …]` stands for
/// the date where there is no `📅`, when it is a day.
TaskFields fieldsOf(String text) {
  final dates = <String, String>{};
  String? recurs;
  String? priority;
  final assignees = <String>[];
  String? id;
  final dependsOn = <String>[];
  String? onCompletion;
  final fields = <String, String>{};
  final people = <String>{};
  for (final span in fieldsIn(text)) {
    if (span.kind == FieldKind.date && isDateKey(span.key)) {
      dates[span.key] ??= span.value;
    } else if (span.kind == FieldKind.priority) {
      priority ??= priorityOf(span.value)?.name;
    } else if (span.kind == FieldKind.recurs) {
      recurs ??= span.value;
    } else if (span.kind == FieldKind.person && !people.contains(personKey(span.value))) {
      people.add(personKey(span.value));
      assignees.add(span.value);
    } else if (span.kind == FieldKind.tasks && span.key == 'id') {
      id ??= span.value;
    } else if (span.kind == FieldKind.tasks && span.key == 'dependsOn') {
      for (final each in span.value.split(',').map(jsTrim)) {
        if (each.isNotEmpty && !dependsOn.contains(each)) dependsOn.add(each);
      }
    } else if (span.kind == FieldKind.tasks && span.key == 'onCompletion') {
      onCompletion ??= span.value;
    } else if (span.kind == FieldKind.inline && !fields.containsKey(span.key)) {
      fields[span.key] = span.value;
    }
  }
  for (final MapEntry(key: name, value: key) in _dataviewNames.entries) {
    final said = fields[name];
    if (said == null) continue;
    if (key == 'priority') {
      priority ??= priorityOf(said)?.name;
    } else if (isIsoDay(said)) {
      dates[key] ??= said;
    }
  }
  return TaskFields(
    due: dates['due'],
    start: dates['start'],
    scheduled: dates['scheduled'],
    done: dates['done'],
    created: dates['created'],
    cancelled: dates['cancelled'],
    recurs: recurs,
    priority: priority,
    assignees: assignees,
    id: id,
    dependsOn: dependsOn,
    onCompletion: onCompletion,
    fields: fields,
  );
}

final RegExp _runOfSpaces = RegExp(r'[ \t]{2,}');

/// [text] with every field taken out, each with the space before it, and the spaces tidied: what an item says, for
/// a title sent to Notion or GitHub and a board card's words. "Fix the login loop @sam #bug ⏫ 📅 2026-10-03" is
/// "Fix the login loop #bug": a tag is words, and what a field says is the field's to show. Give it the words
/// (item_syntax.dart `lineWords`), not the line.
String withoutFields(String text) {
  var out = text;
  for (final span in fieldsIn(text).reversed) {
    out = _removed(out, span, 0);
  }
  return jsTrim(out.replaceAll(_runOfSpaces, ' '));
}

// ---- writing ------------------------------------------------------------------------------------------------------

/// Where a line's words are, as item_syntax.dart reads them: after the lead, before the tail.
({int from, int to}) _wordsOf(String line) {
  final from = listLead(line)?.wordsAt ?? 0;
  final end = wordsEnd(line);
  return (from: from, to: end > from ? end : from);
}

/// Whether a span is one of Tasks' emoji fields, which keep to the run at the end of the words.
bool _isEmojiField(FieldSpan span) => span.kind != FieldKind.person && span.kind != FieldKind.inline;

final RegExp _space = RegExp(r'\s');
final RegExp _blankOrTab = RegExp(r'[ \t]');

/// The run of Tasks' fields at the end of the words, tags among them: where it starts, and its fields in order. A
/// line with no field at the end of its words has none, and starts where its words end.
({int at, List<FieldSpan> fields}) _tasksRun(String line, List<FieldSpan> spans, ({int from, int to}) words) {
  final tags = tagsIn(line).where((tag) => tag.from >= words.from && tag.to <= words.to).toList();
  final fields = <FieldSpan>[];
  var at = words.to;
  var cursor = words.to;
  for (;;) {
    while (cursor > words.from && _space.hasMatch(line[cursor - 1])) {
      cursor -= 1;
    }
    FieldSpan? field;
    for (final span in spans) {
      if (span.to == cursor && _isEmojiField(span)) {
        field = span;
        break;
      }
    }
    if (field != null) {
      fields.insert(0, field);
      at = field.from;
      cursor = field.from;
      continue;
    }
    var moved = false;
    for (final tag in tags) {
      if (tag.to == cursor) {
        cursor = tag.from;
        moved = true;
        break;
      }
    }
    if (!moved) break;
  }
  return (at: at, fields: fields);
}

final RegExp _endsInSpace = RegExp(r'\s$');
final RegExp _startsWithSpace = RegExp(r'^\s');

/// [line] with [text] put in at [at], a space either side where the words there would otherwise touch it.
String _inserted(String line, int at, String text) {
  final before = line.substring(0, at);
  final after = line.substring(at);
  final left = before.isNotEmpty && !_endsInSpace.hasMatch(before) ? ' ' : '';
  final right = after.isNotEmpty && !_startsWithSpace.hasMatch(after) ? ' ' : '';
  return '$before$left$text$right$after';
}

/// [line] without one field and the space before it; a field that opens the words takes the space after it instead,
/// so `- [ ] 📅 2026-10-03 Fix` is `- [ ] Fix` and the box keeps its space.
String _removed(String line, FieldSpan span, int wordsFrom) {
  var from = span.from;
  var to = span.to;
  while (from > wordsFrom && _blankOrTab.hasMatch(line[from - 1])) {
    from -= 1;
  }
  if (from == wordsFrom) {
    from = span.from;
    while (to < line.length && _blankOrTab.hasMatch(line[to])) {
      to += 1;
    }
  }
  return '${line.substring(0, from)}${line.substring(to)}';
}

/// A named field's key as it may be written: a letter or digit, then letters, digits, spaces, `_`, `.`, `/` or `-`.
final RegExp _inlineKey = RegExp(r'^[\p{L}\p{N}][\p{L}\p{N} _./-]*$', unicode: true);

/// A named field's value as it may be written: one line, and no bracket but a note link's.
final RegExp _inlineValue = RegExp(r'^(?:\[\[[^\]\n]*\]\]|[^[\]\n])*$');

final RegExp _wholeRule = RegExp('^$_rule\$', unicode: true);
final RegExp _wholeTaskId = RegExp('^$_taskId\$');
final RegExp _letters = RegExp(r'^[A-Za-z]+$');

/// A Tasks field as the app writes it, or null for a value it cannot hold.
String? _emojiField(String key, String value) {
  final clean = jsTrim(value.replaceAll(_spaces, ' '));
  if (key == 'priority') return priorityOf(clean)?.emoji;
  final sign = fieldEmoji[key]!;
  if (isDateKey(key)) return isIsoDay(clean) ? '$sign $clean' : null;
  if (key == 'recurs') return _wholeRule.hasMatch(clean) ? '$sign $clean' : null;
  if (key == 'dependsOn') {
    final ids = clean.split(',').map(jsTrim).toList();
    return ids.every(_wholeTaskId.hasMatch) ? '$sign ${ids.join(',')}' : null;
  }
  if (key == 'onCompletion') return _letters.hasMatch(clean) ? '$sign $clean' : null;
  return _wholeTaskId.hasMatch(clean) ? '$sign $clean' : null;
}

/// A named field as written: `[key:: value]`, or null for a key or a value it cannot hold.
String? _inlineField(String key, String value) {
  final name = jsTrim(key);
  final clean = jsTrim(value.replaceAll(_spaces, ' '));
  return _inlineKey.hasMatch(name) && _inlineValue.hasMatch(clean) ? '[$name:: $clean]' : null;
}

final RegExp _writtenKey = RegExp(r'^\[([^:\]]*?)[ \t]*::');

/// The line with one field set, replaced or taken off: [value] null takes it off. A date is a day (`2026-10-03`,
/// see days.dart), a priority a name or its emoji, `recurs` its rule in words; any name that is not one of Tasks' is
/// written `[name:: value]`. A field the item has is changed where it is, in the form it is written in (a Dataview
/// `[due:: …]` stays one), and a second of the same is taken off. A new one goes at the end of the words, before the
/// tail: one of Tasks' into the run of them in Tasks' order, a named one before that run. A value the field cannot
/// hold - a date that is not a day, a priority that is not one - leaves the line as it was. People are
/// [withAssignee]'s.
String withField(String line, String key, String? value) {
  final tasks = isTasksKey(key) ? key : null;
  final named = tasks != null ? null : fieldKey(key);
  if (named != null && !_inlineKey.hasMatch(jsTrim(key))) return line;
  final words = _wordsOf(line);
  final spans = fieldsIn(line).where((span) => span.from >= words.from && span.to <= words.to).toList();
  final mine = spans
      .where(
        (span) => tasks != null
            ? (_isEmojiField(span) && span.key == tasks) || (span.kind == FieldKind.inline && _dataviewNames[span.key] == tasks)
            : span.kind == FieldKind.inline && span.key == named,
      )
      .toList();
  if (value == null) {
    var out = line;
    for (final span in mine.reversed) {
      out = _removed(out, span, words.from);
    }
    return out;
  }
  if (mine.isNotEmpty) {
    final first = mine.first;
    String? text;
    if (first.kind == FieldKind.inline) {
      // Kept in the form it is written in, its key as the person wrote it.
      final writtenKey = _writtenKey.firstMatch(line.substring(first.from, first.to))?.group(1) ?? key;
      final said = tasks == 'priority' ? priorityOf(value)?.name : (tasks != null && isDateKey(tasks) && !isIsoDay(jsTrim(value)) ? null : value);
      text = said == null ? null : _inlineField(writtenKey, said);
    } else {
      text = _emojiField(first.key, value);
    }
    if (text == null) return line;
    var rest = line;
    for (final span in mine.skip(1).toList().reversed) {
      rest = _removed(rest, span, words.from);
    }
    return '${rest.substring(0, first.from)}$text${rest.substring(first.to)}';
  }
  final text = tasks != null ? _emojiField(tasks, value) : _inlineField(key, value);
  if (text == null) return line;
  final run = _tasksRun(line, spans, words);
  if (tasks == null) return _inserted(line, run.fields.isNotEmpty ? run.at : words.to, text);
  final order = tasksOrder.indexOf(tasks);
  for (final field in run.fields) {
    if (tasksOrder.indexOf(field.key) > order) return _inserted(line, field.from, text);
  }
  return _inserted(line, run.fields.isNotEmpty ? run.fields.last.to : words.to, text);
}

/// The line with every field under [key] that is not a person or a named one taken off (a reminder's `⏰`), and
/// [text] put in as written where a field Tasks does not read goes: before the run of Tasks' fields at the end of the
/// words, so Tasks still reads the dates after it, or at the words' end. Null [text] only takes them off. The writer of
/// a reminder (lib/reminders/reminder_syntax.dart), which says what the text is.
String withWrittenField(String line, String key, String? text) {
  var out = line;
  final before = _wordsOf(out);
  final mine = fieldsIn(out).where((span) => span.from >= before.from && span.to <= before.to && _isEmojiField(span) && span.key == key).toList();
  for (final span in mine.reversed) {
    out = _removed(out, span, before.from);
  }
  if (text == null || jsTrim(text).isEmpty) return out;
  final words = _wordsOf(out);
  final spans = fieldsIn(out).where((span) => span.from >= words.from && span.to <= words.to).toList();
  final run = _tasksRun(out, spans, words);
  return _inserted(out, run.fields.isNotEmpty ? run.at : words.to, jsTrim(text));
}

/// The line with a person added to its people ([on]), or taken off them: `@sam` before the run of Tasks' fields, so
/// Tasks still reads its dates, after any person already there. A person already on it is not added again, and one
/// not on it is not taken off; a name with nothing a handle can be made of ([personHandle]) leaves the line alone.
String withAssignee(String line, String name, [bool on = true]) {
  final handle = personHandle(name);
  if (handle == null) return line;
  final words = _wordsOf(line);
  final spans = fieldsIn(line).where((span) => span.from >= words.from && span.to <= words.to).toList();
  final theirs = spans.where((span) => span.kind == FieldKind.person && samePerson(span.value, handle)).toList();
  if (!on) {
    var out = line;
    for (final span in theirs.reversed) {
      out = _removed(out, span, words.from);
    }
    return out;
  }
  if (theirs.isNotEmpty) return line;
  final run = _tasksRun(line, spans, words);
  return _inserted(line, run.fields.isNotEmpty ? run.at : words.to, '@$handle');
}
