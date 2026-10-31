/// The morning's ticket digest as a page (Matt, 2026-10-31: "Tapping it opens the My tickets inbox if it exists ...,
/// otherwise a digest note or page you make"): what a tap on the digest's notification opens, its bell row too, where
/// no digest note was written. A sheet over the app, as every page of the app's own is: due today, overdue, blocked,
/// each ticket a tap away; and nothing to say on a morning with none of them.
///
/// The digest itself is lib/book/ticket_digest.dart; this draws it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../book/ticket_digest.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';

/// The digest's sheet.
class TicketDigestSheet extends StatelessWidget {
  const TicketDigestSheet({super.key, required this.digest, required this.onOpen, required this.onClose});

  final TicketDigest digest;

  /// Opens a ticket's note.
  final void Function(String noteId) onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Widget part(String heading, List<DigestItem> items, String? Function(DigestItem item) hint) => SheetGroup(
          children: <Widget>[
            for (final item in items)
              SheetRow(
                key: ValueKey<String>('digest:$heading:${item.noteId}'),
                label: item.named,
                hint: hint(item),
                onPress: () {
                  final open = onOpen;
                  onClose();
                  open(item.noteId);
                },
              ),
          ],
        );
    return Sheet(
      key: const ValueKey<String>('ticket-digest-sheet'),
      label: 'Your tickets today',
      onClose: onClose,
      children: <Widget>[
        SheetTitle.text('Your tickets today'),
        if (digest.empty) const SheetNote('Nothing is due today, overdue or blocked. Enjoy the morning.') else SheetNote(digest.title),
        if (digest.dueToday.isNotEmpty) ...[const SheetHeading('Due today'), part('Due today', digest.dueToday, (_) => null)],
        if (digest.overdue.isNotEmpty) ...[const SheetHeading('Overdue'), part('Overdue', digest.overdue, (item) => item.due == null ? null : 'Due ${item.due}')],
        if (digest.blocked.isNotEmpty) ...[const SheetHeading('Blocked'), part('Blocked', digest.blocked, (item) => item.waitsOn.isEmpty ? null : 'Waits on ${item.waitsOn.join(', ')}')],
      ],
    );
  }
}

/// Shows [digest] over the app until it is closed or a ticket is opened.
Future<void> showTicketDigest(BuildContext context, TicketDigest digest, {required void Function(String noteId) onOpen}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future<void>.value();
  final closed = Completer<void>();
  late final OverlayEntry entry;
  void close() {
    if (closed.isCompleted) return;
    entry.remove();
    closed.complete();
  }

  entry = OverlayEntry(builder: (_) => TicketDigestSheet(digest: digest, onOpen: onOpen, onClose: close));
  overlay.insert(entry);
  return closed.future;
}
