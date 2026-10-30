/// Choosing one of your templates (Matt, 2026-10-30, of a list of plain-Markdown features: "add all 12"): New from
/// template… on the + and in the command search, which makes a note from the one chosen, and Set template… on a
/// folder's menu and a notebook's More sheet, which makes it the place's own (place_templates.dart), with None to take
/// it off. One sheet for both, over the app as its other questions are (lib/sheet/ask_first.dart): each template by
/// its name and its sentence, the place's own ticked.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'note_templates.dart';

/// What was chosen: a template, or (with [none]) none.
typedef TemplateChosen = ({NoteTemplate? template});

/// A test's answer in place of the sheet's.
@visibleForTesting
Future<TemplateChosen?> Function(String title, List<NoteTemplate> templates)? debugChooseTemplate;

/// Asks for one of [templates] under [title]; null for nothing chosen. [none] offers None, answered as a null
/// template; [chosen] is ticked.
Future<TemplateChosen?> chooseTemplate(BuildContext context, {required String title, required List<NoteTemplate> templates, String? note, bool none = false, NoteTemplate? chosen}) {
  final answering = debugChooseTemplate;
  if (answering != null) return answering(title, templates);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future.value(null);
  final answer = Completer<TemplateChosen?>();
  late final OverlayEntry entry;
  void done(TemplateChosen? chose) {
    if (answer.isCompleted) return;
    entry.remove();
    answer.complete(chose);
  }

  entry = OverlayEntry(builder: (_) => TemplateChoiceSheet(title: title, note: note, templates: templates, none: none, chosen: chosen, onChoose: done));
  overlay.insert(entry);
  return answer.future;
}

class TemplateChoiceSheet extends StatelessWidget {
  const TemplateChoiceSheet({super.key, required this.title, required this.templates, required this.onChoose, this.note, this.none = false, this.chosen});

  final String title;
  final String? note;
  final List<NoteTemplate> templates;
  final bool none;
  final NoteTemplate? chosen;
  final ValueChanged<TemplateChosen?> onChoose;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return Sheet(
      key: const ValueKey('template-choice'),
      label: title,
      onClose: () => onChoose(null),
      children: [
        SheetTitle.text(title),
        if (note != null) SheetNote(note),
        SheetGroup(
          children: [
            if (templates.isEmpty) const SheetRow(label: 'No templates yet. Your templates are notes in the Templates notebook.'),
            for (final template in templates)
              SheetRow(
                key: ValueKey<String>('template-choice:${template.name}'),
                label: template.name,
                hint: template.sentence,
                chosen: none ? (chosen?.name == template.name) : null,
                onPress: () => onChoose((template: template)),
              ),
            if (none) SheetRow(key: const ValueKey('template-choice-none'), label: 'None', hint: 'New notes start blank, as before.', chosen: chosen == null, onPress: () => onChoose((template: null))),
          ],
        ),
      ],
    );
  }
}
