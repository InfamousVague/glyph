/// Footnotes, as extended markdown writes them. Ports `src/app/editor/footnotes.ts`.
///
///     The deposit is four hundred[^sam], not four fifty.
///
///     [^sam]: Sam said so on the phone, the email disagrees.
///
/// A marker is raised and quiet, the way a footnote is set in print, and tapping it shows what the note says: on
/// a phone the note itself is a long way down the page. The definition line keeps its `[^sam]:` and is set
/// quietly. Nothing is hidden, and a marker with no definition is left plain - it is a typo, and drawing it as a
/// footnote would hide that.
///
/// What differs: the panel is `lib/editor/view/text_panel.dart`'s; `vertical-align: super` is the raise the
/// extended markdown's superscript uses (`view/extended.dart`).
library;

import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../view/editor_view.dart';
import '../view/text_panel.dart';

class Footnote {
  const Footnote({required this.name, required this.text, required this.line});

  final String name;

  /// What the definition says, without its `[^name]:`.
  final String text;

  /// Which line the definition is on, counting from 1.
  final int line;

  @override
  bool operator ==(Object other) => other is Footnote && other.name == name && other.text == text && other.line == line;

  @override
  int get hashCode => Object.hash(name, text, line);

  @override
  String toString() => 'Footnote($name, "$text", line $line)';
}

/// `[^name]` in the words of a note; the definition is the same at the start of its own line, with a colon.
final RegExp _marker = RegExp(r'\[\^([^\]\s]+)\]');
final RegExp _definition = RegExp(r'^(\s{0,3}\[\^([^\]\s]+)\]:)(\s*)(.*)$');

/// Every footnote the note defines, the first of a repeated name winning.
List<Footnote> footnotesIn(String doc) {
  final found = <Footnote>[];
  final seen = <String>{};
  final lines = doc.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final match = _definition.firstMatch(lines[index]);
    final name = match?.group(2);
    if (match == null || name == null || name.isEmpty || seen.contains(name)) continue;
    seen.add(name);
    found.add(Footnote(name: name, text: (match.group(4) ?? '').trim(), line: index + 1));
  }
  return found;
}

/// The footnote a position is inside, when that position is on one of its markers.
Footnote? noteAtPos(EditorState state, List<Footnote> notes, int pos) {
  final line = state.doc.lineAt(pos);
  if (_definition.hasMatch(line.text)) return null;
  for (final match in _marker.allMatches(line.text)) {
    final from = line.from + match.start;
    if (pos >= from && pos <= from + match.group(0)!.length) return notes.where((note) => note.name == match.group(1)).firstOrNull;
  }
  return null;
}

final Decoration _definitionLine = Decoration.line(className: 'cm-footDefinition');
final Decoration _footMark = Decoration.mark(className: 'cm-footMark', attributes: const <String, String>{'title': 'Footnote'});

DecorationSet _decorate(EditorState state) {
  final notes = footnotesIn(state.doc.toString());
  final marks = <Range<Decoration>>[];
  final defined = <String>{for (final note in notes) note.name};
  for (var n = 1; n <= state.doc.lines; n += 1) {
    final line = state.doc.line(n);
    if (_definition.hasMatch(line.text)) {
      marks.add(_definitionLine.range(line.from));
      continue;
    }
    for (final match in _marker.allMatches(line.text)) {
      // A marker with nothing to point at stays plain words: it is a mistake, and should look like one.
      if (!defined.contains(match.group(1) ?? '')) continue;
      final from = line.from + match.start;
      marks.add(_footMark.range(from, from + match.group(0)!.length));
    }
  }
  return Decoration.set(marks, true);
}

/// The panel a tap on a marker opens, saying what the footnote says.
const String footPanel = 'cm-footPanel';

void _close(EditorViewLike view) {
  if (view is EditorView) closeTextPanel(view, footPanel);
}

final LookSheet _theme = LookSheet('editor/footnotes.ts', <LookRule>[
  // The marker, set the way print sets one: raised, small, and quieter than the words it belongs to.
  // '.cm-footMark, .cm-footMark *': { verticalAlign: 'super', fontSize: '0.72em', textDecoration: 'none',
  //   color: 'var(--app-ink-3, var(--glacier-text-muted))', cursor: 'pointer' }
  // A marker's own words are a link's to the parser, a span inside the marker's: the rule's `*` raises and
  // shrinks that one again, which is the size a marker is read at on the page.
  for (final under in const <bool>[false, true])
    LookRule('cm-footMark', classes: 2, under: under, (p, e) {
      p
        // Blink raises `super` a third of the parent's size and a pixel (view/extended.dart).
        ..shift = p.parentSize / 3 + 1
        ..sizeEm(0.72)
        ..underline = false
        ..lineThrough = false
        ..color = e.t.color('app-ink-3');
    }),
  // The small print at the foot of the note.
  // '.cm-footDefinition, .cm-footDefinition *': { fontSize: '0.88em',
  //   color: 'var(--app-ink-3, var(--glacier-text-muted))', textDecoration: 'none' }
  for (final under in const <bool>[false, true])
    LookRule('cm-footDefinition', classes: 2, under: under, (p, e) {
      p
        ..sizeEm(0.88)
        ..color = e.t.color('app-ink-3')
        ..underline = false
        ..lineThrough = false;
    }),
]);

class _Footnotes extends PluginValue {
  _Footnotes(EditorViewLike view) : decorations = _decorate(view.state), notes = footnotesIn(view.state.doc.toString());

  DecorationSet decorations;
  List<Footnote> notes;

  @override
  void update(ViewUpdate update) {
    if (!update.docChanged) return;
    decorations = _decorate(update.state);
    notes = footnotesIn(update.state.doc.toString());
    _close(update.view);
  }
}

final ViewPlugin<_Footnotes> _plugin = ViewPlugin.define<_Footnotes>(
  _Footnotes.new,
  decorations: (value) => value.decorations,
  eventHandlers: EditorEventHandlers(
    pointerDown: (event, view) {
      final pos = view.posAtCoords(event.position);
      final notes = view.plugin(_plugin)?.notes;
      if (pos == null || notes == null) return false;
      final note = noteAtPos(view.state, notes, pos);
      if (note == null) {
        _close(view);
        return false;
      }
      if (view is EditorView) {
        showTextPanel(view, pos, note.text.isNotEmpty ? note.text : 'Nothing written under [^${note.name}] yet.', className: footPanel, label: 'Footnote ${note.name}');
      }
      return false;
    },
  ),
);

final Extension _footnotes = Extension.list(<Extension>[_plugin, baseTheme(_theme)]);

/// Footnotes: the marker raised, the definition quiet, and what it says on a tap.
Extension footnotes() => _footnotes;
