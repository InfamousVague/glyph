/// The canvas's + sheet (choice 8), in the shell every sheet shares (lib/sheet): what to add - words, a note, a
/// link, a picture, a chart, a table, a group - and then, for a note or a link, its title or its address. A port
/// of `src/app/canvas/AddSheet.tsx` and AddSheet.module.css. It is built only while it is open, so its back
/// gesture is held for as long as it is there.
///
/// What differs from the web: the sheet is drawn in the app's overlay by `Sheet` itself (the web's `createPortal`
/// to the body), so its presses never come to the canvas and the scrim has nothing to keep from it; and the second
/// step's field is the sheet kit's own line of text (`SheetField`), a rule under the words, where the page drew a
/// box round an `input`.
library;

import 'package:flutter/services.dart' show TextCapitalization, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../sheet/css.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';

/// Where the sheet is: choosing what to add, a note's title, or a web address.
enum AddStep { what, note, link }

class AddSheet extends StatefulWidget {
  const AddSheet({
    super.key,
    required this.step,
    required this.titles,
    required this.onClose,
    required this.onWords,
    required this.onNote,
    required this.onLink,
    required this.onPicture,
    required this.onChart,
    required this.onTable,
    required this.onGroup,
    required this.aboutCard,
    required this.onStep,
  });

  final AddStep step;

  /// Every note's title, to find one by part of it.
  final List<String> titles;
  final VoidCallback onClose;
  final VoidCallback onWords;
  final void Function(String title) onNote;
  final void Function(String url) onLink;
  final VoidCallback onPicture;
  final VoidCallback onChart;
  final VoidCallback onTable;
  final VoidCallback onGroup;

  /// Whether a card is picked: a new group is then made about it, and the sheet says so.
  final bool aboutCard;
  final void Function(AddStep step) onStep;

  @override
  State<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<AddSheet> {
  String _words = '';

  Widget _icon(LucideIcon icon) => SheetIcon(icon: AppIcon(icon, size: 18));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final step = widget.step;
    final asked = _words.trim().toLowerCase();
    final found = step == AddStep.note ? widget.titles.where((title) => title.toLowerCase().contains(asked)).take(12).toList() : const <String>[];
    return Sheet(
      label: 'Add a card',
      onClose: widget.onClose,
      children: [
        SheetTitle(child: Text(step == AddStep.what ? 'Add a card' : (step == AddStep.note ? 'Which note?' : 'Which address?'))),
        if (step == AddStep.what)
          SheetGroup(
            children: [
              SheetRow(icon: _icon(Lucide.squarePen), label: 'Words', hint: 'A card to write on.', onPress: widget.onWords),
              SheetRow(icon: _icon(Lucide.fileText), label: 'A note', hint: 'One of your notes, drawn small; tap it to open.', onPress: () => widget.onStep(AddStep.note)),
              SheetRow(icon: _icon(Lucide.link2), label: 'A link', hint: 'A web address, opened with a tap.', onPress: () => widget.onStep(AddStep.link)),
              SheetRow(icon: _icon(Lucide.image), label: 'A picture', hint: "From your phone or computer, kept with your notes' pictures.", onPress: widget.onPicture),
              SheetRow(icon: _icon(Lucide.chartNoAxesCombined), label: 'A chart', hint: 'A diagram, written as Mermaid and drawn on the card.', onPress: widget.onChart),
              SheetRow(icon: _icon(Lucide.table), label: 'A table', hint: 'Rows and columns to fill in.', onPress: widget.onTable),
              SheetRow(
                icon: _icon(Lucide.group),
                label: 'A group',
                hint: widget.aboutCard ? 'A named box round the card you picked; drag its corners to take in more.' : 'A named box to gather cards in; the cards inside move with it.',
                onPress: widget.onGroup,
              ),
            ],
          )
        else
          // `.addField`
          Padding(
            padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetField(
                  label: step == AddStep.note ? 'Part of the note’s title' : 'The web address',
                  autoFocus: true,
                  value: _words,
                  placeholder: step == AddStep.note ? 'Type part of its title' : 'attack.fm/glyph',
                  inputMode: step == AddStep.link ? TextInputType.url : TextInputType.text,
                  autoCapitalize: step == AddStep.link ? TextCapitalization.none : TextCapitalization.sentences,
                  autoCorrect: step != AddStep.link,
                  onChange: (words) => setState(() => _words = words),
                  onSubmitted: (_) {
                    if (step == AddStep.link) {
                      widget.onLink(_words);
                    } else if (found.isNotEmpty) {
                      widget.onNote(found.first);
                    }
                  },
                ),
                SizedBox(height: t.space(2)),
                if (step == AddStep.link)
                  // `.app-word.addGo`: Add, at the end of its line; nothing to press with no address.
                  Align(
                    alignment: Alignment.centerRight,
                    child: Semantics(
                      button: true,
                      enabled: _words.trim().isNotEmpty,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _words.trim().isEmpty ? null : () => widget.onLink(_words),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                          child: Text('Add', style: pageText(t, t.fontSize('md'), weight: 'semibold', color: _words.trim().isEmpty ? t.color('glacier-text-subtle') : t.color('app-ink'))),
                        ),
                      ),
                    ),
                  )
                else
                  // `.addList`: the notes found, or that there are none.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final title in found)
                          Semantics(
                            button: true,
                            child: GestureDetector(
                              key: ValueKey('add note $title'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onNote(title),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                                child: Text(title, style: pageText(t, t.fontSize('md'), color: t.color('glacier-text'))),
                              ),
                            ),
                          ),
                        if (found.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                            child: Text(_words.trim().isEmpty ? 'No notes yet.' : 'No note by that name.', style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle'))),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
