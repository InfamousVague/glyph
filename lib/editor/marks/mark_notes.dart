/// A note on a mark, shown when the words are tapped. Ports `src/app/editor/markNotes.ts`.
///
/// The note is written the way a link's target is, in brackets straight after the mark:
///
///     The deposit is ??four hundred??(Sam said 400, the email says 450) and needs checking.
///
/// Any of Ghost.md's marks can carry one, not only a doubt. The words keep the look the mark gives them
/// (`format_looks.dart`); the bracketed part is hidden so the line reads as a sentence, and tapping the words shows
/// the note. The brackets come back as plain text while the caret is in them, so the note is edited like anything
/// else. Nothing is stored anywhere but the note itself.
///
/// What differs: the panel is `lib/editor/view/text_panel.dart`'s, which the note screen draws over the editor;
/// the page's `mousedown` is the view's `pointerDown`, and as there it never takes the press, so the caret still
/// goes where the finger went.
library;

import '../../core/blanks_syntax.dart' show readFilled;
import '../../plugins/marks.dart';
import '../editor.dart';
import '../view/editor_view.dart';
import '../view/text_panel.dart';

/// A noted mark: the whole thing from the opening delimiter to the closing bracket, the words the mark covers
/// (what a tap has to land on), the bracketed part with its brackets, what the note says, and the mark it is
/// written on.
class MarkNote {
  const MarkNote({required this.from, required this.to, required this.wordsFrom, required this.wordsTo, required this.bracketsFrom, required this.bracketsTo, required this.text, required this.delimiter});

  final int from;
  final int to;
  final int wordsFrom;
  final int wordsTo;
  final int bracketsFrom;
  final int bracketsTo;
  final String text;
  final String delimiter;

  @override
  String toString() => 'MarkNote($from-$to words $wordsFrom-$wordsTo brackets $bracketsFrom-$bracketsTo "$text" $delimiter)';
}

/// The pattern for `<delimiter>words<delimiter>(a note)`, for the marks that are switched on.
RegExp? notePattern(Iterable<GlyphFormat> formats) {
  final delimiters = <String>{for (final format in formats) format.delimiter};
  if (delimiters.isEmpty) return null;
  final any = delimiters.map(RegExp.escape).join('|');
  return RegExp('($any)(?=(\\S))((?:(?!\\1).)*?\\S)\\1\\(([^)\\n]+)\\)');
}

/// Every noted mark in `text`, counting positions from `offset`.
List<MarkNote> notesIn(String text, RegExp pattern, [int offset = 0]) {
  final found = <MarkNote>[];
  for (final match in pattern.allMatches(text)) {
    final whole = match.group(0)!;
    final delimiter = match.group(1) ?? '';
    final note = match.group(4) ?? '';
    final from = offset + match.start;
    final wordsFrom = from + delimiter.length, wordsTo = from + whole.length - note.length - 2 - delimiter.length;
    found.add(
      MarkNote(from: from, to: from + whole.length, wordsFrom: wordsFrom, wordsTo: wordsTo, bracketsFrom: wordsTo + delimiter.length, bracketsTo: from + whole.length, text: note, delimiter: delimiter),
    );
  }
  return found;
}

/// The note whose words `pos` is inside, if there is one.
MarkNote? noteAt(List<MarkNote> notes, int pos) {
  for (final note in notes) {
    if (pos >= note.wordsFrom && pos <= note.to) return note;
  }
  return null;
}

/// Whether these brackets are a colour rather than a note: `==the key==(green)` names a wash, and the mark itself
/// says which names it knows. The brackets are hidden either way; only the tap differs, since there is nothing to
/// say about a colour.
bool isTint(MarkNote note, Iterable<GlyphFormat> formats) {
  for (final format in formats) {
    if (format.delimiter == note.delimiter) return format.tint?.call(note.text) != null;
  }
  return false;
}

/// The brackets, hidden: the mark's own look is the cue and the words are the place to tap.
final Decoration _hidden = Decoration.replace();

({DecorationSet marks, List<MarkNote> notes}) _decorate(EditorState state, RegExp pattern) {
  final builder = RangeSetBuilder<Decoration>();
  final notes = notesIn(state.doc.toString(), pattern);
  for (final note in notes) {
    // The caret inside the brackets: the words are being written, so they stay words.
    final editing = state.selection.ranges.any((range) => range.to >= note.bracketsFrom && range.from <= note.bracketsTo);
    if (editing) continue;
    builder.add(note.bracketsFrom, note.bracketsTo, _hidden);
  }
  return (marks: builder.finish(), notes: notes);
}

/// The panel a tap opens: one at a time, over the words it belongs to.
const String markNotePanel = 'cm-markNotePanel';

void _close(EditorViewLike view) {
  if (view is EditorView) closeTextPanel(view, markNotePanel);
}

class _MarkNotes extends PluginValue {
  _MarkNotes(EditorViewLike view, this.pattern) {
    final drawn = _decorate(view.state, pattern);
    decorations = drawn.marks;
    notes = drawn.notes;
  }

  final RegExp pattern;
  late DecorationSet decorations;
  late List<MarkNote> notes;

  @override
  void update(ViewUpdate update) {
    if (!update.docChanged && !update.selectionSet) return;
    final drawn = _decorate(update.state, pattern);
    decorations = drawn.marks;
    notes = drawn.notes;
    if (update.docChanged) _close(update.view);
  }
}

/// Notes on marks: the brackets hidden after the words, and the panel a tap on them opens.
Extension markNotes(Iterable<GlyphFormat> formats) {
  final pattern = notePattern(formats);
  if (pattern == null) return const Extension.list(<Extension>[]);
  final all = formats.toList();
  late final ViewPlugin<_MarkNotes> plugin;
  plugin = ViewPlugin.define<_MarkNotes>(
    (view) => _MarkNotes(view, pattern),
    decorations: (value) => value.decorations,
    eventHandlers: EditorEventHandlers(
      pointerDown: (event, view) {
        final pos = view.posAtCoords(event.position);
        final notes = view.plugin(plugin)?.notes;
        if (pos == null || notes == null) return false;
        final note = noteAt(notes, pos);
        // A colour is not a note: there is nothing to show, and the tap is the editor's as usual. Nor is a filled
        // blank's bracket, which says where an answer came from: its panel is the fill panel's.
        if (note == null || isTint(note, all) || readFilled(note.text) != null) {
          _close(view);
          return false;
        }
        // The panel opens; the caret still goes where the finger went, so the words can be edited straight after.
        if (view is EditorView) showTextPanel(view, note.wordsFrom, note.text, className: markNotePanel, label: 'Note');
        return false;
      },
    ),
  );
  return plugin;
}
