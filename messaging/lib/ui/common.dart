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
    // Beside the list (lib/ui/shell.dart) there is nowhere to go back to: the list is there to be seen.
    final back = this.back && !PaneRoot.beside(context);
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
          const HeaderEnd(),
          Expanded(child: body),
          if (footer != null) Padding(padding: EdgeInsets.only(bottom: inset > 0 ? inset : pad.bottom), child: footer!),
        ],
      ),
    );
  }
}

/// Something is being fetched: an arc going round, in the page's ink. Still under Android's "Remove animations".
class GhostSpinner extends StatefulWidget {
  const GhostSpinner({super.key, this.size = 22, this.label});
  final double size;

  /// What is being waited for, said under it.
  final String? label;

  @override
  State<GhostSpinner> createState() => _GhostSpinnerState();
}

class _GhostSpinnerState extends State<GhostSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.disableAnimationsOf(context) ? _turn.stop() : _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final arc = RotationTransition(
      turns: _turn,
      child: CustomPaint(size: Size.square(widget.size), painter: _ArcPainter(t.color('app-ink-2'), t.color('app-rule'))),
    );
    return Semantics(
      label: widget.label ?? 'Loading',
      liveRegion: true,
      child: ExcludeSemantics(
        child: widget.label == null
            ? arc
            : Column(mainAxisSize: MainAxisSize.min, children: [
                arc,
                SizedBox(height: t.space(3)),
                Text(widget.label!, textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
              ]),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.ink, this.track);
  final Color ink;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.12;
    final rect = Offset.zero & size;
    final box = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(box, 0, 6.2832, false, paint..color = track);
    canvas.drawArc(box, -1.5708, 1.9, false, paint..color = ink);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.ink != ink || old.track != track;
}

/// A round icon button, the kit's press and focus ring round it.
/// Round the page a wide window shows beside the list of conversations (lib/ui/shell.dart): a conversation, a new
/// message, Settings. [beside] is whether the list is there to be seen, in which case the page draws no way back
/// (GhostPage). A page opened from that one is not under this, and keeps its way back.
class PaneRoot extends InheritedWidget {
  const PaneRoot({super.key, required this.isBeside, required super.child});
  final bool isBeside;

  static bool beside(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PaneRoot>()?.isBeside ?? false;

  @override
  bool updateShouldNotify(PaneRoot old) => old.isBeside != isBeside;
}

/// Round a page that another has been laid over without leaving its place: the list of conversations under the
/// one opened on a narrow screen (lib/ui/shell.dart). Its header no longer says where the update banner hangs.
class HeaderCover extends InheritedWidget {
  const HeaderCover({super.key, required this.covered, required super.child});
  final bool covered;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HeaderCover>()?.covered ?? false;

  @override
  bool updateShouldNotify(HeaderCover old) => old.covered != covered;
}

/// Round a page that stands in a column of the window, not the whole of it: the list of conversations beside a
/// pane (lib/ui/shell.dart). What hangs under that page's header (the update banner) is as wide as the column.
class HeaderColumn extends InheritedWidget {
  const HeaderColumn({super.key, required this.left, required this.width, required super.child});
  final double left;
  final double width;

  @override
  bool updateShouldNotify(HeaderColumn old) => old.left != left || old.width != width;
}

/// Where a page's header ends: a mark of no size that a page puts under its header (GhostPage puts one under its
/// title; the list of conversations puts another under its search field). The update banner hangs just below the
/// lowest one on the page in front, so it is over the page's content and never over its header.
class HeaderEnd extends StatefulWidget {
  const HeaderEnd({super.key});

  static final _marks = <_HeaderEndState>{};

  /// Told whenever a mark comes, goes, or its page comes to the front or leaves it.
  static final changed = ValueNotifier<int>(0);

  /// Where the header of the page in front ends: the lowest such mark, as a line across the screen at its height.
  /// It runs the window's width (a width without end), unless its page stands in a column of the window
  /// ([HeaderColumn]: the list beside a pane), and then it is that column's. Beside a pane the list's mark is the
  /// lowest, its search field being under its title. Null where no page has said.
  static Rect? lowestRect() {
    Rect? found;
    for (final mark in _marks) {
      if (!mark.mounted || mark._covered || !(mark._route?.isCurrent ?? true)) continue;
      final box = mark.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (found == null || y > found.top) found = Rect.fromLTWH(mark._column?.left ?? 0, y, mark._column?.width ?? double.infinity, 0);
    }
    return found;
  }

  /// How far down the screen the header of the page in front ends, or null where no page has said.
  static double? lowest() => lowestRect()?.top;

  @override
  State<HeaderEnd> createState() => _HeaderEndState();
}

class _HeaderEndState extends State<HeaderEnd> {
  ModalRoute<dynamic>? _route;
  bool _covered = false;
  HeaderColumn? _column;

  void _say() => WidgetsBinding.instance.addPostFrameCallback((_) => HeaderEnd.changed.value++);

  @override
  void initState() {
    super.initState();
    HeaderEnd._marks.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The page coming to the front or leaving it is a change of this, and so is its arriving.
    _route = ModalRoute.of(context);
    _covered = HeaderCover.of(context);
    _column = context.dependOnInheritedWidgetOfExactType<HeaderColumn>();
    _say();
  }

  @override
  void dispose() {
    HeaderEnd._marks.remove(this);
    _say();
    super.dispose();
  }

  // Told when it has moved up or down the screen (a row of chips came in over it, a line of words went): what
  // hangs under it follows.
  @override
  Widget build(BuildContext context) => _HeaderMark(onMoved: _say);
}

/// A line of no height that says when it has been drawn somewhere else down the screen than last time.
class _HeaderMark extends LeafRenderObjectWidget {
  const _HeaderMark({required this.onMoved});
  final VoidCallback onMoved;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeaderMark(onMoved);

  @override
  void updateRenderObject(BuildContext context, _RenderHeaderMark mark) => mark.onMoved = onMoved;
}

class _RenderHeaderMark extends RenderBox {
  _RenderHeaderMark(this.onMoved);
  VoidCallback onMoved;
  double? _y;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => Size(constraints.hasBoundedWidth ? constraints.maxWidth : 0, 0);

  @override
  void paint(PaintingContext context, Offset offset) {
    // How far down the screen, which a page sliding in from the side does not change.
    final y = localToGlobal(Offset.zero).dy;
    if (y != _y) {
      _y = y;
      onMoved();
    }
  }
}

/// The app's logo: the white ghost that is a speech bubble, on black, as the icon on the home screen has it
/// (assets/art/ghost-mark.png, cut from the icon by tool/app_icon.py). Black in either theme, since the mark is white.
class GhostLogo extends StatelessWidget {
  const GhostLogo({super.key, this.size});

  /// Its side; 2.75rem where not said, which fills the box an empty screen gives its picture.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = size ?? t.lenOf('2.75rem');
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(color: const Color(0xFF000000), borderRadius: BorderRadius.circular(side * 0.27), border: Border.all(color: t.color('app-rule'))),
      alignment: Alignment.center,
      child: Image.asset('assets/art/ghost-mark.png', width: side * 0.64, height: side * 0.64, filterQuality: FilterQuality.medium),
    );
  }
}

class IconTap extends StatelessWidget {
  const IconTap({super.key, required this.icon, required this.label, required this.onPressed, this.size = 20, this.color, this.filled = false, this.box});

  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  /// Ink-filled disc with the icon in paper: the one main action on a screen (Send).
  final bool filled;

  /// The button's side; 2.75rem (a full touch target) by default.
  final double? box;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final box = this.box ?? t.lenOf('2.75rem');
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
Future<void> showChoices(BuildContext context, {String? title, Widget? header, required List<Choice> choices}) {
  // On the app's outermost navigator, over everything: asked for from the list, whose own navigator stands under the
  // navigation pill, the sheet's last choices were behind the pill and could not be pressed (Matt, 2026-11-14: "the
  // context menu ... opens behind the navbar so you can't click delete").
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => _ChoiceSheet(title: title, header: header, choices: choices),
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
  const _ChoiceSheet({this.title, this.header, required this.choices});
  final String? title;
  final Widget? header;
  final List<Choice> choices;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), pad.bottom + t.space(3)),
        // A sheet's width, where the window is wider than a phone: not a band across the whole of it.
        // And no taller than the screen: a long list of choices scrolls inside the sheet.
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: t.lenOf('30rem'), maxHeight: MediaQuery.sizeOf(context).height - pad.top - pad.bottom - t.space(8)), child: ClipRRect(
          borderRadius: BorderRadius.circular(t.radius('xl')),
          child: ColoredBox(
            color: t.color('app-paper-2'),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(t.space(4), t.space(4), t.space(4), t.space(2)),
                    // A message's own words are cut short by whoever asks; what a sheet explains is said whole.
                    child: Text(title!, maxLines: 14, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'), height: 1.4)),
                  ),
                ?header,
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
            )),
          ),
        )),
      ),
    );
  }
}
