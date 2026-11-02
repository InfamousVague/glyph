/// The Trash, as a section of its own (Matt, 2026-10-23: "add a "trash" section in the app where deleted notes go
/// before getting perma deleted"). The port's own: the web's trash is the sidebar's last folder only, which this
/// app keeps (lib/notes/note_tree.dart), and that folder, All notes' Trash word and the palette's Trash open this.
///
/// A sheet, as a workspace's is (lib/notes/workspace_sheet.dart), over whatever is on screen: from the foot on a
/// phone, a window in the middle on a Mac. Its first page lists the notes in the trash, the last thrown away first,
/// each with when it went in and how long it has left; Delete forever over them; and the rule at the foot, that a
/// note is deleted for good thirty days after it goes in (lib/core/trash.dart `trashKeeps`), an organization's
/// excepted. A note's row opens its own page: Restore, which puts it back where it was, its folder and all, since a
/// note in the trash keeps its filing (and says where that is); Delete forever, which asks once; and Back. Emptying
/// asks once too. The sidebar folder keeps the web's words: Restore, Delete for good, "Delete 3 for good?".
///
/// Nothing is done here: what each row does is the caller's, the app's own note actions (lib/notes/note_actions.dart),
/// so a note restored says so in a toast, and one deleted for good has its Undo, as from the sidebar. In simple mode
/// (GHST-103) a note's page offers Restore, with Delete forever behind a More row that opens in place.
///
/// PAGES, AND DELETE FOREVER AT THE TOP (Matt, 2026-11-02, with some 1,300 notes in his Trash after a cleanup:
/// "paginate the trash and add a 'delete forever' button at the top of the trash modal so we don't have to scroll all
/// the way down"). The list is [trashPageSize] notes a page, the last thrown away first, with Previous, "1–50 of
/// 1,312" and Next over the rows and under them; a Find field over a Trash of more than a page narrows it by title.
/// Delete forever (and, in Advanced, Restore all; Simple keeps it behind More, opened in place) is pinned at the
/// sheet's top over the scrolling rows ([Sheet.pinned]), and asks once on the row itself: "Delete 1,312 notes
/// forever?", "This can’t be undone.", with how many are an organization's where any are, since deleting one for good
/// deletes it for every member (lib/notes/workspace_sheet.dart's folder delete says the same of a team's folder).
/// With Find typed in, both act on the notes found. The sheet shuts as the emptying starts; the notes go in batches,
/// on the Activity tray (lib/notes/note_actions.dart `emptyTrash`). The note's page says Delete forever too.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/trash.dart';
import '../sheet/css.dart';
import '../sheet/flow.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'when.dart';

/// How many notes a page of the Trash lists.
const int trashPageSize = 50;

/// A page of the Trash, as its bar says it: "1–50 of 1,312". [from] and [to] count from one.
String trashPageWords(int from, int to, int total) => '${groupedCount(from)}–${groupedCount(to)} of ${groupedCount(total)}';

/// Delete forever's question, on the row itself: "Delete 1,312 notes forever?".
String trashEmptyQuestion(int count) => count == 1 ? 'Delete 1 note forever?' : 'Delete ${groupedCount(count)} notes forever?';

/// The line under it: that nothing undoes it, and, where [team] of them are an organization's, that those go for
/// every member: "Including 14 team notes, for every member. This can’t be undone."
String trashEmptyNote(int team) {
  if (team <= 0) return 'This can’t be undone.';
  return 'Including ${team == 1 ? '1 team note' : '${groupedCount(team)} team notes'}, for every member. This can’t be undone.';
}

/// When a note went into the trash, as its row says it: "Deleted 2 hr ago", "Deleted yesterday", "Deleted on
/// Tuesday".
String deletedWhen(int at, int now) {
  final said = when(at, now);
  if (said == 'Just now' || said == 'Yesterday') return 'Deleted ${said.toLowerCase()}';
  if (said.endsWith(' ago')) return 'Deleted $said';
  return 'Deleted on $said';
}

/// How long a note has left in the trash, as its row says it after when it went in.
String trashLeft(int at, int now, {required bool team}) {
  if (team) return 'kept until you empty the Trash';
  final days = trashDaysLeft(at, now);
  if (days <= 0) return 'deleted for good today';
  return days == 1 ? 'deleted for good tomorrow' : 'deleted for good in $days days';
}

/// The Trash's sheet.
class TrashSheet extends StatefulWidget {
  const TrashSheet({
    super.key,
    required this.notes,
    required this.held,
    required this.onRestore,
    required this.onDestroy,
    required this.onEmpty,
    required this.onClose,
    this.onRestoreAll,
    this.open,
    this.teamNote,
    this.placeOf,
    this.simple = false,
    this.now,
  });

  /// The notes in the trash, the last thrown away first (lib/core/trash.dart `inTrash`), less any deleted for good
  /// whose Undo still stands.
  final List<Note> notes;

  /// When each went in.
  final TrashHeld held;

  /// Out of the trash, back where it was.
  final ValueChanged<Note> onRestore;

  /// Deleted for good, once asked.
  final ValueChanged<Note> onDestroy;

  /// These deleted for good, once asked: every note in it, or the ones Find found.
  final ValueChanged<List<Note>> onEmpty;
  final VoidCallback onClose;

  /// These out of the trash, each back where it was, once asked: Restore all. None offered where null.
  final ValueChanged<List<Note>>? onRestoreAll;

  /// The note whose page the sheet opens on, by id: one pressed in the sidebar's Trash folder.
  final String? open;

  /// Whether a note is an organization's, which waits for the person's own Empty (lib/core/trash.dart
  /// `expiredInTrash`).
  final bool Function(String id)? teamNote;

  /// Where a note is filed, as Restore's hint says it: "Work › Clients"; null for none.
  final String? Function(String id)? placeOf;

  /// Simple mode (GHST-103): Delete forever behind More on a note's page, and Restore all behind More on the list.
  final bool simple;

  /// The moment "2 hr ago" is counted from; this one where it is left out.
  final int Function()? now;

  @override
  State<TrashSheet> createState() => _TrashSheetState();
}

class _TrashSheetState extends State<TrashSheet> {
  /// The note whose page is open, by id; null for the list.
  late String? _note = widget.open;

  /// Delete forever pressed on a note's page: the sheet asks first.
  bool _destroying = false;

  /// Delete forever pressed at the list's top: the row asks first, in place.
  bool _emptying = false;

  /// Restore all pressed: the row asks first, in place.
  bool _restoring = false;

  /// Simple mode's More, opened on a note's page.
  bool _more = false;

  /// Simple mode's More at the list's top, which opens Restore all in place.
  bool _allMore = false;

  /// The page of the list on screen, from naught.
  int _page = 0;

  /// What Find has typed: the list narrowed to the titles that have it.
  String _query = '';

  /// The list's scroll, put back at the top as the page turns.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int get _now => widget.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  static String _title(Note note) {
    final title = NoteFacts.of(note).title.trim();
    return title.isEmpty ? 'Untitled' : title;
  }

  bool _team(String id) => widget.teamNote?.call(id) ?? false;

  void _list() => setState(() {
        _note = null;
        _destroying = false;
        _emptying = false;
        _restoring = false;
        _more = false;
      });

  void _turn(int page) {
    setState(() {
      _page = page;
      _emptying = false;
      _restoring = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String _hint(Note note, int now) {
    final at = widget.held[note.id] ?? now;
    return '${deletedWhen(at, now)} · ${trashLeft(at, now, team: _team(note.id))}';
  }

  /// The notes the list shows: all of them, or those whose title has what Find has typed.
  List<Note> _found(List<Note> notes) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return notes;
    return [
      for (final note in notes)
        if (_title(note).toLowerCase().contains(query)) note,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final notes = widget.notes;
    final open = _note == null ? null : notes.where((note) => note.id == _note).firstOrNull;

    if (open != null) {
      final title = _title(open);
      if (_destroying) {
        return Sheet(
          label: 'Delete $title forever',
          onBack: () => setState(() => _destroying = false),
          onClose: widget.onClose,
          children: [
            SheetTitle.text('Delete “$title” forever?'),
            SheetNote(_team(open.id) ? 'It is deleted for every member of its organization too.' : 'It cannot be restored from the Trash after this.'),
            SheetGroup(
              children: [
                SheetRow(
                  key: const ValueKey('trash-destroy-yes'),
                  label: 'Delete forever',
                  danger: true,
                  onPress: () {
                    widget.onDestroy(open);
                    _list();
                  },
                ),
                SheetRow(label: 'Cancel', onPress: () => setState(() => _destroying = false)),
              ],
            ),
          ],
        );
      }
      final place = widget.placeOf?.call(open.id);
      final destroy = SheetRow(key: const ValueKey('trash-destroy'), label: 'Delete forever', danger: true, onPress: () => setState(() => _destroying = true));
      return Sheet(
        label: title,
        onBack: _list,
        onClose: widget.onClose,
        children: [
          SheetTitle.text(title),
          SheetNote('${_hint(open, now)}.'),
          SheetGroup(
            children: [
              SheetRow(
                key: const ValueKey('trash-restore'),
                label: 'Restore',
                hint: place == null ? 'Back in your notes.' : 'Back in $place.',
                onPress: () {
                  widget.onRestore(open);
                  if (notes.length <= 1) {
                    widget.onClose();
                  } else {
                    _list();
                  }
                },
              ),
              if (!widget.simple)
                destroy
              else if (_more)
                destroy
              else
                SheetRow(key: const ValueKey('trash-more'), label: 'More', onPress: () => setState(() => _more = true)),
              SheetRow(label: 'Back', onPress: _list),
            ],
          ),
        ],
      );
    }

    final found = _found(notes);
    final narrowed = _query.trim().isNotEmpty;
    final count = found.length;
    // Only the page on screen is built: a Trash of a thousand notes is twenty pages, never a thousand rows.
    final pages = count == 0 ? 1 : (count + trashPageSize - 1) ~/ trashPageSize;
    final page = _page.clamp(0, pages - 1);
    final first = page * trashPageSize;
    final shown = found.sublist(first, (first + trashPageSize).clamp(0, count));
    final team = notes.any((note) => _team(note.id));

    // Delete forever and Restore all, at the top over the scrolling rows; each asks on the row itself.
    final List<Widget> actions;
    if (_emptying && count > 0) {
      actions = [
        SheetRow(
          key: const ValueKey('trash-empty-yes'),
          label: trashEmptyQuestion(count),
          hint: trashEmptyNote(found.where((note) => _team(note.id)).length),
          danger: true,
          onPress: () {
            widget.onEmpty(found);
            widget.onClose();
          },
        ),
        SheetRow(key: const ValueKey('trash-empty-no'), label: 'Cancel', onPress: () => setState(() => _emptying = false)),
      ];
    } else if (_restoring && count > 0 && widget.onRestoreAll != null) {
      actions = [
        SheetRow(
          key: const ValueKey('trash-restore-all-yes'),
          label: count == 1 ? 'Restore 1 note?' : 'Restore ${groupedCount(count)} notes?',
          hint: count == 1 ? 'It goes back where it was.' : 'Each goes back where it was.',
          onPress: () {
            widget.onRestoreAll!(found);
            if (count == notes.length) {
              widget.onClose();
            } else {
              setState(() {
                _restoring = false;
                _query = '';
                _page = 0;
              });
            }
          },
        ),
        SheetRow(key: const ValueKey('trash-restore-all-no'), label: 'Cancel', onPress: () => setState(() => _restoring = false)),
      ];
    } else if (count > 0) {
      final restoreAll = SheetRow(
        key: const ValueKey('trash-restore-all'),
        label: 'Restore all',
        hint: narrowed ? 'The ${groupedCount(count)} found, back where each was.' : 'Every note back where it was.',
        onPress: () => setState(() {
          _restoring = true;
          _emptying = false;
        }),
      );
      actions = [
        SheetRow(
          key: const ValueKey('trash-empty'),
          label: 'Delete forever',
          hint: narrowed
              ? 'The ${groupedCount(count)} found, of ${groupedCount(notes.length)}.'
              : count == 1
                  ? 'Deletes the 1 note in the Trash.'
                  : 'Deletes all ${groupedCount(count)} notes in the Trash.',
          danger: true,
          onPress: () => setState(() {
            _emptying = true;
            _restoring = false;
          }),
        ),
        if (widget.onRestoreAll != null)
          if (!widget.simple || _allMore) restoreAll else SheetRow(key: const ValueKey('trash-all-more'), label: 'More', onPress: () => setState(() => _allMore = true)),
      ];
    } else {
      actions = const [];
    }

    Widget bar(String at) => _PageBar(
          key: ValueKey('trash-pages-$at'),
          at: at,
          words: trashPageWords(first + 1, first + shown.length, count),
          onPrevious: page > 0 ? () => _turn(page - 1) : null,
          onNext: page < pages - 1 ? () => _turn(page + 1) : null,
        );

    return Sheet(
      label: 'Trash',
      onClose: widget.onClose,
      controller: _scroll,
      pinned: [
        const SheetTitle(child: Text('Trash')),
        if (actions.isNotEmpty) SheetGroup(key: const ValueKey('trash-actions'), children: actions),
      ],
      children: [
        SheetNote(notes.isEmpty ? 'Nothing in the Trash.' : 'Deleted notes wait here. Restore one to put it back where it was.'),
        if (notes.length > trashPageSize || narrowed)
          SheetGroup(
            children: [
              SheetField(
                key: const ValueKey('trash-find'),
                label: 'Find',
                value: _query,
                placeholder: 'A note’s title',
                autoCorrect: false,
                onChange: (text) => setState(() {
                  _query = text;
                  _page = 0;
                  _emptying = false;
                  _restoring = false;
                }),
              ),
            ],
          ),
        if (notes.isNotEmpty && count == 0) const SheetNote('No note in the Trash has that in its title.'),
        if (pages > 1) bar('top'),
        if (shown.isNotEmpty)
          SheetGroup(
            children: [
              for (final note in shown) SheetRow(key: ValueKey('trash-note-${note.id}'), label: _title(note), hint: _hint(note, now), onPress: () => setState(() => _note = note.id)),
            ],
          ),
        if (pages > 1) bar('foot'),
        SheetNote(
          team
              ? 'Notes are deleted for good ${trashKeeps.inDays} days after they go in the Trash. An organization’s notes wait until you empty it.'
              : 'Notes are deleted for good ${trashKeeps.inDays} days after they go in the Trash.',
        ),
      ],
    );
  }
}

/// Previous, where the list is ("1–50 of 1,312") and Next: over the rows and under them, so a page turns from either
/// end of it. A button with no page that way is drawn quiet, and does nothing.
class _PageBar extends StatelessWidget {
  const _PageBar({super.key, required this.at, required this.words, required this.onPrevious, required this.onNext});

  /// Which bar, for the buttons' keys: `top` or `foot`.
  final String at;
  final String words;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    Widget button(String label, String key, VoidCallback? onPressed) => GlacierPressable(
          key: ValueKey('trash-pages-$at-$key'),
          onPressed: onPressed,
          semanticLabel: '$label page',
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('sm'),
            child: Container(
              constraints: BoxConstraints(minHeight: t.space(10)),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: t.space(3)),
              decoration: BoxDecoration(color: state.pressed && onPressed != null ? t.color('app-wash') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: pageText(
                    t,
                    sm,
                    weight: 'medium',
                    color: onPressed == null
                        ? t.color('glacier-text-muted')
                        : state.hovered
                            ? t.color('glacier-text')
                            : t.color('glacier-text-subtle'),
                  ),
                ),
              ),
            ),
          ),
        );
    return CssFlow.block(
      margin: EdgeInsets.only(bottom: t.space(3)),
      child: Row(
        children: [
          button('Previous', 'previous', onPrevious),
          Expanded(child: Text(words, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: t.color('glacier-text-subtle')))),
          button('Next', 'next', onNext),
        ],
      ),
    );
  }
}
