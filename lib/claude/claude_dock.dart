/// Claude on the home page's dock (docs/CLAUDE_APP.md, "Claude on the dock"). Matt: "move the Claude chip to a icon
/// on the home page dock and make it match claudes brand colors".
///
/// A ring the size of the dock's others, filled in Claude's orange with its mark in ivory. It opens the Ask Claude
/// sheet, where the chip's menu now lives (what each AI online is doing, Follow, Open). While Claude works in the
/// app its mark turns slowly; while an AI is online through the connector (lib/live/follow.dart [FollowAi.ais]) a
/// small ivory dot sits on the ring's shoulder, as the chip's live dot did.
///
/// Under it, where the build can hear, Talk to Claude ([ClaudeTalkButton]): the same orange on the dock's plain ring.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../home/home_icons.dart' show HomeGlyph, HomeIcon;
import '../live/follow.dart';
import 'claude_mark.dart';
import 'claude_runner.dart';

class ClaudeDockButton extends StatefulWidget {
  const ClaudeDockButton({super.key, required this.runner, this.follow, required this.onPressed});

  final ClaudeRunner runner;

  /// The connector's AIs online, where the build has an account.
  final FollowAi? follow;
  final VoidCallback onPressed;

  @override
  State<ClaudeDockButton> createState() => _ClaudeDockButtonState();
}

class _ClaudeDockButtonState extends State<ClaudeDockButton> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    widget.runner.addListener(_changed);
    widget.follow?.addListener(_changed);
  }

  /// The first look, once the inherited widgets (reduced motion) can be read.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _changed();
  }

  @override
  void didUpdateWidget(ClaudeDockButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.runner, widget.runner)) {
      old.runner.removeListener(_changed);
      widget.runner.addListener(_changed);
    }
    if (!identical(old.follow, widget.follow)) {
      old.follow?.removeListener(_changed);
      widget.follow?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.runner.removeListener(_changed);
    widget.follow?.removeListener(_changed);
    _turn.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final working = widget.runner.working;
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (working && !still && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!working && _turn.isAnimating) {
      _turn.stop();
      _turn.animateTo(_turn.value < 0.5 ? 0 : 1, duration: const Duration(milliseconds: 400), curve: Curves.easeOut).whenComplete(() {
        if (mounted && !widget.runner.working) _turn.value = 0;
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    final working = widget.runner.working;
    final online = widget.follow?.ais ?? const [];
    final at = widget.runner.run?.at;
    final label = working
        ? 'Claude is ${at == null ? 'working' : '${at.doing} ${at.title.isEmpty ? 'a note' : at.title}'}. Open Ask Claude.'
        : online.isNotEmpty
            ? '${online.map((ai) => '${ai.name} is ${ai.words}').join(', ')}. Ask Claude.'
            : 'Ask Claude';
    return GlacierPressable(
      key: const ValueKey('dock-claude'),
      onPressed: widget.onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        offset: 3,
        color: claudeOrange,
        child: AnimatedScale(
          scale: state.pressed ? 0.94 : 1,
          duration: t.duration('glacier-duration-fast'),
          curve: t.curve('glacier-ease-out'),
          child: SizedBox(
            width: ring,
            height: ring,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.hovered ? Color.lerp(claudeOrange, claudeSlate, 0.08) : claudeOrange,
                      boxShadow: working ? [BoxShadow(color: claudeOrange.withValues(alpha: 0.45), blurRadius: 14)] : null,
                    ),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _turn,
                        builder: (context, _) => ClaudeMark(size: 0.5 * ring, color: claudeIvory, turns: _turn.value),
                      ),
                    ),
                  ),
                ),
                if (online.isNotEmpty && !working)
                  Positioned(
                    key: const ValueKey('dock-claude-online'),
                    right: 1,
                    top: 1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: claudeIvory, border: Border.all(color: claudeOrange, width: 2)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Talk to Claude, on the dock under Claude's own ring (lib/claude/claude_voice.dart). Matt, 2026-10-17: "add a
/// microphone icon to the dock bar". A ring the size of the dock's others, the plain kind, its rim and its mic in
/// Claude's orange: Claude's, as the filled orange ring above it is, and plainly not Speak, the ink-filled mic that
/// records a voice note. A press opens the ear; nothing listens before it.
class ClaudeTalkButton extends StatelessWidget {
  const ClaudeTalkButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    return GlacierPressable(
      key: const ValueKey('dock-claude-talk'),
      onPressed: onPressed,
      semanticLabel: 'Talk to Claude',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        offset: 3,
        color: claudeOrange,
        child: AnimatedScale(
          scale: state.pressed ? 0.94 : 1,
          duration: t.duration('glacier-duration-fast'),
          curve: t.curve('glacier-ease-out'),
          child: Container(
            width: ring,
            height: ring,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.hovered ? Color.lerp(t.color('glacier-bg'), claudeOrange, 0.08) : t.color('glacier-bg'),
              border: Border.all(color: claudeOrange, width: t.len('app-line')),
            ),
            child: HomeIcon(HomeGlyph.mic, size: t.lenOf('1.15rem'), strokeWidth: 2.2, color: claudeOrange),
          ),
        ),
      ),
    );
  }
}
