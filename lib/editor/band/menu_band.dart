/// The pieces the press-and-hold menu is drawn from, its actions and its Style page alike (context_band.dart,
/// style_items.dart): a band that scrolls sideways, a word under its drawn icon, and the row that presses it. A port
/// of `src/app/editor/MenuBand.tsx` with the rules of `ContextMenu.module.css` each draws by.
///
/// Each word stands under its icon, in display weight, the same hand as a linked line's drawer. Matt: "make the
/// options typography and iconography heavy so they fit the theme on all context menus".
///
/// What differs:
/// - a `MenuIcon` was any drawn icon component; here it is a [LucideIcon], the kit's as the page draws them
///   (lib/art/app_icon.dart);
/// - `.item + .item` gave every row but the first its hairline; a Flutter child cannot ask what stands before it,
///   so the band tells its rows ([MenuBand] wraps each in a [BandPlace]) and a row reads whether it is first;
/// - `.row[data-more]`'s mask is a [ShaderMask]. On the page the mask also takes the row's shadow off, since a
///   mask cuts everything outside the border box; the band draws its shadow only while nothing is past either end,
///   which is the same picture;
/// - `:active` is the row's own pressed state, kept while a finger is down on it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../shell/wide_screen.dart' show mousePointer;

/// A drawn icon a menu can size and weigh (`MenuIcon`).
typedef MenuIcon = LucideIcon;

/// An icon over its word (`MenuWord`): the icon 20 across at a stroke of 2.1, the word in `.word`'s face. [ink] is
/// the row's `color`. [hint], where given, is one line in plain words under the word, in [hintInk] (the row's third
/// ink): what the Style page's rows wear in simple mode (style_items.dart), for someone who does not know what
/// "Quote" or "Rule" would do to their words.
class MenuWord extends StatelessWidget {
  const MenuWord({super.key, required this.icon, required this.label, required this.ink, this.hint, this.hintInk});

  final MenuIcon icon;
  final String label;
  final Color ink;
  final String? hint;
  final Color? hintInk;

  /// `.word`: the kit's smallest step, bold, a hundredth of an em between its letters.
  static TextStyle style(Tokens t, Color ink) {
    final px = t.len('glacier-font-size-xs');
    return t.textAt(px, weight: 'bold', color: ink, tracking: px * 0.01);
  }

  /// The hint's face: the word's size, a plain weight, so the word still leads.
  static TextStyle hintStyle(Tokens t, Color ink) => t.textAt(t.len('glacier-font-size-xs'), weight: 'medium', color: ink);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hint = this.hint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        AppIcon(icon, size: 20, strokeWidth: 2.1, color: ink),
        // `.item { gap: 3px }`.
        const SizedBox(height: 3),
        Text(label, maxLines: 1, softWrap: false, style: style(t, ink)),
        if (hint != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(hint, maxLines: 1, softWrap: false, style: hintStyle(t, hintInk ?? ink)),
        ],
      ],
    );
  }
}

/// Where a row stands in its band: whether another stands before it (`.item + .item`).
class BandPlace extends InheritedWidget {
  const BandPlace({super.key, required this.first, required super.child});

  final bool first;

  static bool firstOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BandPlace>()?.first ?? true;

  @override
  bool updateShouldNotify(BandPlace oldWidget) => oldWidget.first != first;
}

/// `.item`'s box: the padding, the least size, the hairline before every row but the first, and the paper a
/// pressed row takes. [lit] prints it in reverse (`.style[data-lit]`); [group] gives it a breath of room before it
/// (`.style[data-group]`).
///
/// [hint] is one line in plain words on what the row does. It is always said to a screen reader after the word,
/// and on a desktop it comes up over the row while the pointer rests there ([BandTip]). With [hintShown] it is
/// also drawn under the word, which makes the row taller and wider than the page's measured band: simple mode's
/// Style page draws it (Matt, 2026-10-18: "work on making formatting and stuff easier to understand"); advanced
/// keeps the band as the page drew it.
class BandItemBox extends StatefulWidget {
  const BandItemBox({
    super.key,
    required this.icon,
    required this.label,
    required this.onPress,
    this.name,
    this.lit = false,
    this.group = false,
    this.checkbox = false,
    this.hint,
    this.hintShown = false,
  });

  final MenuIcon icon;
  final String label;
  final VoidCallback onPress;

  /// Its accessible name where the word alone would not say what it does.
  final String? name;
  final bool lit;
  final bool group;

  /// `role="menuitemcheckbox"` with `aria-checked`, where false is a plain `menuitem`.
  final bool checkbox;
  final String? hint;
  final bool hintShown;

  @override
  State<BandItemBox> createState() => _BandItemBoxState();
}

class _BandItemBoxState extends State<BandItemBox> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final first = BandPlace.firstOf(context);
    final ink = t.color(widget.lit ? 'app-paper' : 'app-ink');
    final Color? paper = widget.lit ? t.color('app-ink') : (_down ? t.color('app-paper-3') : null);
    final hairline = t.len('glacier-hairline');
    final hint = widget.hint;
    final drawn = widget.hintShown ? hint : null;
    final Widget box = Semantics(
      container: true,
      button: true,
      checked: widget.checkbox ? widget.lit : null,
      label: widget.name ?? widget.label,
      hint: hint,
      excludeSemantics: true,
      onTap: widget.onPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onPress,
        child: Container(
          margin: widget.group ? EdgeInsets.only(left: t.space(2)) : null,
          // `min-inline-size: 3.5rem; min-block-size: 2.75rem`, of the border box.
          constraints: BoxConstraints(minWidth: t.lenOf('3.5rem'), minHeight: t.lenOf('2.75rem')),
          padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(3) - 2),
          decoration: BoxDecoration(
            color: paper,
            border: first ? null : Border(left: BorderSide(color: t.color('app-rule'), width: hairline)),
          ),
          alignment: Alignment.center,
          child: MenuWord(icon: widget.icon, label: widget.label, ink: ink, hint: drawn, hintInk: widget.lit ? ink : t.color('app-ink-3')),
        ),
      ),
    );
    // Drawn under the word, there is nothing left for a tip to say.
    if (hint == null || drawn != null) return box;
    return BandTip(message: hint, child: box);
  }
}

/// A line of words over a row, on a desktop, while the pointer rests on it: the row's [message], a step above it,
/// in the ink's own paper. Nothing on a phone, where nothing rests, nor where the app has no overlay to draw it in.
/// The dock's tip (lib/shell/page_dock.dart `DockTip`) stands beside its ring, since the dock is a column at the
/// page's end; a row in a band has rows either side, so this one stands above.
class BandTip extends StatefulWidget {
  const BandTip({super.key, required this.message, required this.child, this.wait = const Duration(milliseconds: 450)});

  final String message;
  final Widget child;
  final Duration wait;

  @override
  State<BandTip> createState() => _BandTipState();
}

class _BandTipState extends State<BandTip> {
  final OverlayPortalController _portal = OverlayPortalController(debugLabel: 'band tip');
  final LayerLink _link = LayerLink();
  Timer? _waiting;

  @override
  void dispose() {
    _waiting?.cancel();
    super.dispose();
  }

  void _enter() {
    _waiting?.cancel();
    _waiting = Timer(widget.wait, () {
      if (mounted && Overlay.maybeOf(context) != null) _portal.show();
    });
  }

  void _exit() {
    _waiting?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    if (!mousePointer) return widget.child;
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: Listener(
        onPointerDown: (_) => _exit(),
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: Offset(0, -t.space(2)),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Container(
                    key: const ValueKey('band-tip'),
                    padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
                    decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('sm'))),
                    child: Text(widget.message, maxLines: 1, softWrap: false, style: t.textAt(t.fontSize('xs'), weight: 'medium', height: 1.3, color: t.color('app-paper'))),
                  ),
                ),
              ),
            ),
          ),
          child: CompositedTransformTarget(link: _link, child: widget.child),
        ),
      ),
    );
  }
}

/// One of the menu's rows: a word under its icon, pressed (`MenuItem`). [name] is its accessible name where the
/// word alone would not say what it does.
class MenuItem extends StatelessWidget {
  const MenuItem({super.key, required this.icon, required this.label, required this.onPress, this.name});

  final MenuIcon icon;
  final String label;
  final VoidCallback onPress;
  final String? name;

  @override
  Widget build(BuildContext context) => BandItemBox(icon: icon, label: label, onPress: onPress, name: name);
}

/// How far the band fades at an end that has more (`32px` in the masks).
const double _fade = 32;

/// One band of the menu (`MenuBand`, `.row`). Five words do not always fit a phone held upright, so the band
/// scrolls sideways, and fades at whichever end has more: a word cut off at the edge reads as broken, a word
/// fading out reads as "and more".
class MenuBand extends StatefulWidget {
  const MenuBand({super.key, required this.children});

  final List<Widget> children;

  @override
  State<MenuBand> createState() => MenuBandState();
}

class MenuBandState extends State<MenuBand> {
  final ScrollController _scroll = ScrollController();
  bool _start = false, _end = false;

  /// The band's scroll, for whoever must tell a scroll of the band from a scroll of the note.
  ScrollController get scroll => _scroll;

  /// Which ends have more, as the page's `data-more` says it: '', 'start', 'end' or 'start end'.
  String get more => <String>[if (_start) 'start', if (_end) 'end'].join(' ');

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(MenuBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another page's rows: what is past the ends is read again once they are laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final at = _scroll.position;
    if (!at.hasContentDimensions) return;
    // `scrollLeft > 1`, and `scrollLeft + clientWidth < scrollWidth - 1`.
    final start = at.pixels > 1;
    final end = at.pixels < at.maxScrollExtent - 1;
    if (start != _start || end != _end) {
      setState(() {
        _start = start;
        _end = end;
      });
    }
  }

  bool _measured(ScrollMetricsNotification _) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hairline = t.len('glacier-hairline');
    const radius = 18.0;
    final masked = _start || _end;
    Widget row = DecoratedBox(
      decoration: BoxDecoration(
        color: t.color('app-paper-2'),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.color('app-rule'), width: hairline),
        boxShadow: masked ? null : const <BoxShadow>[BoxShadow(color: Color(0x47000000), offset: Offset(0, 10), blurRadius: 28)],
      ),
      child: Padding(
        padding: EdgeInsets.all(hairline),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - hairline),
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _measured,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final (index, child) in widget.children.indexed) BandPlace(key: child.key, first: index == 0, child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (masked) {
      final start = _start, end = _end;
      row = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final edge = bounds.width <= 0 ? 0.0 : (_fade / bounds.width).clamp(0.0, 0.5);
          const clear = Color(0x00000000), solid = Color(0xFF000000);
          return LinearGradient(
            colors: <Color>[start ? clear : solid, solid, solid, end ? clear : solid],
            stops: <double>[0, start ? edge : 0, end ? 1 - edge : 1, 1],
          ).createShader(bounds);
        },
        child: row,
      );
    }
    return row;
  }
}
