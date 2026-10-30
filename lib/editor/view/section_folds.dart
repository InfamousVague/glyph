/// Sections folded away, and toggle blocks (Matt, 2026-10-30: "add all 12", the plain-Markdown features): a heading
/// folds what is under it, and a `<details>` block is drawn as a toggle that opens and closes. Neither writes a
/// thing into the note: what is folded is this device's, kept for each note in its storage ([foldsKey]).
///
/// - **A heading folds** everything under it until the next heading of the same level or higher (`## Plan` folds its
///   `###`s too), its trailing blank lines left out so the next heading keeps its room. Its triangle is in the line's
///   gutter, before the comment glyph (lib/editor/comments/comment_gutter.dart draws both): with a pointer it comes
///   on a hover, and a folded heading wears it all the time; under a finger every heading that folds wears it. A
///   folded heading has a quiet ⋯ after its words, which unfolds it too. A heading with nothing but blank lines
///   under it does not fold.
/// - **A toggle** is the HTML GitHub, GitLab, Obsidian, VS Code and Typora all draw as one:
///
///       <details>
///       <summary>Packing list</summary>
///
///       - Boots
///
///       </details>
///
///   `<details>` and `<summary>` on one line are read the same, `<details open>` starts open, and toggles nest. It
///   was picked over a callout (`> [!toggle] Title`) because a callout is Obsidian's alone, and only its own five
///   kinds there: GitHub draws `[!toggle]` as the words of a quote, and every other app as a quote, where `<details>`
///   is a toggle in all of them and round-trips byte for byte. The head is drawn as a row, its triangle and its
///   summary; the closing `</details>` as a short rule. Each steps aside for its lines while the caret is on them,
///   as an embed does (drawn_block.dart), so the summary is edited where it is written. Inserted from the +'s More
///   and the `/` palette (lib/editor/plus/add_rows.dart `toggleSeed`).
/// - **What is folded stays found.** The words are the note's as ever: the note's find bar matches inside a fold,
///   and a match there, or a landing on a line in one (a search's hit, a `[[Note#Heading]]`), unfolds what holds it
///   rather than leaving the caret where nothing shows. A pointer's press that would land in one lands at the end
///   of its heading.
/// - **Never typed into unseen.** A person's edit that would change what is folded without taking it whole (a
///   Backspace at the start of the heading after it, a Delete at the end of the folded heading) unfolds it instead,
///   and the next press does what it says; a selection that holds the whole of it deletes it as it is. What the app
///   writes (a sync, an undo) goes through, and the folds follow their headings.
/// - **Keys**: Cmd-Alt-[ folds the section or the toggle the caret is in (Ctrl-Alt-[ off a Mac), Cmd-Alt-] unfolds it.
/// - **Kept per device, per note**, under [foldsKey]: what differs from how the note opens (a heading open, a toggle
///   shut unless it says `open`), by the heading's level, words and which of the same it is. The newest
///   [foldsRemembered] notes.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/stored.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../editor.dart';
import '../input/keymap.dart' show editorKeymap;
import '../commands/commands.dart' show KeyBinding;
import '../looks/look.dart' show layoutUnitFloor;
import '../looks/note_face.dart';
import 'blocks.dart' show ClassedBlockWidget;
import 'drawn_block.dart';
import 'editor_view.dart';
import 'extended.dart' show frontMatter;
import 'lines.dart' show docLineInFence;

/// What folds: a heading's section or a toggle block.
enum FoldKind { heading, toggle }

/// One place that folds, read from the words.
@immutable
class FoldPoint {
  const FoldPoint({required this.kind, required this.line, required this.from, required this.headTo, required this.bodyFrom, required this.to, required this.title, this.level = 0, this.open = false, this.closeFrom});

  final FoldKind kind;

  /// The heading's line, or the toggle's first, from 1.
  final int line;

  /// Where that line starts: what a fold is known by while the note is open.
  final int from;

  /// The end of what stays drawn: the heading's line, or the toggle's `<summary>` line.
  final int headTo;

  /// What folds away: from the start of the line after the head to the end of the section's last line of words, or
  /// to the end of the toggle's `</details>` line.
  final int bodyFrom;
  final int to;

  /// The heading's words, or the summary's.
  final String title;

  /// A heading's level; 0 for a toggle.
  final int level;

  /// A toggle written `<details open>`.
  final bool open;

  /// Where a toggle's `</details>` line starts.
  final int? closeFrom;

  /// Whether [pos] is in what folds away.
  bool hides(int pos) => pos >= bodyFrom && pos <= to;

  @override
  String toString() => 'FoldPoint(${kind.name} $line "$title" $from-$headTo|$bodyFrom-$to)';
}

final RegExp _heading = RegExp(r'^ {0,3}(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$');
final RegExp _open = RegExp(r'^\s*<details(\s+open(?:=(?:"[^"]*"|' "'[^']*'" r'|\S+))?)?\s*>\s*(?:<summary>(.*?)</summary>\s*)?$', caseSensitive: false);
final RegExp _summary = RegExp(r'^\s*<summary>(.*?)</summary>\s*$', caseSensitive: false);
final RegExp _close = RegExp(r'^\s*</details>\s*$', caseSensitive: false);

/// A toggle's head as written, `<details>` with its `<summary>` on the same line or the next: whether it starts
/// open and its summary's words. Null for a line that is no toggle's head. [next] is the line after, for a summary
/// written on a line of its own, and [lines] says how many lines the head is.
({bool open, String title, int lines})? toggleHead(String text, [String? next]) {
  final match = _open.firstMatch(text);
  if (match == null) return null;
  final open = match.group(1) != null;
  final same = match.group(2);
  if (same != null) return (open: open, title: same.trim(), lines: 1);
  final below = next == null ? null : _summary.firstMatch(next);
  if (below != null) return (open: open, title: below.group(1)!.trim(), lines: 2);
  // GitHub draws a toggle with no summary as "Details".
  return (open: open, title: 'Details', lines: 1);
}

/// What one line is to the folds: a heading, a toggle's `<details>` (with its summary when it is on the same line),
/// a `<summary>` line of its own, or a `</details>`.
@immutable
class _FoldLine {
  const _FoldLine.heading(this.level, this.title)
      : kind = 1,
        open = false;
  const _FoldLine.toggle(this.open, this.title)
      : kind = 2,
        level = 0;
  const _FoldLine.summary(this.title)
      : kind = 3,
        level = 0,
        open = false;
  const _FoldLine.close()
      : kind = 4,
        level = 0,
        open = false,
        title = null;

  final int kind;
  final int level;
  final bool open;
  final String? title;
}

/// The lines that fold, kept with the document's tree: a letter typed reads only the line it changed.
final LineFact<_FoldLine> _lines = LineFact<_FoldLine>((text) {
  if (text.contains('<')) {
    final open = _open.firstMatch(text);
    if (open != null) return _FoldLine.toggle(open.group(1) != null, open.group(2)?.trim());
    final summary = _summary.firstMatch(text);
    if (summary != null) return _FoldLine.summary(summary.group(1)!.trim());
    if (_close.hasMatch(text)) return const _FoldLine.close();
  }
  if (!text.contains('#')) return null;
  final heading = _heading.firstMatch(text);
  return heading == null ? null : _FoldLine.heading(heading.group(1)!.length, heading.group(2)!.trim());
});

/// Every place [doc] folds, in order: its headings with words under them and its closed toggles (see the header).
/// Read from the kept lines alone, and the few blank lines at a section's end: never the whole note.
List<FoldPoint> foldPoints(Doc doc) => _points.of(doc);

final DocMemo<List<FoldPoint>> _points = DocMemo<List<FoldPoint>>(_read);

List<FoldPoint> _read(Doc doc) {
  final facts = _lines.of(doc);
  if (facts.isEmpty) return const [];
  final out = <FoldPoint>[];
  final front = frontMatter(doc)?.to ?? 0;
  // Headings still open, innermost last, each with the toggle depth it is at; toggles still open likewise.
  final headings = <({FactLine<_FoldLine> line, int depth})>[];
  final toggles = <({FactLine<_FoldLine> line, FactLine<_FoldLine> head, String title})>[];

  /// A heading's section ends on line [last], which ends at [lastTo]: its blank lines at the end left out.
  void closeHeading(({FactLine<_FoldLine> line, int depth}) h, int last, int lastTo) {
    var end = last, endTo = lastTo;
    while (end > h.line.number) {
      final line = doc.line(end);
      if (line.text.trim().isNotEmpty) break;
      end -= 1;
      endTo = line.from - 1;
    }
    if (end <= h.line.number) return;
    out.add(FoldPoint(kind: FoldKind.heading, line: h.line.number, from: h.line.from, headTo: h.line.to, bodyFrom: h.line.to + 1, to: endTo, title: h.line.fact.title ?? '', level: h.line.fact.level));
  }

  for (var i = 0; i < facts.length; i += 1) {
    final line = facts[i];
    if (line.number <= front || docLineInFence(doc, line.number)) continue;
    final fact = line.fact;
    switch (fact.kind) {
      case 2:
        // Its summary on the next line, where it is written there.
        final next = i + 1 < facts.length ? facts[i + 1] : null;
        final below = fact.title == null && next != null && next.number == line.number + 1 && next.fact.kind == 3 ? next : null;
        toggles.add((line: line, head: below ?? line, title: fact.title ?? below?.fact.title ?? 'Details'));
        if (below != null) i += 1;
      case 4:
        if (toggles.isEmpty) continue;
        final toggle = toggles.removeLast();
        // Its headings end with it.
        while (headings.isNotEmpty && headings.last.depth > toggles.length) {
          closeHeading(headings.removeLast(), line.number - 1, line.from - 1);
        }
        out.add(FoldPoint(
          kind: FoldKind.toggle,
          line: toggle.line.number,
          from: toggle.line.from,
          headTo: toggle.head.to,
          bodyFrom: toggle.head.to + 1,
          to: line.to,
          title: toggle.title,
          open: toggle.line.fact.open,
          closeFrom: line.from,
        ));
      case 1:
        final depth = toggles.length;
        while (headings.isNotEmpty && headings.last.depth == depth && headings.last.line.fact.level >= fact.level) {
          closeHeading(headings.removeLast(), line.number - 1, line.from - 1);
        }
        headings.add((line: line, depth: depth));
    }
  }
  // A toggle left open is no toggle, and its headings end with the note.
  while (headings.isNotEmpty) {
    closeHeading(headings.removeLast(), doc.lines, doc.length);
  }
  out.sort((a, b) => a.from.compareTo(b.from));
  return out;
}

// ---- kept on the device -------------------------------------------------------------------------------------------

/// This device's folds, `{note id: {fold's key: folded}}`: only what differs from how the note opens.
const String foldsKey = 'glyph-folds';

/// How many notes' folds are remembered: the newest.
const int foldsRemembered = 200;

/// A fold's name across openings: its kind, a heading's level, its words, and which of the same it is.
List<String> foldKeys(List<FoldPoint> points) {
  final seen = <String, int>{};
  return [
    for (final point in points)
      () {
        final base = point.kind == FoldKind.heading ? 'h${point.level}|${point.title}' : 't|${point.title}';
        final nth = seen[base] = (seen[base] ?? -1) + 1;
        return '$base|$nth';
      }(),
  ];
}

Map<String, Map<String, bool>> _keptAll() => stored.read<Map<String, Map<String, bool>>>(
      foldsKey,
      const {},
      (raw) => raw is Map
          ? {
              for (final note in raw.entries)
                if (note.key is String && note.value is Map)
                  note.key as String: {
                    for (final fold in (note.value as Map).entries)
                      if (fold.key is String && fold.value is bool) fold.key as String: fold.value as bool,
                  },
            }
          : null,
    );

/// What this device keeps of note [noteId]'s folds.
Map<String, bool> keptFolds(String noteId) => _keptAll()[noteId] ?? const {};

/// Keeps [folds] as note [noteId]'s, the newest of [foldsRemembered].
void keepFolds(String noteId, Map<String, bool> folds) {
  final all = {..._keptAll()}..remove(noteId);
  if (folds.isNotEmpty) all[noteId] = folds;
  final keys = all.keys.toList();
  stored.write(foldsKey, {for (final key in keys.skip(keys.length > foldsRemembered ? keys.length - foldsRemembered : 0)) key: all[key]});
}

bool _foldedAtFirst(FoldPoint point) => point.kind == FoldKind.toggle && !point.open;

// ---- the state ----------------------------------------------------------------------------------------------------

/// What the note's screen gives the folds: the note's id, for what this device keeps of them. Without one nothing
/// is kept, and every heading opens open and every toggle as it is written.
@immutable
class SectionFolds {
  const SectionFolds({this.noteId});
  final String? noteId;
}

final Facet<SectionFolds, List<SectionFolds>> _hooks = Facet.define();

String? _noteOf(EditorState state) {
  final all = state.facet(_hooks);
  return all.isEmpty ? null : all.first.noteId;
}

/// A fold folded or unfolded, by where its line starts.
final StateEffectType<({int at, bool folded})> _setFold = StateEffect.define<({int at, bool folded})>(map: (value, mapping) => (at: mapping.mapPos(value.at, 1), folded: value.folded));

class _Folds {
  const _Folds(this.points, this.folded, this.decorations, this.hidden, this.atomic);
  final List<FoldPoint> points;

  /// The folded points, by [FoldPoint.from].
  final Set<int> folded;
  final DecorationSet decorations;

  /// The points whose fold is drawn (none inside another that is).
  final List<FoldPoint> hidden;

  /// What the caret steps over: what is folded away, and nothing else (a toggle's head is stepped onto, to edit).
  final DecorationSet atomic;

  /// Whether what is drawn moves with the caret: a toggle's head and end step aside for it.
  bool get caretMatters => points.any((point) => point.kind == FoldKind.toggle);
}

_Folds _made(EditorState state, List<FoldPoint> points, Set<int> folded) {
  final ranges = <Range<Decoration>>[];
  final away = <Range<Decoration>>[];
  final hidden = <FoldPoint>[];
  var hiddenTo = -1;
  for (final point in points) {
    if (point.from <= hiddenTo) continue;
    final shut = folded.contains(point.from);
    if (point.kind == FoldKind.toggle) {
      if (!caretIn(state, point.from, point.headTo)) {
        ranges.add(Decoration.replace(widget: ToggleHeadWidget(title: point.title, folded: shut, from: point.from), block: true).range(point.from, point.headTo));
      }
      if (shut) {
        ranges.add(_hiddenFold.range(point.bodyFrom, point.to));
        away.add(_hiddenFold.range(point.bodyFrom, point.to));
        hidden.add(point);
        hiddenTo = point.to;
      } else if (point.closeFrom case final close? when !caretIn(state, close, point.to)) {
        ranges.add(Decoration.replace(widget: ToggleEndWidget(from: close), block: true).range(close, point.to));
      }
      continue;
    }
    if (!shut) continue;
    ranges.add(Decoration.widget(widget: FoldedMarkWidget(from: point.from), side: 1).range(point.headTo));
    ranges.add(_hiddenFold.range(point.bodyFrom, point.to));
    away.add(_hiddenFold.range(point.bodyFrom, point.to));
    hidden.add(point);
    hiddenTo = point.to;
  }
  return _Folds(points, folded, ranges.isEmpty ? Decoration.none : Decoration.set(ranges, true), hidden, away.isEmpty ? Decoration.none : Decoration.set(away));
}

_Folds _create(EditorState state) {
  final points = foldPoints(state.doc);
  final noteId = _noteOf(state);
  final kept = noteId == null ? const <String, bool>{} : keptFolds(noteId);
  final keys = foldKeys(points);
  final folded = <int>{
    for (var i = 0; i < points.length; i += 1)
      if (kept[keys[i]] ?? _foldedAtFirst(points[i])) points[i].from,
  };
  return _made(state, points, folded);
}

final StateField<_Folds> _field = StateField.define<_Folds>(
  create: _create,
  update: (value, tr) {
    var folded = value.folded;
    var moved = false;
    if (tr.docChanged) {
      folded = {for (final at in folded) tr.changes.mapPos(at, 1)};
      moved = true;
    }
    for (final effect in tr.effects) {
      final told = _setFold.cast(effect);
      if (told == null) continue;
      folded = {...folded};
      told.value.folded ? folded.add(told.value.at) : folded.remove(told.value.at);
      moved = true;
    }
    if (tr.reconfigured) return _create(tr.state);
    if (!moved && ((tr.selection == null && !focusMoved(tr)) || !value.caretMatters)) return value;
    final points = tr.docChanged ? foldPoints(tr.state.doc) : value.points;
    if (tr.docChanged) {
      final at = {for (final point in points) point.from};
      folded = {for (final from in folded) if (at.contains(from)) from};
    }
    return _made(tr.state, points, folded);
  },
  provide: (f) => EditorViewLike.decorations.from<_Folds>(f, (value) => value.decorations),
);

/// The folded points that hold [pos], outermost first.
List<FoldPoint> _holding(_Folds folds, int pos) => [
      for (final point in folds.points)
        if (folds.folded.contains(point.from) && point.hides(pos)) point,
    ];

/// A selection that lands in a fold (see the header): a press of a pointer lands at the end of its head; anything
/// else (a find's match, a landing) unfolds what holds it.
Object _kept(Transaction tr) {
  if (tr.docChanged) return tr;
  final folds = tr.startState.fieldOrNull(_field);
  if (folds == null || folds.hidden.isEmpty) return tr;
  final holding = <FoldPoint>{};
  // A find's match brought into view: the find bar scrolls to it and leaves the caret where it was.
  for (final effect in tr.effects) {
    final target = EditorViewLike.scrollIntoViewEffect.cast(effect);
    if (target != null) holding.addAll(_holding(folds, target.value.range.head));
  }
  final selection = tr.selection;
  if (selection == null && holding.isEmpty) return tr;
  for (final range in selection?.ranges ?? const <SelectionRange>[]) {
    holding
      ..addAll(_holding(folds, range.head))
      ..addAll(_holding(folds, range.anchor));
  }
  if (holding.isEmpty) return tr;
  if (selection != null && tr.isUserEvent('select.pointer')) {
    int keep(int pos) {
      for (final point in folds.hidden) {
        if (point.hides(pos)) return point.headTo;
      }
      return pos;
    }

    return <Object>[
      tr,
      TransactionSpec(selection: EditorSelection.create([for (final r in selection.ranges) EditorSelection.range(keep(r.anchor), keep(r.head))], selection.mainIndex), sequential: true),
    ];
  }
  return <Object>[
    tr,
    TransactionSpec(effects: [for (final point in holding) _setFold.of((at: point.from, folded: false))], sequential: true),
  ];
}

/// A person's edit that would change a fold's words unseen (see the header): the fold opened in its place.
Object _guarded(Transaction tr) {
  if (!tr.docChanged) return tr;
  final event = tr.annotation(Transaction.userEvent);
  if (event == null || tr.isUserEvent('undo') || tr.isUserEvent('redo')) return tr;
  final folds = tr.startState.fieldOrNull(_field);
  if (folds == null || folds.hidden.isEmpty) return tr;
  final touched = <FoldPoint>{};
  tr.changes.iterChangedRanges((fromA, toA, fromB, toB) {
    for (final point in folds.hidden) {
      // The whole of what is folded and the line break before it: taken whole, as it was selected.
      if (fromA <= point.bodyFrom - 1 && toA >= point.to) continue;
      final inside = fromA == toA ? point.hides(fromA) && fromA != point.bodyFrom - 1 : fromA < point.to + 1 && toA > point.bodyFrom - 1;
      if (inside) touched.add(point);
    }
  });
  if (touched.isEmpty) return tr;
  return TransactionSpec(effects: [for (final point in touched) _setFold.of((at: point.from, folded: false))], selection: tr.startState.selection);
}

/// What this device keeps, written as a fold is folded or unfolded.
void _remember(ViewUpdate update) {
  if (!update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(_setFold)))) return;
  final noteId = _noteOf(update.state);
  final folds = update.state.fieldOrNull(_field);
  if (noteId == null || folds == null) return;
  final keys = foldKeys(folds.points);
  final differ = <String, bool>{
    for (var i = 0; i < folds.points.length; i += 1)
      if (folds.folded.contains(folds.points[i].from) != _foldedAtFirst(folds.points[i])) keys[i]: folds.folded.contains(folds.points[i].from),
  };
  keepFolds(noteId, differ);
}

/// The innermost point whose section or toggle holds [pos]: its head, or what it folds.
FoldPoint? _around(List<FoldPoint> points, int pos) {
  FoldPoint? found;
  for (final point in points) {
    if (pos >= point.from && pos <= point.to && (found == null || point.from >= found.from)) found = point;
  }
  return found;
}

/// Cmd-Alt-[: the section or the toggle the caret is in, folded, the caret at the end of its head.
bool foldHere(StateCommandTarget target) {
  final folds = target.state.fieldOrNull(_field);
  if (folds == null) return false;
  final point = _around(folds.points, target.state.selection.main.head);
  if (point == null || folds.folded.contains(point.from)) return point != null;
  target.dispatch(target.state.update(TransactionSpec(effects: _setFold.of((at: point.from, folded: true)), selection: EditorSelection.single(point.headTo), userEvent: 'fold')));
  return true;
}

/// Cmd-Alt-]: the fold at the caret's line, or round the caret, unfolded.
bool unfoldHere(StateCommandTarget target) {
  final folds = target.state.fieldOrNull(_field);
  if (folds == null) return false;
  final head = target.state.selection.main.head;
  final line = target.state.doc.lineAt(head);
  FoldPoint? point;
  for (final each in folds.points) {
    if (folds.folded.contains(each.from) && each.from <= line.from && each.headTo >= line.from) point = each;
  }
  point ??= _around([for (final each in folds.points) if (folds.folded.contains(each.from)) each], head);
  if (point == null) return false;
  target.dispatch(target.state.update(TransactionSpec(effects: _setFold.of((at: point.from, folded: false)), userEvent: 'fold')));
  return true;
}

/// The keys: Mod-Alt-[ and Mod-Alt-].
final List<KeyBinding> foldKeymap = <KeyBinding>[
  const KeyBinding(key: 'Mod-Alt-[', run: foldHere, preventDefault: true),
  const KeyBinding(key: 'Mod-Alt-]', run: unfoldHere, preventDefault: true),
];

/// The folds (see the header), with what the note's screen gives them.
Extension sectionFolds([SectionFolds hooks = const SectionFolds()]) => Extension.list(<Extension>[
      _hooks.of(hooks),
      trackFocus,
      _field,
      EditorViewLike.atomicRanges.of((view) => view.state.fieldOrNull(_field)?.atomic ?? Decoration.none),
      EditorState.transactionFilter.of(_guarded),
      EditorState.transactionFilter.of(_kept),
      EditorViewLike.updateListener.of(_remember),
      Prec.high(editorKeymap.of(foldKeymap)),
    ]);

// ---- asked by the gutter, and by a test ---------------------------------------------------------------------------

/// Whether [state] has the folds.
bool hasSectionFolds(EditorState state) => state.fieldOrNull(_field) != null;

/// The headings that fold and are drawn now (none inside a fold), each by its line from 1, and whether it is folded:
/// what the gutter draws a triangle beside.
List<({int line, int from, bool folded})> gutterFolds(EditorState state) {
  final folds = state.fieldOrNull(_field);
  if (folds == null) return const [];
  final out = <({int line, int from, bool folded})>[];
  var hiddenTo = -1;
  for (final point in folds.points) {
    if (point.from <= hiddenTo) continue;
    final shut = folds.folded.contains(point.from);
    if (point.kind == FoldKind.heading) out.add((line: point.line, from: point.from, folded: shut));
    if (shut) hiddenTo = point.to;
  }
  return out;
}

/// Every place that folds now, and which are folded.
List<FoldPoint> foldPointsOf(EditorState state) => state.fieldOrNull(_field)?.points ?? const [];
Set<int> foldedOf(EditorState state) => state.fieldOrNull(_field)?.folded ?? const {};

/// What is folded away and drawn as nothing now.
List<({int from, int to})> hiddenFolds(EditorState state) => [for (final point in state.fieldOrNull(_field)?.hidden ?? const <FoldPoint>[]) (from: point.bodyFrom, to: point.to)];

/// The fold whose line starts at [from], folded or unfolded: what a triangle's press does.
void setFold(EditorViewLike view, int from, bool folded) => view.dispatch(TransactionSpec(effects: _setFold.of((at: from, folded: folded)), userEvent: 'fold'));

/// The fold whose line starts at [from], the other way.
void toggleFold(EditorViewLike view, int from) => setFold(view, from, !foldedOf(view.state).contains(from));

// ---- drawn --------------------------------------------------------------------------------------------------------

/// What is folded away, drawn as nothing.
class _Hidden extends EditorWidget implements ClassedBlockWidget {
  const _Hidden();

  @override
  String get className => 'cm-sectionFold';

  @override
  bool eq(_Hidden other) => true;

  @override
  double get estimatedHeight => 0;

  @override
  bool get isHidden => true;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final Decoration _hiddenFold = Decoration.replace(widget: const _Hidden(), block: true);

/// The disclosure triangle: pointing at the words while folded, down while open.
class FoldTriangle extends StatelessWidget {
  const FoldTriangle({super.key, required this.folded, required this.size, required this.color});

  final bool folded;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _Triangle(folded: folded, color: color)));
}

class _Triangle extends CustomPainter {
  const _Triangle({required this.folded, required this.color});
  final bool folded;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    // An equilateral-ish triangle, its weight in the middle of the box.
    final half = 0.32 * s, deep = 0.5 * s;
    final path = Path();
    if (folded) {
      path
        ..moveTo(c.dx - deep / 2, c.dy - half)
        ..lineTo(c.dx + deep / 2, c.dy)
        ..lineTo(c.dx - deep / 2, c.dy + half);
    } else {
      path
        ..moveTo(c.dx - half, c.dy - deep / 2)
        ..lineTo(c.dx + half, c.dy - deep / 2)
        ..lineTo(c.dx, c.dy + deep / 2);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 0.08 * s,
    );
  }

  @override
  bool shouldRepaint(_Triangle old) => old.folded != folded || old.color != color;
}

/// A folded heading's ⋯ after its words: a press unfolds it.
class FoldedMarkWidget extends EditorWidget {
  const FoldedMarkWidget({required this.from});
  final int from;

  @override
  bool eq(FoldedMarkWidget other) => other.from == from;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.of(context);
    final look = view is EditorView ? view.look : null;
    final em = look?.env.body ?? t.len('app-body');
    final quiet = t.color('app-ink-3');
    return Padding(
      padding: EdgeInsetsDirectional.only(start: 0.4 * em),
      child: Semantics(
        button: true,
        label: 'Folded. Unfold this section',
        onTap: () => setFold(view, from, false),
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey<String>('folded-mark-$from'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setFold(view, from, false),
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.colorOf('color-mix(in srgb, var(--app-ink) 7%, transparent)'), borderRadius: BorderRadius.circular(t.radius('sm'))),
              child: Padding(
                // The icon's, not a letter: a note's coding face may have no ⋯ to draw.
                padding: EdgeInsets.symmetric(horizontal: 0.3 * em, vertical: 0.12 * em),
                child: AppIcon(Lucide.ellipsis, size: 0.85 * em, color: quiet),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A toggle's head, drawn: its triangle, which opens and closes it, and its summary, a press on which puts the caret
/// on the line to edit it.
class ToggleHeadWidget extends EditorWidget implements ClassedBlockWidget {
  const ToggleHeadWidget({required this.title, required this.folded, required this.from});

  final String title;
  final bool folded;
  final int from;

  @override
  String get className => 'cm-toggleHead';

  @override
  bool eq(ToggleHeadWidget other) => other.title == title && other.folded == folded && other.from == from;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.of(context);
    final look = view is EditorView ? view.look : null;
    final em = look?.env.body ?? t.len('app-body');
    final gutter = layoutUnitFloor(look?.env.gutter ?? t.len('app-gutter'));
    final ink = t.color('app-ink');
    final quiet = t.color('app-ink-3');
    final mark = (0.7 * em).roundToDouble();
    final said = '${title.isEmpty ? 'Toggle' : title}, ${folded ? 'closed' : 'open'}';
    void flip() => setFold(view, from, !folded);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, layoutUnitFloor(0.2 * em), gutter, layoutUnitFloor(0.2 * em)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            button: true,
            expanded: !folded,
            label: said,
            onTap: flip,
            excludeSemantics: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey<String>('toggle-head-$from'),
                behavior: HitTestBehavior.opaque,
                onTap: flip,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(end: 0.35 * em, top: 0.2 * em, bottom: 0.2 * em),
                  child: FoldTriangle(folded: folded, size: mark, color: quiet),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openOnPress(view, from),
              child: Semantics(
                tooltip: 'Edit the summary',
                child: Text(title.isEmpty ? 'Details' : title, style: noteFace(t, look, em, weight: 'medium', color: ink)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A toggle's `</details>`, drawn: a short rule under what it holds, a press on which puts the caret on the line.
class ToggleEndWidget extends EditorWidget implements ClassedBlockWidget {
  const ToggleEndWidget({required this.from});
  final int from;

  @override
  String get className => 'cm-toggleEnd';

  @override
  bool eq(ToggleEndWidget other) => other.from == from;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.of(context);
    final look = view is EditorView ? view.look : null;
    final em = look?.env.body ?? t.len('app-body');
    final gutter = layoutUnitFloor(look?.env.gutter ?? t.len('app-gutter'));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openOnPress(view, from),
      child: Semantics(
        label: 'End of the toggle',
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, layoutUnitFloor(0.35 * em), gutter, layoutUnitFloor(0.45 * em)),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(width: 2.2 * em, height: 1, child: ColoredBox(color: t.color('glacier-border-subtle'))),
          ),
        ),
      ),
    );
  }
}
