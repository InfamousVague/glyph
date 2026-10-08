/// What the + beside the line offers (add_list.dart draws it), whether each row is there, and what each writes. A
/// port of `src/app/editor/addRows.ts`.
///
/// Matt: "Fuller but hide extras behind nested menu". So the list has the things people reach for, the phone's own
/// first (a picture, a video, a place, the time) and then the things made of words (a table, a board, a database, a
/// link to a note, a to-do), and a last row, More, which turns the list over to the rest: the forms a line takes,
/// the blocks, and the small marks the Guide teaches, each with a seed to write over.
///
/// **A row is there, dimmed or not there** by one rule. A row this device or this build can never do is not drawn.
/// A row a choice the person made stands in the way of is drawn dimmed, with the choice named under it: Local only,
/// for a place. A refusal found only by trying (location blocked for the app) keeps the row, and is said when it
/// happens.
///
/// Where each goes is commands/inserts.dart: a drawn thing on a line of its own, a block with blank lines where
/// words are near, words at the caret. Every write is one Undo, and appears at once (docs/DESIGN.md §140, §141 in
/// ../glyph).
///
/// What differs:
/// - **What the device can do is the screen's to say.** `canPickPicture` and `placeRow` read the web's platform
///   (`isMacApp`, `window.GlyphHost`, `navigator.geolocation`); here a row is there when the screen hands the list
///   its callback (add_list.dart `AddConfig`), so [readGates] takes only the answers, and Local only as a flag.
/// - **Three gates the web does not have**, for rows whose blocks later stages draw: [AddGates.board] (a board's
///   fence, stage 5), [AddGates.database] (a query's fence, stage 5) and [AddGates.blank] (a blank for the AI,
///   stage 8). Each is on unless said, so the rows and their order are the web's; the screen turns them off until
///   the editor draws them. With the database off a board is one write, not a page of two.
/// - **The effects are handed in** ([PlusEffect]), where the web asked its plugin registry
///   (`plugins.formats()`): the marks are another piece's (lib/editor/marks).
/// - **A row's id is a string** (`'picture'`, `'query:week'`, `'effect:Heat'`), as it is on the page.
/// - [planFor] and [writeRow] take the state or a dispatch target rather than a view; [planFor] answers a
///   [RowWrite].
/// - **The moment in words is English, day first** ([stamp], [timeLabel]): the web asks `Intl` for the device's
///   own order and month names, which this app has no tables for yet (lib/notes/note_templates.dart's `longDay` is
///   the same).
/// - `CHART_CARD` (canvas/edits.ts), `QUERY_TEMPLATES` and `queryFence` (core/query) and `onNamingLine`
///   (editor/openHeading.ts) are written here until their own pieces land (query_templates.dart, [onNamingLine]).
/// - `withProperty` is `withFrontMatterValue` (lib/notes/note_templates.dart): `ticket` and `To do` are words YAML
///   reads as they are, so nothing is quoted.
library;

import '../../art/app_icon.dart' show LucideIcon;
import '../../core/boards/fence.dart';
import '../../core/boards/items.dart';
import '../../core/boards/make.dart';
import '../../core/days.dart';
import '../../core/front_matter.dart';
import '../../core/item_syntax.dart';
import '../../core/properties.dart';
import '../../core/task_fields.dart';
import '../../notes/note_templates.dart' show clockTime, formatStamp;
import '../commands/format.dart';
import '../commands/inserts.dart';
import '../state/change.dart';
import '../state/state.dart';
import '../state/text.dart';
import '../view/extended.dart' show frontMatter;
import '../view/plugin.dart';
import 'query_templates.dart';

/// A step inside the list rather than a write: More, the ways to start a board, the ready-made databases, or
/// choosing a note or a canvas.
enum AddStep { more, board, database, note, canvas }

/// A row as the list draws it. [id] is one of `picture`, `video`, `place`, `time`, `table`, `note`, `todo`, `more`,
/// `heading`, `bullets`, `numbers`, `quote`, `callout`, `choice`, `code`, `divider`, `board`, `query`,
/// `query:<template>`, `dated`, `ticket`, `chart`, `formula`, `canvas`, `footnote`, `tag`, `counter`, `sum`,
/// `blank`, `blankCells`, `effect:<name>`.
class AddRow {
  const AddRow({required this.id, required this.words, this.label, this.dimmed, this.step});

  final String id;
  final String words;

  /// Its name to a screen reader, where the words alone do not say it (the time row).
  final String? label;

  /// Why it cannot be pressed: a choice the person made, named.
  final String? dimmed;
  final AddStep? step;

  @override
  String toString() => 'AddRow($id, $words)';
}

/// Whether a place can be added: on, dimmed under Local only, or not there.
enum PlaceGate { on, dimmed, absent }

/// An effect a row can start (`InlineFormat` of kind `effect`, plugins/types.ts): its name, the marks either side of
/// its words, the word it is said by while recording, and its mark in the list.
class PlusEffect {
  const PlusEffect({required this.name, required this.delimiter, this.cue, this.icon});

  final String name;
  final String delimiter;
  final String? cue;

  /// Its icon in the list; the sparkles when null.
  final LucideIcon? icon;
}

/// What the screen can do, read once when the list opens.
class AddGates {
  const AddGates({
    required this.picture,
    required this.video,
    required this.place,
    required this.note,
    required this.canvas,
    this.effects = const <PlusEffect>[],
    this.tableAbove = false,
    this.ticket = false,
    this.board = true,
    this.database = true,
    this.blank = true,
  });

  final bool picture;
  final bool video;
  final PlaceGate place;
  final bool note;
  final bool canvas;
  final List<PlusEffect> effects;

  /// The +'s empty line sits straight under a table with an empty body cell: Blanks in the empty cells
  /// (docs/DESIGN.md §145).
  final bool tableAbove;

  /// The note can be made a ticket: it is not one, and not a notebook (docs/TICKETS.md).
  final bool ticket;

  /// The editor draws a board's fence (see the header).
  final bool board;

  /// The editor draws a query's fence.
  final bool database;

  /// The app fills a blank.
  final bool blank;
}

/// The gates, for a screen that can do these (a picture picker, a video, a place, a note to link, a canvas to
/// frame). `localOnly` is the person's Local only, which dims a place.
AddGates readGates({
  required bool picture,
  required bool video,
  required bool place,
  required bool note,
  required bool canvas,
  bool localOnly = false,
  bool tableAbove = false,
  bool ticket = false,
  bool board = true,
  bool database = true,
  bool blank = true,
  List<PlusEffect> effects = const <PlusEffect>[],
}) => AddGates(
  picture: picture,
  video: video,
  place: !place ? PlaceGate.absent : (localOnly ? PlaceGate.dimmed : PlaceGate.on),
  note: note,
  canvas: canvas,
  effects: effects,
  tableAbove: tableAbove,
  ticket: ticket,
  board: board,
  database: database,
  blank: blank,
);

// ---- the moment, in words (core/stamp.ts, core/noteNames.ts) -----------------------------------------------------------

/// en-GB's short months, as `Intl` writes them: "Sept", and no stop.
const List<String> _shortMonths = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
const List<String> _months = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "28 Sept 2026, 14:05": the day and the short month, the year, and the time on a 24-hour clock (`stamp`).
String stamp(DateTime at) => '${at.day} ${_shortMonths[at.month - 1]} ${at.year}, ${clockTime(at)}';

/// "2026-09-28 14.05": the minute as a name, as a journal names an entry (`minuteName`, core/noteNames.ts).
String minuteName(DateTime at) => formatStamp(at, 'YYYY-MM-DD HH.mm');

/// "The date and time, 28 September 2026, 14:05": the time row read aloud, with the month in full.
String timeLabel(DateTime at) => 'The date and time, ${at.day} ${_months[at.month - 1]} ${at.year}, ${clockTime(at)}';

/// What the time row writes: the stamp, "28 Sept 2026, 14:05", or on the line that names the note, the minute's
/// name, "2026-09-28 14.05" (docs/DESIGN.md §144). There the words are the note's name and its file's, and the
/// stamp's colon and comma make a file called `28 Sept 2026, 1405.md`; the minute's name is the third name on a
/// blank page's chips, so the two can never differ.
({String words, String label}) timeWords(DateTime now, bool naming) {
  if (!naming) return (words: stamp(now), label: timeLabel(now));
  final name = minuteName(now);
  return (words: name, label: 'The date and time as a name, $name');
}

// ---- the line that names the note (editor/openHeading.ts) --------------------------------------------------------------

final RegExp _openHeading = RegExp(r'^ {0,3}#{1,6}\s*$');

/// The note's first line of words: the first line after its front matter with anything on it (`firstWordsLine`).
Line? firstWordsLine(EditorState state) {
  final front = frontMatter(state.doc);
  for (var n = front != null ? front.to + 1 : 1; n <= state.doc.lines; n += 1) {
    final line = state.doc.line(n);
    if (jsTrim(line.text).isNotEmpty) return line;
  }
  return null;
}

/// Whether the caret is on the line that names the note: its first line of words, with no words of its own yet. A
/// blank note's line 1, or an open first heading (`# `). The + writes the minute's name there, not the stamp, since
/// what goes there is the note's name and its file's (`onNamingLine`).
bool onNamingLine(EditorState state) {
  final main = state.selection.main;
  if (!main.empty) return false;
  final line = state.doc.lineAt(main.head);
  if (jsTrim(line.text).isNotEmpty && !_openHeading.hasMatch(line.text)) return false;
  final front = frontMatter(state.doc);
  if (front != null && line.number <= front.to) return false;
  final words = firstWordsLine(state);
  return words == null || words.number >= line.number;
}

// ---- the rows ----------------------------------------------------------------------------------------------------------

/// The list's first page: the things reached for most, as far as this screen can do them, and More. The phone's own
/// come first (a picture, a video, a place, the time), then the data trio made of words - a table, a board, a
/// database - since those are the Notion and Jira features people came for (Matt: make "queries and boards and
/// stuff easier to create"), then a link to a note and a to-do. `naming`: the caret is on the line that names the
/// note.
List<AddRow> topRows(AddGates gates, DateTime now, [bool naming = false]) {
  final time = timeWords(now, naming);
  return <AddRow>[
    if (gates.picture) const AddRow(id: 'picture', words: 'A picture'),
    if (gates.video) const AddRow(id: 'video', words: 'A video'),
    if (gates.place != PlaceGate.absent) AddRow(id: 'place', words: 'A place', dimmed: gates.place == PlaceGate.dimmed ? 'Local only is on.' : null),
    AddRow(id: 'time', words: time.words, label: time.label),
    const AddRow(id: 'table', words: 'A table'),
    // With no database to make a ticket board of, a board is the one write (see the header).
    if (gates.board) AddRow(id: 'board', words: 'A board', step: gates.database ? AddStep.board : null),
    if (gates.database) const AddRow(id: 'query', words: 'A database', step: AddStep.database),
    if (gates.note) const AddRow(id: 'note', words: 'A note', step: AddStep.note),
    const AddRow(id: 'todo', words: 'A to-do'),
    const AddRow(id: 'more', words: 'More', step: AddStep.more),
  ];
}

/// Every row the slash menu can reach, in one flat list to filter by typing (the `/` command palette): the first
/// page's things without More, then everything More holds. The steps (a board, a database, a note, a canvas) are
/// here too, so `/board` finds the board page.
List<AddRow> allRows(AddGates gates, DateTime now, [bool naming = false]) => <AddRow>[...topRows(gates, now, naming).where((row) => row.id != 'more'), ...moreRows(gates)];

/// More: the forms a line takes, the blocks, and the small marks, each with a seed. A board and a database are on
/// the first page, not here; what is left is the rest a note is made of.
List<AddRow> moreRows(AddGates gates) => <AddRow>[
  const AddRow(id: 'heading', words: 'A heading'),
  const AddRow(id: 'bullets', words: 'A bulleted list'),
  const AddRow(id: 'numbers', words: 'A numbered list'),
  const AddRow(id: 'quote', words: 'A quote'),
  const AddRow(id: 'callout', words: 'A callout'),
  const AddRow(id: 'choice', words: 'A choice'),
  const AddRow(id: 'dated', words: 'A to-do with a due date'),
  const AddRow(id: 'code', words: 'A block of code'),
  const AddRow(id: 'divider', words: 'A divider'),
  // A note that is not a ticket yet, and not a notebook, can be made one: its front matter written for it (§160).
  if (gates.ticket) const AddRow(id: 'ticket', words: 'Make this a ticket'),
  const AddRow(id: 'chart', words: 'A diagram'),
  const AddRow(id: 'formula', words: 'A formula'),
  if (gates.canvas) const AddRow(id: 'canvas', words: 'A canvas', step: AddStep.canvas),
  const AddRow(id: 'footnote', words: 'A footnote'),
  const AddRow(id: 'tag', words: 'A tag'),
  const AddRow(id: 'counter', words: 'A counter'),
  const AddRow(id: 'sum', words: 'A sum'),
  // A question for the AI where its answer belongs (docs/DESIGN.md §145): writing one needs no model. Under a table
  // with an empty cell, a blank in every one.
  if (gates.blank) const AddRow(id: 'blank', words: 'A blank for the AI'),
  if (gates.blank && gates.tableAbove) const AddRow(id: 'blankCells', words: 'Blanks in the empty cells', label: 'Blanks in the empty cells of the table above'),
  for (final effect in gates.effects) AddRow(id: 'effect:${effect.name}', words: effectWords(effect)),
];

/// An effect's row, named as it is said while recording ("heated", "frosted"), so it reads as words that look a
/// way: "Heated words". An effect with no word of its own is named by its name.
String effectWords(PlusEffect effect) {
  final cue = jsTrim(effect.cue ?? '');
  final said = cue.isNotEmpty ? cue : effect.name;
  if (said.isEmpty) return ' words';
  return '${said.substring(0, 1).toUpperCase()}${said.substring(1).toLowerCase()} words';
}

// ---- the seeds ---------------------------------------------------------------------------------------------------------

/// A callout, as the Guide teaches it: a quote whose first line names its kind, the caret on the line under it.
const String calloutSeed = '> [!NOTE]\n> ';

/// A block of code with nothing in it yet, the caret inside.
const String codeSeed = '```\n\n```';

/// A formula on its own: a `$$` block with nothing in it yet, the caret on the empty line between the fences.
const String formulaSeed = '\$\$\n\n\$\$';

/// What a new chart card starts with (`CHART_CARD`, canvas/edits.ts).
const String chartCard = '```mermaid\nflowchart LR\n  A[Start] --> B[Then]\n  B --> C[Done]\n```\n';

/// A chart that reads as one at a glance: three boxes in a row with arrows between, in Mermaid, with "Start"
/// selected to be written over.
final String chartSeed = chartCard.trimRight();

/// A counter, with what it counts selected to be written over, as the Guide's `- Water [3/8]` is.
const String counterSeed = 'Count [0/8]';

/// The words an effect's seed holds, selected to be written over.
const String effectSeedWords = 'words';

/// A small board, as Make a board writes one (core/boards `boardFrom`): the three columns, and one to-do named in
/// the first, its words selected to be written over. The anchor is one no item in the note has yet.
({String text, BlockSelect select}) boardSeed(String doc) {
  const words = 'First card';
  final id = anchorFor(words, itemsIn(doc).map((item) => item.id));
  final columns = <BoardColumn>[
    for (var index = 0; index < newColumns.length; index += 1) BoardColumn(name: newColumns[index], cards: index == 0 ? <String>[id] : const <String>[]),
  ];
  final fence = <String>['```board', writeBoard(columns), '```'].join('\n');
  final item = '- [ ] $words ^$id';
  final text = '$fence\n\n$item';
  final from = text.length - item.length + '- [ ] '.length;
  return (text: text, select: BlockSelect.at(from, from + words.length));
}

/// A board's page: the two ways to start one, so the two kinds of board are a single choice rather than a name to
/// guess between. Fresh columns is a `board` fence of its own ([boardSeed]); From your tickets is the ready-made
/// ticket board, a query grouped into lanes, which fills itself from the library.
List<AddRow> boardRows() => const <AddRow>[AddRow(id: 'board', words: 'Fresh columns'), AddRow(id: 'query:board', words: 'From your tickets')];

/// A database's page: the ready-made queries (query_templates.dart), each a row of its own, Write your own last.
List<AddRow> databaseRows() => <AddRow>[for (final template in queryTemplates) AddRow(id: 'query:${template.id}', words: template.words)];

/// A ready-made query as a block: drawn at once with the caret on the line after it, or, for Write your own, with
/// its kind selected to be written over, the fence's lines showing.
({String text, BlockSelect select})? querySeed(String id) {
  QueryTemplate? template;
  for (final each in queryTemplates) {
    if ('query:${each.id}' == id) template = each;
  }
  if (template == null) return null;
  final text = queryFence(template.lines);
  final select = template.select;
  if (select == null) return (text: text, select: const BlockSelect.after());
  final from = text.indexOf(select);
  return (text: text, select: BlockSelect.at(from, from + select.length));
}

/// The words a dated to-do starts with, selected to be written over.
const String datedWords = 'To-do';

/// A to-do with a due date (core/task_fields.dart; docs/DESIGN.md §158), due tomorrow, its words selected to be
/// written over and the chip there to tap for another day: a to-do's own lead, where A to-do would put it, then
/// the words and the day, as one change.
Plan datedPlan(EditorState state, int at, DateTime now) {
  final base = itemPlan(state, at, ItemKind.todo);
  final first = state.update(TransactionSpec(changes: base.changes, selection: base.editorSelection));
  final caret = first.state.selection.main.head;
  final words = '$datedWords ${fieldEmoji['due']} ${isoDayAfterDate(now, 1)}';
  return Plan(
    changes: first.changes.compose(first.state.changes(ChangeSpec(from: caret, insert: words))),
    selection: (anchor: caret, head: caret + datedWords.length),
  );
}

/// The note made a ticket (docs/TICKETS.md): `type: ticket` and, where it has no status yet, `status: To do`,
/// written into its front matter as one change, the rest of the note and the caret where they were.
Plan? ticketPlan(EditorState state) {
  final doc = state.doc.toString();
  if (isTicket(doc)) return null;
  final typed = withFrontMatterValue(doc, 'type', ticketType);
  final next = frontMatterValue(doc, 'status') != null && frontMatterValue(doc, 'status')!.isNotEmpty ? typed : withFrontMatterValue(typed, 'status', 'To do');
  var start = 0;
  while (start < doc.length && start < next.length && doc.codeUnitAt(start) == next.codeUnitAt(start)) {
    start += 1;
  }
  var end = doc.length;
  var nextEnd = next.length;
  while (end > start && nextEnd > start && doc.codeUnitAt(end - 1) == next.codeUnitAt(nextEnd - 1)) {
    end -= 1;
    nextEnd -= 1;
  }
  return Plan(changes: ChangeSpec(from: start, to: end, insert: next.substring(start, nextEnd)));
}

/// What a row that writes at once writes: a plan, or a block for [insertBlock] to place.
sealed class RowWrite {
  const RowWrite();
}

/// Words, a lead or a form at the caret.
class RowPlan extends RowWrite {
  const RowPlan(this.plan);
  final Plan plan;
}

/// A block, with where the caret goes in it.
class RowBlock extends RowWrite {
  const RowBlock(this.text, this.select);
  final String text;
  final BlockSelect select;
}

/// What a row that writes at once writes at the caret; null for a row that is not one of those. `effects` are the
/// effects the list was given, for an `effect:` row.
RowWrite? planFor(EditorState state, String id, DateTime now, {List<PlusEffect> effects = const <PlusEffect>[]}) {
  final at = state.selection.main.head;
  switch (id) {
    case 'time':
      return RowPlan(wordsPlan(state, at, timeWords(now, onNamingLine(state)).words));
    case 'todo':
      return RowPlan(itemPlan(state, at, ItemKind.todo));
    case 'choice':
      return RowPlan(itemPlan(state, at, ItemKind.choice));
    case 'bullets':
      return RowPlan(itemPlan(state, at, ItemKind.bullet));
    case 'numbers':
      return RowPlan(itemPlan(state, at, ItemKind.number));
    case 'heading':
      return RowPlan(formPlan(state, at, LineForm.heading));
    case 'quote':
      return RowPlan(formPlan(state, at, LineForm.quote));
    case 'sum':
      return RowPlan(formPlan(state, at, LineForm.sum));
    case 'footnote':
      return RowPlan(footnotePlan(state, at));
    case 'tag':
      return RowPlan(wordsPlan(state, at, '#tag', (from: 1, to: 4)));
    case 'counter':
      return RowPlan(wordsPlan(state, at, counterSeed, (from: 0, to: counterSeed.indexOf(' ['))));
    case 'blank':
      return RowPlan(blankPlan(state, at));
    case 'blankCells':
      final plan = emptyCellsPlan(state, at);
      return plan != null ? RowPlan(plan) : null;
    case 'table':
      return RowBlock(tableSeed.text, tableSeed.select);
    case 'callout':
      return const RowBlock(calloutSeed, BlockSelect.at(calloutSeed.length));
    case 'code':
      return const RowBlock(codeSeed, BlockSelect.at(4));
    case 'formula':
      return const RowBlock(formulaSeed, BlockSelect.at(3));
    case 'divider':
      return const RowBlock('---', BlockSelect.after());
    case 'chart':
      final start = chartSeed.indexOf('Start');
      return RowBlock(chartSeed, BlockSelect.at(start, start + 'Start'.length));
    case 'board':
      final board = boardSeed(state.doc.toString());
      return RowBlock(board.text, board.select);
    case 'dated':
      return RowPlan(datedPlan(state, at, now));
    case 'ticket':
      final plan = ticketPlan(state);
      return plan != null ? RowPlan(plan) : null;
  }
  if (id.startsWith('query:')) {
    final block = querySeed(id);
    return block != null ? RowBlock(block.text, block.select) : null;
  }
  if (id.startsWith('effect:')) {
    PlusEffect? effect;
    for (final each in effects) {
      if ('effect:${each.name}' == id) {
        effect = each;
        break;
      }
    }
    if (effect == null) return null;
    // Its marks round a word to write over, as the tag's and the chart's seeds are: the marks alone draw nothing.
    final mark = effect.delimiter;
    return RowPlan(wordsPlan(state, at, '$mark$effectSeedWords$mark', (from: mark.length, to: mark.length + effectSeedWords.length)));
  }
  return null;
}

final RegExp _quoteMarks = RegExp(r'^\s*(?:>\s*)+');

/// A blank, `{?}`, with the caret between its `?` and `}` so the question is typed straight in, as the tag row
/// leaves `tag` to write over. On an empty list item or to-do it is the item's words, since a blank there is meant
/// as one; anywhere else it takes a line of its own by the rule every drawn thing keeps ([ownLinePlan]), a blank
/// line first under a table row, a list item or a quote, or the parser reads it as part of that block.
Plan blankPlan(EditorState state, int at) {
  final line = state.doc.lineAt(at);
  final lead = listLead(line.text.replaceFirst(_quoteMarks, ''));
  if (lead != null && lineWords(line.text).isEmpty) return wordsPlan(state, line.to, '{?}', (from: 2, to: null));
  final plan = ownLinePlan(state, at, '{?}');
  final change = plan.changes as Change;
  return Plan(changes: plan.changes, selection: (anchor: change.from + (change.insert as String).indexOf('{?}') + 2, head: null));
}

final RegExp _pipe = RegExp(r'(?<!\\)\|');
final RegExp _rowStart = RegExp(r'^\s*\|');
final RegExp _divider = RegExp(r'^\s*\|?\s*:?-+');

/// The table straight above the line at `at`, its body rows' empty cells as ranges, or null where there is none or
/// none is empty.
List<({int from, int to})>? emptyCellsAbove(EditorState state, int at) {
  final line = state.doc.lineAt(at);
  if (line.number < 2) return null;
  final rows = <({int from, String text})>[];
  for (var n = line.number - 1; n >= 1; n -= 1) {
    final above = state.doc.line(n);
    if (!_rowStart.hasMatch(above.text)) break;
    rows.insert(0, (from: above.from, text: above.text));
  }
  if (rows.length < 3 || !_divider.hasMatch(rows[1].text)) return null;
  final cells = <({int from, int to})>[];
  for (final row in rows.skip(2)) {
    final pipes = <int>[for (final found in _pipe.allMatches(row.text)) found.start];
    for (var i = 0; i + 1 < pipes.length; i += 1) {
      final inside = row.text.substring(pipes[i] + 1, pipes[i + 1]);
      if (jsTrim(inside).isEmpty) cells.add((from: row.from + pipes[i] + 1, to: row.from + pipes[i + 1]));
    }
  }
  return cells.isNotEmpty ? cells : null;
}

/// A blank in every empty body cell of the table above, as one Undo; the caret stays where it was, outside the
/// table.
Plan? emptyCellsPlan(EditorState state, int at) {
  final cells = emptyCellsAbove(state, at);
  if (cells == null) return null;
  // Every cell is above the caret, so it moves on by what they grew.
  var grew = 0;
  for (final cell in cells) {
    grew += ' {?} '.length - (cell.to - cell.from);
  }
  return Plan(
    changes: <ChangeSpec>[for (final cell in cells) ChangeSpec(from: cell.from, to: cell.to, insert: ' {?} ')],
    selection: (anchor: at + grew, head: null),
  );
}

bool _focused(StateCommandTarget view) => view is EditorViewLike && view.hasFocus;

/// Writes a row that writes at once, as one Undo; answers whether it wrote.
bool writeRow(StateCommandTarget view, String id, DateTime now, {List<PlusEffect> effects = const <PlusEffect>[]}) {
  final found = planFor(view.state, id, now, effects: effects);
  switch (found) {
    case null:
      return false;
    case RowBlock():
      view.dispatch(insertBlock(view.state, found.text, found.select, userEvent: 'input.plus', hasFocus: _focused(view)));
    case RowPlan():
      view.dispatch(applyPlan(view.state, found.plan, userEvent: 'input.plus', hasFocus: _focused(view)));
  }
  return true;
}

/// A link to another note at the caret: `[[Title]]`, spaced from the words around it.
void writeNoteLink(StateCommandTarget view, String title) {
  view.dispatch(applyPlan(view.state, wordsPlan(view.state, view.state.selection.main.head, '[[$title]]'), userEvent: 'input.plus', hasFocus: _focused(view)));
}

/// A canvas drawn in a frame, on a line of its own: `![[Title]]`.
void writeCanvasFrame(StateCommandTarget view, String title) {
  view.dispatch(
    applyPlan(view.state, ownLinePlan(view.state, view.state.selection.main.head, '![[$title]]', apart: true), userEvent: 'input.plus.drawn', hasFocus: _focused(view)),
  );
}

final RegExp _unlinkable = RegExp(r'[|#\]]');

/// The titles a link can be made to: a link cannot hold `|`, `#` or `]`, and a note does not link to itself. Those
/// that hold part of `looking`, at most twelve.
List<String> linkableTitles(Iterable<String> titles, String own, String looking) {
  final words = jsTrim(looking).toLowerCase();
  return titles.where((title) => title.isNotEmpty && !_unlinkable.hasMatch(title) && title != own && title.toLowerCase().contains(words)).take(12).toList();
}
