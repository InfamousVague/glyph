import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart' show AppIcon, LucideIcon;
import '../../art/lucide.g.dart' show Lucide;
import '../../kit/settings_type.dart';
import 'bevel.dart';
import 'retro_button.dart';

/// The smaller pieces Dial-Up's layout is made of (lib/looks.dart): what the app's own widgets turn into while
/// [isDialup] (lib/ui/common.dart's GhostPage, IconTap and Avatar, the composer, the navigation, the list).

/// What stands on a title bar's band: the page's ink, and the words and icons drawn in it, are the band's white, so a
/// page's own header (a face, a name, a line under it) and its icon buttons read there without knowing they are on
/// navy. A class in assets/css/app.css (`.dialup-band`), so it is a scope of the tokens like `.app-inverse`.
class DialupBand extends StatelessWidget {
  const DialupBand({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GlacierScope(classes: const {'dialup-band'}, child: child);
}

/// The silver panel along a page's foot (the composer's): the page's ground is the window's silver there, so what a
/// conversation draws on the page's ground under its words (lib/ui/thread.dart's composer) is the panel's.
class DialupPanel extends StatelessWidget {
  const DialupPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GlacierScope(classes: const {'dialup-panel'}, child: child);
}

/// A kit field (a search field, an input) set into a [Sunken] frame: white, and without its own line round it, since
/// the frame is its edge (`.dialup-well` in assets/css/app.css). The kit reads its colours in its own build, so the
/// scope reaches it.
class DialupWell extends StatelessWidget {
  const DialupWell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Sunken(child: GlacierScope(classes: const {'dialup-well'}, child: child));
}

/// Round buttons that are to stand up off the panel as raised [RetroButton]s (the composer's +, stickers,
/// microphone): an IconTap (lib/ui/common.dart) under this draws as one. Elsewhere an IconTap is a flat tool button,
/// as the era's toolbars and title bars had them, which shows its bevel only while it is held.
class RetroIcons extends InheritedWidget {
  const RetroIcons({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RetroIcons>() != null;

  @override
  bool updateShouldNotify(RetroIcons old) => false;
}

/// An IconTap under Dial-Up, away from [RetroIcons]: a flat square the size of a press, its icon in the page's ink,
/// that sinks into a bevel while held. Off, its icon is faint.
class DialupTool extends StatelessWidget {
  const DialupTool({super.key, required this.icon, required this.label, required this.onPressed, this.size = 20, this.color, this.box = 44});

  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final double box;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = DialupColors.of(t);
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) {
        final off = onPressed == null;
        final held = state.pressed && !off;
        final ink = color ?? t.color('app-ink');
        final mark = Opacity(opacity: off ? 0.4 : 1, child: AppIcon(icon, size: size, color: ink));
        return GlacierFocusRing(
          visible: state.focused,
          radius: 0,
          offset: 0,
          width: 1,
          color: ink,
          child: SizedBox.square(
            dimension: box,
            child: held
                ? CustomPaint(
                    painter: BevelPainter(colors: c, style: BevelStyle.pressed, face: const Color(0x00000000), ring: Bevel.ringOf(context)),
                    child: Center(child: Transform.translate(offset: const Offset(1, 1), child: mark)),
                  )
                : Center(child: mark),
          ),
        );
      },
    );
  }
}

/// A face (a person's picture or initials) set into the page: square, in one ring of the sunken bevel, as the era
/// set every picture in a frame.
class DialupFace extends StatelessWidget {
  const DialupFace({super.key, required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ring = Bevel.ringOf(context);
    return SizedBox.square(
      dimension: size,
      child: Bevel(style: BevelStyle.sunken, rings: 1, color: context.tokens.color('app-paper'), child: ClipRect(child: SizedBox.square(dimension: size - ring * 2, child: child))),
    );
  }
}

/// A count on a button's corner (the taskbar's Archive, Contacts, Settings): a small red square with white figures in
/// a black line, not the app's round badge.
class DialupCount extends StatelessWidget {
  const DialupCount({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = DialupColors.of(t);
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.colorOf('var(--app-count, var(--app-danger))'), border: Border.all(color: c.afterHours ? c.hi : c.dark)),
      child: Text(count > 99 ? '99+' : '$count', style: pageText(t, 11, weight: 'bold', height: 1.2, color: t.colorOf('var(--app-on-count, #FFFFFF)'))),
    );
  }
}

/// A square box with a tick in it, sunk into the page: choosing several rows of a list.
class DialupCheck extends StatelessWidget {
  const DialupCheck({super.key, required this.checked, this.size = 20});
  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox.square(
      dimension: size,
      child: Sunken(
        child: checked ? Center(child: AppIcon(Lucide.check, size: size - 6, strokeWidth: 3, color: t.color('app-ink'))) : null,
      ),
    );
  }
}
