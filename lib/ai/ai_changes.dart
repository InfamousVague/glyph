/// The AI's changes, tracked in the note: what it added, what it took away, and what Keep and Revert do to them. A
/// port of the state half of `src/app/editor/aiChanges.ts`.
///
/// Matt chose auto-apply with marks over a preview: the model's lines go into the note as they finish (ai/land.dart),
/// and the note itself is always the text as it now reads, which is what is saved, synced and shared. So the marks
/// are records over that text, never text in it. The records live in a state field ([aiChangesField]), mapped through
/// every edit, so a person can type around them while the model is still writing.
///
/// A change is kept - its marks go - when Keep is tapped, when Keep all is, or when the person types on its line: the
/// words are theirs then. Revert puts the old words back and takes the new ones out. Both are one edit, so one Undo
/// takes either back.
///
/// The landing state ([landingField]) is the lander's bookmark while it runs: where the next line goes and where the
/// old words end, mapped through the person's typing, with the ranges they touched, which are theirs and are never
/// struck.
///
/// What differs: this is the half with nothing drawn, so it is under lib/ai and needs only the editor's state
/// (lib/editor/state). Left for the editor's AI surface (piece 8K), which builds over these fields:
/// - the decorations (`decorate`): for each change in [aiChangesField], a mark over `from`-`to` (`cm-aiAdded`), the
///   words that went struck through (`GoneWidget`: a block above the line at `doc.lineAt(from).from` for a `block`
///   change, inline at `from` with its leading whitespace off otherwise, both side -1), and one pair of Keep and
///   Revert pills (`PillsWidget`, side 1) at `doc.lineAt(group.to).to` for each of [groupChanges]' groups, calling
///   [keepChanges] and [revertChanges] with the group's ids;
/// - the theme (`cm-aiAdded`, `cm-aiGone`, `cm-aiGoneBlock`, `cm-aiGoneLine`, `cm-aiPills`, `cm-aiPill`);
/// - `aiChanges(options)` itself, with `AiChangesOptions.onMarks`: [aiChangesState] is its two fields, and the
///   update listener that tells the note its marks is `EditorViewLike.updateListener.of((update) { final now =
///   changedMarks(update.startState, update.state); if (now != null) onMarks(now); })`.
/// The functions the web gives an `EditorView` take a [StateCommandTarget] (a state and a dispatch), which an
/// `EditorViewLike` is. `aiEdit`'s four words are the [AiEdit] enum. `setLanding` carries a [LandingSpot] (the web's
/// `Pick<Landing, 'runId' | 'start' | 'cursor' | 'oldEnd'>`). A range the person touched is a `({from, to})` record,
/// and so is a group of changes (`({ids, to})`). The field's lists are unmodifiable.
library;

import 'dart:math' as math;

import '../editor/state/change.dart';
import '../editor/state/state.dart';
import '../editor/state/text.dart';

/// One change the AI made (`AiChange`).
class AiChange {
  const AiChange({required this.id, required this.runId, required this.from, required this.to, required this.removed, required this.block});

  final String id;
  final String runId;

  /// The added words, as a range in the note; empty (`from == to`) for a change that only took words away.
  final int from;
  final int to;

  /// The words the change took away, drawn struck through where they were; empty for words only added.
  final String removed;

  /// Whether the change is whole lines (drawn as a block, reverted with its newline) or words within a line.
  final bool block;

  AiChange copyWith({String? id, String? runId, int? from, int? to, String? removed, bool? block}) => AiChange(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    from: from ?? this.from,
    to: to ?? this.to,
    removed: removed ?? this.removed,
    block: block ?? this.block,
  );

  /// The change as the page keeps it with a note (ai/marks.dart).
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'runId': runId, 'from': from, 'to': to, 'removed': removed, 'block': block};

  /// A change read back, or null for anything that is not one.
  static AiChange? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], runId = raw['runId'], from = raw['from'], to = raw['to'], removed = raw['removed'], block = raw['block'];
    if (id is! String || runId is! String || from is! num || to is! num || removed is! String || block is! bool) return null;
    return AiChange(id: id, runId: runId, from: from.toInt(), to: to.toInt(), removed: removed, block: block);
  }

  @override
  bool operator ==(Object other) =>
      other is AiChange && other.id == id && other.runId == runId && other.from == from && other.to == to && other.removed == removed && other.block == block;

  @override
  int get hashCode => Object.hash(id, runId, from, to, removed, block);

  @override
  String toString() => 'AiChange($id, $runId, $from-$to, removed: "$removed", block: $block)';
}

/// Where a run is landing, as [setLanding] says it: a [Landing] without what the person touched.
class LandingSpot {
  const LandingSpot({required this.runId, required this.start, required this.cursor, required this.oldEnd});

  /// Whose bookmark it is, so a run that ended after another took its place never puts the newer one away.
  final String? runId;

  /// Where the run's first line landed.
  final int start;

  /// Where the next line goes.
  final int cursor;

  /// Where the old words the run is replacing end.
  final int oldEnd;

  @override
  bool operator ==(Object other) => other is LandingSpot && other.runId == runId && other.start == start && other.cursor == cursor && other.oldEnd == oldEnd;

  @override
  int get hashCode => Object.hash(runId, start, cursor, oldEnd);
}

/// The lander's bookmark while it runs (`Landing`).
class Landing {
  const Landing({required this.runId, required this.start, required this.cursor, required this.oldEnd, required this.touched});

  /// Whose bookmark it is, so a run that ended after another took its place never puts the newer one away.
  final String? runId;

  /// Where the run's first line landed.
  final int start;

  /// Where the next line goes.
  final int cursor;

  /// Where the old words the run is replacing end.
  final int oldEnd;

  /// What the person typed while the run was on: theirs, never struck.
  final List<({int from, int to})> touched;

  @override
  bool operator ==(Object other) {
    if (other is! Landing || other.runId != runId || other.start != start || other.cursor != cursor || other.oldEnd != oldEnd) return false;
    if (other.touched.length != touched.length) return false;
    for (var i = 0; i < touched.length; i += 1) {
      if (other.touched[i] != touched[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(runId, start, cursor, oldEnd, Object.hashAll(touched));

  @override
  String toString() => 'Landing($runId, start: $start, cursor: $cursor, oldEnd: $oldEnd, touched: $touched)';
}

/// What an edit of the AI's is: landing a line, reverting a change, undoing a run, signing the note.
enum AiEdit { land, revert, undo, sign }

/// On every transaction the AI makes.
final AnnotationType<AiEdit> aiEdit = Annotation.define<AiEdit>();

AiChange _mapChange(AiChange change, ChangeDesc mapping) => change.copyWith(from: mapping.mapPos(change.from, 1), to: mapping.mapPos(change.to, -1));

List<AiChange> _mapChanges(List<AiChange> changes, ChangeDesc mapping) => <AiChange>[for (final c in changes) _mapChange(c, mapping)];

/// Changes the AI just made, to mark.
final StateEffectType<List<AiChange>> addAiChanges = StateEffect.define<List<AiChange>>(map: _mapChanges);

final StateEffectType<List<String>> _keepAiChanges = StateEffect.define<List<String>>();

/// Every mark goes; the words stay.
final StateEffectType<Null> keepAllAiChanges = StateEffect.define<Null>();

/// The marks a note was closed with, back on it (ai/marks.dart).
final StateEffectType<List<AiChange>> restoreAiChanges = StateEffect.define<List<AiChange>>(map: _mapChanges);

/// Sets the lander's bookmark, or with null puts it away.
final StateEffectType<LandingSpot?> setLanding = StateEffect.define<LandingSpot?>(
  map: (landing, mapping) => landing == null
      ? null
      : LandingSpot(runId: landing.runId, start: mapping.mapPos(landing.start, -1), cursor: mapping.mapPos(landing.cursor, -1), oldEnd: mapping.mapPos(landing.oldEnd, -1)),
);

/// The AI's changes still marked on the note, in the order they sit in it.
final StateField<List<AiChange>> aiChangesField = StateField.define<List<AiChange>>(
  create: (_) => const <AiChange>[],
  update: (value, tr) {
    var next = value;
    if (tr.docChanged && next.isNotEmpty) {
      next = <AiChange>[
        for (final c in _mapChanges(next, tr.changes))
          if (c.to >= c.from && (c.to > c.from || c.removed.isNotEmpty)) c,
      ];
      if (tr.annotation(aiEdit) == null) {
        // The person wrote on a change's line: the words are theirs now, and the marks go.
        final lines = _touchedLines(tr.newDoc, tr.changes);
        next = <AiChange>[
          for (final c in next)
            if (!_onLines(tr.newDoc, c, lines)) c,
        ];
      }
    }
    for (final effect in tr.effects) {
      final added = addAiChanges.cast(effect);
      final kept = _keepAiChanges.cast(effect);
      final restored = restoreAiChanges.cast(effect);
      if (added != null) {
        next = <AiChange>[...next, ...added.value];
      } else if (kept != null) {
        final gone = kept.value.toSet();
        next = <AiChange>[
          for (final c in next)
            if (!gone.contains(c.id)) c,
        ];
      } else if (effect.isOf(keepAllAiChanges)) {
        next = const <AiChange>[];
      } else if (restored != null) {
        next = <AiChange>[...restored.value];
      }
    }
    if (!identical(next, value)) next = List<AiChange>.unmodifiable(_sorted(next));
    return next;
  },
);

/// By where they start, then where they end; equals stay in the order they were in, as JavaScript's sort leaves them.
List<AiChange> _sorted(List<AiChange> changes) {
  final out = <AiChange>[...changes];
  for (var i = 1; i < out.length; i += 1) {
    final c = out[i];
    var j = i - 1;
    while (j >= 0 && (out[j].from > c.from || (out[j].from == c.from && out[j].to > c.to))) {
      out[j + 1] = out[j];
      j -= 1;
    }
    out[j + 1] = c;
  }
  return out;
}

Set<int> _touchedLines(Doc doc, ChangeDesc changes) {
  final lines = <int>{};
  changes.iterChangedRanges((fromA, toA, fromB, toB) {
    final first = doc.lineAt(math.min(fromB, doc.length)).number;
    final last = doc.lineAt(math.min(toB, doc.length)).number;
    for (var n = first; n <= last; n += 1) {
      lines.add(n);
    }
  });
  return lines;
}

bool _onLines(Doc doc, AiChange change, Set<int> lines) {
  final first = doc.lineAt(math.min(change.from, doc.length)).number;
  final last = doc.lineAt(math.min(change.to, doc.length)).number;
  for (var n = first; n <= last; n += 1) {
    if (lines.contains(n)) return true;
  }
  return false;
}

/// The lander's bookmark, or null while no run is landing.
final StateField<Landing?> landingField = StateField.define<Landing?>(
  create: (_) => null,
  update: (value, tr) {
    var next = value;
    if (next != null && tr.docChanged) {
      final touched = <({int from, int to})>[for (final r in next.touched) (from: tr.changes.mapPos(r.from, -1), to: tr.changes.mapPos(r.to, 1))];
      if (tr.annotation(aiEdit) == null) {
        tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => touched.add((from: fromB, to: toB)));
      }
      next = Landing(
        runId: next.runId,
        start: tr.changes.mapPos(next.start, -1),
        cursor: tr.changes.mapPos(next.cursor, -1),
        oldEnd: tr.changes.mapPos(next.oldEnd, -1),
        touched: List<({int from, int to})>.unmodifiable(touched),
      );
    }
    for (final effect in tr.effects) {
      final set = setLanding.cast(effect);
      if (set == null) continue;
      final spot = set.value;
      next = spot == null
          ? null
          : Landing(runId: spot.runId, start: spot.start, cursor: spot.cursor, oldEnd: spot.oldEnd, touched: next?.touched ?? const <({int from, int to})>[]);
    }
    return next;
  },
);

/// Whether a stretch of the note is one the person wrote in while the run was on.
bool touchedIn(Landing landing, int from, int to) => landing.touched.any((r) => r.from < math.max(to, from + 1) && r.to > from);

/// Changes that touch or sit on neighbouring lines, from one run, share one pair of pills: each group's ids, and
/// where its last change ends.
List<({List<String> ids, int to})> groupChanges(Doc doc, List<AiChange> changes) {
  final groups = <_Group>[];
  for (final change in changes) {
    final line = doc.lineAt(math.min(change.to, doc.length)).number;
    final last = groups.isEmpty ? null : groups.last;
    if (last != null && last.runId == change.runId && line <= last.line + 1) {
      last.ids.add(change.id);
      last.to = math.max(last.to, change.to);
      last.line = math.max(last.line, line);
    } else {
      groups.add(_Group(<String>[change.id], change.to, change.runId, line));
    }
  }
  return <({List<String> ids, int to})>[for (final g in groups) (ids: g.ids, to: g.to)];
}

class _Group {
  _Group(this.ids, this.to, this.runId, this.line);

  final List<String> ids;
  int to;
  final String runId;
  int line;
}

// ---- acting -------------------------------------------------------------------------------------------------------

/// These changes are the person's now: their marks go, the words stay.
void keepChanges(StateCommandTarget view, List<String> ids) {
  view.dispatch(TransactionSpec(effects: _keepAiChanges.of(<String>[...ids])));
}

/// Every change is the person's now.
void keepAllChanges(StateCommandTarget view) {
  view.dispatch(TransactionSpec(effects: keepAllAiChanges.of(null)));
}

/// The edit that puts one change back as it was.
ChangeSpec _revertSpec(AiChange change, Doc doc) {
  if (!change.block) return ChangeSpec(from: change.from, to: change.to, insert: change.removed);
  if (change.to > change.from) {
    if (change.removed.isNotEmpty) return ChangeSpec(from: change.from, to: change.to, insert: change.removed);
    // Words only added, on lines of their own: the lines go, their newline with them.
    final after = doc.sliceString(change.to, math.min(change.to + 1, doc.length));
    return ChangeSpec(from: change.from, to: after == '\n' ? change.to + 1 : change.to, insert: '');
  }
  // Lines only taken away: back where they were, on lines of their own.
  final before = change.from > 0 ? doc.sliceString(change.from - 1, change.from) : '\n';
  final lead = before == '\n' ? '' : '\n';
  final tail = change.from < doc.length ? '\n' : '';
  return ChangeSpec(from: change.from, to: change.from, insert: '$lead${change.removed}$tail');
}

/// The old words back, the new ones out, in one edit.
void revertChanges(StateCommandTarget view, List<String> ids) {
  final wanted = ids.toSet();
  final mine = <AiChange>[
    for (final c in view.state.field(aiChangesField))
      if (wanted.contains(c.id)) c,
  ];
  if (mine.isEmpty) return;
  final doc = view.state.doc;
  view.dispatch(
    TransactionSpec(
      changes: <ChangeSpec>[for (final c in mine) _revertSpec(c, doc)],
      effects: _keepAiChanges.of(<String>[...ids]),
      annotations: aiEdit.of(AiEdit.revert),
      userEvent: 'ai.revert',
    ),
  );
}

// ---- the extension ------------------------------------------------------------------------------------------------

/// The marks as they now are when a step from [start] to [now] changed them, and null when it did not: what the
/// web's update listener asks before it tells the note (`AiChangesOptions.onMarks`).
List<AiChange>? changedMarks(EditorState start, EditorState now) {
  final marks = now.field(aiChangesField);
  return identical(marks, start.field(aiChangesField)) ? null : marks;
}

/// The two fields, [aiChangesField] and [landingField]: the web's `aiChanges(options)` without what it draws.
Extension aiChangesState() => Extension.list(<Extension>[aiChangesField, landingField]);
