/// Where a thing put into a note goes: the rules the + beside the line keeps, and with it press and hold's Add
/// image, a pasted picture and Style's table and rule. A port of `src/app/editor/inserts.ts`.
///
/// Three kinds of insert, by what they are (docs/DESIGN.md §141 in tauri/):
///
/// - **A thing drawn on a line of its own**, a picture, a place, a film, a canvas's frame: it takes the caret's line
///   when that line says nothing ([givesWay]), or goes on a new line after it, so a line is never split. A blank
///   line goes before it when the line above is a list item, a quote or a table row, or the thing would be read as
///   part of that block: `- [ ] ` then a picture was a to-do whose words were the picture, and a picture on the
///   empty line under a table was a row of it. A place, a film and a frame are links, so they keep apart from a
///   paragraph above too (`apart`): under `Lunch at the harbour` a place would be read, by any other reader, as the
///   end of the sentence. A picture under a paragraph stays as it was, which every reader draws as a picture of its
///   own. The caret is left on a fresh line after it, so typing carries on underneath.
/// - **A block**, a table, a rule, a fence: the same, and a blank line on either side where the line there has
///   words. Without the one after, a table took the next line of words as a row. Without the one before, a rule
///   under a paragraph reads as a heading in Obsidian and GitHub, though never in the app, whose parser has no
///   setext headings.
/// - **Words at the caret**, the time, a link to a note: a space either side where a sentence needs one.
///
/// And a line's lead, for a to-do, a list or a heading: an empty item's lead becomes the new one, keeping its
/// indent, and a line of words gets a new line under it, since the + adds and never rewrites what a line says.
///
/// Every insert is one transaction with its history isolated, so one Undo takes back exactly it. The plans are
/// pure, over a state; [applyPlan] makes the transaction of one.
///
/// Some writes land late: a place waits for its fix and its name, a picture for the picker. The place they go is
/// kept from the tap ([reserveSpot]) and mapped through every change made meanwhile, and a write that lands after
/// the person has gone to another field does not take the focus back to the note ([FocusToken]).
///
/// What differs:
/// - the web's functions take the view and dispatch; these take the state and answer the [Transaction] (`apply` is
///   [applyPlan], with `view.hasFocus` a parameter);
/// - [reserveSpot] answers the handle and the transaction that keeps it; [releaseSpot] answers a transaction, and
///   the web's guard for a view already taken out of the page is the caller's;
/// - [insertLineAt] answers its transaction and where the new line starts: the caller dispatches it, takes focus
///   back when the token is fresh and the view has lost it, then reserves that place on the new state
///   (`reserveSpot(tr.state, lineStart)`), which the web does in the one call;
/// - [nameLater] answers the transaction, or null where the web answers false;
/// - `focusToken` listened to the page's `focusin`; a [FocusToken] is told by whoever owns focus ([FocusToken.moved]);
/// - `afterComposition` waits on the view's composition and is the input layer's (lib/editor/input), not here;
/// - a [Plan]'s selection is a record, and [Plan.editorSelection] makes the state's selection of it; a
///   `BlockSelect` is [BlockSelect.at] or [BlockSelect.after];
/// - the parser always has the whole tree (syntax_tree.dart), so `holds` never falls back to the line's own lead
///   for want of one, though it reads the lead first as the web does.
library;

import '../../core/item_syntax.dart';
import '../state/change.dart';
import '../state/history.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/text.dart';
import '../syntax/tree.dart';
import 'syntax_tree.dart';

/// What an insert changes, and where the caret or the selection goes after (`Plan`).
class Plan {
  const Plan({required this.changes, this.selection});

  /// A [ChangeSpec] or a `List` of them.
  final Object changes;

  /// Where the caret goes (`anchor` alone) or what is selected; null to leave the selection to be mapped.
  final ({int anchor, int? head})? selection;

  /// [selection] as the state's selection, for a transaction.
  EditorSelection? get editorSelection => selection == null ? null : EditorSelection.single(selection!.anchor, selection!.head);
}

/// Where the caret goes in a block: an offset into its text (a range, to select a word to write over), or a fresh
/// line after it (`BlockSelect`).
class BlockSelect {
  /// At `from` in the block's text, or `from` to `to` selected.
  const BlockSelect.at(int this.from, [this.to]);

  /// On a fresh line after the block: the web's `'after'`.
  const BlockSelect.after() : from = null, to = null;

  final int? from;
  final int? to;

  /// Whether this is the fresh line after.
  bool get isAfter => from == null;
}

/// Whether a line may be taken whole by an insert: it says nothing ([lineWords]), and holds no bookmark or anchor
/// that taking it would lose. `- [ ] ^ship` names a card on a board; it is kept, and the insert goes under it.
bool givesWay(String text) => lineWords(text) == '' && withoutBookmark(text) == text && anchorSpan(text) == null;

/// The syntax nodes a line inside which lazily takes the next line in.
const Set<String> _holding = <String>{'ListItem', 'BulletList', 'OrderedList', 'Blockquote', 'Table', 'TableRow', 'TableHeader'};

final RegExp _quoteStart = RegExp(r'^\s*>');
final RegExp _rowStart = RegExp(r'^\s*\|');

/// Whether a line is part of a list, a quote or a table, which a line of its own under it would join: read from the
/// line's own lead, and from the app's parser for a line with none (an item's words run on to a second line).
bool _holds(EditorState state, Line? line) {
  if (line == null || jsTrim(line.text).isEmpty) return false;
  if (listLead(line.text) != null || _quoteStart.hasMatch(line.text) || _rowStart.hasMatch(line.text)) return true;
  final tree = ensureSyntaxTree(state, line.to, 50);
  for (SyntaxNode? node = tree.resolveInner(line.to, -1); node != null; node = node.parent) {
    if (_holding.contains(node.name)) return true;
  }
  return false;
}

Line? _lineBefore(EditorState state, Line line) => line.number > 1 ? state.doc.line(line.number - 1) : null;

Line? _lineAfter(EditorState state, Line line) => line.number < state.doc.lines ? state.doc.line(line.number + 1) : null;

Line _lineAtPos(EditorState state, int at) => state.doc.lineAt(at < 0 ? 0 : (at > state.doc.length ? state.doc.length : at));

bool _hasWords(Line? line) => line != null && jsTrim(line.text).isNotEmpty;

/// A thing drawn on a line of its own, at the caret's line `at` (see the header). `apart`, for a link drawn as a
/// card (a place, a film, a frame), keeps a blank line from any words above as well as from a block.
Plan ownLinePlan(EditorState state, int at, String text, {bool apart = false}) {
  final line = _lineAtPos(state, at);
  final take = givesWay(line.text);
  final above = take ? _lineBefore(state, line) : line;
  final gap = _holds(state, above) || (apart && _hasWords(above)) ? '\n' : '';
  final insert = take ? '$gap$text\n' : '\n$gap$text\n';
  final from = take ? line.from : line.to;
  return Plan(changes: ChangeSpec(from: from, to: line.to, insert: insert), selection: (anchor: from + insert.length, head: null));
}

/// A block at the caret's line `at`, with `select` saying where the caret goes in it (see the header).
Plan blockPlan(EditorState state, int at, String text, BlockSelect select) {
  final line = _lineAtPos(state, at);
  final take = givesWay(line.text);
  final above = take ? _lineBefore(state, line) : line;
  final before = take ? (_hasWords(above) ? '\n' : '') : '\n\n';
  final next = _lineAfter(state, line);
  final after = select.isAfter
      ? '\n'
      : _hasWords(next)
      ? '\n'
      : '';
  final insert = '$before$text$after';
  final from = take ? line.from : line.to;
  final start = from + before.length;
  final ({int anchor, int? head}) selection = select.isAfter
      ? (anchor: from + insert.length, head: null)
      : (anchor: start + select.from!, head: start + (select.to ?? select.from!));
  return Plan(changes: ChangeSpec(from: from, to: line.to, insert: insert), selection: selection);
}

/// What a word before the caret ends with that wants a space after it: a letter, a digit, or closing punctuation.
final RegExp _spaceAfter = RegExp(r'[\p{L}\p{N}.,:;!?)\]]', unicode: true);

/// What a word after the caret starts with that wants a space before it.
final RegExp _spaceBefore = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Words at the caret, spaced from the words either side; the caret after them, or `select` within them.
Plan wordsPlan(EditorState state, int at, String words, [({int from, int? to})? select]) {
  final before = state.doc.sliceString(at - 1 < 0 ? 0 : at - 1, at);
  final after = state.doc.sliceString(at, at + 1 > state.doc.length ? state.doc.length : at + 1);
  final lead = _spaceAfter.hasMatch(before) ? ' ' : '';
  final tail = _spaceBefore.hasMatch(after) ? ' ' : '';
  final start = at + lead.length;
  final ({int anchor, int? head}) selection = select != null
      ? (anchor: start + select.from, head: start + (select.to ?? select.from))
      : (anchor: start + words.length, head: null);
  return Plan(changes: ChangeSpec(from: at, insert: '$lead$words$tail'), selection: selection);
}

/// A quote's markers at the start of a line, and the spaces after them.
final RegExp _quoted = RegExp(r'^\s*(?:>[ \t]*)+');
final RegExp _endsInSpace = RegExp(r'\s$');

/// A line's quote, and a space after it where it has none, for a lead that goes inside it.
String _quoteOf(String text) {
  final quote = _quoted.firstMatch(text)?.group(0) ?? '';
  return quote.isNotEmpty && !_endsInSpace.hasMatch(quote) ? '$quote ' : quote;
}

/// The kinds of item the + can start (`ItemKind`).
enum ItemKind { todo, choice, bullet, number }

final RegExp _numbered = RegExp(r'^(\d+)[.)]$');
final RegExp _isBullet = RegExp(r'^[-*+]$');

/// The number of the next step after `line`, when it is a numbered item; 1 otherwise.
int _nextNumber(Line? line) {
  final lead = line != null ? listLead(line.text) : null;
  final n = lead != null ? _numbered.firstMatch(lead.marker)?.group(1) : null;
  // JavaScript's Number of a run of digits too long for an int is still a number; a note has no such step.
  return n != null && n.isNotEmpty ? (int.tryParse(n) ?? 0) + 1 : 1;
}

/// An item's whole lead for `kind`, with `indent` before it and `marker` as the list's own where the kind allows.
String _leadFor(ItemKind kind, String indent, String? marker, int number) {
  final bullet = marker != null && _isBullet.hasMatch(marker) ? marker : '-';
  if (kind == ItemKind.todo) return '$indent${marker ?? '-'} [ ] ';
  if (kind == ItemKind.choice) return '$indent$bullet ( ) ';
  if (kind == ItemKind.bullet) return '$indent$bullet ';
  final numbered = marker != null && _numbered.hasMatch(marker) ? marker : '$number.';
  return '$indent$numbered ';
}

/// Whether a lead already is what `kind` would write, so nothing is written and no second box is added.
bool _already(ItemKind kind, ListLead lead) {
  final bullet = _isBullet.hasMatch(lead.marker);
  if (kind == ItemKind.todo) return lead.done != null;
  if (kind == ItemKind.choice) return lead.picked != null;
  if (kind == ItemKind.bullet) return bullet && lead.done == null && lead.picked == null;
  return !bullet && lead.done == null && lead.picked == null;
}

/// An item started at the caret's line (the + never changes what a line says, which is Style's job):
///
/// - on an empty item, its lead becomes the kind's, keeping its indent and, where it can, its marker; an item that
///   is that kind already is left as it is, and the caret goes to its end;
/// - on an empty quote line, the item goes inside the quote;
/// - on an empty line, the item takes the indent of an item above it;
/// - under a line of words, a new line carries it, with the line's quote and, for an item, its indent.
Plan itemPlan(EditorState state, int at, ItemKind kind) {
  final line = _lineAtPos(state, at);
  final quote = _quoteOf(line.text);
  final quotedLength = (_quoted.firstMatch(line.text)?.group(0) ?? '').length;
  final rest = line.text.substring(quotedLength > line.text.length ? line.text.length : quotedLength);
  final lead = listLead(rest);
  final above = _lineBefore(state, line);
  if (lineWords(line.text).isNotEmpty) {
    final own = lead != null
        ? _leadFor(kind, lead.indent, kind == ItemKind.number ? null : lead.marker, _nextNumber(line))
        : _leadFor(kind, '', null, 1);
    final insert = '\n$quote$own';
    return Plan(changes: ChangeSpec(from: line.to, insert: insert), selection: (anchor: line.to + insert.length, head: null));
  }
  if (lead != null) {
    final leadFrom = line.from + (line.text.length - rest.length);
    if (_already(kind, lead)) return Plan(changes: const <ChangeSpec>[], selection: (anchor: line.to, head: null));
    final own = _leadFor(kind, lead.indent, kind == ItemKind.number ? null : lead.marker, _nextNumber(above));
    return Plan(
      changes: ChangeSpec(from: leadFrom, to: leadFrom + lead.wordsAt, insert: own),
      selection: (anchor: leadFrom + own.length + (line.to - leadFrom - lead.wordsAt), head: null),
    );
  }
  if (quote.isNotEmpty) {
    final own = _leadFor(kind, '', null, 1);
    return Plan(
      changes: ChangeSpec(from: line.from, to: line.to, insert: '$quote$own'),
      selection: (anchor: line.from + quote.length + own.length, head: null),
    );
  }
  final aboveLead = above != null ? listLead(above.text) : null;
  final own = _leadFor(kind, aboveLead?.indent ?? '', null, _nextNumber(above));
  return Plan(changes: ChangeSpec(from: line.from, to: line.to, insert: own), selection: (anchor: line.from + own.length, head: null));
}

/// The forms a line takes that are not a list: a heading, a quote, a sum (`LineForm`).
enum LineForm { heading, quote, sum }

const Map<LineForm, String> _formLeads = <LineForm, String>{LineForm.heading: '## ', LineForm.quote: '> ', LineForm.sum: '= '};

/// A line's form at the caret's line. On an empty line it is written there; inside a quote it stays inside; an
/// empty item's lead gives way to a heading or a quote, and stays before a sum, which a list item may be. Under a
/// line of words, a new line carries it.
Plan formPlan(EditorState state, int at, LineForm form) {
  final line = _lineAtPos(state, at);
  final prefix = _formLeads[form]!;
  final quote = _quoteOf(line.text);
  if (lineWords(line.text).isNotEmpty) {
    final insert = '\n${form == LineForm.quote ? '' : quote}$prefix';
    return Plan(changes: ChangeSpec(from: line.to, insert: insert), selection: (anchor: line.to + insert.length, head: null));
  }
  final rest = line.text.substring((_quoted.firstMatch(line.text)?.group(0) ?? '').length);
  final lead = listLead(rest);
  if (form == LineForm.quote && quote.isNotEmpty) return Plan(changes: const <ChangeSpec>[], selection: (anchor: line.to, head: null));
  String insert;
  if (form == LineForm.sum && lead != null) {
    insert = '$quote${lead.indent}${lead.marker} $prefix';
  } else {
    insert = '$quote$prefix';
  }
  return Plan(changes: ChangeSpec(from: line.from, to: line.to, insert: insert), selection: (anchor: line.from + insert.length, head: null));
}

/// A footnote's reference in words, and its definition's opening at the start of a line.
final RegExp _footnoteRef = RegExp(r'\[\^(\d+)\]');
final RegExp _footnoteDef = RegExp(r'^\s{0,3}\[\^[^\]\s]+\]:');
final RegExp _rowOrFence = RegExp(r'^\s*(\||```|~~~)');
final RegExp _trailingSpace = RegExp(r'\s+$');

/// A line a footnote's marker may close: words, and not a table's row, a fence or a footnote's own line.
bool _annotatable(Line? line) {
  if (line == null || lineWords(line.text).isEmpty) return false;
  return !_rowOrFence.hasMatch(line.text) && !_footnoteDef.hasMatch(line.text);
}

/// A footnote: the next free number, and its line at the end of the note, with the caret on it to write what it
/// says. The number goes where the caret is, as words are put there; but on an empty line, which is where the +
/// beside the line is, it closes the words just above instead, as the Guide writes one (`four hundred[^1]`), since
/// a marker alone on a line is a footnote to nothing.
Plan footnotePlan(EditorState state, int at) {
  final doc = state.doc.toString();
  var number = 0;
  for (final found in _footnoteRef.allMatches(doc)) {
    // A number too long to be one is no footnote a person wrote; JavaScript reads it as a float and goes on.
    final n = int.tryParse(found.group(1)!) ?? 0;
    if (n > number) number = n;
  }
  number += 1;
  final marker = '[^$number]';
  final line = _lineAtPos(state, at);
  final above = lineWords(line.text).isNotEmpty ? null : _lineBefore(state, line);
  final Plan words = _annotatable(above)
      ? Plan(changes: ChangeSpec(from: above!.from + above.text.replaceFirst(_trailingSpace, '').length, insert: marker))
      : wordsPlan(state, at, marker);
  final change = words.changes as Change;
  final from = change.from, inserted = change.insert as String;
  final text = from == doc.length ? '$doc$inserted' : doc;
  final last = text.substring(text.lastIndexOf('\n') + 1);
  final gap = text.isEmpty
      ? ''
      : _footnoteDef.hasMatch(last)
      ? '\n'
      : text.endsWith('\n\n')
      ? ''
      : text.endsWith('\n')
      ? '\n'
      : '\n\n';
  final definition = '$gap[^$number]: ';
  final shift = inserted.length;
  return Plan(
    changes: <ChangeSpec>[change, ChangeSpec(from: doc.length, insert: definition)],
    selection: (anchor: doc.length + shift + definition.length, head: null),
  );
}

/// The transaction of a plan as one step of its own, the caret kept in view while the note has focus (`apply`).
Transaction applyPlan(EditorState state, Plan plan, {String userEvent = 'input.plus', bool hasFocus = false}) {
  return state.update(
    TransactionSpec(
      changes: plan.changes,
      selection: plan.editorSelection,
      scrollIntoView: hasFocus,
      userEvent: userEvent,
      annotations: isolateHistory.of('full'),
    ),
  );
}

// ---- the places kept for writes that come late --------------------------------------------------------------------

/// Where writes still coming will go, kept in step with every edit made meanwhile. Saving a picture takes a moment
/// (shrinking, then a trip to Rust), and on Android the caret can move under it, and a place waits for its fix, so
/// the place is taken when it is asked for, not when the thing is ready.
final StateEffectType<({int id, int pos})> markSpot = StateEffect.define<({int id, int pos})>();
final StateEffectType<int> _clearSpot = StateEffect.define<int>();
final StateField<Map<int, int>> _spots = StateField.define<Map<int, int>>(
  create: (_) => const <int, int>{},
  update: (value, tr) {
    var next = value;
    if (tr.docChanged && value.isNotEmpty) {
      next = <int, int>{for (final entry in value.entries) entry.key: tr.changes.mapPos(entry.value, 1)};
    }
    for (final effect in tr.effects) {
      final mark = markSpot.cast(effect);
      if (mark != null) {
        next = <int, int>{...next, mark.value.id: mark.value.pos};
      } else if (effect.isOf(_clearSpot)) {
        next = <int, int>{...next}..remove(effect.value);
      }
    }
    return next;
  },
);

/// The kept places, for an editor that takes late writes: installed with the pictures.
final StateField<Map<int, int>> insertSpots = _spots;

int _spotIds = 0;

/// Remembers `pos` (the caret by default), for a write that will come later. Answers a handle for it, and the
/// transaction that keeps it.
({int spot, Transaction tr}) reserveSpot(EditorState state, [int? pos]) {
  final id = _spotIds += 1;
  return (spot: id, tr: state.update(TransactionSpec(effects: markSpot.of((id: id, pos: pos ?? state.selection.main.head)))));
}

/// Where a kept place is now, or null when it was let go.
int? spotAt(EditorState state, int spot) => state.fieldOrNull(_spots)?[spot];

/// Whether a place is still kept (the web's `field(spots, false)?.has(spot)`).
bool hasSpot(EditorState state, int spot) => state.fieldOrNull(_spots)?.containsKey(spot) ?? false;

/// Forgets a kept place, when the write never came or has landed.
Transaction releaseSpot(EditorState state, int spot) => state.update(TransactionSpec(effects: _clearSpot.of(spot)));

/// Whether the person has gone somewhere else since a write was asked for: a focus anywhere outside the note (the
/// Find bar, a sheet's field) makes the token stale, and a write that lands then takes no selection, no scroll and
/// no focus. Focus falling to nothing at all, as it does on the way back from a picker, is not somewhere else, and
/// is not told to the token.
class FocusToken {
  bool _stale = false;

  /// Told of every focus that lands while the write is awaited: `insideNote` for one inside the editor.
  void moved({required bool insideNote}) {
    if (!insideNote) _stale = true;
  }

  /// Whether the person is still where they were.
  bool fresh() => !_stale;
}

/// A line of its own at a kept place, by [ownLinePlan], as one step. The caret goes after it only if it is still
/// where it was when the write was asked for; when not `fresh` (a stale [FocusToken]) nothing but the words moves,
/// and no scroll. A caret left on the empty line the thing took is carried past it all the same, or the first
/// letter typed on coming back would go in front of the thing and break it. Answers the transaction, and where the
/// new line starts in its document, for a kept place for a name that follows it ([nameLater]).
({Transaction tr, int lineStart}) insertLineAt(EditorState state, int spot, String text, {String? userEvent, bool fresh = true, bool apart = false}) {
  final pos = spotAt(state, spot) ?? state.selection.main.head;
  final main = state.selection.main;
  final stayed = main.empty && main.head == pos;
  final plan = ownLinePlan(state, pos, text, apart: apart);
  final change = plan.changes as Change;
  final lineStart = change.from + (change.insert as String).length - text.length - 1;
  final took = givesWay(_lineAtPos(state, pos).text);
  final moved = fresh && stayed && plan.selection != null;
  final tr = state.update(
    TransactionSpec(
      changes: plan.changes,
      selection: moved
          ? plan.editorSelection
          : took
          ? state.selection.map(state.changes(plan.changes), 1)
          : null,
      scrollIntoView: moved,
      userEvent: userEvent,
      annotations: isolateHistory.of('full'),
    ),
  );
  return (tr: tr, lineStart: lineStart);
}

/// A place's name that came after its line was written with the coordinates: written over them only while that
/// line is still the newest change the note's history holds and nothing waits to be redone, so the first Undo gives
/// back the coordinates and the second takes the line. Anything the person did since - typing, an Undo - keeps the
/// coordinates, or the next Undo would take back a name instead of what they just did. `depth` is the history's
/// depth just after the line, and steps the person did not take are the caller's to count into it. A note live on
/// two devices undoes with Yjs, and there nothing is written. Null when nothing is written.
Transaction? nameLater(EditorState state, int spot, int depth, String was, String named) {
  if (state.fieldOrNull(historyField) == null) return null;
  if (undoDepth(state) != depth || redoDepth(state) != 0) return null;
  final pos = spotAt(state, spot);
  if (pos == null) return null;
  final line = state.doc.lineAt(pos < state.doc.length ? pos : state.doc.length);
  if (line.from != pos || line.text != was) return null;
  return state.update(
    TransactionSpec(
      changes: ChangeSpec(from: line.from, to: line.to, insert: named),
      userEvent: 'input.plus.drawn',
      annotations: isolateHistory.of('full'),
    ),
  );
}
