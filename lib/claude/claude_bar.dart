/// The bar under the top bar while the app's own Claude works (docs/CLAUDE_APP.md, "Following along"): Claude's
/// mark, what it is doing and where, the words it is saying as it says them, and Stop following and Stop. When the
/// run ends it says Claude's answer in a line, with Reply (the sheet) and a close; the next ask takes its place.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../sheet/css.dart';
import 'claude_mark.dart';
import 'store_neutral.dart';
import 'claude_run.dart';
import 'claude_runner.dart';

class ClaudeBar extends StatefulWidget {
  const ClaudeBar({super.key, required this.runner, required this.onReply, required this.onOpenNote});

  final ClaudeRunner runner;

  /// The Ask Claude sheet.
  final VoidCallback onReply;
  final void Function(String noteId) onOpenNote;

  @override
  State<ClaudeBar> createState() => _ClaudeBarState();
}

class _ClaudeBarState extends State<ClaudeBar> {
  /// The run whose ending was closed: nothing is said of it again.
  ClaudeRun? _closed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.runner,
      builder: (context, _) {
        final run = widget.runner.run;
        if (run == null || run.state == ClaudeState.idle || identical(run, _closed)) return const SizedBox.shrink();
        final t = context.tokens;
        final sm = t.fontSize('sm');
        final hair = t.len('glacier-hairline');
        final at = run.at;
        final String words;
        if (run.working) {
          final saying = run.saying.trim().replaceAll('\n', ' ');
          if (saying.isNotEmpty) {
            words = saying.length > 140 ? '…${saying.substring(saying.length - 139)}' : saying;
          } else if (at != null) {
            words = neutral('Claude is ${at.doing} ${at.title.isEmpty ? 'a note' : at.title}');
          } else {
            words = neutral('Claude is thinking');
          }
        } else {
          words = switch (run.state) {
            ClaudeState.failed => run.problem ?? 'Claude stopped with an error.',
            ClaudeState.stopped => 'Stopped.',
            _ => run.answer.isEmpty ? 'Done.' : run.answer.split('\n').firstWhere((line) => line.trim().isNotEmpty, orElse: () => 'Done.'),
          };
        }
        Widget button(String key, String label, VoidCallback onPress) => GlacierPressable(
              key: ValueKey(key),
              onPressed: onPress,
              semanticLabel: label,
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                radius: t.radius('full'),
                child: Container(
                  margin: EdgeInsets.only(left: t.space(2)),
                  padding: EdgeInsets.symmetric(vertical: 0.2 * sm, horizontal: 0.8 * sm),
                  decoration: ShapeDecoration(
                    color: state.hovered || state.pressed ? claudeOrange.withValues(alpha: 0.14) : null,
                    shape: StadiumBorder(side: BorderSide(color: claudeOrange, width: hair)),
                  ),
                  child: ExcludeSemantics(child: Text(label, style: pageText(t, sm, weight: 'medium', color: claudeOrange))),
                ),
              ),
            );
        return Semantics(
          container: true,
          liveRegion: true,
          label: words,
          explicitChildNodes: true,
          child: Container(
            key: const ValueKey('claude-bar'),
            padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(1) + 1),
            decoration: BoxDecoration(
              // Opaque: the bar stands over the note's first lines.
              color: Color.alphaBlend(claudeOrange.withValues(alpha: 0.10), t.color('app-paper')),
              border: Border(bottom: BorderSide(color: claudeOrange.withValues(alpha: 0.35), width: hair)),
            ),
            child: Row(
              children: [
                const ClaudeMark(size: 14),
                SizedBox(width: t.space(2)),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onReply,
                    child: ExcludeSemantics(
                      child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink'))),
                    ),
                  ),
                ),
                if (run.working && at != null && run.following) button('claude-bar-unfollow', 'Stop following', run.stopFollowing),
                if (run.working && at != null && !run.following)
                  // The note opened, Claude's caret shown where it last typed and the page scrolled there.
                  button('claude-bar-watch', 'Watch', run.follow),
                if (run.working) button('claude-bar-stop', 'Stop', run.stop),
                if (!run.working) button('claude-bar-reply', 'Reply', widget.onReply),
                if (!run.working) button('claude-bar-close', 'Close', () => setState(() => _closed = run)),
              ],
            ),
          ),
        );
      },
    );
  }
}
