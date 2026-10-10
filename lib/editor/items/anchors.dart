/// The anchor on a line, and a pointer at one from the words. Ports `src/app/editor/boards/anchors.ts` and the
/// three rules of `boards/theme.ts` that draw them.
///
/// `^ship-page` at the end of an item is a name, not something to read: it is drawn small and faint, so the line
/// reads as its words. `[[#^ship-page]]` in the middle of a line is the other end of the same thing - a tap on it
/// goes to the item it names, wherever in the note that is.
///
/// What differs: `opacity` on a span is its ink's alpha here (the same picture for words on a flat ground); the
/// page finds the pointer under a press from the DOM, and here it is the pointer whose characters the press is
/// on. `goToLine` is `boards/navigate.ts`'s, kept here until the boards are ported.
library;

import '../../core/boards.dart';
import '../../core/item_syntax.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../marks/run_paint.dart';
import '../view/line_facts.dart';

final Decoration _anchorMark = Decoration.mark(className: 'cm-itemAnchor');
final Decoration _refMark = Decoration.mark(className: 'cm-itemRef');
final Decoration _goneMark = Decoration.mark(className: 'cm-itemRef cm-itemRefGone');

/// The anchors and the pointers at them, from the lines the tree keeps of each (lib/editor/view/line_facts.dart):
/// a letter typed reads the lines it changed, where the page reads every line of the note.
DecorationSet _anchors(EditorState state) {
  final doc = state.doc;
  final found = <Range<Decoration>>[];
  // The `^anchor` naming the item on the line - last, or with an item's mark after it.
  for (final line in itemAnchorFacts.of(doc)) {
    found.add(_anchorMark.range(line.from + line.fact.from, line.from + line.fact.to));
  }
  final refs = itemRefFacts.of(doc);
  if (refs.isNotEmpty) {
    final named = <String>{for (final item in itemsOf(doc)) item.id};
    for (final line in refs) {
      for (final ref in line.fact) {
        found.add((named.contains(ref.id) ? _refMark : _goneMark).range(line.from + ref.from, line.from + ref.to));
      }
    }
  }
  return Decoration.set(found, true);
}

final StateField<DecorationSet> _anchorField = StateField.define<DecorationSet>(
  create: _anchors,
  update: (value, tr) => tr.docChanged ? _anchors(tr.state) : value,
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// The caret put on a line of the note, and the note scrolled to it.
void goToLine(EditorViewLike view, int line) {
  if (line < 1 || line > view.state.doc.lines) return;
  final at = view.state.doc.line(line);
  // At the end of the item's words, not the end of the line: typed there, a letter would go into the anchor.
  final caret = at.from + wordsEnd(at.text);
  view.dispatch(TransactionSpec(selection: EditorSelection.single(caret), effects: EditorViewLike.scrollIntoView(at.from, y: ScrollStrategy.center), scrollIntoView: true));
  view.focus();
}

/// A tap on `[[#^anchor]]`: the caret goes to the item it names.
final Extension _refTaps = EditorViewLike.eventHandlers(
  EditorEventHandlers(
    pointerDown: (event, view) {
      final at = view.posAtCoords(event.position);
      if (at == null) return false;
      final line = view.state.doc.lineAt(at);
      final ref = refsIn(line.text, line.from).where((found) => found.from <= at && found.to >= at).firstOrNull;
      final item = ref == null ? null : itemOf(view.state.doc, ref.id);
      if (item == null) return false;
      goToLine(view, item.line);
      return true;
    },
  ),
);

bool _gone(LookElement element, LineContext context) => element.has('cm-itemRefGone');
bool _there(LookElement element, LineContext context) => !element.has('cm-itemRefGone');

void _refLine(Props p, {required bool gone}) {
  // '.cm-itemRef': { textDecoration: 'underline', textUnderlineOffset: '0.2em', textDecorationThickness: '0.06em',
  //   textDecorationColor: 'color-mix(in oklch, currentColor 45%, transparent)', cursor: 'pointer' }
  p
    ..underline = false
    ..painter = MarkPaint.add(p.painter, UnderlineLayer(offset: p.em(0.2), thickness: p.em(0.06), opacity: 0.45, style: gone ? UnderlineStyle.dotted : UnderlineStyle.solid));
}

final LookSheet _theme = LookSheet('editor/boards/theme.ts', <LookRule>[
  // '.cm-itemAnchor': { fontSize: '0.82em', opacity: '0.45' }
  LookRule('cm-itemAnchor', classes: 2, (p, e) {
    p
      ..sizeEm(0.82)
      ..color = p.color.withValues(alpha: p.color.a * 0.45);
  }),
  LookRule('cm-itemRef', classes: 2, when: _there, null, box: (p, e) => _refLine(p, gone: false)),
  // '.cm-itemRefGone': { opacity: '0.55', textDecorationStyle: 'dotted' }
  LookRule('cm-itemRef', classes: 2, when: _gone, (p, e) => p.color = p.color.withValues(alpha: p.color.a * 0.55), box: (p, e) => _refLine(p, gone: true)),
  // What is inside is a span of the highlighter's (a list's words, a link's): the opacity is on all of it, and
  // the words inside a pointer keep the pointer's line and lose their own.
  LookRule.under('cm-itemAnchor', classes: 2, null, box: (p, e) => p.color = p.color.withValues(alpha: p.color.a * 0.45)),
  LookRule.under('cm-itemRef', classes: 2, when: _there, null, box: (p, e) => _refLine(p, gone: false)),
  LookRule.under(
    'cm-itemRef',
    classes: 2,
    when: _gone,
    null,
    box: (p, e) {
      p.color = p.color.withValues(alpha: p.color.a * 0.55);
      _refLine(p, gone: true);
    },
  ),
]);

/// Anchors drawn quiet, pointers at them drawn as links, and a tap on a pointer going to its item.
final Extension itemAnchors = Extension.list(<Extension>[_anchorField, _refTaps, baseTheme(_theme)]);
