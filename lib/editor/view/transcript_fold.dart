/// A meeting's transcript kept out of its note's words (Matt, 2026-10-30: "Also use a button to switch to the
/// transcript in the note don't show the transcript on the note section"). The note is still one file, its summary
/// and its transcript together (Matt, 2026-10-29: "make it so the transcripts and meeting summaries are shown in one
/// file"); only what the editor shows changes. The note's screen has Note and Transcript over it
/// (lib/root/note_desk.dart), and the transcript is read, followed and played in its own view
/// (lib/tapes/transcript_words.dart).
///
/// - **What is folded**: each level-2 section of a meeting's note headed `## Transcript` or `## Captions`, from its
///   heading's line to the line before the next level-2 heading or the end ([meetingFolds]). A section that is the
///   note's first line is left: there is nothing before it to stand on. A note that is no meeting ([TranscriptFold
///   .meeting]) folds nothing, whatever its headings.
/// - **Drawn as nothing**: a block in place of those lines, of no height ([_Folded]), as the front matter holding only
///   unsaid keys is (extended.dart `NoFrontWidget`).
/// - **Never typed into**: a caret or a selection that would land in a fold lands at the end of the last line of words
///   before it, where typing goes on the note's words ([_kept]); and an edit the person makes (a key, a paste, a cut, Select
///   all and Delete) leaves every fold and the line break before it as they were, byte for byte ([_guarded]). What the
///   app writes (a write-up landing, a team member's edit, Rebuild transcript) has no person's event on it and goes
///   through, as an undo or a redo does.
/// - **Found anyway**: the note's find bar still matches the words in a fold, and a match there, or a landing on a
///   line in one (a search's hit, a `[[Note#^line]]`), opens the transcript at it ([TranscriptFold.reveal], with the
///   offset in the document), rather than the caret going where nothing shows.
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import 'blocks.dart' show ClassedBlockWidget;

/// What the note's screen answers the fold.
class TranscriptFold {
  const TranscriptFold({required this.meeting, this.reveal});

  /// Whether the note is a meeting's, asked as its words change, with the words.
  final bool Function(Doc doc) meeting;

  /// Opens the transcript at offset [at] of the document: a match of the find bar, or a landing, in a fold.
  final void Function(int at)? reveal;
}

/// The headings whose sections are folded.
const Set<String> foldedHeadings = {'## Transcript', '## Captions'};

/// The folds of [doc]: each section's first offset (its heading line's start) and its last (the end of its last
/// line), in order, touching ones made one (see the header).
List<({int from, int to})> meetingFolds(Doc doc) {
  final out = <({int from, int to})>[];
  int? open;
  var last = 0;
  for (var n = 1; n <= doc.lines; n += 1) {
    final line = doc.line(n);
    if (line.text.startsWith('## ')) {
      final folded = foldedHeadings.contains(line.text.trimRight());
      if (open != null && !folded) {
        out.add((from: open, to: last));
        open = null;
      }
      if (folded && open == null && line.from > 0) open = line.from;
    }
    last = line.to;
  }
  if (open != null) out.add((from: open, to: doc.length));
  return out;
}

/// A fold drawn as nothing.
class _Folded extends EditorWidget implements ClassedBlockWidget {
  const _Folded();

  @override
  String get className => 'cm-transcriptFold';

  @override
  bool eq(_Folded other) => true;

  @override
  double get estimatedHeight => 0;

  @override
  bool get isHidden => true;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final Decoration _fold = Decoration.replace(widget: const _Folded(), block: true);

class _Folds {
  const _Folds(this.ranges, this.decorations);
  final List<({int from, int to})> ranges;
  final DecorationSet decorations;
}

/// The note screen's hooks, one an editor.
final Facet<TranscriptFold, List<TranscriptFold>> _hooks = Facet.define();

TranscriptFold? _hooksOf(EditorState state) {
  final all = state.facet(_hooks);
  return all.isEmpty ? null : all.first;
}

List<({int from, int to})> _rangesOf(EditorState state, Doc doc) {
  final hooks = _hooksOf(state);
  if (hooks == null || !hooks.meeting(doc)) return const [];
  return meetingFolds(doc);
}

_Folds _foldsOf(EditorState state) {
  final ranges = _rangesOf(state, state.doc);
  if (ranges.isEmpty) return _Folds(const [], Decoration.none);
  return _Folds(ranges, Decoration.set(<Range<Decoration>>[for (final r in ranges) _fold.range(r.from, r.to)]));
}

final StateField<_Folds> _field = StateField.define<_Folds>(
  create: _foldsOf,
  update: (value, tr) => tr.docChanged || tr.reconfigured ? _foldsOf(tr.state) : value,
  provide: (f) => EditorViewLike.decorations.from<_Folds>(f, (value) => value.decorations),
);

/// Where a position in a fold is taken: the end of the last line of words before it, so what is typed there goes on
/// the note's words, and a new line starts under them.
int _before(Doc doc, ({int from, int to}) fold) {
  var at = fold.from - 1;
  while (at > 0) {
    final c = doc.sliceString(at - 1, at);
    if (c != '\n' && c.trim().isNotEmpty) break;
    at -= 1;
  }
  return at;
}

({int from, int to})? _foldAt(List<({int from, int to})> folds, int pos) {
  for (final fold in folds) {
    if (pos >= fold.from && pos <= fold.to) return fold;
  }
  return null;
}

/// The folds a person's edit may not touch, each with the line break before it (see the header).
Object _guarded(Transaction tr) {
  if (!tr.docChanged) return true;
  final event = tr.annotation(Transaction.userEvent);
  if (event == null || tr.isUserEvent('undo') || tr.isUserEvent('redo')) return true;
  final folds = tr.startState.fieldOrNull(_field)?.ranges ?? const [];
  if (folds.isEmpty) return true;
  return <int>[for (final fold in folds) ...[fold.from - 1, fold.to]];
}

/// A selection that would land in a fold, landed before it; one put there by the app (a find's, a landing's) asks
/// for the transcript at it as well.
Object _kept(Transaction tr) {
  final selection = tr.selection;
  if (selection == null) return tr;
  // The folds of the words this transaction leaves.
  final doc = tr.newDoc;
  final folds = tr.docChanged ? _rangesOf(tr.startState, doc) : (tr.startState.fieldOrNull(_field)?.ranges ?? const []);
  if (folds.isEmpty) return tr;
  int? asked;
  var moved = false;
  int keep(int pos) {
    final fold = _foldAt(folds, pos);
    if (fold == null) return pos;
    moved = true;
    asked ??= pos;
    return _before(doc, fold);
  }

  final ranges = [for (final r in selection.ranges) EditorSelection.range(keep(r.anchor), keep(r.head))];
  if (!moved) return tr;
  final event = tr.annotation(Transaction.userEvent);
  final person = event != null && (event.startsWith('select') || event.startsWith('input') || event.startsWith('delete') || event.startsWith('move'));
  final reveal = _hooksOf(tr.startState)?.reveal;
  final at = asked;
  if (!person && reveal != null && at != null) _later(() => reveal(at));
  return <Object>[tr, TransactionSpec(selection: EditorSelection.create(ranges, selection.mainIndex), sequential: true)];
}

/// A find's match brought into view in a fold: the transcript, at it.
void _heard(ViewUpdate update) {
  final reveal = _hooksOf(update.state)?.reveal;
  if (reveal == null) return;
  final folds = update.state.fieldOrNull(_field)?.ranges ?? const [];
  if (folds.isEmpty) return;
  for (final tr in update.transactions) {
    for (final effect in tr.effects) {
      final target = EditorViewLike.scrollIntoViewEffect.cast(effect);
      if (target == null) continue;
      final at = target.value.range.head;
      if (_foldAt(folds, at) != null) {
        _later(() => reveal(at));
        return;
      }
    }
  }
}

/// [then] after the frame this is in, a frame asked for: never inside the dispatch that found it.
void _later(VoidCallback then) {
  WidgetsBinding.instance
    ..addPostFrameCallback((_) => then())
    ..ensureVisualUpdate();
}

/// The fold (see the header), with the note screen's [hooks].
Extension transcriptFold(TranscriptFold hooks) => Extension.list(<Extension>[
      _hooks.of(hooks),
      _field,
      EditorViewLike.atomicRanges.of((view) => view.state.fieldOrNull(_field)?.decorations ?? Decoration.none),
      EditorState.changeFilter.of(_guarded),
      EditorState.transactionFilter.of(_kept),
      EditorViewLike.updateListener.of(_heard),
    ]);

/// The folds [state] draws now: for a test to ask.
List<({int from, int to})> transcriptFolds(EditorState state) => state.fieldOrNull(_field)?.ranges ?? const [];
