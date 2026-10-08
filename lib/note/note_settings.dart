/// One note's More sheet, from the three dots in its tools: how it is read, its comments, the AI's runs on it, its
/// sharing, where it sits (pin, archive, the workspace it is in, its versions, where it was written), what it is
/// linked to, help, then Move to Trash, apart at the bottom. A port of `src/app/editor/NoteSettings.tsx`, with the
/// two classes of `NoteSettings.module.css` that are the More sheet's alone (`.viewChoice`, `.ask`).
///
/// A sheet from the bottom over a dimmed note (lib/sheet/sheet.dart). The Workspace row, the version history and
/// the cheat sheet open as pages inside the sheet, under one way back; back returns to the sheet before it closes
/// it.
///
/// What differs, each a row whose feature is another stage's, taken as something nullable so the sheet is whole the
/// day it arrives:
/// - Plugins' rows ("Linked to", stage 9) are [NoteSettings.linked], the rows themselves; their own pages and an
///   action's choices come with the registry.
/// - Sharing (share/ShareRows.tsx, stage 7) is [NoteSettings.sharing], its rows.
/// - The AI's rows (stage 8) are drawn from [aiKinds] when [NoteSettings.onAi] is given; the dot a run in progress
///   wears, and Fill the blanks, come with the runs.
/// - A journal's page and a notebook's ticket key (book/, stage 5) are not here; the Name field is.
/// - The cheat sheet's page is [NoteSettings.cheatSheet], and the Help group is there only with it.
/// - Where it was written (core/location.ts, later) is [NoteSettings.location]; the hints are ported.
/// - It is built only while it is open, by the screen, where the page's returned null while shut.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/icons.dart';
import '../core/geotag.dart';
import '../core/look.dart';
import '../core/versions_file.dart';
import '../core/versions_record.dart';
import '../core/workspaces.dart';
import '../sheet/css.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'version_history.dart';
import 'workspace_picker.dart';

/// Why a fix cannot be had (`LocateFailure`, core/location.ts).
enum LocateFailure { refused, blocked, unavailable, timeout, none, mac, ios, localOnly }

/// Why a fix cannot be asked for here, as the row says it under "Add my location" (`CANNOT`).
const Map<LocateFailure, String> cannotLocate = {
  LocateFailure.localOnly: 'Local only is on. A location fix would ask the phone’s location service.',
  LocateFailure.mac: 'This Mac can’t say where it is yet. Tag it on the phone and it syncs here.',
  LocateFailure.ios: 'Ghost.md can’t find where you are on this device yet.',
  LocateFailure.unavailable: 'Update Ghost.md to tag notes with where they were written.',
  LocateFailure.none: 'This browser can’t say where you are.',
  LocateFailure.refused: 'Ghost.md wasn’t allowed to know where you are.',
  LocateFailure.blocked: 'Location is off for Ghost.md.',
  LocateFailure.timeout: 'Couldn’t find where you are.',
};

/// Where the note was written, for its row (`location`).
@immutable
class NoteLocation {
  const NoteLocation({required this.tag, this.cannot, this.asksName = true, this.refused, this.onPhone = true, required this.onAdd, required this.onRemove});

  final GeoTag? tag;

  /// Why a fix cannot be asked for here; null where it can (`can`).
  final LocateFailure? cannot;
  final bool asksName;

  /// Why the last automatic tag did not come.
  final LocateFailure? refused;

  /// The phone's app, which asks again after a first refusal.
  final bool onPhone;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
}

/// The location row's hint on an untagged note: why it was not tagged on its own, or what a press will do
/// (`locationHint`).
String locationHint(NoteLocation location) {
  final cannot = location.cannot;
  if (cannot != null) return cannotLocate[cannot]!;
  if (location.refused == LocateFailure.blocked) return 'Location is off for Ghost.md, so this note wasn’t tagged. Allow it in the phone’s settings, or tap to try again.';
  if (location.refused != null && location.onPhone) return 'Ghost.md wasn’t allowed to know where you are, so this note wasn’t tagged. Tap to ask again.';
  if (location.refused != null) return 'Ghost.md wasn’t allowed to know where you are, so this note wasn’t tagged. Allow location for this site in the browser’s settings, then tap to try again.';
  return location.asksName ? 'Where you are now, kept in the note. Its name is asked of OpenStreetMap once.' : 'Where you are now, kept in the note.';
}

/// One of the AI's runs as the sheet offers it (`KindWords`, ai/kinds.ts, with its icon of ai/icons.ts).
@immutable
class AiKind {
  const AiKind(this.id, this.label, this.hint, this.icon);
  final String id;
  final String label;
  final String hint;
  final LucideIcon icon;
}

/// The AI's runs in the sheet, in order (`SHEET_KINDS`; docs/DESIGN.md §145, 11).
const List<AiKind> aiKinds = [
  AiKind('format', 'Format', 'Tidy and organise, keeping every word that matters.', Lucide.wandSparkles),
  AiKind('summarize', 'Summarize', 'The point of the note and its tasks, in far fewer words.', Lucide.scanText),
  AiKind('enhance', 'Enhance', 'Every thought finished and the note made fuller, without inventing.', Lucide.sparkles),
  AiKind('fix', 'Fix spelling', 'Spelling, grammar and punctuation, and not a word more.', Lucide.spellCheck),
  AiKind('shape', 'Make a list', 'Tasks, a list or a table out of what is there.', Lucide.listChecks),
  AiKind('continue', 'Continue', 'Carries on from the last line in the note’s own voice.', Lucide.penLine),
];

/// The field to name a canvas or a notebook by (`name`).
@immutable
class NoteName {
  const NoteName({required this.value, required this.onChange, required this.kind});
  final String value;
  final ValueChanged<String> onChange;

  /// `canvas`, `notebook` or `journal`, for the field's placeholder.
  final String kind;
}

/// The note's look, for its row of choices (`look`).
@immutable
class NoteLook {
  const NoteLook({required this.value, required this.canMap, required this.onChange});
  final Look? value;
  final bool canMap;
  final ValueChanged<Look?> onChange;
}

/// The note's version history (`history`): whether it keeps one, its words now, and how a version is put back.
@immutable
class NoteHistory {
  const NoteHistory({required this.record, required this.keeps, required this.current, required this.onRestore, this.onShareFile});
  final VersionsRecord record;
  final bool keeps;
  final String Function() current;
  final void Function(String text, Version version) onRestore;
  final Future<String?> Function(String noteId, String title)? onShareFile;
}

/// A page of the sheet, opened from a row.
enum NoteSettingsPage { workspace, cheatsheet, history }

class NoteSettings extends StatefulWidget {
  const NoteSettings({
    super.key,
    required this.noteId,
    required this.title,
    required this.pinned,
    required this.workspaces,
    required this.onClose,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
    this.onBookmark,
    this.marked = false,
    this.onFind,
    this.onMakeBoard,
    this.name,
    this.onSpeak,
    this.speakLabel = 'Talk into this note',
    this.look,
    this.onAi,
    this.onComment,
    this.commentsSummary,
    this.onCommentsList,
    this.sharing,
    this.sharingSection,
    this.linked,
    this.location,
    this.history,
    this.startAt,
    this.cheatSheet,
    this.say,
  });

  final String noteId;
  final String title;
  final bool pinned;
  final WorkspaceStore workspaces;
  final VoidCallback onClose;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  /// The bookmark: set at the caret's line, moved, or taken off. Absent while the note's words are not showing.
  final VoidCallback? onBookmark;
  final bool marked;

  /// Opens find and replace in the note.
  final VoidCallback? onFind;

  /// Lays the note's list out as a board; absent where there is nothing to make one of.
  final VoidCallback? onMakeBoard;
  final NoteName? name;

  /// Talk into this note, or, on a journal, speak a new entry.
  final VoidCallback? onSpeak;
  final String speakLabel;
  final NoteLook? look;

  /// Asks the AI for a run of that kind, with an instruction for `ask`.
  final void Function(String kind, [String? instruction])? onAi;

  /// A comment started on the caret's line or the selection; with [commentsSummary], the threads' list.
  final VoidCallback? onComment;
  final String? commentsSummary;
  final VoidCallback? onCommentsList;

  /// Sharing's rows (share/ShareRows.tsx), under their heading.
  final List<Widget>? sharing;

  /// Sharing with its own heading and group, where [sharing] is rows for this sheet's.
  final Widget? sharingSection;

  /// What the note is linked to, a plugin's row each.
  final List<Widget>? linked;
  final NoteLocation? location;
  final NoteHistory? history;

  /// A page to open at, from a button in the bar: the version history.
  final NoteSettingsPage? startAt;

  /// The formatting cheat sheet's page (guide/CheatSheet.tsx), built when its row is pressed.
  final WidgetBuilder? cheatSheet;
  final void Function(String message)? say;

  @override
  State<NoteSettings> createState() => _NoteSettingsState();
}

class _NoteSettingsState extends State<NoteSettings> {
  NoteSettingsPage? _page;

  @override
  void initState() {
    super.initState();
    widget.workspaces.addListener(_changed);
    if (widget.startAt == NoteSettingsPage.history && widget.history != null) _page = NoteSettingsPage.history;
  }

  @override
  void dispose() {
    widget.workspaces.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _back() => _page != null ? setState(() => _page = null) : widget.onClose();

  String get _here => widget.title.isEmpty ? 'This note' : widget.title;

  static Widget _lucide(LucideIcon icon, [double stroke = 2]) => AppIcon(icon, size: 18, strokeWidth: stroke);
  static Widget _drawn(DrawnIcon icon) => DrawnIconView(icon, size: 18);

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    final page = _page;
    if (page == NoteSettingsPage.history && history != null) {
      return Sheet(
        label: 'Version history',
        onClose: widget.onClose,
        onBack: _back,
        children: [
          VersionHistory(
            noteId: widget.noteId,
            title: widget.title,
            record: history.record,
            current: history.current,
            onRestore: (text, version) {
              history.onRestore(text, version);
              widget.onClose();
            },
            onBack: () => setState(() => _page = null),
            onShareFile: history.onShareFile,
            say: widget.say,
          ),
        ],
      );
    }
    if (page == NoteSettingsPage.workspace || (page == NoteSettingsPage.cheatsheet && widget.cheatSheet != null)) {
      final workspace = page == NoteSettingsPage.workspace;
      return Sheet(
        label: workspace ? 'Workspace' : 'Formatting cheat sheet',
        onClose: widget.onClose,
        onBack: _back,
        children: [
          SheetBack(label: _here, onPressed: () => setState(() => _page = null)),
          if (workspace) WorkspacePicker(noteId: widget.noteId, workspaces: widget.workspaces, onDone: () => setState(() => _page = null)) else widget.cheatSheet!(context),
        ],
      );
    }

    final name = widget.name;
    final look = widget.look;
    final location = widget.location;
    final filed = widget.workspaces.workspaceOf(widget.noteId);
    final reading = widget.onFind != null || widget.onMakeBoard != null || look != null || widget.onBookmark != null;
    return Sheet(
      label: 'Settings for ${widget.title.isEmpty ? 'this note' : widget.title}',
      onClose: widget.onClose,
      onBack: _back,
      children: [
        SheetTitle.text(widget.title.isEmpty ? 'Untitled' : widget.title),
        // The mic, from the top bar: the first thing here, as it was the first thing a thumb reached there.
        if (widget.onSpeak != null)
          SheetGroup(
            children: [
              SheetRow(
                icon: _lucide(Lucide.mic),
                label: widget.speakLabel,
                onPress: () {
                  widget.onClose();
                  widget.onSpeak!();
                },
              ),
            ],
          ),
        if (name != null)
          SheetGroup(
            children: [SheetField(label: 'Name', value: name.value, onChange: name.onChange, placeholder: 'What this ${name.kind} is called', autoCorrect: false)],
          ),
        if (reading) ...[
          const SheetHeading('Reading it'),
          SheetGroup(
            children: [
              if (look != null) LookChoice(look: look),
              if (widget.onBookmark != null)
                SheetRow(
                  icon: _lucide(Lucide.bookmark, 2.2),
                  label: widget.marked ? 'Move or remove the bookmark' : 'Bookmark this line',
                  hint: widget.marked ? 'Moves it to the line the caret is on, or takes it off when it is already there.' : 'Marks the line the caret is on, to come back to.',
                  onPress: widget.onBookmark,
                ),
              if (widget.onFind != null) SheetRow(icon: _lucide(Lucide.textSearch, 2.2), label: 'Find and replace', onPress: widget.onFind),
              // A list laid out as columns, in the note's own words (docs/BOARDS.md).
              if (widget.onMakeBoard != null) SheetRow(icon: _drawn(AppIcons.board), label: 'Make a board', hint: 'Every item in this note becomes a card.', onPress: widget.onMakeBoard),
            ],
          ),
        ],
        // Comment, near the top where a thumb is quick to it.
        if (widget.onComment != null) ...[
          const SheetHeading('Comments'),
          SheetGroup(
            children: [
              SheetRow(
                icon: _lucide(Lucide.messageSquarePlus, 2.2),
                label: 'Comment',
                hint: 'On the words selected, or on the line the caret is on.',
                onPress: () {
                  widget.onClose();
                  widget.onComment!();
                },
              ),
              if (widget.commentsSummary != null)
                SheetRow(
                  icon: _lucide(Lucide.messageSquare, 2.2),
                  label: widget.commentsSummary!,
                  hint: 'Read them, reply, or resolve them.',
                  onPress: () {
                    widget.onClose();
                    widget.onCommentsList?.call();
                  },
                ),
            ],
          ),
        ],
        if (widget.onAi != null) ...[
          const SheetHeading('AI'),
          SheetGroup(
            children: [
              for (final kind in aiKinds)
                SheetRow(
                  key: ValueKey('ai:${kind.id}'),
                  icon: _lucide(kind.icon, 2.1),
                  label: kind.label,
                  hint: kind.hint,
                  onPress: () {
                    widget.onClose();
                    widget.onAi!(kind.id);
                  },
                ),
              AskField(
                onAsk: (instruction) {
                  widget.onClose();
                  widget.onAi!('ask', instruction);
                },
              ),
            ],
          ),
        ],
        // Read by anyone with its link, and nobody else (share/share.ts, docs/SHARING.md).
        if (widget.sharing != null) ...[const SheetHeading('Sharing'), SheetGroup(children: widget.sharing!)],
        ?widget.sharingSection,
        const SheetHeading('Where it sits'),
        SheetGroup(
          children: [
            SheetRow(icon: _drawn(AppIcons.pin), label: widget.pinned ? 'Unpin' : 'Pin to the top', onPress: widget.onPin),
            SheetRow(icon: _drawn(AppIcons.archiveBox), label: 'Archive', onPress: widget.onArchive),
            SheetRow(
              icon: _drawn(AppIcons.workspace),
              label: 'Workspace',
              hint: filed != null ? filed.name : (widget.workspaces.value.list.isNotEmpty ? 'Not in one' : 'None yet. Make one to sort your notes.'),
              onPress: () => setState(() => _page = NoteSettingsPage.workspace),
            ),
            // Every version kept, to go back to (Matt: "allow versioning on personal notes by enabling it under the more menu").
            if (history != null)
              if (history.keeps)
                SheetRow(
                  icon: _lucide(Lucide.history),
                  label: 'Version history',
                  hint: history.record.versionsByDefault(widget.noteId) ? 'Kept for an organization’s notes. Go back to any version.' : 'Every version kept. Go back to any of them.',
                  onPress: () => setState(() => _page = NoteSettingsPage.history),
                )
              else
                SheetRow(
                  icon: _lucide(Lucide.history),
                  label: 'Keep version history',
                  hint: 'Saves a version as you write, to go back to like git. Kept beside the note as a .versions file.',
                  onPress: () {
                    history.record.setKeepsVersions(widget.noteId, true);
                    setState(() => _page = NoteSettingsPage.history);
                  },
                ),
            // Where it was written, last of where it sits: the tag added or taken off, and why it can't be here.
            if (location != null)
              if (location.tag != null)
                SheetRow(icon: _drawn(AppIcons.locate), label: 'Remove location', hint: tagLabel(location.tag!), onPress: location.onRemove)
              else
                SheetRow(icon: _drawn(AppIcons.locate), label: 'Add my location', hint: locationHint(location), onPress: location.cannot == null ? location.onAdd : null),
          ],
        ),
        if (widget.linked != null && widget.linked!.isNotEmpty) ...[const SheetHeading('Linked to'), SheetGroup(children: widget.linked!)],
        if (widget.cheatSheet != null) ...[
          const SheetHeading('Help'),
          SheetGroup(
            children: [
              SheetRow(
                icon: _lucide(Lucide.listChecks, 2.2),
                label: 'Formatting cheat sheet',
                hint: 'Every mark you can type, and what it looks like, on one page.',
                onPress: () => setState(() => _page = NoteSettingsPage.cheatsheet),
              ),
            ],
          ),
        ],
        // Into the trash, from where it is brought back or deleted for good (core/trash.ts).
        SheetGroup(
          children: [SheetRow(icon: _drawn(AppIcons.bin), label: 'Move to Trash', onPress: widget.onDelete, danger: true)],
        ),
      ],
    );
  }
}

/// How the note looks - Plain, Reading, or its map (`.row[data-choice]`, `.viewChoice`): a row of words, the chosen
/// one filled. The row itself is not pressed, its words are. Always the first row of its group.
class LookChoice extends StatelessWidget implements SheetRuled {
  const LookChoice({super.key, required this.look});
  final NoteLook look;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md'), sm = t.fontSize('sm');
    final ink = t.color('glacier-text');
    final options = <(Look?, String)>[(null, 'Plain'), (Look.reading, 'Reading'), if (look.canMap) (Look.map, 'Map')];
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: t.space(12)),
      child: Padding(
        // `.row { padding: var(--glacier-space-3) var(--glacier-space-4) }`
        padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
        // `justify-content: space-between`
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          spacing: t.space(3),
          children: [
            Text('Look', style: pageText(t, md, weight: 'medium', color: ink)),
            Semantics(
              container: true,
              label: 'How this note looks',
              child: Container(
                // `padding: 3px; border: var(--app-line) solid var(--glacier-border-strong); border-radius: full`
                padding: const EdgeInsets.all(3),
                // Measured on the page (Chromium, two device pixels to one): the 1.5px line is drawn 1px here, the box 40 tall
                // over its 32px words and the first of them 4px in. `snapBorder` would make it 1.5.
                decoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-strong'), width: t.len('app-line').floorToDouble()), borderRadius: BorderRadius.circular(t.radius('full'))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (value, label) in options)
                      GlacierPressable(
                        key: ValueKey('look:$label'),
                        onPressed: () => look.onChange(value),
                        semanticLabel: label,
                        selected: look.value == value,
                        pressScale: null,
                        builder: (context, state) {
                          final on = look.value == value;
                          return Container(
                            // `min-block-size: 2rem; padding: 0 var(--glacier-space-3); border-radius: full`
                            constraints: BoxConstraints(minHeight: t.lenOf('2rem')),
                            padding: EdgeInsets.symmetric(horizontal: t.space(3)),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: on ? ink : null, borderRadius: BorderRadius.circular(t.radius('full'))),
                            // `font-size: sm; font-weight: semibold; color: muted`, and on: `background: text; color: bg`.
                            child: Text(label, style: pageText(t, sm, weight: 'semibold', color: on ? t.color('glacier-bg') : t.color('glacier-text-muted'))),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Ask field (`.ask`), a row of the AI group: its ring, the words, and a send that is quiet until there are
/// words (Matt: "Those, plus an Ask field").
class AskField extends StatefulWidget implements SheetRuled {
  const AskField({super.key, required this.onAsk});
  final ValueChanged<String> onAsk;

  @override
  State<AskField> createState() => _AskFieldState();
}

class _AskFieldState extends State<AskField> {
  final TextEditingController _words = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'Ask the AI');

  @override
  void initState() {
    super.initState();
    _words.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _words.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final said = _words.text.trim();
    if (said.isNotEmpty) widget.onAsk(said);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final ink = t.color('glacier-text');
    final empty = _words.text.trim().isEmpty;
    final style = pageText(t, md, color: ink);
    final rule = snapBorder(context, 1);
    final send = t.lenOf('2.25rem');
    return Semantics(
      container: true,
      label: 'Ask the AI',
      child: DecoratedBox(
        // `border-block-start: 1px solid var(--glacier-border-subtle)`
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: rule))),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: t.space(12)),
          child: Padding(
            // `padding: space-2 space-3 space-2 space-4`
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2) + rule, t.space(3), t.space(2)),
            child: IconTheme(
              data: IconThemeData(color: ink, size: md),
              child: Row(
                spacing: t.space(3),
                children: [
                  const SheetIcon(icon: AppIcon(Lucide.bot, size: 18, strokeWidth: 2.1)),
                  Expanded(
                    child: Padding(
                      // `.askInput { padding: var(--glacier-space-2) 0 }`
                      padding: EdgeInsets.symmetric(vertical: t.space(2)),
                      child: Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [
                          if (_words.text.isEmpty)
                            ExcludeSemantics(child: Text('Ask it to do something with this note', maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(color: t.color('glacier-text-subtle')))),
                          Semantics(
                            label: 'What to do with this note',
                            textField: true,
                            child: EditableText(
                              controller: _words,
                              focusNode: _focus,
                              style: style,
                              cursorColor: ink,
                              cursorWidth: 1,
                              backgroundCursorColor: t.color('glacier-text-subtle'),
                              selectionColor: t.color('glacier-selection'),
                              autocorrect: false,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _submit(),
                              keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  GlacierPressable(
                    onPressed: empty ? null : _submit,
                    semanticLabel: 'Ask',
                    builder: (context, state) {
                      final color = empty ? t.color('glacier-text-muted') : ink;
                      return Container(
                        width: send,
                        height: send,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: snapBorder(context, t.len('app-line')))),
                        child: AppIcon(Lucide.arrowUp, size: 18, strokeWidth: 2.2, color: color),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
