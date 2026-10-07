import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/back.dart';

/// How much room a [PopMenu] may take: `down` for one hanging from the top bar, `either` for one that may open above
/// or below its anchor (`Reach`, editor/PopMenu.tsx).
enum PopReach { down, either }

/// The opened Fold, as the + list knows it (`OPENED_FOLD`): a finger on a window 600px and wider.
const double _openedFold = 600;

/// How near a panel comes to the window's edges, and to the crease: the kit's padding, and the + list's gap.
const double _edge = 8, _creaseGap = 16;

/// Whether the pointer is a finger (`(pointer: coarse)`): here, whether the app is on a phone or a tablet.
bool get coarsePointer => switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      _ => false,
    };

/// The widest panel the kit draws: its own `min(22rem, 100vw - 2rem)`.
double _widestPanel(Tokens t) => t.lenOf('min(22rem, calc(100vw - 2rem))');

/// The alignment that keeps the panel on its anchor's side of the opened Fold's crease, the window's middle, and
/// whether it is creased at all (`offTheCrease`, editor/PopMenu.tsx). An anchor in the left half keeps its alignment
/// only if the widest panel would still end [_creaseGap] before the crease, and otherwise hangs by its end, growing
/// toward the outer edge; one in the right half mirrors that.
({Placement placement, bool creased}) offTheCrease(Rect? box, Placement asked, {required double window, required double widestPanel, required bool coarse}) {
  if (box == null || !coarse || window < _openedFold) return (placement: asked, creased: false);
  final side = asked.side;
  if (side != AnchorSide.top && side != AnchorSide.bottom) return (placement: asked, creased: true);
  final crease = window / 2;
  final widest = math.min(widestPanel, crease - _edge - _creaseGap);
  final left = switch (asked.align) {
    AnchorAlignment.start => box.left,
    AnchorAlignment.end => box.right - widest,
    AnchorAlignment.center => box.left + box.width / 2 - widest / 2,
  };
  final physical = side == AnchorSide.top ? PhysicalSide.top : PhysicalSide.bottom;
  if (box.left + box.width / 2 < crease) {
    return (placement: left + widest > crease - _creaseGap ? Placement.of(physical, AnchorAlignment.end) : asked, creased: true);
  }
  return (placement: left < crease + _creaseGap ? Placement.of(physical, AnchorAlignment.start) : asked, creased: true);
}

/// The kit's menu, hung from something already on the page: a tab or a group chip (notes/tabs/tab_menus.dart), the
/// top bar's people icon (notes/note_tabs.dart); or from a point. Ports the web app's editor/PopMenu.tsx with
/// PopMenu.module.css.
///
/// It is up for as long as it is in the tree: its owner mounts it to open it, and takes it down on [onDismiss].
/// What it adds to the kit's [GlacierMenu] is what the app's own menus had:
///
/// - **The back gesture closes it** (core/back.dart), and is used by it alone.
/// - **A press anywhere closes it.** A press on its anchor or in any panel of the menu is the menu's own.
/// - **It goes with what it hangs from**: an anchor gone from the page, or wholly off the screen.
/// - **Rows a thumb's height under a finger**, in the + list's type, and a height inside the room it has: under the
///   top bar for one that hangs from it ([PopReach.down]), half the screen for one that hangs from the page.
/// - **On the opened Fold it keeps to its anchor's side of the crease**: its alignment is chosen as it opens, once,
///   and its width capped at half the window.
/// - **Nested rows in place** ([PopSub]) unless a mouse has room for a flyout either side of the menu.
/// - **The owner hears one [onDismiss], a microtask after the kit's close**, however many ways it closes at once.
///
/// Differs from the web:
/// - The kit's menu here takes an anchor itself and hears the back gesture and a press outside on the way down, so
///   the stand-in trigger (`AnchorAt`), the mark at a point and the window's capture listener are not needed: this
///   passes [anchor] on, and `at` is `GlacierAnchor.point`.
/// - `aria-controls` on the anchor is not written; Flutter's semantics name a panel from its trigger only where the
///   menu builds the trigger.
/// - A finger is the device ([coarsePointer]) rather than the pointer that is down.
/// - The anchor is looked at on each frame the app draws while the menu is up, where the page listened for scroll
///   and resize.
class PopMenu extends StatefulWidget {
  const PopMenu({
    super.key,
    required this.anchor,
    this.placement = Placement.bottomStart,
    this.reach = PopReach.either,
    required this.onDismiss,
    required this.ariaLabel,
    this.coarse,
    required this.children,
  });

  /// What it hangs from: something on the page by its key, or a point (`GlacierAnchor.point`).
  final GlacierAnchor anchor;
  final Placement placement;
  final PopReach reach;

  /// Every way it closes, once, a microtask later; the owner takes it down.
  final VoidCallback onDismiss;
  final String ariaLabel;

  /// Whether the rows are a finger's; the device's answer unless a test says.
  final bool? coarse;
  final List<Widget> children;

  /// The panel's look for [reach] (PopMenu.module.css `.pop.down`, `.pop.either`, `.pop.creased`, and the rows'
  /// size under a finger).
  static GlacierMenuStyle styleOf(Tokens t, PopReach reach, {required bool coarse, bool creased = false}) {
    final maxHeight = switch (reach) {
      // The room under the bar, less the kit's 8px offset from its anchor and its 8px edge.
      PopReach.down => t.lenOf('calc(100vh - var(--app-inset-top) - var(--app-tabs) - 16px)'),
      // Half the room, so whichever side the kit turns it to holds it whole.
      PopReach.either => t.lenOf('calc((100vh - var(--app-inset-top)) / 2 - 32px)'),
    };
    final size = coarse ? t.fontSize('md') : t.fontSize('sm');
    return GlacierMenuStyle(
      maxHeight: math.max(0, maxHeight),
      maxWidth: creased ? math.min(_widestPanel(t), t.lenOf('calc(50vw - 24px)')) : null,
      item: GlacierMenuItemStyle(
        // `@media (pointer: coarse) { min-block-size: 2.75rem; font-size: md; font-weight: medium }`
        minHeight: coarse ? t.lenOf('2.75rem') : null,
        textStyle: coarse
            ? TextStyle(fontSize: size, fontWeight: t.weight('medium'), fontVariations: [FontVariation('wght', t.len('glacier-font-weight-medium')), FontVariation('opsz', size)])
            : null,
        // `.pop [role^='menuitem'] svg { inline-size: 1.15em }`, for a finger and a mouse alike.
        iconSize: 1.15 * size,
      ),
    );
  }

  @override
  State<PopMenu> createState() => _PopMenuState();
}

class _PopMenuState extends State<PopMenu> {
  bool _gone = false;
  bool _open = true;
  ({Placement placement, bool creased})? _side;
  VoidCallback? _offBack;
  bool _looking = true;

  bool get _coarse => widget.coarse ?? coarsePointer;

  /// One onDismiss however many ways it closes at once, and a microtask later: the kit reports a close and only then
  /// hands the focus back to what it hangs from.
  void _dismiss() {
    if (_gone) return;
    _gone = true;
    if (mounted) setState(() => _open = false);
    scheduleMicrotask(() {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void initState() {
    super.initState();
    _offBack = BackScope.of(context).onBack(() {
      _dismiss();
      return true;
    });
    SchedulerBinding.instance.addPostFrameCallback((at) {
      _place();
      _look(at);
    });
  }

  ({Placement placement, bool creased})? _sided() {
    final box = widget.anchor.rect();
    if (box == null) return null;
    return offTheCrease(box, widget.placement, window: MediaQuery.sizeOf(context).width, widestPanel: _widestPanel(context.tokens), coarse: _coarse);
  }

  /// On the opened Fold, the alignment that keeps it on its anchor's side of the crease, chosen once as it opens:
  /// after the first frame where the anchor was drawn with it and has no box until then.
  void _place() {
    if (!mounted || _side != null) return;
    final side = _sided();
    if (side == null) return;
    setState(() => _side = side);
  }

  /// Gone with what it hangs from: an anchor taken off the page, or wholly off the screen. Asked after each frame
  /// the app draws, once the page has moved; it asks for no frames of its own.
  void _look(Duration _) {
    if (!mounted || !_looking || _gone) return;
    final box = widget.anchor.rect();
    final window = MediaQuery.maybeSizeOf(context);
    if (box == null) {
      _dismiss();
      return;
    }
    if (window != null && (box.bottom < 0 || box.top > window.height || box.right < 0 || box.left > window.width)) {
      _dismiss();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback(_look);
  }

  @override
  void dispose() {
    _looking = false;
    _offBack?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = (_side ??= _sided()) ?? (placement: widget.placement, creased: false);
    return GlacierMenu(
      open: _open,
      onOpenChange: (open) {
        if (!open) _dismiss();
      },
      anchor: widget.anchor,
      placement: side.placement,
      ariaLabel: widget.ariaLabel,
      style: PopMenu.styleOf(t, widget.reach, coarse: _coarse, creased: side.creased),
      children: widget.children,
    );
  }
}

/// Whether a flyout fits (`flyoutFits`, editor/PopMenu.tsx): a mouse, on a window that holds the menu and a widest
/// flyout on either side of it, with the kit's 2px offsets and 8px edges - 1076px at the app's own interface size.
bool flyoutFits(Tokens t, double window, {required bool coarse}) => !coarse && window >= 3 * _widestPanel(t) + 2 * (2 + _edge);

/// Rows under a name, inside a [PopMenu] (`PopSub`, editor/PopMenu.tsx): the kit's flyout where one fits, and
/// otherwise listed in place under a label, in the same panel. A finger never gets a flyout, which keeps one off the
/// Fold's crease and a phone's edge. A label is not tied to its rows, so each row carries its whole name itself
/// (`ariaLabel`).
///
/// Differs from the web: the rows are [rows] of a menu's `children` list, so this is a function that answers the
/// widgets to spread into it, where the web's was a component that drew a fragment.
class PopSub {
  const PopSub._();

  /// The rows under [label]: one flyout row, or the label and then [children].
  static List<Widget> rows(BuildContext context, {required String label, PopReach reach = PopReach.either, bool? coarse, required List<Widget> children}) {
    final t = context.tokens;
    final finger = coarse ?? coarsePointer;
    if (flyoutFits(t, MediaQuery.sizeOf(context).width, coarse: finger)) {
      return [GlacierMenuSub(label: Text(label), menuStyle: PopMenu.styleOf(t, reach, coarse: finger), children: children)];
    }
    return [GlacierMenuLabel(child: Text(label)), ...children];
  }
}

/// A row in the app's one red, for Delete in a note's menu and a tab's (notes/NoteMenu.module.css `.danger`): the
/// kit paints a danger row with its danger text, which this app's ink leaves near the page's own, so the row and its
/// icon are given the red here, past the kit's own rule.
GlacierMenuItemStyle dangerRowStyle(Tokens t) => GlacierMenuItemStyle(
      color: t.color('glacier-red-11'),
      iconColor: t.color('glacier-red-11'),
      hoverColor: t.colorOf('color-mix(in srgb, var(--glacier-red-9) 14%, transparent)'),
    );
