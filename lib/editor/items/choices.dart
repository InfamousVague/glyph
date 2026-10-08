/// Choices: list items with a round box, of which one is picked. Ports `src/app/editor/choices.ts`.
///
///     Where do we stay?
///     - ( ) Tent
///     - (x) Cabin
///     - ( ) Hotel
///
/// A tap on a round box picks that item and clears the others in its group: the choice lines next to each other
/// at the same indent. Tapping the picked one again clears it, so nothing needs to stay picked. One edit, one
/// undo. The words beside the box are for writing, as with a to-do's box.
library;

import 'dart:ui' show Offset;

import 'package:glacier/glacier.dart' show HapticKind, haptic;

import '../../core/item_syntax.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../view/lines.dart';
import 'box_taps.dart';

class Choice {
  const Choice({required this.line, required this.from, required this.picked, required this.indent});

  final int line;

  /// Where the `(` is.
  final int from;
  final bool picked;
  final int indent;

  @override
  bool operator ==(Object other) => other is Choice && other.line == line && other.from == from && other.picked == picked && other.indent == indent;

  @override
  int get hashCode => Object.hash(line, from, picked, indent);

  @override
  String toString() => 'Choice(line $line, from $from, picked $picked, indent $indent)';
}

/// The choice on a line: its bullet, then `( )`, `(x)` or `(X)`; or null.
Choice? choiceOn(Doc doc, int lineNumber) {
  final line = doc.line(lineNumber);
  final lead = listLead(line.text);
  if (lead == null || lead.picked == null) return null;
  return Choice(line: lineNumber, from: line.from + lead.boxAt, picked: lead.picked!, indent: lead.indent.length);
}

final RegExp _leading = RegExp(r'^\s*');

/// The choices grouped with the one on `lineNumber`: next to it, at its indent, with deeper lines between
/// allowed.
List<Choice> groupOf(Doc doc, int lineNumber) {
  final self = choiceOn(doc, lineNumber);
  if (self == null) return const <Choice>[];
  final group = <Choice>[self];
  void walk(int step) {
    for (var n = lineNumber + step; n >= 1 && n <= doc.lines; n += step) {
      final text = doc.line(n).text;
      final choice = choiceOn(doc, n);
      if (choice != null && choice.indent == self.indent) {
        group.add(choice);
        continue;
      }
      // A line indented under a choice belongs to it; anything else ends the group.
      final depth = _leading.firstMatch(text)!.group(0)!.length;
      if (jsTrim(text).isNotEmpty && depth > self.indent) continue;
      break;
    }
  }

  walk(-1);
  walk(1);
  return group..sort((a, b) => a.line - b.line);
}

/// The changes a tap on the choice at `lineNumber` makes: it picked (or cleared, if it was), its group cleared.
Transaction? pick(EditorState state, int lineNumber) {
  final group = groupOf(state.doc, lineNumber);
  final chosen = group.where((c) => c.line == lineNumber).firstOrNull;
  if (chosen == null) return null;
  final changes = <ChangeSpec>[];
  for (final c in group) {
    final want = c.line == lineNumber ? !chosen.picked : false;
    if (want != c.picked) changes.add(ChangeSpec(from: c.from + 1, to: c.from + 2, insert: want ? 'x' : ' '));
  }
  return state.update(TransactionSpec(changes: changes, userEvent: 'input.choice'));
}

/// The choice whose round box a tap at `at` lands on, or null.
Choice? _choiceUnder(EditorViewLike view, Offset at) {
  final pos = view.posAtCoords(at, precise: false);
  if (pos == null) return null;
  final choice = choiceOn(view.state.doc, view.state.doc.lineAt(pos).number);
  return choice != null && tapsRange(view, at, choice.from, choice.from + 3) ? choice : null;
}

final Decoration _box = Decoration.mark(className: 'cm-choiceBox');
final Decoration _boxPicked = Decoration.mark(className: 'cm-choiceBox cm-choicePicked');

DecorationSet _decorate(EditorViewLike view) {
  final builder = RangeSetBuilder<Decoration>();
  forEachVisibleLine(view, (line) {
    final choice = choiceOn(view.state.doc, line.number);
    if (choice != null) builder.add(choice.from, choice.from + 3, choice.picked ? _boxPicked : _box);
  });
  return builder.finish();
}

final LookSheet _theme = LookSheet('editor/choices.ts', <LookRule>[
  // '.cm-choiceBox': { color: 'var(--glacier-accent-text, currentColor)', fontWeight: '500',
  //   fontFamily: 'var(--glacier-font-mono)', cursor: 'pointer' }
  // One width picked or not, as a to-do's box is: in the prose face `( )` is narrower than `(x)`.
  LookRule('cm-choiceBox', classes: 2, (p, e) {
    p
      ..color = e.t.color('glacier-accent-text')
      ..weight = 500
      ..families = e.monoFamilies;
  }),
]);

class _Choices extends PluginValue {
  _Choices(EditorViewLike view) : decorations = _decorate(view);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged || update.viewportChanged) decorations = _decorate(update.view);
  }
}

final Extension _choices = Extension.list(<Extension>[
  ViewPlugin.define<_Choices>(_Choices.new, decorations: (value) => value.decorations),
  baseTheme(_theme),
  EditorViewLike.eventHandlers(
    EditorEventHandlers(
      pointerDown: (event, view) {
        if (!plainPress(event, view)) return false;
        final choice = _choiceUnder(view, event.position);
        if (choice == null) return false;
        final tr = pick(view.state, choice.line);
        if (tr == null) return false;
        view.dispatch(tr);
        haptic(HapticKind.selection);
        return true;
      },
    ),
  ),
]);

/// `- ( )` choices, one picked by a tap.
Extension choices() => _choices;
