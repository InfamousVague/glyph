/// The lander: a run's lines into the note, one as each finishes, as tracked changes (ai/ai_changes.dart). A port of
/// `src/app/ai/land.ts`.
///
/// It works from the landing state the editor keeps - where the next line goes, where the old words end - so the
/// person can type while it runs and the bookmark moves with their words. Each line is placed by the reading rules
/// in ai/landing.dart: kept where the old line is the same, rewritten word by word where it is nearly the same,
/// added where it is new; the old lines a match passed over are struck. Lines the person wrote while the run was on
/// are theirs: never struck, never rewritten, and a line of the model's that would have replaced one is dropped and
/// counted, so the strip can say so.
///
/// When the run is done, whatever old words are left below the landed ones are struck, and the finished text (tidied
/// once at the end, its links put back) is read over the landed lines the same way, so a bullet the tidy-up
/// straightened or a link that came back late lands as one more small change rather than a rewrite of everything.
///
/// What differs: the page's `EditorView` is a [StateCommandTarget] (a state and a dispatch), which an editor's view
/// is; the tick under the thumb (`fireFelt('light')`) is [landFelt], the kit's motor, which a test stills; the arriving smoke is the
/// editor's own annotation (lib/editor/marks/wisp_motion.dart [wisp]).
library;

import 'dart:math' as math;

import 'package:glacier/glacier.dart' show HapticFn, HapticKind, fireMotor;

import '../editor/marks/wisp_motion.dart' show WispKind, wisp;
import '../editor/state/change.dart';
import '../editor/state/state.dart';
import 'ai_changes.dart';
import 'landing.dart';

/// The tick as a line lands (`fireFelt`).
HapticFn landFelt = fireMotor;

class _OldLine {
  const _OldLine({required this.text, required this.from, required this.to, required this.newline});

  final String text;
  final int from;

  /// The end of the words, before the newline.
  final int to;

  /// Whether a newline follows. Only the note's last line has none.
  final bool newline;
}

int _count = 0;
String _changeId() => 'c-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${_count += 1}';

/// How a lander lands (`LanderOptions`).
class LanderOptions {
  const LanderOptions({required this.wisp, required this.haptic});

  /// The lines arrive from smoke (ai/editor/wisp_arrivals.dart), when the person has the wisp on.
  final bool wisp;

  /// A tick under the thumb as each line lands.
  final bool haptic;
}

/// Where a run's lines were up to, kept across the note being closed and opened again while it runs, with the note
/// as it was before any landed.
final Map<String, ({int landed, int start, int cursor, int oldEnd, String before})> _progress = {};

/// See the header (`Lander`).
class Lander {
  Lander(this._view, this._runId, this._options, String before) {
    // The note was closed and opened again mid-run: carry on where the lines were up to, with the note as it was
    // before the first landed. A landing already set is a fresh start, whatever an earlier lander for this run left.
    final kept = _progress[_runId];
    if (kept != null && _view.state.field(landingField) == null) {
      _landed = kept.landed;
      this.before = kept.before;
      _view.dispatch(TransactionSpec(effects: setLanding.of(LandingSpot(runId: _runId, start: kept.start, cursor: kept.cursor, oldEnd: kept.oldEnd))));
    } else {
      _progress.remove(_runId);
      this.before = before;
    }
  }

  final StateCommandTarget _view;
  final String _runId;
  final LanderOptions _options;
  int _landed = 0;

  /// Lines of the model's that were dropped because the person had written over their place.
  int dropped = 0;

  /// The note before the run's first line landed, for the log's Undo.
  late final String before;

  /// This run's bookmark: null once another run has put its own in its place.
  Landing? _landing() {
    final landing = _view.state.field(landingField);
    return landing != null && (landing.runId == null || landing.runId == _runId) ? landing : null;
  }

  /// The bookmark put away, if it is still this run's.
  void _clear() {
    if (_landing() != null) _view.dispatch(TransactionSpec(effects: setLanding.of(null), annotations: aiEdit.of(AiEdit.land)));
  }

  /// Lands the lines the run has finished so far, past the ones already landed.
  void land(List<String> lines) {
    for (var i = _landed; i < lines.length; i += 1) {
      _landOne(lines[i]);
    }
    _landed = lines.length;
    _remember();
  }

  void _remember() {
    final landing = _landing();
    if (landing != null) _progress[_runId] = (landed: _landed, start: landing.start, cursor: landing.cursor, oldEnd: landing.oldEnd, before: before);
  }

  /// The old lines still ahead of the cursor, with where each sits.
  List<_OldLine> _oldLines(Landing landing) {
    final doc = _view.state.doc;
    final out = <_OldLine>[];
    var at = landing.cursor;
    final end = math.max(landing.cursor, landing.oldEnd);
    while (at < end) {
      final line = doc.lineAt(at);
      final to = math.min(line.to, end);
      final newline = to < doc.length && doc.sliceString(to, to + 1) == '\n' && to < end;
      out.add(_OldLine(text: doc.sliceString(at, to), from: at, to: to, newline: newline));
      at = newline ? to + 1 : to;
      if (!newline) break;
    }
    return out;
  }

  void _dispatch({List<ChangeSpec> changes = const <ChangeSpec>[], List<AiChange> records = const <AiChange>[], required int cursor, required int oldEnd, int? start, required bool removed}) {
    final landing = _landing();
    // The effect's positions are in the note as it will read after the edit; the start it keeps has to be moved too.
    final moved = changes.isNotEmpty ? ChangeSet.of(changes, _view.state.doc.length) : null;
    final at = start ?? (landing != null ? (moved != null ? moved.mapPos(landing.start, -1) : landing.start) : cursor);
    _view.dispatch(
      TransactionSpec(
        changes: changes,
        effects: <StateEffect<Object?>>[
          if (records.isNotEmpty) addAiChanges.of(records),
          setLanding.of(LandingSpot(runId: _runId, start: at, cursor: cursor, oldEnd: math.max(cursor, oldEnd))),
        ],
        annotations: <Annotation<Object?>>[
          aiEdit.of(AiEdit.land),
          if (_options.wisp && changes.isNotEmpty) wisp.of(removed ? WispKind.rewrite : WispKind.heard),
        ],
        userEvent: 'ai.land',
      ),
    );
    if (_options.haptic && changes.isNotEmpty) landFelt(HapticKind.light);
  }

  /// The old lines up to [until] go: struck in runs, except the ones the person wrote, which are passed over.
  /// Answers the cursor after them and how much the note shrank.
  ({int cursor, int shrank}) _strike(Landing landing, List<_OldLine> old, int until) {
    var cursor = landing.cursor;
    var shrank = 0;
    var run = <_OldLine>[];
    void flush() {
      if (run.isEmpty) return;
      final first = run.first;
      final last = run.last;
      final from = first.from - shrank;
      final to = (last.newline ? last.to + 1 : last.to) - shrank;
      final removed = [for (final l in run) l.text].join('\n');
      // Blank lines go without a mark: there is nothing to draw struck through, and nothing worth a Revert.
      final records = removed.trim().isNotEmpty ? [AiChange(id: _changeId(), runId: _runId, from: from, to: from, removed: removed, block: true)] : const <AiChange>[];
      _dispatch(changes: [ChangeSpec(from: from, to: to, insert: '')], records: records, cursor: from, oldEnd: landing.oldEnd - shrank - (to - from), removed: true);
      shrank += to - from;
      cursor = from;
      run = <_OldLine>[];
    }

    for (var i = 0; i < until; i += 1) {
      final line = old[i];
      if (touchedIn(landing, line.from, line.to)) {
        flush();
        cursor = (line.newline ? line.to + 1 : line.to) - shrank;
      } else {
        run.add(line);
      }
    }
    flush();
    return (cursor: cursor, shrank: shrank);
  }

  void _landOne(String line) {
    final landing = _landing();
    if (landing == null) return;
    final old = _oldLines(landing);
    final match = matchLine([for (final o in old) o.text], line);
    if (match.kind == MatchKind.insert) {
      // The next old line is one the person wrote while the model worked: a line of the model's that matches nothing
      // ahead is most likely its version of that line, and theirs stands.
      if (old.isNotEmpty && touchedIn(landing, old.first.from, old.first.to)) {
        dropped += 1;
        return;
      }
      _insert(landing, line);
      return;
    }
    final target = old[match.at!];
    final struck = _strike(landing, old, match.at!);
    final after = _landing() ??
        Landing(runId: landing.runId, start: landing.start, cursor: struck.cursor, oldEnd: landing.oldEnd - struck.shrank, touched: landing.touched);
    final from = target.from - struck.shrank;
    final to = target.to - struck.shrank;
    if (match.kind == MatchKind.keep || touchedIn(after, from, to)) {
      if (match.kind != MatchKind.keep) dropped += 1;
      _pass(after, from, to, target.newline);
      return;
    }
    _replace(after, line, from, to, target.newline, target.text);
  }

  /// The cursor moves past a line that stays as it is, a newline put after it if the note ends there.
  void _pass(Landing landing, int from, int to, bool newline) {
    if (newline) {
      _dispatch(cursor: to + 1, oldEnd: landing.oldEnd, removed: false);
      return;
    }
    _dispatch(changes: [ChangeSpec(from: to, insert: '\n')], cursor: to + 1, oldEnd: math.max(landing.oldEnd, to) + 1, removed: false);
  }

  /// A line the model added, on a line of its own at the cursor.
  void _insert(Landing landing, String line) {
    final doc = _view.state.doc;
    var at = landing.cursor;
    var oldEnd = landing.oldEnd;
    final changes = <ChangeSpec>[];
    // The cursor is always at the start of a line, unless the note's last line has no newline yet. A newline put in
    // for that is the note's, not the run's: the run's words start after it.
    int? start;
    if (at > 0 && doc.sliceString(at - 1, at) != '\n') {
      changes.add(ChangeSpec(from: at, insert: '\n'));
      at += 1;
      oldEnd += 1;
      if (landing.start == landing.cursor) start = at;
    }
    changes.add(ChangeSpec(from: landing.cursor, insert: '$line\n'));
    final from = at;
    final to = at + line.length;
    _dispatch(
      changes: changes,
      records: [AiChange(id: _changeId(), runId: _runId, from: from, to: to, removed: '', block: true)],
      cursor: to + 1,
      oldEnd: oldEnd + line.length + 1,
      start: start,
      removed: false,
    );
  }

  /// An old line rewritten: the new words in, and only the words that differ marked.
  void _replace(Landing landing, String line, int from, int to, bool newline, String oldText) {
    final records = <AiChange>[];
    var pos = from;
    var gone = '';
    for (final segment in wordDiff(oldText, line)) {
      if (segment.kind == SegmentKind.removed) {
        gone += segment.text;
        continue;
      }
      if (segment.kind == SegmentKind.added) {
        records.add(AiChange(id: _changeId(), runId: _runId, from: pos, to: pos + segment.text.length, removed: gone, block: false));
        gone = '';
      } else if (gone.isNotEmpty) {
        records.add(AiChange(id: _changeId(), runId: _runId, from: pos, to: pos, removed: gone, block: false));
        gone = '';
      }
      pos += segment.text.length;
    }
    if (gone.isNotEmpty) records.add(AiChange(id: _changeId(), runId: _runId, from: pos, to: pos, removed: gone, block: false));
    final changes = <ChangeSpec>[ChangeSpec(from: from, to: to, insert: line), if (!newline) ChangeSpec(from: to, insert: '\n')];
    final grew = line.length - (to - from);
    _dispatch(
      changes: changes,
      records: records,
      cursor: from + line.length + 1,
      oldEnd: math.max(landing.oldEnd, to) + grew + (newline ? 0 : 1),
      removed: records.any((r) => r.removed != ''),
    );
  }

  /// The run is done: the old words left below the landed lines go, and the finished text is read over the landed
  /// lines, so what the tidy-up changed lands too. Then the bookmark is put away.
  void finish(List<String> finalLines) {
    final landing = _landing();
    if (landing == null) return;
    final old = _oldLines(landing);
    _strike(landing, old, old.length);
    final after = _landing();
    if (after != null) {
      // Read the finished text over what landed: the landed lines are the old ones now.
      _dispatch(cursor: after.start, oldEnd: after.cursor, start: after.start, removed: false);
      _landed = 0;
      for (final line in finalLines) {
        _landOne(line);
      }
      final last = _landing();
      if (last != null) _strike(last, _oldLines(last), _oldLines(last).length);
    }
    _clear();
    _progress.remove(_runId);
  }

  /// The run stopped or failed: what landed stays, nothing more is struck.
  void abandon() {
    _clear();
    _progress.remove(_runId);
  }
}
