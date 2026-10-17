/// Claude in the app's top bar, and the bar that says it is being followed (docs/CLAUDE_LIVE.md, "What a person
/// sees", 1 and 3).
///
/// [AiChip] is drawn in the bar while an AI is online on the account, in an organization's room or the account's
/// own (lib/live/presence.dart `aisOnline`): the AI's name with a small live dot in its colour. A tap opens a small
/// menu: what it is doing, Follow (or Stop following), and Open the note it is on. [FollowBar] is the slim bar
/// under the top bar while one is followed: "Following Claude", and Stop.
///
/// Both hear [FollowAi] (lib/live/follow.dart) for themselves, so the shell hands them over once. The web app has
/// neither yet: they are the app's own.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../live/follow.dart';
import '../live/presence.dart';
import '../sheet/css.dart';
import 'pop_menu.dart';

/// The top bar's Claude chip, or nothing while no AI is online.
class AiChip extends StatefulWidget {
  const AiChip({super.key, required this.follow, required this.onOpen, this.coarse});

  final FollowAi follow;

  /// Opens the note an AI is on, at its caret: the menu's Open.
  final void Function(AiOnline ai) onOpen;

  /// Whether the menu's rows are a finger's; the device's answer unless a test says.
  final bool? coarse;

  /// Whether there is a chip to draw: an AI online.
  static bool shows(FollowAi follow) => follow.ais.isNotEmpty;

  @override
  State<AiChip> createState() => _AiChipState();
}

class _AiChipState extends State<AiChip> {
  final GlobalKey _anchor = GlobalKey(debugLabel: 'AI chip');
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.follow.addListener(_changed);
  }

  @override
  void didUpdateWidget(AiChip old) {
    super.didUpdateWidget(old);
    if (!identical(old.follow, widget.follow)) {
      old.follow.removeListener(_changed);
      widget.follow.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.follow.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (widget.follow.ais.isEmpty) _open = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final follow = widget.follow;
    final ais = follow.ais;
    if (ais.isEmpty) return const SizedBox.shrink();
    // The one followed, else the first by name; "+1" for each other.
    final lead = follow.following ?? ais.first;
    final more = ais.length - 1;
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final ring = t.len('app-bar-ring');
    final hair = t.len('glacier-hairline');
    final said = [for (final ai in ais) '${ai.name} is ${ai.words}'].join(', ');
    final chip = Semantics(
      expanded: _open,
      child: GlacierPressable(
        key: const ValueKey('ai-chip'),
        onPressed: () => setState(() => _open = !_open),
        semanticLabel: '$said. ${follow.isFollowing ? 'Following ${lead.name}.' : ''}'.trim(),
        builder: (context, state) => GlacierScope(
          attrs: {'hue': lead.hue ?? 'ink'},
          child: Builder(
            builder: (context) {
              final here = context.tokens;
              final space = here.colorOf('var(--app-space, var(--app-ink))');
              final lit = state.hovered || state.pressed || _open;
              return GlacierFocusRing(
                visible: state.focused,
                radius: here.radius('full'),
                child: Container(
                  key: _anchor,
                  height: ring,
                  padding: EdgeInsets.symmetric(horizontal: here.space(2) + 2),
                  decoration: ShapeDecoration(
                    color: here.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) ${lit ? 16 : 8}%, transparent)'),
                    shape: StadiumBorder(side: BorderSide(color: here.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) 40%, transparent)'), width: hair)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The live dot, ringed in the paper as a member's is on their initial.
                      Container(
                        key: const ValueKey('ai-chip-dot'),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: space),
                      ),
                      SizedBox(width: here.space(2) - 2),
                      Text(more > 0 ? '${lead.name} +$more' : lead.name, softWrap: false, style: pageText(here, sm, weight: 'medium', color: here.color('app-ink'))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    if (!_open) return chip;
    void close() => setState(() => _open = false);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        chip,
        PopMenu(
          anchor: GlacierAnchor.key(_anchor),
          placement: Placement.bottomEnd,
          reach: PopReach.down,
          ariaLabel: 'Claude',
          coarse: widget.coarse,
          onDismiss: close,
          children: [
            for (final (i, ai) in ais.indexed) ...[
              if (i > 0) const GlacierMenuSeparator(),
              // A sentence, not a heading: the kit sets a Text label in capitals, and this one is said as it is.
              GlacierMenuLabel(child: Builder(builder: (context) => Text('${ai.name} is ${ai.words}', key: ValueKey('ai-menu-doing:${ai.key}')))),
              if (follow.following?.key == ai.key)
                GlacierMenuItem(key: ValueKey('ai-menu-stop:${ai.key}'), onSelect: follow.stop, child: Text('Stop following ${ai.name}'))
              else
                GlacierMenuItem(key: ValueKey('ai-menu-follow:${ai.key}'), onSelect: () => follow.follow(ai), child: Text('Follow ${ai.name}')),
              if (ai.at != null)
                GlacierMenuItem(
                  key: ValueKey('ai-menu-open:${ai.key}'),
                  onSelect: () => widget.onOpen(ai),
                  child: Text('Open ${ai.at!.title.isEmpty ? (ai.at!.kind == 'canvas' ? 'the canvas' : 'the note') : ai.at!.title}'),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The slim bar while an AI is followed: "Following Claude", and Stop. Nothing while none is.
class FollowBar extends StatelessWidget {
  const FollowBar({super.key, required this.follow});

  final FollowAi follow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: follow,
      builder: (context, _) {
        final ai = follow.following;
        if (ai == null) return const SizedBox.shrink();
        final t = context.tokens;
        final sm = t.fontSize('sm');
        final hair = t.len('glacier-hairline');
        return GlacierScope(
          attrs: {'hue': ai.hue ?? 'ink'},
          child: Builder(
            builder: (context) {
              final here = context.tokens;
              final space = here.colorOf('var(--app-space, var(--app-ink))');
              return Semantics(
                container: true,
                liveRegion: true,
                label: 'Following ${ai.name}',
                explicitChildNodes: true,
                child: Container(
                  key: const ValueKey('follow-bar'),
                  padding: EdgeInsets.symmetric(horizontal: here.space(4), vertical: here.space(1) + 1),
                  decoration: BoxDecoration(
                    // Opaque: the bar stands over the note's first lines.
                    color: here.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) 12%, var(--app-paper))'),
                    border: Border(bottom: BorderSide(color: here.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) 35%, transparent)'), width: hair)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: space)),
                      SizedBox(width: here.space(2)),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            ai.at == null ? 'Following ${ai.name}' : 'Following ${ai.name} · ${ai.words}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: pageText(here, sm, weight: 'medium', color: here.color('app-ink')),
                          ),
                        ),
                      ),
                      SizedBox(width: here.space(2)),
                      GlacierPressable(
                        key: const ValueKey('follow-stop'),
                        onPressed: follow.stop,
                        semanticLabel: 'Stop following ${ai.name}',
                        builder: (context, state) => GlacierFocusRing(
                          visible: state.focused,
                          radius: here.radius('full'),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 0.2 * sm, horizontal: 0.8 * sm),
                            decoration: ShapeDecoration(
                              color: state.hovered || state.pressed ? here.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) 14%, transparent)') : null,
                              shape: StadiumBorder(side: BorderSide(color: space, width: hair)),
                            ),
                            child: ExcludeSemantics(child: Text('Stop', style: pageText(here, sm, weight: 'medium', color: space))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
