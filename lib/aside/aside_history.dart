import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/versions_live.dart';
import '../core/versions_record.dart';
import '../note/version_history.dart';
import '../sheet/css.dart';

/// The open note's version history in the desktop's aside (Matt: "make a sidebar that can be expanded on desktop to
/// see the version history"): the More sheet's timeline (lib/note/version_history.dart), beside the note rather than
/// over it, so a version can be read against the words while they are still on screen. It compares with the
/// editor's words and restores through the editor (lib/core/versions_live.dart), so a restore here is one change to
/// undo, as it is there. A note that keeps no history says so, with the way to start one. A port of
/// `src/app/aside/AsideHistory.tsx`, less its head, which the panel it is in draws (aside_panel.dart).
class AsideHistory extends StatefulWidget {
  const AsideHistory({super.key, required this.noteId, required this.title, required this.record, this.onShareFile, this.say});

  final String noteId;
  final String title;
  final VersionsRecord record;
  final Future<String?> Function(String noteId, String title)? onShareFile;
  final void Function(String message)? say;

  @override
  State<AsideHistory> createState() => _AsideHistoryState();
}

class _AsideHistoryState extends State<AsideHistory> {
  @override
  void initState() {
    super.initState();
    widget.record.keeping.addListener(_heard);
    liveNotes.addListener(_heard);
  }

  @override
  void didUpdateWidget(AsideHistory old) {
    super.didUpdateWidget(old);
    if (identical(old.record, widget.record)) return;
    old.record.keeping.removeListener(_heard);
    widget.record.keeping.addListener(_heard);
  }

  @override
  void dispose() {
    widget.record.keeping.removeListener(_heard);
    liveNotes.removeListener(_heard);
    super.dispose();
  }

  bool _waiting = false;

  /// A note says it is on screen as its screen is made, and that it has gone as it is let go: both while the tree
  /// is being built, when this is drawn after the frame.
  void _heard() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) return setState(() {});
    if (_waiting) return;
    _waiting = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _waiting = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = t.color('glacier-text-muted');
    final sm = t.fontSize('sm');
    // `.empty { margin: var(--glacier-space-2) var(--glacier-space-1); color: var(--glacier-text-muted) }`
    Widget empty(String text) => Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(1)),
          child: Text(text, style: t.textAt(sm, color: muted)),
        );
    if (!widget.record.keepsVersions(widget.noteId)) {
      // `.historyOff { display: grid; gap: var(--glacier-space-2); justify-items: start }`
      return Column(
        key: const ValueKey('aside-history-off'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          empty('This note keeps no version history.'),
          SizedBox(height: t.space(2)),
          GlacierPressable(
            key: const ValueKey('aside-history-on'),
            semanticLabel: 'Keep version history',
            excludeSemantics: true,
            onPressed: () => widget.record.setKeepsVersions(widget.noteId, true),
            builder: (context, state) => ConstrainedBox(
              // `.historyOn { min-block-size: 2.25rem; padding: 0 var(--glacier-space-3); border: 1px solid
              //   var(--glacier-border-subtle); border-radius: var(--glacier-radius-full); font-weight: medium }`
              constraints: BoxConstraints(minHeight: t.lenOf('2.25rem')),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: t.color('glacier-border-subtle'), width: snapBorder(context, 1)),
                  borderRadius: BorderRadius.circular(999),
                  // `.historyOn:hover { background: color-mix(in srgb, var(--glacier-text) 6%, transparent) }`
                  color: state.hovered ? t.color('glacier-text').withValues(alpha: 0.06) : null,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space(3)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('Keep version history', style: t.textAt(sm, weight: 'medium', color: t.color('glacier-text')))],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: t.space(2)),
          // `.historyWhy { margin: 0; color: var(--glacier-text-muted); font-size: var(--glacier-font-size-xs) }`
          Text(
            'A version is saved as you write, to go back to like git. It is kept beside the note as a .versions file.',
            style: t.textAt(t.fontSize('xs'), color: muted),
          ),
        ],
      );
    }
    final live = liveNote(widget.noteId);
    if (live == null) return empty('Reading the note…');
    return VersionHistory(
      key: ValueKey('aside-history:${widget.noteId}'),
      noteId: widget.noteId,
      title: widget.title,
      record: widget.record,
      current: live.current,
      onRestore: live.restore,
      onShareFile: widget.onShareFile,
      say: widget.say,
    );
  }
}
