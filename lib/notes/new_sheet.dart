/// What the + makes. A port of `src/app/notes/NewSheet.tsx` (Matt: "make the plus button ask if they want to create a
/// canvas, note or memo"; memos were then taken out of the app).
///
/// A small sheet offering a note, a canvas or a notebook, in the note's settings' own look, from every + there is -
/// the home dock's, the tab strip's and the sidebar's - so a + means the same thing wherever it is. A tap on the
/// scrim, the back gesture or a drag down closes it and makes nothing.
///
/// And a meeting, only where one can be recorded; under it, where this device can put its own sound in a meeting,
/// the switch for that, ticked when on. And a copy of something shared with you: "From a shared link" takes a link
/// and saves it into this library as your own copy. And, with a journal, a new entry, right after Note: the row asks
/// what the entry starts with before it makes one, the journal's usual template first.
///
/// The sheet is lib/sheet/sheet.dart and its rows lib/sheet/kit.dart, already ported and measured; this file is
/// which rows, in what order, saying what.
///
/// What differs:
/// - **Every row that makes something the port does not have yet takes its callback and is left out without it**:
///   Canvas ([NewSheet.onCanvas]), Notebook ([NewSheet.onBook]), Meeting ([NewSheet.onMeeting]), From a shared link
///   ([NewSheet.onFromLink]) and an entry in a journal ([NewSheet.entry]). On the page Canvas and Notebook are always
///   there; Note alone is here until those arrive.
/// - **The switch for a meeting's own sound** is [NewSheet.sound], its words and whether it is on handed in, where
///   the page asked `capture/systemSound.ts` and wrote the preference itself.
/// - `book/entryStarts.ts` ([entryStarts], [startLine]) and the journal's presets (`book/journal.ts` `PRESETS`) were
///   ported here first; they are lib/book/entry_starts.dart and lib/book/journal.dart now, and this file hands them
///   on. A template's line is filled by lib/core/template.dart, whose days and months are English (see there).
/// - A failure saving a copy is said as `'$failure'` says it, less a leading "Exception: " (`core/failure.ts` took an
///   `Error`'s message).
/// - The template cards a new note can start from are not in this sheet on the page either: they are on the new
///   note's blank page (lib/notes/template_cards.dart).
library;

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../book/entry_starts.dart' show entryStarts, startLine;
import '../sheet/css.dart';
import '../sheet/flow.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';

export '../book/entry_starts.dart' show EntryStart, entryStarts, startLine;
export '../book/journal.dart' show EntryPreset, entryPresets, entryTitle;

/// How long a template's line runs on its row before it stops (`HINT_MOST`).
const int _hintMost = 90;

/// A template's line cut at a word near the end of the room, with an ellipsis (`clip`).
String clipHint(String line) {
  if (line.length <= _hintMost) return line;
  final cut = line.substring(0, _hintMost);
  final space = cut.lastIndexOf(' ');
  return '${(space > _hintMost * 0.6 ? cut.substring(0, space) : cut).trimRight()}…';
}

// ---- the sheet ----------------------------------------------------------------------------------------------------

/// A new entry in the journal on screen, else the one written in last (`NewSheetProps['entry']`).
@immutable
class NewSheetEntry {
  const NewSheetEntry({required this.journal, required this.hint, required this.usual, required this.onPress});

  /// The journal's name.
  final String journal;

  /// What an entry starts with, in a sentence.
  final String hint;

  /// The journal's usual template itself.
  final String usual;

  /// Makes the entry from the template chosen: null for the usual one, which is read from the journal afresh as the
  /// entry is made.
  final ValueChanged<String?> onPress;
}

/// The switch under Meeting for the device's own sound in a recording (`meetingSoundWords`, the `meetingSound`
/// preference).
@immutable
class NewSheetSound {
  const NewSheetSound({required this.label, required this.hint, required this.on, required this.onToggle});

  /// "Include sound from other apps" on Android, "Record the computer's sound too" on a Mac.
  final String label;
  final String hint;
  final bool on;
  final VoidCallback onToggle;
}

/// What the + makes (`src/app/notes/NewSheet.tsx`). The rows whose features are not ported take their callbacks and
/// are left out without them; the library doc says which, and what else differs.
class NewSheet extends StatefulWidget {
  const NewSheet({super.key, required this.open, required this.onClose, required this.onNote, this.onCanvas, this.onBook, this.entry, this.onMeeting, this.sound, this.onFromLink, this.clock});

  final bool open;
  final VoidCallback onClose;
  final VoidCallback onNote;

  /// A canvas; left out, no Canvas row (the canvas is a later stage of the port).
  final VoidCallback? onCanvas;

  /// A notebook or a journal; left out, no Notebook row.
  final VoidCallback? onBook;
  final NewSheetEntry? entry;

  /// Records a meeting; given only where one can be recorded here.
  final VoidCallback? onMeeting;

  /// The switch under Meeting, where the device can put its own sound in one.
  final NewSheetSound? sound;

  /// Saves a copy of a shared note or book from its link; answers nothing, or throws what went wrong.
  final Future<void> Function(String link)? onFromLink;

  /// The minute a template's line is told for; this one where it is left out.
  final DateTime Function()? clock;

  @override
  State<NewSheet> createState() => _NewSheetState();
}

class _NewSheetState extends State<NewSheet> {
  /// The shared link being pasted, while its field is open; null when it is not.
  String? _link;
  String? _problem;
  bool _busy = false;

  /// The entry row pressed: the sheet shows what the entry can start with.
  bool _starting = false;

  @override
  void didUpdateWidget(NewSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // However it closed - the scrim, a drag down, the back gesture, a choice made - the next + opens on the choices,
    // not on the field and the words left in it.
    if (!widget.open && oldWidget.open) {
      _link = null;
      _problem = null;
      _starting = false;
    }
  }

  Future<void> _fork() async {
    final save = widget.onFromLink;
    final link = _link?.trim() ?? '';
    if (save == null || link.isEmpty) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await save(link);
      if (mounted) widget.onClose();
    } catch (failure) {
      if (mounted) setState(() => _problem = '$failure'.replaceFirst(RegExp(r'^Exception: '), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  VoidCallback _pick(VoidCallback make) => () {
        widget.onClose();
        make();
      };

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final t = context.tokens;
    final entry = widget.entry;
    if (entry != null && _starting) {
      final now = widget.clock?.call() ?? DateTime.now();
      // The way back at the top, as the More sheet's pages have it, and the back gesture steps back rather than
      // closing. Keyed apart from the choices, so each step opens at its own top.
      return Sheet(
        key: const ValueKey('start'),
        label: 'New',
        onClose: widget.onClose,
        onBack: () => setState(() => _starting = false),
        children: [
          CssFlow.block(
            // `.back { margin: 0 0 var(--glacier-space-3) }`
            margin: EdgeInsets.only(bottom: t.space(3)),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: GlacierPressable(
                key: const ValueKey('new-sheet-back'),
                onPressed: () => setState(() => _starting = false),
                builder: (context, state) => Padding(
                  // `padding: var(--glacier-space-1) 0`
                  padding: EdgeInsets.symmetric(vertical: t.space(1)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    // `display: inline-flex; align-items: center; gap: var(--glacier-space-2)`
                    spacing: t.space(2),
                    children: [
                      AppIcon(Lucide.arrowLeft, color: t.color('glacier-text')),
                      // `color: var(--glacier-text); font-weight: medium`
                      Text('New', style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('glacier-text'))),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SheetTitle.text('Start the entry with'),
          SheetGroup(
            children: [
              for (final start in entryStarts(entry.usual))
                SheetRow(
                  key: ValueKey('start-${start.id}'),
                  icon: const AppIcon(Lucide.feather, size: 18),
                  label: start.id == 'usual' ? '${start.name} · usual' : start.name,
                  hint: clipHint(startLine(start.text, entry.journal, now)),
                  onPress: _pick(() => entry.onPress(start.id == 'usual' ? null : start.text)),
                ),
            ],
          ),
        ],
      );
    }
    final canvas = widget.onCanvas, book = widget.onBook, meeting = widget.onMeeting, sound = widget.sound, fromLink = widget.onFromLink;
    final link = _link;
    return Sheet(
      key: const ValueKey('new'),
      label: 'New',
      onClose: widget.onClose,
      children: [
        SheetTitle.text('New'),
        SheetGroup(
          children: [
            SheetRow(key: const ValueKey('new-note'), icon: const AppIcon(Lucide.squarePen, size: 18), label: 'Note', hint: 'A page of markdown, typed or said.', onPress: _pick(widget.onNote)),
            if (entry != null) SheetRow(key: const ValueKey('new-entry'), icon: const AppIcon(Lucide.feather, size: 18), label: 'Entry in ${entry.journal}', hint: entry.hint, onPress: () => setState(() => _starting = true)),
            if (canvas != null) SheetRow(key: const ValueKey('new-canvas'), icon: const AppIcon(Lucide.workflow, size: 18), label: 'Canvas', hint: 'Cards on a page with lines between them.', onPress: _pick(canvas)),
            if (book != null) SheetRow(key: const ValueKey('new-book'), icon: const AppIcon(Lucide.book, size: 18), label: 'Notebook', hint: 'Notes in an order with an index, or a journal of dated entries.', onPress: _pick(book)),
            if (meeting != null) SheetRow(key: const ValueKey('new-meeting'), icon: const DrawnIconView(AppIcons.cassette), label: 'Meeting', hint: 'Record a meeting. The screen can go off. It is written up afterwards.', onPress: _pick(meeting)),
            if (meeting != null && sound != null)
              // A switch, not a choice that makes something: the sheet stays open for Meeting.
              SheetRow(key: const ValueKey('new-sound'), icon: const AppIcon(Lucide.volume2, size: 18), label: sound.label, hint: sound.hint, chosen: sound.on, onPress: sound.onToggle),
            if (fromLink != null && link == null)
              SheetRow(key: const ValueKey('new-link'), icon: const AppIcon(Lucide.link2, size: 18), label: 'From a shared link', hint: 'A copy of a note or notebook someone shared with you.', onPress: () => setState(() => _link = '')),
          ],
        ),
        if (fromLink != null && link != null)
          SheetGroup(
            children: [
              SheetField(
                label: 'Shared link',
                value: link,
                autoFocus: true,
                placeholder: 'Paste the link',
                autoCorrect: false,
                autoCapitalize: TextCapitalization.none,
                onChange: (text) => setState(() => _link = text),
                onSubmitted: (_) => _fork(),
              ),
              SheetRow(key: const ValueKey('new-save-copy'), icon: const AppIcon(Lucide.link2, size: 18), label: _busy ? 'Saving…' : 'Save a copy', hint: _problem ?? 'Yours to change; the shared one stays as it is.', onPress: _fork),
            ],
          ),
      ],
    );
  }
}
