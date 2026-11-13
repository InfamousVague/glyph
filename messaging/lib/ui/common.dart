import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../sms.dart';

/// The page under every screen: the ground, a bar with the way back (or a big title), its actions, and the body.
class GhostPage extends StatelessWidget {
  const GhostPage({super.key, required this.title, required this.body, this.back = true, this.actions = const [], this.titleWidget, this.footer});

  final String title;
  final Widget? titleWidget;
  final Widget body;
  final bool back;
  final List<Widget> actions;

  /// Kept above the keyboard: a conversation's composer.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: pad.top),
          SizedBox(
            height: t.lenOf('3.5rem'),
            child: Row(
              children: [
                SizedBox(width: t.space(back ? 1 : 4)),
                if (back) IconTap(icon: Lucide.arrowLeft, label: 'Back', size: 22, onPressed: () => Navigator.of(context).maybePop()),
                Expanded(
                  child: titleWidget ??
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: pageText(t, back ? t.fontSize('lg') : t.fontSize('2xl'), weight: back ? 'semibold' : 'bold', color: t.color('app-ink')),
                      ),
                ),
                ...actions,
                SizedBox(width: t.space(2)),
              ],
            ),
          ),
          Expanded(child: body),
          if (footer != null) Padding(padding: EdgeInsets.only(bottom: inset > 0 ? inset : pad.bottom), child: footer!),
        ],
      ),
    );
  }
}

/// A round icon button, the kit's press and focus ring round it.
class IconTap extends StatelessWidget {
  const IconTap({super.key, required this.icon, required this.label, required this.onPressed, this.size = 20, this.color, this.filled = false});

  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  /// Ink-filled disc with the icon in paper: the one main action on a screen (Send).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final box = t.lenOf('2.75rem');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) {
        final off = onPressed == null;
        final ink = filled ? t.color('app-paper') : (color ?? t.color(state.pressed ? 'app-ink-3' : 'app-ink'));
        return GlacierFocusRing(
          visible: state.focused,
          radius: box,
          child: AnimatedScale(
            scale: state.pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: box,
              height: box,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? (off ? t.color('app-ink-4') : t.color('app-ink'))
                    : (state.pressed ? t.color('app-paper-3') : const Color(0x00000000)),
              ),
              alignment: Alignment.center,
              child: Opacity(opacity: off && !filled ? 0.4 : 1, child: AppIcon(icon, size: size, color: ink)),
            ),
          ),
        );
      },
    );
  }
}

/// The section colours of settings.css, one per person by their number, so a face keeps its colour everywhere.
const _hues = ['blue', 'purple', 'coral', 'green', 'amber', 'indigo', 'orange', 'cyan', 'rose', 'mint', 'magenta', 'slate'];

String hueFor(String address) {
  final digits = address.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
  final key = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _hues[h % _hues.length];
}

String initials(String label) {
  final words = label.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w[0])).toList();
  if (words.isEmpty) return '';
  if (words.length == 1) return words[0][0].toUpperCase();
  return (words.first[0] + words.last[0]).toUpperCase();
}

/// A person's face: their contact photo, else their initials on their colour; a group is two faces overlapped.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.people, this.size = 44});
  final List<Person> people;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (people.length > 1) {
      final small = size * 0.68;
      return SizedBox.square(
        dimension: size,
        child: Stack(children: [
          Positioned(left: 0, top: 0, child: _Face(person: people[0], size: small)),
          Positioned(right: 0, bottom: 0, child: _Ringed(size: small, child: _Face(person: people[1], size: small))),
        ]),
      );
    }
    return _Face(person: people.isEmpty ? const Person(address: '') : people.first, size: size);
  }
}

class _Ringed extends StatelessWidget {
  const _Ringed({required this.size, required this.child});
  final double size;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.tokens.color('glacier-bg'), width: 2)),
        child: child,
      );
}

class _Face extends StatelessWidget {
  const _Face({required this.person, required this.size});
  final Person person;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GlacierScope(
      attrs: {'hue': hueFor(person.address)},
      child: Builder(builder: (context) {
        final t = context.tokens;
        final letters = initials(person.name ?? '');
        final fallback = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: settingsHueWash(t)),
          alignment: Alignment.center,
          child: letters.isEmpty
              ? AppIcon(Lucide.userRound, size: size * 0.5, color: settingsHue(t))
              : Text(letters, style: pageText(t, size * 0.38, weight: 'semibold', color: settingsHue(t))),
        );
        if (person.photo == null) return fallback;
        return FutureBuilder<Uint8List?>(
          future: Sms.instance.photo(person.photo!),
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes == null) return fallback;
            return ClipOval(child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true));
          },
        );
      }),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// A conversation's time in the list: the time today, the weekday this week, else the date.
String listWhen(DateTime d, [DateTime? now]) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final ago = today.difference(day).inDays;
  if (ago <= 0) return clock(d);
  if (ago == 1) return 'Yesterday';
  if (ago < 7) return _days[d.weekday - 1];
  if (d.year == now.year) return '${_months[d.month - 1]} ${d.day}';
  return '${d.month}/${d.day}/${d.year % 100}';
}

/// The heading over a day's messages in a conversation.
String dayHeading(DateTime d, [DateTime? now]) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final ago = today.difference(day).inDays;
  if (ago <= 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  if (ago < 7) return _weekdays[d.weekday - 1];
  if (d.year == now.year) return '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Opens a page from the right, as Ghost Keyboard's settings pages do.
Future<T?> push<T>(BuildContext context, WidgetBuilder builder) => Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (context, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
          child: child,
        ),
      ),
    );

void toast(BuildContext context, String message, {GlacierToastTone tone = GlacierToastTone.neutral, GlacierToastAction? action}) {
  GlacierToast.of(context).toast(message: Text(message), tone: tone, action: action);
}

/// A sheet rising from the foot of the screen with a list of choices: a long press's menu.
Future<void> showChoices(BuildContext context, {String? title, required List<Choice> choices}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => _ChoiceSheet(title: title, choices: choices),
    transitionsBuilder: (context, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

class Choice {
  const Choice(this.label, this.icon, this.onPress, {this.danger = false});
  final String label;
  final LucideIcon icon;
  final VoidCallback onPress;
  final bool danger;
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({this.title, required this.choices});
  final String? title;
  final List<Choice> choices;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), pad.bottom + t.space(3)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.radius('xl')),
          child: ColoredBox(
            color: t.color('app-paper-2'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(t.space(4), t.space(4), t.space(4), t.space(2)),
                    child: Text(title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                  ),
                for (final c in choices)
                  GlacierPressable(
                    onPressed: () {
                      Navigator.of(context).pop();
                      c.onPress();
                    },
                    builder: (context, state) {
                      final ink = c.danger ? t.colorOf('#dd3a30') : t.color('app-ink');
                      return ColoredBox(
                        color: state.pressed ? t.color('app-paper-3') : const Color(0x00000000),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
                          child: Row(children: [
                            AppIcon(c.icon, size: 20, color: ink),
                            SizedBox(width: t.space(3)),
                            Text(c.label, style: pageText(t, t.fontSize('md'), weight: 'medium', color: ink)),
                          ]),
                        ),
                      );
                    },
                  ),
                SizedBox(height: t.space(2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
