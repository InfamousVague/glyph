/// What the screens draw of the plugins: the tabs of the list's sections, a section's row as its plugin describes
/// it, and a quiet note a plugin can put in a widget slot. Drawn by the app, in the app's own type and colours; a
/// plugin says what, in words (plugin.dart).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/svg_path.dart';
import '../kit/settings_type.dart';
import '../reactions.dart';
import '../sms.dart';
import '../ui/common.dart';
import '../ui/nav_bar.dart';
import 'companies.dart' show ghostDomain;
import 'plugin.dart';
import 'registry.dart';

/// The list's tabs, under its search field: "Messages" and each section that has conversations in it, with how
/// many, as one segmented toggle (Matt, 2026-11-14: "change the messages and codes to a segmented toggle"). They
/// were chips in a row that scrolled sideways.
///
/// A press with the other button on a tab, or a long press, asks for that tab's menu ([onMenu]; Matt, the same
/// message: "add a right click menu for the codes and messages tabs"). It is the kit's middle size (Matt, later
/// that day: "the segmented toggle for messages vs codes can be a size larger").
class SectionTabs extends StatelessWidget {
  const SectionTabs({super.key, required this.sections, required this.counts, required this.unread, required this.chosen, required this.onPick, this.onMenu});

  final List<PluginSection> sections;
  final Map<String, int> counts;

  /// The sections with something unread in them.
  final Set<String> unread;

  /// The section chosen; null is the main list.
  final String? chosen;
  final ValueChanged<String?> onPick;

  /// Asked for a tab's menu; null for the main list's.
  final ValueChanged<String?>? onMenu;

  /// What the toggle calls the main list, which the app calls null.
  static const _main = '';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final values = [_main, for (final s in sections) s.id];

    // In the toggle's own type and colour, which are the chosen tab's or a quiet one's by turns.
    Widget label(String words, {LucideIcon? icon, int? count, bool dot = false}) => Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[AppIcon(icon, size: 15, strokeWidth: 2.2, wash: false), SizedBox(width: t.space(1))],
          Flexible(child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
          if (count != null) ...[SizedBox(width: t.space(1)), Opacity(opacity: 0.6, child: Text('$count'))],
          if (dot) ...[SizedBox(width: t.space(1)), Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('#4f5bd5')))],
        ]);

    return LayoutBuilder(builder: (context, box) {
      // The tabs share the toggle's width equally, so where a press landed says which tab it was on.
      void menu(double x) {
        final at = (x / (box.maxWidth / values.length)).floor().clamp(0, values.length - 1);
        onMenu?.call(values[at] == _main ? null : values[at]);
      }

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: onMenu == null ? null : (d) => menu(d.localPosition.dx),
        onLongPressStart: onMenu == null ? null : (d) => menu(d.localPosition.dx),
        child: GlacierSegmentedControl(
          fullWidth: true,
          size: GlacierSegmentedSize.md,
          ariaLabel: 'Which conversations',
          value: chosen ?? _main,
          onValueChange: (v) => onPick(v == _main ? null : v),
          options: [
            GlacierSegmentedOption(value: _main, label: label('Messages')),
            for (final s in sections) GlacierSegmentedOption(value: s.id, label: label(s.section.label, icon: s.section.icon, count: counts[s.id] ?? 0, dot: unread.contains(s.id))),
          ],
        ),
      );
    });
  }
}

/// The button beside the list's tabs that marks every conversation of the tab shown as read (Matt, 2026-11-14:
/// "a button to mark all read"): its picture alone in a circle as tall as the tabs' toggle (Matt, later that day:
/// "change mark all as read to just be the icon in a circle button"), with its words in a tip while a pointer
/// rests on it. Quiet while nothing there is unread.
class MarkAllRead extends StatelessWidget {
  const MarkAllRead({super.key, required this.unread, required this.onPress});

  /// How many conversations of the tab shown are unread.
  final int unread;
  final VoidCallback onPress;

  /// How wide and tall it is: the tabs' toggle's height, so the two stand level.
  static double size(Tokens t) => t.len('glacier-control-height-md');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final any = unread > 0;
    final ink = t.color(any ? 'app-ink' : 'app-ink-4');
    return HoverTip(
      message: any ? 'Mark all read' : 'Nothing unread',
      below: true,
      end: true,
      child: GlacierPressable(
        onPressed: any ? onPress : null,
        semanticLabel: any ? 'Mark all read, $unread unread' : 'Mark all read, nothing unread',
        builder: (context, state) => GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('full'),
          child: Container(
            width: size(t),
            height: size(t),
            decoration: BoxDecoration(
              color: t.color(state.pressed && any ? 'app-paper-3' : 'app-paper-2'),
              shape: BoxShape.circle,
              border: Border.all(color: t.color('app-rule')),
            ),
            alignment: Alignment.center,
            child: ExcludeSemantics(child: AppIcon(Lucide.checkCheck, size: 17, strokeWidth: 2.2, wash: false, color: ink)),
          ),
        ),
      ),
    );
  }
}

/// A conversation in a section, drawn as the section's plugin describes it ([RowLook]): a card with its face and
/// name as the main list has them, then a value drawn large over the words (a code), or the words with a quiet line under them
/// saying why it is here; a button at its end and a word to press, where the look has them.
class PluginRow extends StatelessWidget {
  const PluginRow({super.key, required this.conversation, required this.look, required this.host, required this.onPress, required this.onLongPress, this.selecting = false, this.selected = false});

  final Conversation conversation;
  final RowLook look;

  /// What the look's actions are run with.
  final PluginHost host;

  /// A tap, where the look has none of its own.
  final VoidCallback onPress;
  final VoidCallback onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = conversation;
    final unread = c.unread;
    final face = t.lenOf('3rem');
    final words = (reactionSnippet(c.snippet) ?? c.snippet).replaceAll('\n', ' ');
    final value = look.value;
    final tap = look.tap;
    final quiet = pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'), height: 1.35);
    return GestureDetector(
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: GlacierPressable(
        // While several are being chosen a tap chooses, as in the main list.
        onPressed: selecting || tap == null ? onPress : () => tap.run(host),
        semanticLabel: selecting ? '${look.title ?? c.title}, ${selected ? 'selected' : 'not selected'}' : (tap == null ? null : '${look.title ?? c.title}, ${value ?? words}. ${tap.label}'),
        // A card, as the main list's rows are (ConversationRow), with the same line round the one chosen.
        builder: (context, state) => Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.lenOf('0.1875rem')),
          child: Container(
            decoration: BoxDecoration(
              color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
              borderRadius: BorderRadius.circular(t.lenOf('1rem')),
              border: Border.all(color: selected ? t.color('app-ink') : const Color(0x00000000), width: 2),
            ),
            padding: EdgeInsets.symmetric(horizontal: t.space(3) - 2, vertical: t.space(3) - 2),
            child: Row(
              children: [
                if (selecting)
                  Container(
                    width: face,
                    height: face,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? t.colorOf('#4f5bd5') : const Color(0x00000000),
                      border: Border.all(color: selected ? t.colorOf('#4f5bd5') : t.color('app-ink-4'), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: selected ? const AppIcon(Lucide.check, size: 22, strokeWidth: 2.6, wash: false, color: Color(0xFFFFFFFF)) : null,
                  )
                else if (look.face != null)
                  BrandFace(face: look.face!, size: face)
                else
                  // Named by its section (a company a code is from, read out of its words): the name's letters
                  // stand in its picture, where its number's would have said nothing.
                  Avatar(people: look.title != null && c.people.length == 1 ? [Person(address: c.people.first.address, name: look.title)] : c.people, size: face),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(look.title ?? c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize(value == null ? 'md' : 'sm'), weight: unread ? 'bold' : 'semibold', color: t.color(value == null ? 'app-ink' : 'app-ink-2')))),
                        if (unread) ...[
                          SizedBox(width: t.space(2)),
                          Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('#4f5bd5'))),
                        ],
                        SizedBox(width: t.space(2)),
                        Text(listWhen(c.date), style: pageText(t, t.fontSize('xs'), weight: unread ? 'semibold' : 'regular', color: t.color(unread ? 'app-ink' : 'app-ink-3'))),
                      ]),
                      SizedBox(height: t.lenOf('0.15rem')),
                      if (value != null) ...[
                        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('2xl'), weight: 'semibold', color: t.color('app-ink'), mono: true, tracking: 2, height: 1.2)),
                        SizedBox(height: t.lenOf('0.15rem')),
                        Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet),
                      ] else
                        Text(words, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: unread ? 'medium' : 'regular', color: t.color(unread ? 'app-ink' : 'app-ink-2'), height: 1.35)),
                      if (look.caption != null || look.word != null) ...[
                        SizedBox(height: t.lenOf('0.2rem')),
                        Row(children: [
                          if (look.caption != null) Flexible(child: Text(look.caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet)),
                          if (look.caption != null && look.word != null) Text('  ·  ', style: quiet),
                          if (look.word != null && !selecting)
                            GlacierPressable(
                              onPressed: () => look.word!.run(host),
                              semanticLabel: look.word!.label,
                              builder: (context, state) => Text(
                                look.word!.label,
                                style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color(state.pressed ? 'app-ink-3' : 'app-ink'), height: 1.35).copyWith(decoration: TextDecoration.underline),
                              ),
                            ),
                        ]),
                      ],
                    ],
                  ),
                ),
                if (look.end != null && !selecting) ...[
                  SizedBox(width: t.space(1)),
                  IconTap(icon: look.end!.icon, label: look.end!.label, size: 19, color: t.color('app-ink-2'), onPressed: () => look.end!.run(host)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet line or two for a widget slot: what a section is, over its list.
class PluginNote extends StatelessWidget {
  const PluginNote(this.words, {super.key});
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(2)),
      child: Text(words, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'), height: 1.4)),
    );
  }
}

/// A company's face on a row (plugin.dart, RowFace): a disc of its own colour with its mark on it where the app
/// has one, else its name's first letter, in white or in ink, whichever reads on that colour.
class BrandFace extends StatelessWidget {
  const BrandFace({super.key, required this.face, required this.size});
  final RowFace face;
  final double size;

  /// Whether ink reads better than white on [color] (0xRRGGBB): by how light the colour is to the eye.
  static bool inkOn(int color) {
    double part(int c) {
      final v = c / 255;
      return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final light = 0.2126 * part((color >> 16) & 0xff) + 0.7152 * part((color >> 8) & 0xff) + 0.0722 * part(color & 0xff);
    return light > 0.5;
  }

  /// How much of the disc's width a mark's square takes. A company's name written out ("coinbase", "DISCOVER") is
  /// wide and low and can run nearly the disc's width; a badge that fills its square has to stay inside the round.
  static double markShare(String mark) {
    final box = svgPath(mark).getBounds();
    return box.height < box.width * 0.5 ? 0.78 : 0.56;
  }

  /// The letter that stands for [name]: its first letter or figure.
  static String letterOf(String name) {
    final m = RegExp('[A-Za-z0-9]').firstMatch(name);
    return m == null ? '?' : m.group(0)!.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = Color(0xFF000000 | face.color);
    return Semantics(
      label: face.name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: t.color('app-rule'), width: 1)),
        alignment: Alignment.center,
        // Our own codes wear the app's ghost, white on black, as the icon on the home screen has it.
        child: face.domain == ghostDomain
            ? Image.asset('assets/art/ghost-mark.png', width: size * 0.62, height: size * 0.62, filterQuality: FilterQuality.medium)
            : face.mark != null
            ? CustomPaint(size: Size.square(size * markShare(face.mark!)), painter: _MarkPainter(face.mark!, inkOn(face.color) ? const Color(0xFF111111) : const Color(0xFFFFFFFF)))
            : Text(
                letterOf(face.name),
                style: pageText(t, size * 0.44, weight: 'bold', color: inkOn(face.color) ? const Color(0xFF111111) : const Color(0xFFFFFFFF), height: 1),
              ),
      ),
    );
  }
}

/// A company's mark: one filled path on a 24 by 24 square, drawn to fit.
class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.mark, this.color);
  final String mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(svgPath(mark), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.mark != mark || old.color != color;
}
