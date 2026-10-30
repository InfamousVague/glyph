/// Buttons in a note, drawn (Matt, 2026-10-30, of a list of plain-Markdown features: "add all 12"; the syntax is
/// lib/core/note_buttons.dart, the run button_run.dart). A `[Move to done](ghost:set?status=Done)` off the caret's
/// lines is a real button: its label on a quiet raised ground, the mark of what it does before it. On the caret's lines
/// it is the link as it is written, to be changed as any words are, as every drawn mark in the note is. Inside code it
/// is code.
///
/// A press runs it ([runButton]); what it says (Posted to #launch., or why not) the note says. In a view that cannot be
/// edited only an open runs: the rest are drawn quieter, and a press on them does nothing.
///
/// The note's screen adds it to its extensions with what reaches past the note:
///
///     noteButtons(ButtonHooks(noteId: () => id, title: () => title, world: () => buttonWorld, say: say))
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/note_buttons.dart';
import '../editor.dart';
import '../media/inline_box.dart';
import '../syntax/syntax.dart' show inQuietText;
import '../view/line.dart' show EditorRunScope;
import '../view/lines.dart';
import '../view/syntax_tree.dart';
import 'button_run.dart';

export 'button_run.dart';

/// What the note's screen gives its buttons.
class ButtonHooks {
  const ButtonHooks({required this.noteId, required this.title, this.world, this.say});

  /// The note the buttons are in, and its title, for a post's and Claude's job.
  final String Function() noteId;
  final String Function() title;

  /// What reaches past the note; absent, a button sets its fields and does nothing else.
  final ButtonWorld? Function()? world;

  /// Says a sentence on the note: what a press did, or why it did nothing.
  final void Function(String said)? say;
}

final Facet<ButtonHooks?, ButtonHooks?> _hooks = Facet.define<ButtonHooks?, ButtonHooks?>(combine: (values) => values.where((v) => v != null).firstOrNull);

/// The buttons on screen, none in code, none on a line the caret is on in a view being typed in.
DecorationSet _decorate(EditorViewLike view) {
  final state = view.state;
  final doc = state.doc;
  final editable = state.facet(EditorViewLike.editable) && !state.readOnly;
  final active = editable && view.hasFocus ? selectedLines(state) : const <int>{};
  final tree = syntaxTree(state);
  final found = <Range<Decoration>>[];
  final seen = <int>{};
  for (final range in view.visibleRanges) {
    final first = doc.lineAt(range.from).number, last = doc.lineAt(range.to).number;
    for (var n = first; n <= last; n += 1) {
      final line = doc.line(n);
      if (!seen.add(n) || active.contains(n) || !line.text.contains('ghost:')) continue;
      for (final button in buttonsIn(line.text)) {
        final from = line.from + button.from;
        if (inQuietText(tree, from)) continue;
        found.add(Decoration.replace(widget: NoteButtonWidget(button.markdown, button.label, button.verb, runs: editable || button.runsReadOnly)).range(from, line.from + button.to));
      }
    }
  }
  return Decoration.set(found, true);
}

class _Buttons extends PluginValue {
  _Buttons(EditorViewLike view) : decorations = _decorate(view), _active = ActiveLines(view);

  DecorationSet decorations;
  final ActiveLines _active;

  @override
  void update(ViewUpdate update) {
    // While an IME composes, the line must not be replaced (glyph_lines.dart).
    if (update.view.composing) {
      if (update.docChanged) decorations = decorations.map(update.changes);
      return;
    }
    if (update.docChanged || update.viewportChanged || (update.selectionSet && _active.differ(update.view)) || update.focusChanged || !identical(syntaxTree(update.startState), syntaxTree(update.state))) {
      _active.take(update.view);
      decorations = _decorate(update.view);
    }
  }
}

/// The note's buttons, drawn and pressable.
Extension noteButtons(ButtonHooks hooks) => Extension.list(<Extension>[
      _hooks.of(hooks),
      ViewPlugin.define<_Buttons>(_Buttons.new, decorations: (value) => value.decorations),
    ]);

/// The mark of what a button does.
LucideIcon buttonIcon(ButtonVerb verb) => switch (verb) {
      ButtonVerb.set => Lucide.check,
      ButtonVerb.post => Lucide.send,
      ButtonVerb.claude => Lucide.sparkles,
      ButtonVerb.open => Lucide.squareArrowOutUpRight,
      ButtonVerb.make => Lucide.copyPlus,
    };

/// A button as the note draws it: found again by its words when pressed, since the note may have moved meanwhile.
class NoteButtonWidget extends EditorWidget {
  const NoteButtonWidget(this.markdown, this.label, this.verb, {required this.runs});

  final String markdown;
  final String label;
  final ButtonVerb verb;

  /// Whether a press runs it here: always, where the note can be changed; only an open where it cannot.
  final bool runs;

  @override
  bool eq(NoteButtonWidget other) => other.markdown == markdown && other.runs == runs;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.maybeOf(context);
    return NoteButtonChip(label: label, verb: verb, runs: runs, onPress: view == null || !runs ? null : () => unawaited(_press(context, view)));
  }

  Future<void> _press(BuildContext context, EditorViewLike view) async {
    final hooks = view.state.facet(_hooks);
    final doc = view.state.doc.toString();
    final button = buttonsIn(doc).where((each) => each.markdown == markdown).firstOrNull ?? buttonOf(label, markdown.substring(markdown.lastIndexOf('](') + 2, markdown.length - 1));
    if (button == null) return;
    fireMotor(HapticKind.selection);
    final editable = view.state.facet(EditorViewLike.editable) && !view.state.readOnly;
    final said = await runButton(context, button, view: view, editable: editable, noteId: hooks?.noteId() ?? '', title: hooks?.title() ?? '', world: hooks?.world?.call());
    if (said != null) hooks?.say?.call(said);
  }
}

/// A button's face: the mark of what it does and its label, on a raised ground with a rule round it, a step smaller
/// than the words it sits among. Quieter where a press does nothing.
class NoteButtonChip extends StatelessWidget {
  const NoteButtonChip({super.key, required this.label, required this.verb, required this.runs, required this.onPress});

  final String label;
  final ButtonVerb verb;
  final bool runs;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = EditorRunScope.maybeOf(context);
    final em = scope?.look.fontSize ?? t.len('app-body');
    final size = (em * 0.86).roundToDouble();
    final ink = runs ? t.color('app-ink') : t.color('app-ink-3');
    final style = (scope?.look.style ?? t.textAt(em)).copyWith(fontSize: size, color: ink, decoration: TextDecoration.none, fontWeight: FontWeight.w500);
    final chip = Container(
      key: ValueKey<String>('note-button:$label'),
      padding: EdgeInsets.symmetric(horizontal: size * 0.7, vertical: size * 0.12),
      decoration: BoxDecoration(
        color: t.color('app-paper-2'),
        border: Border.all(color: t.color('app-rule')),
        borderRadius: BorderRadius.circular(size * 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppIcon(buttonIcon(verb), size: size * 0.95, color: ink),
          SizedBox(width: size * 0.4),
          Flexible(child: InlineWords(label.isEmpty ? 'Button' : label, style: style, lineHeight: size * 1.5, ellipsis: true)),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: onPress != null,
      label: label,
      hint: runs ? null : 'Runs where the note can be changed',
      onTap: onPress,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: em * 0.1),
          child: InlineRaise(by: -size * 0.1, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onPress, child: chip)),
        ),
      ),
    );
  }
}
