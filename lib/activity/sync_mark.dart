/// A note's sync by its title (docs/ACTIVITY.md, In place; Matt, 2026-10-29: "per-note sync marks (blue arrow → tick)
/// in lists and the note's header"): a small arrow in the sync's blue while it waits to go, a tick for a moment as it
/// goes, then nothing; a still red mark where it could not be sent, the reason in a bubble on hover or a long press.
/// What it reads is lib/sync/sync_marks.dart; where it is drawn: the home's and All notes' cards, the icon view's
/// tiles, the sidebar's rows and the open notes' tabs.
///
/// Calm draws it in ink, as every `--activity-*` colour is; where the device asks for less motion the tick comes and
/// goes at once. Simple mode shows it as advanced does.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/background_jobs.dart' show JobKind, JobLook;
import '../core/note.dart';
import '../sync/notes.dart' show FileKind;
import '../sync/sync_marks.dart';
import 'activity_look.dart';
import 'activity_tray.dart' show JobBar;

/// [child] (a note's title) with [note]'s mark after it while it has one, [size] square; [child] alone otherwise, so a
/// note with nothing to say is laid out as it always was. [expand], the title takes the row's room (a list's row);
/// otherwise the two sit together in the middle (a tile's name). [top] holds the mark down from the row's top, to sit
/// by a title's first line; null centres it.
class NoteSyncMarked extends StatelessWidget {
  const NoteSyncMarked({super.key, required this.note, required this.child, this.size = 14, this.expand = true, this.top, this.marks});

  final Note note;
  final Widget child;
  final double size;
  final bool expand;
  final double? top;

  /// The app's [noteSyncMarks] unless given.
  final NoteSyncMarks? marks;

  @override
  Widget build(BuildContext context) {
    final marks = this.marks ?? noteSyncMarks;
    return ListenableBuilder(
      listenable: marks,
      builder: (context, _) {
        final mark = marks.of(note);
        if (mark.look == NoteSyncLook.none) return child;
        final drawn = NoteSyncMarkView(key: ValueKey('note-sync:${note.id}'), mark: mark, size: size, marks: marks);
        final placed = top == null ? drawn : Padding(padding: EdgeInsets.only(top: top!), child: drawn);
        return Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: top == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            if (expand) Expanded(child: child) else Flexible(child: child),
            SizedBox(width: size * 0.4),
            placed,
          ],
        );
      },
    );
  }
}

/// The mark itself: the arrow, the tick or the red mark. A tick asks to be drawn again as its moment ends.
class NoteSyncMarkView extends StatefulWidget {
  const NoteSyncMarkView({super.key, required this.mark, this.size = 14, this.marks});

  final NoteSyncMark mark;
  final double size;
  final NoteSyncMarks? marks;

  @override
  State<NoteSyncMarkView> createState() => _NoteSyncMarkViewState();
}

class _NoteSyncMarkViewState extends State<NoteSyncMarkView> {
  Timer? _tick;
  Timer? _bubbleGoes;
  final OverlayPortalController _bubble = OverlayPortalController();
  final LayerLink _link = LayerLink();

  /// Whether the mark is past the middle of the window, so its bubble hangs back toward the start.
  bool _towardStart = true;

  @override
  void initState() {
    super.initState();
    _time();
  }

  @override
  void didUpdateWidget(NoteSyncMarkView old) {
    super.didUpdateWidget(old);
    if (old.mark != widget.mark || old.mark.left != widget.mark.left) _time();
    if (widget.mark.look != NoteSyncLook.failed && _bubble.isShowing) _bubble.hide();
  }

  /// The tick's moment: once it is up, the marks are asked again (they answer nothing, or the arrow of a change since).
  void _time() {
    _tick?.cancel();
    _tick = null;
    final left = widget.mark.left;
    if (widget.mark.look != NoteSyncLook.sent || left == null) return;
    _tick = Timer(left, () {
      if (mounted) setState(() {});
      // Every mark of this note is drawn again from the marks.
      (widget.marks ?? noteSyncMarks).refresh();
    });
  }

  void _show({Duration? forHow}) {
    if (widget.mark.look != NoteSyncLook.failed) return;
    _bubbleGoes?.cancel();
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) _towardStart = box.localToGlobal(box.size.center(Offset.zero)).dx > MediaQuery.sizeOf(context).width / 2;
    _bubble.show();
    if (forHow != null) _bubbleGoes = Timer(forHow, () => _bubble.hide());
  }

  void _hide() {
    _bubbleGoes?.cancel();
    if (_bubble.isShowing) _bubble.hide();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _bubbleGoes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mark = widget.mark;
    final size = widget.size;
    final (icon, look, said) = switch (mark.look) {
      NoteSyncLook.waiting => (Lucide.arrowUp, JobLook.sync, 'Waiting to sync'),
      NoteSyncLook.sent => (Lucide.check, JobLook.sync, 'Synced'),
      NoteSyncLook.failed => (Lucide.circleAlert, JobLook.needsYou, 'Not synced${mark.reason == null ? '' : ': ${mark.reason}'}'),
      NoteSyncLook.none => (Lucide.check, JobLook.sync, ''),
    };
    final colour = jobColour(t, look);
    Widget drawn = AppIcon(icon, key: ValueKey('note-sync-mark:${mark.look.name}'), size: size, color: colour, strokeWidth: 2.4);
    drawn = AnimatedSwitcher(duration: activityMoves(context) ? const Duration(milliseconds: 200) : Duration.zero, child: drawn);
    if (mark.look == NoteSyncLook.failed) {
      final reason = mark.reason ?? 'It could not be sent. It is tried again at the next sync.';
      drawn = CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _bubble,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            // Hung toward the middle of the window from the mark, so it never runs off the edge the mark is near.
            targetAnchor: _towardStart ? Alignment.bottomRight : Alignment.bottomLeft,
            followerAnchor: _towardStart ? Alignment.topRight : Alignment.topLeft,
            offset: Offset(_towardStart ? 4 : -4, 6),
            child: Align(alignment: _towardStart ? Alignment.topRight : Alignment.topLeft, child: SyncReasonBubble(reason: reason)),
          ),
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: (_) => _hide(),
            child: GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: () => _show(forHow: const Duration(seconds: 4)), child: drawn),
          ),
        ),
      );
    }
    return Semantics(label: said, tooltip: mark.look == NoteSyncLook.failed ? mark.reason : null, child: ExcludeSemantics(child: SizedBox.square(dimension: size, child: drawn)));
  }
}

/// A thin bar in [kind]'s colour while the file goes to the service (a picture by its name, a recording by its note's
/// id: lib/sync/sync_marks.dart [NoteSyncMarks.sending]), sweeping since the send cannot say how far, still where the
/// device asks for less motion; nothing otherwise. Laid along the foot of what it is for (docs/ACTIVITY.md, In place:
/// "upload progress on share rows, pictures and recordings").
class FileSendingBar extends StatelessWidget {
  const FileSendingBar({super.key, required this.file, required this.name, required this.kind, this.top = 0, this.marks});

  final FileKind file;
  final String name;
  final JobKind kind;

  /// Room over it while it shows; none while it does not.
  final double top;
  final NoteSyncMarks? marks;

  @override
  Widget build(BuildContext context) {
    final marks = this.marks ?? noteSyncMarks;
    return ListenableBuilder(
      listenable: marks,
      builder: (context, _) {
        if (!marks.isSending(file, name)) return const SizedBox.shrink();
        return Semantics(
          label: file == FileKind.recording ? 'Sending the recording' : 'Sending the picture',
          liveRegion: true,
          child: Padding(padding: EdgeInsets.only(top: top), child: JobBar(key: ValueKey('file-sending:${file.name}/$name'), colour: kindColour(context.tokens, kind))),
        );
      },
    );
  }
}

/// Why a note could not be sent, in a small bubble under its red mark.
class SyncReasonBubble extends StatelessWidget {
  const SyncReasonBubble({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final red = jobColour(t, JobLook.needsYou);
    return ConstrainedBox(
      key: const ValueKey('note-sync-reason'),
      constraints: BoxConstraints(maxWidth: t.lenOf('16rem')),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
        decoration: BoxDecoration(
          color: t.colorOf('color-mix(in srgb, var(--glacier-bg) 96%, var(--glacier-text) 4%)'),
          borderRadius: BorderRadius.circular(t.radius('sm')),
          border: Border.all(color: red.withValues(alpha: red.a * 0.5)),
          boxShadow: const [BoxShadow(color: Color(0x24000000), offset: Offset(0, 4), blurRadius: 12)],
        ),
        child: Text('Not synced: $reason', style: t.text('xs', color: t.color('glacier-text'))),
      ),
    );
  }
}
