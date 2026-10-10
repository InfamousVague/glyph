/// A to-do's fields drawn. Ports `src/app/editor/taskFields.ts`. Off the caret's line each one is a small chip,
/// and on it the characters are there as written, to be edited.
///
///     - [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03
///
/// reads "Fix the login loop (S) sam #bug ⇈ Sat 3 Oct", the date red once it has passed, amber on the day and
/// quiet once the box is ticked (`field_chips.dart` says how each looks). What a field is, is
/// `lib/core/task_fields.dart`'s; this only says where one is drawn. Nothing in code, an address, HTML, a comment
/// or maths is a field, nor anything in a blank's question or in the note's front matter.
///
/// A tap on a due, start or scheduled day, a priority or a person opens the press-and-hold menu on that field's
/// page (`field_items.dart`): the chip is the field's handle. The press is kept from the editor, so the caret
/// stays where it was and the keyboard does not rise. A tap on any other chip is the editor's, and puts the caret
/// on its line, where it is the characters again. On a page that cannot be edited the chips are drawn and a tap
/// does nothing.
///
/// What differs: the day the chips count from is [fieldsToday], which a test sets, and the language a day is
/// named in [fieldsLocale]; where neither is given they are the device's.
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../../core/blanks_syntax.dart';
import '../../core/days.dart';
import '../../core/item_syntax.dart';
import '../../core/task_fields.dart';
import '../editor.dart';
import '../syntax/syntax.dart';
import '../view/extended.dart' show frontMatter;
import '../view/lines.dart';
import '../view/syntax_tree.dart';
import 'field_chips.dart';
import 'field_menu.dart';

/// What a line with a drawn field has in it: an at sign, a named field's `::`, or one of the signs. A line with
/// none has no chip, and is passed over without reading it.
final RegExp _signs = RegExp('@|::|📅|📆|🗓|🛫|⏳|⌛|✅|➕|❌|🔁|🔺|⏫|🔼|🔽|⏬', unicode: true);

/// The day the chips count from; the device's own where none is said.
final Facet<String Function(), String Function()?> fieldsToday = Facet.define<String Function(), String Function()?>(combine: (values) => values.isEmpty ? null : values.first);

/// The language a day is named in (`en-GB`); the device's own where none is said.
final Facet<String, String?> fieldsLocale = Facet.define<String, String?>(combine: (values) => values.isEmpty ? null : values.first);

String _today(EditorState state) => state.facet(fieldsToday)?.call() ?? isoDay(DateTime.now());

/// The menu a chip opens, as the page of the band it turns to; null for a chip a tap edits.
FieldPage? pageOf(ChipLook look) {
  if (look.menu == FieldMenu.priority) return const PriorityPage();
  if (look.menu == FieldMenu.person) return PersonPage(look.key);
  if (look.menu == FieldMenu.date && (look.key == 'due' || look.key == 'start' || look.key == 'scheduled')) return DatePage(look.key);
  return null;
}

class FieldWidget extends EditorWidget {
  const FieldWidget(this.look, this.tappable);

  final ChipLook look;

  /// Whether a tap opens its menu: a chip that has one, on a page that can be edited.
  final bool tappable;

  @override
  bool eq(FieldWidget other) => other.tappable == tappable && sameLook(other.look, look);

  /// A chip with a menu answers its own taps; any other is the editor's, which puts the caret on its line.
  @override
  bool takesPointer(_) => tappable && pageOf(look) != null;

  @override
  Widget build(BuildContext context) {
    final page = tappable ? pageOf(look) : null;
    if (page == null) return FieldChip(look);
    final view = EditorViewScope.maybeOf(context);
    return FieldChip(
      look,
      onTap: (box) {
        if (view == null) return;
        // Read where it is now: the line may have moved since the chip was drawn.
        final pos = view.posAtCoords(box.center, precise: false);
        if (pos == null) return;
        tapField(view, FieldTap(page: page, line: view.state.doc.lineAt(pos).number, x: (box.left + box.right) / 2, y: box.top));
      },
    );
  }
}

/// Whether a line's item is finished: its box ticked, or a done day written on it.
bool _finished(String text, List<FieldSpan> spans) => taskBox(text)?.done == true || spans.any((span) => span.kind == FieldKind.date && span.key == 'done');

/// A line with one of the fields' signs in it, kept for every line of a document (`LineFact`): the lines on screen
/// are not put to the pattern again on every letter and every move of the caret.
final LineFact<bool> _signed = LineFact<bool>((text) => _maySign(text) && _signs.hasMatch(text) ? true : null);

/// Whether a line could have one of the signs: an `@`, a colon, or a letter past the Latin ones, where every sign
/// but those two is. A line of plain words has none, and is not put to the pattern, which is slow where patterns
/// are not compiled (a phone): 160 microseconds of each letter typed on the Mac went to it.
bool _maySign(String text) {
  for (var i = 0; i < text.length; i += 1) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x40 || unit == 0x3a || unit >= 0x2000) return true;
  }
  return false;
}

DecorationSet _decorate(EditorViewLike view, String today) {
  final builder = RangeSetBuilder<Decoration>();
  final state = view.state;
  final editable = state.facet(EditorViewLike.editable) && !state.readOnly;
  // The lines the selection touches show their fields as written, while the note is being written.
  final active = editable && view.hasFocus ? selectedLines(state) : const <int>{};
  // The note's front matter is its properties, not a to-do's words, and the parser reads it as words.
  final front = frontMatter(state.doc);
  final tree = syntaxTree(state);
  final locale = state.facet(fieldsLocale);
  final doc = state.doc;
  for (final range in view.visibleRanges) {
    // Only the lines on screen with a field's sign in them, as the tree keeps them.
    for (final line in _signed.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number)) {
      if (active.contains(line.number)) continue;
      if (front != null && line.number >= front.from && line.number <= front.to) continue;
      final spans = fieldsIn(line.text, line.from);
      if (spans.isEmpty) continue;
      final done = _finished(line.text, spans);
      final blanks = line.text.contains('{?') ? blankMatches(line.text, line.from) : const <Blank>[];
      for (final span in spans) {
        if (inQuietText(tree, span.from) || blanks.any((b) => span.from > b.from && span.from < b.to)) continue;
        final look = chipLook(span, today: today, done: done, locale: locale);
        if (look != null) builder.add(span.from, span.to, Decoration.replace(widget: FieldWidget(look, editable)));
      }
    }
  }
  return builder.finish();
}

class _TaskFields extends PluginValue {
  _TaskFields(EditorViewLike view) : today = _today(view.state), _active = ActiveLines(view) {
    decorations = _decorate(view, today);
  }

  late DecorationSet decorations;

  /// The lines the selection was on when the chips were last drawn: what a selection changes of them.
  final ActiveLines _active;

  /// The day the chips count from: "Today" is tomorrow's "Yesterday", so a new day draws them again.
  String today;

  @override
  void update(ViewUpdate update) {
    // While an IME composes, the line is left alone, and the chips with it.
    if (update.view.composing) {
      if (update.docChanged) decorations = decorations.map(update.changes);
      return;
    }
    final now = _today(update.state);
    final newDay = now != today;
    // A selection that stays on its lines shows the same fields as written: nothing is read for it.
    if (newDay || update.docChanged || update.viewportChanged || (update.selectionSet && _active.differ(update.view)) || update.focusChanged || !identical(syntaxTree(update.startState), syntaxTree(update.state))) {
      _active.take(update.view);
      today = now;
      decorations = _decorate(update.view, now);
    }
  }
}

final Extension _taskFields = ViewPlugin.define<_TaskFields>(_TaskFields.new, decorations: (value) => value.decorations);

/// The fields drawn as chips, and a tap on one opening its page of the press-and-hold menu.
Extension taskFields() => _taskFields;
