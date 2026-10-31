/// Who is on a team's page, drawn (docs/TEAMSPACES.md, "Presence"): [PresenceAvatars] in the open note's header,
/// overlapping rounds in each member's colour with their initial, three and then +N, a press listing who; and
/// [PresenceDot] beside the page's row in the sidebar, a dot in the colour of the one there (a tiny stack of them
/// for several). [PresenceMarked] is the dot put after a row's name, drawing the name alone while nobody is there.
///
/// Each reads the [PagePresence] the root hands down in a [PagePresenceScope] (lib/team/presence.dart) and hears it
/// for itself, so a row or a header is drawn again only for its own page; with no scope (a build with no account,
/// signed out, a test that brings none) each draws nothing. Simple mode draws them too, as they are: there is
/// nothing to set (Matt, 2026-10-17: "simple mode has a much more approachable UI with fancy features hidden";
/// faces on a page are not a fancy feature).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../sheet/css.dart';
import '../shell/pop_menu.dart';
import 'presence.dart';

export 'presence.dart' show PagePresence, PresentMember;

/// The [PagePresence] for everything under it; null where there is none.
class PagePresenceScope extends InheritedWidget {
  const PagePresenceScope({super.key, required this.presence, required super.child});

  final PagePresence? presence;

  static PagePresence? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PagePresenceScope>()?.presence;

  @override
  bool updateShouldNotify(PagePresenceScope old) => !identical(old.presence, presence);
}

/// Who is on [noteId], heard for itself from the scope: [builder] given the members (none while nobody is there).
class _OnPage extends StatelessWidget {
  const _OnPage({required this.noteId, required this.members, required this.builder});

  final String noteId;
  final List<PresentMember>? members;
  final Widget Function(BuildContext context, List<PresentMember> members) builder;

  @override
  Widget build(BuildContext context) {
    final given = members;
    if (given != null) return builder(context, given);
    final presence = PagePresenceScope.maybeOf(context);
    if (presence == null) return builder(context, const []);
    return ValueListenableBuilder<Map<String, List<PresentMember>>>(
      valueListenable: presence,
      builder: (context, on, _) => builder(context, on[noteId] ?? const []),
    );
  }
}

/// Who is here, as said aloud and in the list: "ana and sam are here", "ana, sam and 2 others are here".
String presenceWords(List<PresentMember> members) {
  final names = [for (final member in members) member.name];
  if (names.isEmpty) return 'Nobody else is here';
  if (names.length == 1) return '${names.first} is here';
  if (names.length <= 3) return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last} are here';
  final rest = names.length - 2;
  return '${names.take(2).join(', ')} and $rest others are here';
}

/// The header's avatars: up to [most] overlapping rounds, then a +N round for the rest, each ringed in the paper so they read
/// apart; a press (or a press and hold) opens the list of who is here. Nothing at all while nobody is, and [end]
/// is the room it keeps after itself only while it draws.
class PresenceAvatars extends StatefulWidget {
  const PresenceAvatars({super.key, required this.noteId, this.members, this.most = 3, this.end = 0, this.coarse});

  final String noteId;

  /// Who to draw, where a test or a caller already has them; the scope's when null.
  final List<PresentMember>? members;
  final int most;
  final double end;

  /// Whether the list's rows are a finger's; the device's answer unless a test says.
  final bool? coarse;

  static const Key avatarsKey = ValueKey<String>('presence-avatars'), moreKey = ValueKey<String>('presence-more'), listKey = ValueKey<String>('presence-list');

  /// One member's round, by their id.
  static Key avatarKey(String id) => ValueKey<String>('presence-avatar:$id');

  /// One member's line in the list, by their id.
  static Key lineKey(String id) => ValueKey<String>('presence-line:$id');

  @override
  State<PresenceAvatars> createState() => _PresenceAvatarsState();
}

class _PresenceAvatarsState extends State<PresenceAvatars> {
  final GlobalKey _anchor = GlobalKey(debugLabel: 'presence avatars');
  bool _open = false;

  @override
  Widget build(BuildContext context) => _OnPage(noteId: widget.noteId, members: widget.members, builder: _build);

  Widget _build(BuildContext context, List<PresentMember> members) {
    if (members.isEmpty) {
      if (_open) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => _open = false) : null);
      return const SizedBox.shrink();
    }
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    final side = (ring * 0.72).roundToDouble();
    final step = (side * 0.68).roundToDouble();
    final shown = members.take(widget.most).toList();
    final more = members.length - shown.length;
    final rounds = <Widget>[
      for (final member in shown) _Round(key: PresenceAvatars.avatarKey(member.id), hue: member.hue, side: side, words: member.initial),
      if (more > 0) _Round(key: PresenceAvatars.moreKey, hue: null, side: side, words: '+$more', quiet: true),
    ];
    final said = presenceWords(members);
    void toggle() => setState(() => _open = !_open);
    final stack = GlacierPressable(
      key: PresenceAvatars.avatarsKey,
      onPressed: toggle,
      onLongPress: toggle,
      semanticLabel: said,
      toggled: _open,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('full'),
        child: SizedBox(
          key: _anchor,
          height: ring,
          width: side + step * (rounds.length - 1),
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              // The first on top, as a face stack reads: the later ones tuck under the one before.
              for (final (i, round) in rounds.indexed.toList().reversed) PositionedDirectional(start: step * i, child: round),
            ],
          ),
        ),
      ),
    );
    final drawn = widget.end > 0 ? Padding(padding: EdgeInsetsDirectional.only(end: widget.end), child: stack) : stack;
    if (!_open) return drawn;
    void close() => setState(() => _open = false);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        drawn,
        PopMenu(
          key: PresenceAvatars.listKey,
          anchor: GlacierAnchor.key(_anchor),
          placement: Placement.bottomEnd,
          reach: PopReach.down,
          ariaLabel: 'Who is here',
          coarse: widget.coarse,
          onDismiss: close,
          children: [
            // A sentence, not a heading: the kit sets a Text label in capitals, and this one is said as it is.
            GlacierMenuLabel(child: Builder(builder: (context) => Text(members.length == 1 ? 'Here now' : '${members.length} here now'))),
            for (final member in members)
              GlacierMenuLabel(
                child: Builder(
                  builder: (context) => Row(
                    key: PresenceAvatars.lineKey(member.id),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Round(hue: member.hue, side: context.tokens.fontSize('md') * 1.3, words: member.initial, ring: false),
                      SizedBox(width: context.tokens.space(2)),
                      Text(member.name),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One round: the member's colour as a wash on the paper with their initial in the colour itself, as their line
/// on the organization's page draws it (`_MemberLine`); ink for one with no colour, and the quiet ink for +N.
class _Round extends StatelessWidget {
  const _Round({super.key, required this.hue, required this.side, required this.words, this.quiet = false, this.ring = true});

  final String? hue;
  final double side;
  final String words;
  final bool quiet;
  final bool ring;

  @override
  Widget build(BuildContext context) => GlacierScope(
        attrs: {'hue': hue ?? 'ink'},
        child: Builder(
          builder: (context) {
            final here = context.tokens;
            final hued = hue != null && !quiet;
            final ink = quiet ? here.color('app-ink-2') : (hued ? here.colorOf('var(--app-space, var(--app-ink))') : here.color('app-ink'));
            return Container(
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Opaque, so a round tucked under the one before does not show through it.
                color: hued ? here.colorOf('color-mix(in oklch, var(--app-space) 22%, var(--app-paper))') : here.colorOf('color-mix(in oklch, var(--app-ink) 8%, var(--app-paper))'),
                border: ring ? Border.all(color: here.color('app-paper'), width: 1.5) : null,
              ),
              child: ExcludeSemantics(
                child: Text(words, maxLines: 1, softWrap: false, style: pageText(here, (side * (words.length > 2 ? 0.36 : 0.44)).roundToDouble(), weight: 'semibold', color: ink, height: 1)),
              ),
            );
          },
        ),
      );
}

/// The sidebar's mark of a page someone else has open: one dot in their colour, or for several a tiny stack of
/// up to three; nothing while nobody is there. Said aloud as who is here.
class PresenceDot extends StatelessWidget {
  const PresenceDot({super.key, required this.noteId, this.members, this.size = 7});

  final String noteId;

  /// Who is there, where a caller already has them; the scope's when null.
  final List<PresentMember>? members;
  final double size;

  static Key keyOf(String noteId) => ValueKey<String>('presence-dot:$noteId');

  @override
  Widget build(BuildContext context) => _OnPage(noteId: noteId, members: members, builder: (context, on) => on.isEmpty ? const SizedBox.shrink() : dotFor(context, on));

  /// The dot or the stack for [on], who are there.
  Widget dotFor(BuildContext context, List<PresentMember> on) {
    final shown = on.take(3).toList();
    final step = size * 0.6;
    final paper = context.tokens.color('app-paper');
    Widget dot(PresentMember member) => GlacierScope(
          attrs: {'hue': member.hue ?? 'ink'},
          child: Builder(
            builder: (context) => Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.tokens.colorOf('var(--app-space, var(--app-ink))'),
                border: shown.length > 1 ? Border.all(color: paper, width: 1) : null,
              ),
            ),
          ),
        );
    return Semantics(
      key: keyOf(noteId),
      label: presenceWords(on),
      child: SizedBox(
        width: size + step * (shown.length - 1),
        height: size,
        child: Stack(
          children: [
            for (final (i, member) in shown.indexed.toList().reversed) PositionedDirectional(start: step * i, top: 0, child: dot(member)),
          ],
        ),
      ),
    );
  }
}

/// A sidebar row's name with the [PresenceDot] after it while someone else has the page open: the name alone, as
/// it was, the rest of the time.
class PresenceMarked extends StatelessWidget {
  const PresenceMarked({super.key, required this.noteId, required this.child});

  final String noteId;
  final Widget child;

  @override
  Widget build(BuildContext context) => _OnPage(
        noteId: noteId,
        members: null,
        // Always the row, the name its first child, so the name keeps itself (its sync mark's state) as the dot comes
        // and goes.
        builder: (context, on) => Row(
          children: [
            Flexible(fit: FlexFit.tight, child: child),
            if (on.isNotEmpty) ...[
              SizedBox(width: context.tokens.space(2)),
              PresenceDot(noteId: noteId, members: on),
            ],
          ],
        ),
      );
}
