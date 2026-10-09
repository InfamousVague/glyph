/// A note's sharing, in its cog. A port of `src/app/share/ShareRows.tsx`: share it by a read-only link, copy or send
/// the link, stop sharing (lib/share/share.dart). Signed out, the one line says where to sign in, since a share is
/// kept with an account.
///
/// A shared note that says where it was written (or a book with such a chapter) gets one more row, "Share where it
/// was written", with the kit's tick: the link leaves the location out until it is ticked. One whose words hold a
/// place gets its own, "Share the places in it", ticked apart, so a tick given for the one never carries the other.
///
/// A notebook's row says its pages go with it. A journal is shared an entry at a time, so one not shared has one
/// quiet row saying so; a notebook shared before it was kept as a journal goes on being shared as it was.
///
/// What differs from the web original:
/// - The account and the shares are the [AccountServices] it is handed; with none it is the signed-out line.
/// - The rows are the sheet kit's (lib/sheet/kit.dart `SheetHeading`, `SheetGroup`, `SheetRow`), which is what the
///   note's settings draws its rows with (editor/NoteSettings.module.css `.heading`, `.group`, `.row`).
/// - **Send the link** is the platform's share sheet, which this app has no way to yet: its row is drawn only when
///   [ShareRows.onSend] is given, as the page draws it only where `navigator.share` exists.
/// - The note's settings sheet is the editor's to port; until it holds these rows, [ShareSheet] is a sheet of them
///   alone.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/note.dart';
import '../../sheet/css.dart';
import '../../sheet/flow.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../share.dart';

/// What the link carries of where its pages were written and of the places in their words, in one sentence for
/// what the pages hold: nothing where they hold neither (`linkCarries`).
String linkCarries({required bool tag, required bool places, required bool withTag, required bool withPlaces}) {
  if (tag && places) {
    if (withTag && withPlaces) return 'The link carries where it was written and the places in it.';
    if (withPlaces) return 'The link carries the places in it. Where it was written stays out.';
    if (withTag) return 'The link carries where it was written. The places in it stay out.';
    return 'Where it was written and the places in it stay out of the link.';
  }
  if (tag) return withTag ? 'The link carries where it was written.' : 'Where it was written stays out of the link.';
  if (places) return withPlaces ? 'The link carries the places in it.' : 'The places in it stay out of the link.';
  return '';
}

/// What a note is, for its sharing (`kind`).
enum ShareKind { note, notebook, journal }

/// The Sharing heading and its group (`ShareRows`).
class ShareRows extends StatefulWidget {
  const ShareRows({super.key, required this.services, required this.noteId, this.kind = ShareKind.note, this.onSend});

  final AccountServices? services;
  final String noteId;
  final ShareKind kind;

  /// Hands the link to the platform's share sheet (`navigator.share({ url })`).
  final void Function(String url)? onSend;

  @override
  State<ShareRows> createState() => _ShareRowsState();
}

class _ShareRowsState extends State<ShareRows> {
  bool _busy = false;
  String? _said;
  ({bool tag, bool places}) _held = (tag: false, places: false);
  String? _heldFor;

  Shares? get _shares => widget.services?.shares;
  String? get _link => (widget.services?.signedIn ?? false) || _shares?.linkFor(widget.noteId) != null ? _shares?.linkFor(widget.noteId) : null;

  @override
  void initState() {
    super.initState();
    widget.services?.changes.addListener(_changed);
    _readHeld();
  }

  @override
  void didUpdateWidget(ShareRows old) {
    super.didUpdateWidget(old);
    if (old.noteId != widget.noteId) {
      _said = null;
      _held = (tag: false, places: false);
      _heldFor = null;
      _readHeld();
    }
  }

  @override
  void dispose() {
    widget.services?.changes.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _readHeld();
  }

  /// Whether the pages have a tag, and places in their words, to share: read once the note is shared, from the
  /// library as the share reads it.
  void _readHeld() {
    final shares = _shares;
    final link = _link;
    final key = '${widget.noteId}:$link';
    if (shares == null || link == null || key == _heldFor) return;
    _heldFor = key;
    unawaited(() async {
      try {
        final notes = await shares.listNotes();
        Note? note;
        for (final each in notes) {
          if (each.id == widget.noteId) note = each;
        }
        if (mounted && key == _heldFor) setState(() => _held = (tag: note != null && sharesPlace(note, notes), places: note != null && sharesPlaces(note, notes)));
      } catch (_) {
        // The two rows are not offered.
      }
    }());
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      await work();
    } catch (failure) {
      if (mounted) setState(() => _said = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _said = 'The link is copied.');
    } catch (_) {
      if (mounted) setState(() => _said = text);
    }
  }

  Future<void> _share() => _run(() async {
        final shares = _shares!;
        final notes = await shares.listNotes();
        Note? note;
        for (final each in notes) {
          if (each.id == widget.noteId) note = each;
        }
        if (note == null) throw const ShareError('Save the note first: there is nothing to share yet.');
        await _copy(await shares.shareNote(note, notes));
      });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shares = _shares;
    final signedIn = widget.services?.signedIn ?? false;
    final link = shares?.linkFor(widget.noteId);
    final id = widget.noteId;
    final said = _said;
    final send = widget.onSend;
    const mark = AppIcon(Lucide.link2, size: 18, strokeWidth: 2.2);

    final List<Widget> rows;
    if (widget.kind == ShareKind.journal && link == null) {
      rows = const [SheetRow(icon: mark, label: 'A journal is shared an entry at a time. Open one to share it.')];
    } else if (!signedIn || shares == null) {
      rows = const [SheetRow(icon: mark, label: 'Share a read-only link', hint: 'Sign in under Settings › Account first: a share is kept with your account.')];
    } else if (link == null) {
      rows = [
        SheetRow(
          key: const ValueKey('share-start'),
          icon: mark,
          label: _busy ? 'Sharing…' : 'Share a read-only link',
          hint: 'Anyone with the link can read it, and your edits follow. The server can’t read it.${widget.kind == ShareKind.notebook ? ' Every page goes with it.' : ''}',
          disabled: _busy,
          onPress: () => unawaited(_share()),
        ),
      ];
    } else {
      final withPlace = shares.sharingPlace(id), withPlaces = shares.sharingPlaces(id);
      final carries = linkCarries(tag: _held.tag, places: _held.places, withTag: withPlace, withPlaces: withPlaces);
      rows = [
        SheetRow(
          key: const ValueKey('share-copy'),
          icon: const AppIcon(Lucide.copy, size: 18, strokeWidth: 2.2),
          label: 'Copy the link',
          hint: 'Shared, read-only. Your edits reach readers a few seconds after you save.${carries.isEmpty ? '' : ' $carries'}',
          onPress: () => unawaited(_copy(link)),
        ),
        if (_held.tag)
          SheetRow(
            key: const ValueKey('share-place'),
            icon: const DrawnIconView(AppIcons.locate, size: 18),
            label: 'Share where it was written',
            hint: 'The place and the map, on the shared page.',
            disabled: _busy,
            chosen: withPlace,
            onPress: () => unawaited(_run(() => shares.shareWithPlace(id, on: !withPlace))),
          ),
        if (_held.places)
          SheetRow(
            key: const ValueKey('share-places'),
            icon: const AppIcon(Lucide.mapPinned, size: 18, strokeWidth: 2.2),
            label: 'Share the places in it',
            hint: 'The places written in it, and their maps.',
            disabled: _busy,
            chosen: withPlaces,
            onPress: () => unawaited(_run(() => shares.shareWithPlaces(id, on: !withPlaces))),
          ),
        if (send != null) SheetRow(key: const ValueKey('share-send'), icon: const AppIcon(Lucide.share2, size: 18, strokeWidth: 2.2), label: 'Send the link', onPress: () => send(link)),
        SheetRow(
          key: const ValueKey('share-stop'),
          icon: const AppIcon(Lucide.x, size: 18, strokeWidth: 2.2),
          label: _busy ? 'Stopping…' : 'Stop sharing',
          hint: 'The link reads nothing from then on.',
          disabled: _busy,
          onPress: () => unawaited(_run(() => shares.stopSharing(id))),
        ),
      ];
    }

    // Blocks of the sheet's own flow, as the page's fragment is: the heading's margin collapses with the title's or
    // the group's before it, where a Column added the two and the section stood 8.9px low.
    return CssFlow(
      collapse: true,
      children: [
        const SheetHeading('Sharing'),
        SheetGroup(
          children: [
            ...rows,
            if (said != null)
              Padding(
                // `padding: var(--glacier-space-2) var(--glacier-space-4)`
                padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(4)),
                child: Semantics(liveRegion: true, child: Text(said, key: const ValueKey('share-said'), style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle')))),
              ),
          ],
        ),
      ],
    );
  }
}

/// A sheet of a note's sharing alone, from the bar's Share (NoteScreen.tsx `sharing`): the More sheet's rows in a
/// window of their own, under "Share" and the note's title.
class ShareSheet extends StatelessWidget {
  const ShareSheet({super.key, required this.services, required this.noteId, required this.title, this.kind = ShareKind.note, required this.onClose, this.onSend});

  final AccountServices? services;
  final String noteId;

  /// The note's title, over the rows.
  final String title;
  final ShareKind kind;
  final VoidCallback onClose;
  final void Function(String url)? onSend;

  @override
  Widget build(BuildContext context) => Sheet(
        label: 'Share ${title.isEmpty ? 'this note' : title}',
        onClose: onClose,
        children: [
          // `<SheetTitle>Share {title || 'this note'}</SheetTitle>`
          SheetTitle.text('Share ${title.isEmpty ? 'this note' : title}'),
          ShareRows(services: services, noteId: noteId, kind: kind, onSend: onSend),
        ],
      );
}
