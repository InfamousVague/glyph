/// The header toolbar's kit (lib/shell/header_toolbar.dart): a control's press with the old bar's labels and the card
/// it toggles, a hint under it for a mouse, a glyph drawn in a style of the line's own but the pack that was chosen,
/// the bell's dot, a count, and a menu hung from the bar.
///
/// Iconography stays the app's own: every glyph is an [AppIcon] (or the app's house), so the pack chosen in
/// Settings › Appearance is the pack the line draws in; the line varies only the style ([styled]: outline, solid,
/// filled), the stroke, and the ground under the glyph. No icon is added.
///
/// The hint is new to the bar: the old bar's rings had none (the page's `title` had no counterpart here). Under a mouse
/// a control's own words show under it after a moment's rest; a finger has the screen reader's label alone, as
/// before. A hint is never read out: the label already is.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/icon_packs.dart';
import '../../art/icons.dart' show HouseIcon;
import '../../art/lucide.g.dart';
import '../../core/workspaces.dart' show OrgLike;
import '../../market/market_items.dart' show marketHues;
import '../../notes/floating_card.dart' show FloatingCardToggle, cardOpenedFrom;
import '../../note/note_tools.dart' show NoteMenuGroup, NoteMenuItem;
import '../../notes/tabs/bar_parts.dart' show HueDot;
import '../header_toolbar.dart';
import '../pop_menu.dart';

/// [child] with its icons drawn in [style], in whichever pack is chosen.
Widget styled(BuildContext context, IconStyle style, Widget child) => IconLookScope(look: IconLook(IconLook.of(context).pack, style), child: child);

/// A hue's two shades: the deeper the light page wears, the brighter the dark one's.
(Color, Color) hueShades(String hue) => marketHues[hue] ?? marketHues['indigo']!;

/// A hue as ink on the page: its deep shade on paper, its bright one in the dark.
Color hueInk(Tokens t, String hue) {
  final (deep, bright) = hueShades(hue);
  return t.isDark ? bright : deep;
}

/// The glyph of [act], at [size], in [color].
class HeaderGlyph extends StatelessWidget {
  const HeaderGlyph(this.act, {super.key, required this.size, required this.color, this.strokeWidth = 2.1, this.wash = true});

  final HeaderAct act;
  final double size;
  final Color color;
  final double strokeWidth;
  final bool wash;

  @override
  Widget build(BuildContext context) {
    final icon = act.icon;
    Widget glyph = act.house || icon == null ? HouseIcon(size: size, strokeWidth: strokeWidth, color: color) : AppIcon(icon, size: size, strokeWidth: strokeWidth, color: color, wash: wash);
    if (act.mirrored) glyph = Transform.flip(flipX: true, child: glyph);
    return glyph;
  }
}

/// One control of the line's row: the press, the old bar's label and states for a screen reader, the floating card it
/// toggles, the hint for a mouse, and the key it is found by (`header:<id>`). [face] draws it for the press's
/// state; with nothing to do it is drawn at 30%, as the old bar's dead rings were.
class HeaderPress extends StatelessWidget {
  const HeaderPress({super.key, required this.act, required this.fine, required this.face, this.onPressed, this.expanded, this.anchorKey, this.radius = 8});

  final HeaderAct act;
  final bool fine;
  final Widget Function(BuildContext context, PressState state) face;

  /// In place of [HeaderAct.onPress]: a menu's trigger.
  final VoidCallback? onPressed;
  final bool? expanded;

  /// A key on the face's own box, for a menu to hang from.
  final Key? anchorKey;

  /// The focus ring's round.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final press = onPressed ?? act.onPress;
    Widget control = Semantics(
      expanded: expanded ?? act.expanded,
      selected: act.current ? true : null,
      child: GlacierPressable(
        // A card this opens hangs under this control (lib/notes/floating_card.dart `cardOpenedFrom`).
        onPressed: press == null
            ? null
            : () {
                cardOpenedFrom(context);
                press();
              },
        semanticLabel: act.label,
        toggled: act.toggled,
        pressScale: null,
        builder: (context, state) {
          Widget drawn = KeyedSubtree(key: anchorKey, child: face(context, state));
          if (state.disabled) drawn = Opacity(opacity: 0.3, child: drawn);
          return GlacierFocusRing(visible: state.focused, radius: radius, child: drawn);
        },
      ),
    );
    if (act.toggle case final toggle?) control = FloatingCardToggle(toggle: toggle, child: control);
    return KeyedSubtree(key: act.key, child: HeaderHint(message: act.word.replaceAll('…', ''), enabled: fine, child: control));
  }
}

/// A control's words under it, for a mouse that rests on it: drawn over everything, never read out, gone at a press.
class HeaderHint extends StatefulWidget {
  const HeaderHint({super.key, required this.message, required this.enabled, required this.child});

  final String message;
  final bool enabled;
  final Widget child;

  @override
  State<HeaderHint> createState() => _HeaderHintState();
}

class _HeaderHintState extends State<HeaderHint> {
  final OverlayPortalController _shown = OverlayPortalController();
  final LayerLink _link = LayerLink();
  Timer? _rest;

  void _enter() {
    _rest?.cancel();
    _rest = Timer(const Duration(milliseconds: 550), () {
      if (mounted) _shown.show();
    });
  }

  void _leave() {
    _rest?.cancel();
    if (_shown.isShowing) _shown.hide();
  }

  @override
  void dispose() {
    _rest?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.message.isEmpty || Overlay.maybeOf(context) == null) return widget.child;
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _leave(),
      child: Listener(
        onPointerDown: (_) => _leave(),
        child: CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _shown,
            overlayChildBuilder: (context) => Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.bottomCenter,
                followerAnchor: Alignment.topCenter,
                offset: const Offset(0, 6),
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
                      decoration: BoxDecoration(color: t.color('glacier-text'), borderRadius: BorderRadius.circular(t.radius('sm'))),
                      child: Text(widget.message, style: t.text('xs', weight: 'medium', color: t.color('glacier-bg'))),
                    ),
                  ),
                ),
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The bell's dot: the gold the bar's bell wears, ringed in [rim].
class HeaderDot extends StatelessWidget {
  const HeaderDot({super.key, this.size = 7, required this.rim});
  final double size;
  final Color rim;

  @override
  Widget build(BuildContext context) => GlacierScope(
        classes: const {'app-gold'},
        child: Builder(
          builder: (context) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: context.tokens.colorOf('var(--app-gold, var(--glacier-text))'),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: rim, spreadRadius: 2)],
            ),
          ),
        ),
      );
}

/// A number at a control's corner, as the old bar's ring wore the links' count.
class HeaderCount extends StatelessWidget {
  const HeaderCount({super.key, required this.count, required this.ink, required this.paper});
  final int count;
  final Color ink, paper;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(7), border: Border.all(color: ink, width: 1)),
        child: Text(count > 99 ? '99+' : '$count', style: t.textAt(9, weight: 'bold', color: ink, height: 1.15)),
      ),
    );
  }
}

/// [child] with [act]'s dot and count at its top end corner, where it has either.
Widget withMarks(HeaderAct act, Widget child, {required Color rim, required Color ink, required Color paper}) {
  final count = act.count ?? 0;
  if (!act.dot && count <= 0) return child;
  return Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      if (act.dot) PositionedDirectional(top: 3, end: 3, child: HeaderDot(rim: rim)),
      if (count > 0) PositionedDirectional(top: -3, end: -4, child: HeaderCount(count: count, ink: ink, paper: paper)),
    ],
  );
}

/// One row of the line's menu.
sealed class HeaderMenuEntry {
  const HeaderMenuEntry();
}

/// A section's name.
class HeaderMenuLabel extends HeaderMenuEntry {
  const HeaderMenuLabel(this.words);
  final String words;
}

/// A rule between sections.
class HeaderMenuRule extends HeaderMenuEntry {
  const HeaderMenuRule();
}

/// A control as a row: its glyph ([icon], else its own in the menu's ink), its word, and [badge] at the end; a tick
/// at the end where it is the one [checked] of several, and the app's red where it is [danger] (Move to Trash).
class HeaderMenuAct extends HeaderMenuEntry {
  const HeaderMenuAct(this.act, {this.icon, this.badge, this.checked = false, this.danger = false});
  final HeaderAct act;
  final Widget? icon;
  final String? badge;
  final bool checked;
  final bool danger;
}

/// Rows made as the menu is drawn, not before: a note's More sheet's, some of which are read from the note as it is
/// when the menu opens (note_settings.dart `noteSheetGroups`).
class HeaderMenuLater extends HeaderMenuEntry {
  const HeaderMenuLater(this.build);
  final List<HeaderMenuEntry> Function(BuildContext context) build;
}

/// Simple mode's More… inside a menu (GHST-103: the "fancy" things behind a More row that opens in place): a row
/// that shows [entries] under it in the same panel, the menu kept open, and hides them again as Less.
class HeaderMenuMore extends HeaderMenuEntry {
  const HeaderMenuMore(this.entries, {this.id = 'note-more'});
  final String id;
  final List<HeaderMenuEntry> entries;
}

/// One of the organizations you belong to, its colour's dot beside its name: a pick opens its dashboard.
class HeaderMenuOrg extends HeaderMenuEntry {
  const HeaderMenuOrg(this.org, this.onPick);
  final OrgLike org;
  final ValueChanged<String> onPick;
}

/// The rows for the app's own - the bell, the organizations one by one and all of them, Settings - in that order,
/// under a label each where there is more than one: what the button for you and the menus of more hold.
List<HeaderMenuEntry> youEntries(HeaderParts parts, {Widget? Function(HeaderAct act)? icon}) {
  final rows = <HeaderMenuEntry>[];
  if (parts.bell case final bell?) rows.add(HeaderMenuAct(bell, icon: icon?.call(bell), badge: parts.unread ? 'New' : null));
  if (parts.organizations case final all?) {
    final picks = parts.onOrganization;
    if (parts.orgs.isNotEmpty && picks != null) {
      if (rows.isNotEmpty) rows.add(const HeaderMenuRule());
      rows.add(const HeaderMenuLabel('Organizations'));
      for (final org in parts.orgs) {
        rows.add(HeaderMenuOrg(org, picks));
      }
    }
    rows.add(HeaderMenuAct(all, icon: icon?.call(all)));
  }
  if (parts.settings case final cog?) {
    if (rows.isNotEmpty) rows.add(const HeaderMenuRule());
    rows.add(HeaderMenuAct(cog, icon: icon?.call(cog)));
  }
  return rows;
}

/// A control that opens a menu hung from the bar: [face] is the trigger, drawn as [HeaderPress] draws any control;
/// the menu is up while it is open, and a row's press does what the control would have and closes it.
class HeaderMenuButton extends StatefulWidget {
  const HeaderMenuButton({super.key, required this.act, required this.fine, required this.entries, required this.face, this.menuLabel, this.radius = 8, this.glyphInk});

  /// The trigger, as a control: its id, label and glyph. Its own press is ignored: it opens the menu.
  final HeaderAct act;
  final bool fine;
  final List<HeaderMenuEntry> entries;
  final Widget Function(BuildContext context, PressState state, bool open) face;

  /// What a screen reader calls the open menu; the trigger's label unless given.
  final String? menuLabel;
  final double radius;

  /// The ink the rows' own glyphs are drawn in; the menu's text colour unless given.
  final Color? glyphInk;

  @override
  State<HeaderMenuButton> createState() => _HeaderMenuButtonState();
}

class _HeaderMenuButtonState extends State<HeaderMenuButton> {
  bool _open = false;
  final GlobalKey _anchor = GlobalKey(debugLabel: 'header-menu');

  /// Simple's More… opened in place, while the menu is up.
  bool _moreShown = false;

  /// The rows as drawn: what is made later made now, and what More… holds under it while it is open.
  List<HeaderMenuEntry> _flat(BuildContext context, List<HeaderMenuEntry> entries) => [
        for (final entry in entries)
          ...switch (entry) {
            HeaderMenuLater(:final build) => _flat(context, build(context)),
            HeaderMenuMore(:final entries) => [entry, if (_moreShown) ..._flat(context, entries)],
            _ => [entry],
          },
      ];

  Widget _row(BuildContext context, HeaderMenuEntry entry) {
    final t = context.tokens;
    switch (entry) {
      case HeaderMenuLater():
        return const SizedBox.shrink();
      case HeaderMenuMore(:final id):
        // The menu stays up: what it holds comes in under it, as the sheet's More… opens in place.
        return GlacierMenuItem(
          key: HeaderAct.keyOf(id),
          closes: false,
          onSelect: () => setState(() => _moreShown = !_moreShown),
          ariaLabel: _moreShown ? 'Less: back to the short list' : 'More: its name, bookmarks, links, comments, the AI, sharing and filing',
          icon: AppIcon(_moreShown ? Lucide.chevronUp : Lucide.ellipsis, size: 16, strokeWidth: 2.2, color: widget.glyphInk ?? t.color('glacier-text-muted')),
          child: Text(_moreShown ? 'Less' : 'More…'),
        );
      case HeaderMenuLabel(:final words):
        return GlacierMenuLabel(child: Text(words));
      case HeaderMenuRule():
        return const GlacierMenuSeparator();
      case HeaderMenuOrg(:final org, :final onPick):
        return GlacierMenuItem(key: HeaderAct.keyOf('org:${org.id}'), onSelect: () => onPick(org.id), icon: HueDot(org.hue), child: Text(org.name));
      case HeaderMenuAct(:final act, :final icon, :final badge, :final checked, :final danger):
        // A row that opens a floating card is the card's own press, as its ring would be: choosing Notifications
        // with the card open closes it, rather than the press closing it and the row opening it again.
        final row = GlacierMenuItem(
          key: act.key,
          danger: danger,
          style: danger ? dangerRowStyle(t) : null,
          // A card the row opens hangs under the button the menu hangs from.
          onSelect: act.onPress == null
              ? null
              : () {
                  if (_anchor.currentContext case final from?) cardOpenedFrom(from);
                  act.onPress!();
                },
          disabled: act.onPress == null,
          ariaLabel: act.label,
          icon: icon ?? HeaderGlyph(act, size: 16, color: danger ? t.color('glacier-red-11') : widget.glyphInk ?? t.color('glacier-text-muted')),
          shortcut: checked
              ? AppIcon(Lucide.check, size: 14, strokeWidth: 2.4, color: t.color('glacier-text'))
              : badge == null
              ? null
              : Container(
                  padding: EdgeInsets.symmetric(horizontal: t.space(1) * 1.5, vertical: 1),
                  decoration: BoxDecoration(color: hueInk(t, 'amber'), borderRadius: BorderRadius.circular(t.radius('full'))),
                  child: Text(badge, style: t.text('xs', weight: 'semibold', color: const Color(0xFFFFFFFF))),
                ),
          child: Text(act.word),
        );
        return act.toggle == null ? row : FloatingCardToggle(toggle: act.toggle!, child: row);
    }
  }

  /// The floating cards the menu's rows open: a press on the trigger is theirs too, so opening the menu does not
  /// close a card one of its rows would close.
  Widget _theirs(Widget trigger) {
    var wrapped = trigger;
    for (final entry in widget.entries) {
      if (entry case HeaderMenuAct(act: HeaderAct(:final toggle?))) wrapped = FloatingCardToggle(toggle: toggle, child: wrapped);
    }
    return wrapped;
  }

  @override
  Widget build(BuildContext context) {
    final trigger = HeaderPress(
      act: widget.act,
      fine: widget.fine,
      radius: widget.radius,
      expanded: _open,
      anchorKey: _anchor,
      onPressed: widget.entries.isEmpty ? null : () => setState(() => _open = !_open),
      face: (context, state) => widget.face(context, state, _open),
    );
    if (!_open) return _theirs(trigger);
    final rows = _flat(context, widget.entries);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _theirs(trigger),
        PopMenu(
          anchor: GlacierAnchor.key(_anchor),
          placement: Placement.bottomEnd,
          reach: PopReach.down,
          ariaLabel: widget.menuLabel ?? widget.act.label,
          coarse: !widget.fine,
          onDismiss: () {
            if (mounted) {
              setState(() {
                _open = false;
                _moreShown = false;
              });
            }
          },
          children: [for (final entry in rows) _row(context, entry)],
        ),
      ],
    );
  }
}

/// The acts of [all] that are not one of [shown], in order.
List<HeaderAct> notShown(List<HeaderAct> all, Iterable<HeaderAct> shown) {
  final ids = {for (final act in shown) act.id};
  return [for (final act in all) if (!ids.contains(act.id)) act];
}

/// The button for you: the account's round, on which the bell's dot is worn; its menu is the app's own.
HeaderAct youAct(HeaderParts parts) => HeaderAct(
      id: 'you',
      label: parts.unread ? 'You: notifications, organizations and Settings, something new' : 'You: notifications, organizations and Settings',
      word: 'You',
      hue: 'magenta',
      icon: Lucide.userRound,
      onPress: () {},
      dot: parts.unread,
    );

/// [HeaderParts.kept] as the first rows of the line's •••, with a rule after them where [more] rows follow.
List<HeaderMenuEntry> keptEntries(HeaderParts parts, {bool more = true, Widget? Function(HeaderAct act)? icon}) => [
      for (final act in parts.kept) HeaderMenuAct(act, icon: icon?.call(act)),
      if (more && parts.kept.isNotEmpty) const HeaderMenuRule(),
    ];

/// The menu of more's own act.
HeaderAct moreAct({String label = 'More'}) => HeaderAct(id: 'overflow', label: label, word: 'More', hue: 'indigo', icon: Lucide.ellipsis, onPress: () {});

// ---- a note's More sheet as rows of its ••• ------------------------------------------------------------------------

/// The hue each of the sheet's groups wears in a menu of •••, by the group's id, and a row's own where it has one
/// (the note's actions', as the bar's pill has them).
const Map<String, String> _noteGroupHues = {
  'speak': 'red',
  'names': 'indigo',
  'page': 'blue',
  'reading': 'amber',
  'reading-more': 'amber',
  'around': 'cyan',
  'comments': 'coral',
  'ai': 'purple',
  'sits': 'rose',
  'filing': 'orange',
  'verify': 'green',
  'linked': 'mint',
  'help': 'lime',
};
const Map<String, String> _noteItemHues = {'pin': 'rose', 'archive': 'orange', 'comment': 'coral', 'bookmark': 'yellow', 'speak': 'red', 'history': 'purple', 'links': 'mint'};

/// The act a sheet's row is in the menu: keyed `header:note:<id>`.
HeaderAct noteMenuAct(NoteMenuGroup group, NoteMenuItem item) => HeaderAct(
      id: 'note:${item.id}',
      label: item.label,
      word: item.label,
      hue: _noteItemHues[item.id] ?? _noteGroupHues[group.id] ?? 'indigo',
      icon: item.icon,
      onPress: item.onPress,
      on: item.on,
    );

/// A note's More sheet as rows of its ••• (Matt, 2026-11-02: "Show more items in the more dropdown we should be able
/// to scroll on it instead of needing to open a new modal"): each of the sheet's groups under its heading, a rule
/// between, then [more] (the whole sheet, for what is not a row: the name, the AI's Ask, sharing), then Move to Trash
/// apart at the foot. Rows whose ids are in [leave] are left out (the bar's pill has them). In simple mode the groups
/// the sheet keeps behind its More… are behind one here, opened in place ([HeaderMenuMore]). A row the bar has an
/// action of its own for is drawn as that action ([own], by the row's id). [hued] draws each
/// glyph in its group's hue, as Grouped command's menu draws its rows; otherwise in the menu's ink.
List<HeaderMenuEntry> noteMenuEntries(BuildContext context, List<NoteMenuGroup> groups, {HeaderAct? more, Set<String> leave = const {}, Map<String, HeaderAct> own = const {}, bool hued = false}) {
  final t = context.tokens;
  Widget? glyphOf(NoteMenuGroup group, NoteMenuItem item, HeaderAct act) {
    final ink = item.danger ? t.color('glacier-red-11') : (hued ? hueInk(t, act.hue) : t.color('glacier-text-muted'));
    if (item.glyph case final drawn?) return drawn(context, 16, ink);
    return hued || item.danger ? HeaderGlyph(act, size: 16, color: ink, strokeWidth: 2) : null;
  }

  List<HeaderMenuEntry> rowsOf(List<NoteMenuGroup> list, {required bool ruleFirst}) {
    final rows = <HeaderMenuEntry>[];
    for (final group in list) {
      final items = [for (final item in group.items) if (!leave.contains(item.id)) item];
      if (items.isEmpty) continue;
      if (rows.isNotEmpty || ruleFirst) rows.add(const HeaderMenuRule());
      if (group.heading case final heading?) rows.add(HeaderMenuLabel(heading));
      for (final item in items) {
        // The bar's own action for this row, where it has one ([own]): its words, its count and its key.
        if (own[item.id] case final mine?) {
          rows.add(HeaderMenuAct(mine, icon: hued ? HeaderGlyph(mine, size: 16, color: hueInk(t, mine.hue), strokeWidth: 2) : null));
          continue;
        }
        final act = noteMenuAct(group, item);
        rows.add(HeaderMenuAct(act, icon: glyphOf(group, item, act), checked: item.checked, danger: item.danger));
      }
    }
    return rows;
  }

  final trash = [for (final group in groups) if (group.id == 'trash') group];
  final plain = [for (final group in groups) if (group.id != 'trash' && !group.fancy) group];
  final fancy = [for (final group in groups) if (group.id != 'trash' && group.fancy) group];
  // Simple's More… sits after the short list's groups and before Help, where the sheet has it.
  final help = [for (final group in plain) if (group.id == 'help') group];
  final first = [for (final group in plain) if (group.id != 'help') group];
  final rows = rowsOf(first, ruleFirst: false);
  final hidden = rowsOf(fancy, ruleFirst: true);
  if (hidden.isNotEmpty) rows.addAll([if (rows.isNotEmpty) const HeaderMenuRule(), HeaderMenuMore(hidden)]);
  rows.addAll(rowsOf(help, ruleFirst: rows.isNotEmpty));
  if (more != null) rows.addAll([if (rows.isNotEmpty) const HeaderMenuRule(), HeaderMenuAct(more, icon: hued ? HeaderGlyph(more, size: 16, color: hueInk(t, more.hue), strokeWidth: 2) : null)]);
  rows.addAll(rowsOf(trash, ruleFirst: rows.isNotEmpty));
  return rows;
}

/// The ••• row that opens the whole More sheet, as the ring did: kept under the `more` id the bar has always given it.
HeaderAct allSettingsAct(VoidCallback onMore) =>
    HeaderAct(id: 'more', label: 'All settings for this note', word: 'All settings…', hue: 'indigo', icon: Lucide.slidersHorizontal, onPress: onMore);
