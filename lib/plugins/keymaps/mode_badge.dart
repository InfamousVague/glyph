/// The Keyboard modes plugin's badge at the foot of the note (keymaps.dart): a small pill in the page's second ink
/// and its paper, in the kit's mono face. With Vim it says the mode (NORMAL, INSERT, VISUAL, VISUAL LINE) while the
/// note has the keyboard, the keys of a command typed so far and Vim's last word after it, or the command line
/// itself while one is open (`:wq`, `/word`). With Emacs it is there only while something is held: the mark (MARK),
/// a search as it is typed (`I-search: foo`), a `C-x` waiting for its key.
///
/// Drawn by the note's desk over the editor, at its foot and above the keyboard, where the find bar goes; never with
/// the find bar, and never where no hardware keyboard has been used (editor_keys.dart `hardwareKeyboardSeen`). It
/// takes no touches: what is under it is pressed through it.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../editor/view/editor_view.dart';
import 'editor_keys.dart';
import 'keymaps.dart' show KeyboardMode;

/// The parts of the badge, for a test.
abstract final class KeymapBadgeKeys {
  static const Key badge = ValueKey<String>('keymap-badge');
  static const Key words = ValueKey<String>('keymap-badge-words');
}

class KeymapBadge extends StatefulWidget {
  const KeymapBadge({super.key, required this.view});

  final EditorView view;

  @override
  State<KeymapBadge> createState() => _KeymapBadgeState();
}

class _KeymapBadgeState extends State<KeymapBadge> {
  KeymapSession? _session;

  @override
  void initState() {
    super.initState();
    _hear();
  }

  @override
  void didUpdateWidget(KeymapBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) _hear();
  }

  void _hear() {
    _session?.removeListener(_changed);
    _session = keymapSessionOf(widget.view)?..addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    // Told while a frame is being built: drawn after it.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    super.dispose();
  }

  /// What the badge says now, its main words and the quieter ones after them; null for no badge.
  (String, String?)? _words() {
    final session = _session;
    if (session == null || !session.showing || !session.focused) return null;
    switch (session.mode) {
      case KeyboardMode.vim:
        final vim = session.vim;
        if (vim == null) return null;
        final line = vim.commandLine;
        if (line != null) return (line, null);
        final after = [if (vim.pending.isNotEmpty) vim.pending, ?vim.message].join('  ');
        return (vim.mode.label, after.isEmpty ? null : after);
      case KeyboardMode.emacs:
        final badge = session.emacs?.badge;
        return badge == null ? null : (badge, null);
      case KeyboardMode.off:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = _words();
    if (words == null) return const SizedBox.shrink();
    final t = context.tokens;
    final (main, after) = words;
    final face = t.text('xs', mono: true, weight: 'medium', color: t.color('app-ink-2'));
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: after == null ? main : '$main, $after',
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.only(left: t.space(4), right: t.space(4), bottom: t.space(3) + MediaQuery.paddingOf(context).bottom),
            child: Align(
              alignment: Alignment.bottomLeft,
              heightFactor: 1,
              child: Container(
                key: KeymapBadgeKeys.badge,
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
                decoration: BoxDecoration(
                  color: t.color('app-paper-2'),
                  border: Border.all(color: t.color('app-rule')),
                  borderRadius: BorderRadius.circular(t.radius('full')),
                ),
                child: Text.rich(
                  key: KeymapBadgeKeys.words,
                  TextSpan(children: [
                    TextSpan(text: main),
                    if (after != null) TextSpan(text: '  $after', style: TextStyle(color: t.color('app-ink-3'))),
                  ]),
                  style: face,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
