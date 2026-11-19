/// A circle drawn as its list, the one way a circle is drawn (Matt, 2026-11-17: "Lets remove the other views and focus
/// on the list view / layout it's the most practical of them all so far"): its face, name and who is on at the top,
/// then its spaces under their headings, each with its kind's mark in the kind's colour, a line of what is going on in
/// it (who is talking, how many files, the newest message), its unread count, and New space at the foot.
///
/// It is the circle's sidebar on a computer and an unfolded Fold, and the whole page on a phone, where a space opens
/// over it ([CircleView.wide] says which). It draws in every look (lib/looks.dart), Dial-Up's bevels among them, light
/// and dark, through the app's tokens.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../kit/semantic_colors.dart';
import '../../kit/settings_type.dart';
import '../../voice/voice.dart';
import '../common.dart';
import '../dialup/bevel.dart';
import '../shell.dart';
import 'circle_face.dart';
import 'circle_view.dart';

/// [view] as the circle's page: [CirclePage] round its [CircleSpaceList].
class CircleList extends StatelessWidget {
  const CircleList({super.key, required this.view});
  final CircleView view;

  @override
  Widget build(BuildContext context) => CirclePage(view: view, body: CircleSpaceList(view: view));
}

/// A circle's page: the way back, its face and name (a press opens its menu), Invite and its settings, and [body]
/// under them. Dial-Up's
/// window draws its own title bar from it.
class CirclePage extends StatelessWidget {
  const CirclePage({super.key, required this.view, required this.body});
  final CircleView view;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = view.circle;
    final live = view.live.fold(0, (n, s) => n + s.inVoice.length);
    final line = [
      '${view.spaces.length} ${view.spaces.length == 1 ? 'space' : 'spaces'}',
      if (view.online > 0) '${view.online} on now',
      if (live > 0) '$live talking',
    ].join(' · ');
    return GhostPage(
      title: c.name,
      subtitle: line,
      onTitle: view.onMenu,
      onBack: view.onBack,
      titleLeading: TitleBarMark(icon: circleIconOf(c.icon), child: CircleFace.of(c, size: 18)),
      titleWidget: GlacierPressable(
        onPressed: view.onMenu,
        semanticLabel: '${c.name}, $line, options',
        builder: (context, _) => Row(children: [
          CircleFace.of(c, size: 32),
          SizedBox(width: t.space(2) + 2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'bold'))),
                AppIcon(Lucide.chevronDown, size: 16, color: t.color('app-ink-2')),
              ]),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ]),
          ),
        ]),
      ),
      // Nothing beside the name: the circle's settings are the dock's, and adding people is the Members drawer's (Matt,
      // 2026-11-18: "remove the add user from the header next to the circle header and in the dock and simply leave it
      // under the users drawer").
      body: body,
    );
  }
}

/// A circle's spaces under their headings, with New space at the foot where this device may add one.
class CircleSpaceList extends StatelessWidget {
  const CircleSpaceList({super.key, required this.view});
  final CircleView view;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bevel = isBevelChrome(t);
    // Under Dial-Up the well ends above the taskbar, so the list needs no room of its own for it.
    final foot = AppShell.pillRoom(context) + MediaQuery.paddingOf(context).bottom;
    final list = ListView(
      padding: EdgeInsets.only(top: t.space(2), bottom: bevel ? t.space(2) : foot + t.space(4)),
      children: [
        for (final g in view.sections) ...[
          if (g.name != null) CircleSectionHeading(name: g.name!, onAdd: view.canEdit ? () => view.onNewSpace(section: g.name) : null),
          for (final s in g.spaces) CircleSpaceTile(space: s, selected: s.seed == view.selected, onPress: () => view.onOpen(s), onLongPress: view.onSpaceMenu == null ? null : () => view.onSpaceMenu!(s)),
        ],
        if (view.spaces.isEmpty)
          Padding(
            padding: EdgeInsets.all(t.space(6)),
            child: Text(view.canEdit ? 'No spaces yet. Add one for chat and voice, texting or files.' : 'No spaces yet.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ),
        if (view.canEdit) _NewSpaceRow(onPress: () => view.onNewSpace()),
      ],
    );
    // Dial-Up: the list in the window's white well, sunk into the silver as the Chat List's is (conversations.dart),
    // with its bevel and a margin of silver round it. It was a flat white fill to the window's edges, so a circle in
    // the list's place had no well border (Matt, 2026-11-18: "the sidebar in circles on the dial up theme is missing
    // the border bevel").
    if (!bevel) return list;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(1), t.space(1), t.space(1), t.space(1) + foot),
      child: Sunken(child: list),
    );
  }
}

/// New space, muted, at the foot of the list: lined up with the spaces' marks above it.
class _NewSpaceRow extends StatelessWidget {
  const _NewSpaceRow({required this.onPress});
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bevel = isBevelChrome(t);
    return GlacierPressable(
      key: const ValueKey('circle-new-space'),
      onPressed: onPress,
      semanticLabel: 'New space',
      builder: (context, state) => Container(
        margin: bevel ? EdgeInsets.only(top: t.space(1)) : EdgeInsets.fromLTRB(t.space(2), t.space(1), t.space(2), 0),
        padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: bevel ? t.space(2) : t.space(3)),
        decoration: BoxDecoration(
          color: !bevel && (state.pressed || state.hovered) ? t.color('app-paper-2') : null,
          borderRadius: bevel ? null : BorderRadius.circular(t.radius('md')),
        ),
        child: Row(children: [
          // As large as a space's mark beside it (CircleSpaceTile).
          Container(
            width: bevel ? 28 : t.lenOf('2.1rem'),
            height: bevel ? 28 : t.lenOf('2.1rem'),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: bevel ? DialupColors.of(t).shadow : t.color('app-rule'), width: 1),
              borderRadius: BorderRadius.circular(bevel ? 0 : t.lenOf('2.1rem') * 0.32),
            ),
            child: AppIcon(Lucide.plus, size: bevel ? 16 : t.lenOf('2.1rem') * 0.5, color: t.color('app-ink-3')),
          ),
          SizedBox(width: t.space(3) + 2),
          Text('New space', style: pageText(t, t.fontSize('lg'), color: t.color('app-ink-3'))),
        ]),
      ),
    );
  }
}

/// A heading of a circle's list, with a + where this device may add a space under it.
class CircleSectionHeading extends StatelessWidget {
  const CircleSectionHeading({super.key, required this.name, this.onAdd});
  final String name;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(4), t.space(4), t.space(2), t.space(1)),
      child: Row(children: [
        Expanded(child: Text(name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'bold', color: t.color('app-ink-3'), tracking: 0.6))),
        if (onAdd != null) IconTap(icon: Lucide.plus, label: 'New space in $name', size: 16, onPressed: onAdd!),
      ]),
    );
  }
}

/// What a space's row says under its name: who is talking in a call (green), how many files a Files space holds, or
/// the newest message; null where there is nothing to say.
String? circleSpaceLine(CircleSpaceView s) {
  if (s.live) {
    final names = s.inVoice.take(3).join(', ');
    return s.inVoice.length == 1 ? '$names is talking' : '${s.inVoice.length} talking · $names';
  }
  if (s.kind == SpaceKind.files && s.files != null && (s.lastMessage == null || s.unread == 0)) return s.files == 0 ? 'No files yet' : '${s.files} ${s.files == 1 ? 'file' : 'files'}';
  return s.lastMessage;
}

/// A space's row: its kind's mark in the kind's colour, its name (bold while unread), what is going on in it, then
/// its unread count or how many are talking.
class CircleSpaceTile extends StatelessWidget {
  const CircleSpaceTile({super.key, required this.space, required this.onPress, this.onLongPress, this.selected = false});
  final CircleSpaceView space;
  final VoidCallback onPress;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bevel = isBevelChrome(t);
    final d = bevel ? DialupColors.of(t) : null;
    final highlit = d != null && selected;
    final bold = space.unread > 0 || selected;
    final ink = highlit ? d.onHighlight : t.color(bold ? 'app-ink' : 'app-ink-2');
    final sub = circleSpaceLine(space);
    // The kind's mark as large as the one by a space's name in its header (hangout_screen.dart), 2.1rem (Matt,
    // 2026-11-19: "make the circles spaces in the sidebar a tad bit smaller to match the icon size of the header icon
    // for a space"); Dial-Up's as small as its rows.
    final mark = bevel ? 28.0 : t.lenOf('2.1rem');
    return GlacierPressable(
      key: ValueKey('circle-space-${space.seed}'),
      onPressed: onPress,
      onLongPress: onLongPress,
      semanticLabel: [space.name, spaceKindTitle(space.kind), if (space.unread > 0) '${space.unread} unread', ?sub].join(', '),
      builder: (context, state) => Container(
        // A size nearer the conversations' rows (Matt, 2026-11-18: "The spaces should be a bit larger in the sidebar they
        // feel small compared to the rest of the app"): a larger mark, name and line, and more room round them.
        margin: bevel ? EdgeInsets.zero : EdgeInsets.symmetric(horizontal: t.space(2), vertical: 2),
        padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: bevel ? t.space(2) : t.space(3)),
        decoration: BoxDecoration(
          color: d != null ? (selected ? d.highlight : null) : (selected ? t.color('app-paper-3') : (state.pressed || state.hovered ? t.color('app-paper-2') : null)),
          borderRadius: bevel ? null : BorderRadius.circular(t.radius('md')),
        ),
        child: Row(children: [
          // Dial-Up's chosen row is its navy highlight: the mark in the highlight's own ink, where its hue would sink.
          if (highlit) SizedBox.square(dimension: mark, child: Center(child: AppIcon(space.icon, size: mark * 0.56, color: d.onHighlight, wash: false))) else SpaceKindBadge(kind: space.kind, live: space.live, size: mark),
          SizedBox(width: t.space(3) + 2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(space.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: bold ? 'semibold' : 'medium', color: ink)),
              if (sub != null && sub.isNotEmpty)
                Row(children: [
                  if (space.live) ...[
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: highlit ? d.onHighlight : t.online, shape: bevel ? BoxShape.rectangle : BoxShape.circle)),
                    SizedBox(width: t.space(1) + 2),
                  ],
                  Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: space.unread > 0 && !space.live ? 'medium' : 'regular', color: highlit ? d.onHighlight : (space.live ? t.online : t.color(space.unread > 0 ? 'app-ink-2' : 'app-ink-3'))))),
                ]),
            ]),
          ),
          if (space.unread > 0) ...[
            SizedBox(width: t.space(2)),
            UnreadBadge(count: space.unread, mentioned: space.mentions > 0, color: highlit ? d.onHighlight : t.color('app-accent'), ink: highlit ? d.highlight : t.color('app-on-accent'), square: bevel),
          ] else if (space.live) ...[
            SizedBox(width: t.space(2)),
            AppIcon(spaceKindIcon(SpaceKind.voice), size: 14, color: highlit ? d.onHighlight : t.online, wash: false),
            SizedBox(width: t.space(1)),
            Text('${space.inVoice.length}', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: highlit ? d.onHighlight : t.online)),
          ],
        ]),
      ),
    );
  }
}
