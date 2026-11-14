/// What the screens draw of the plugins: the chips of the list's sections, a section's row as its plugin describes
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
import 'plugin.dart';
import 'registry.dart';

/// The sections of the list, under its search field: "Messages" and a chip for each section that has conversations
/// in it, with how many. The one chosen is in ink. It scrolls sideways where the chips are wider than the list.
class SectionChips extends StatelessWidget {
  const SectionChips({super.key, required this.sections, required this.counts, required this.unread, required this.chosen, required this.onPick});

  final List<PluginSection> sections;
  final Map<String, int> counts;

  /// The sections with something unread in them.
  final Set<String> unread;

  /// The section chosen; null is the main list.
  final String? chosen;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: t.lenOf('2.5rem'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // From the search field's edge, which is the cards' edge too.
        padding: EdgeInsets.fromLTRB(t.space(2), 0, t.space(2), t.space(2)),
        child: Row(children: [
          _Chip(label: 'Messages', chosen: chosen == null, onPress: () => onPick(null)),
          for (final s in sections) ...[
            SizedBox(width: t.space(2)),
            _Chip(label: s.section.label, icon: s.section.icon, count: counts[s.id] ?? 0, unread: unread.contains(s.id), chosen: chosen == s.id, onPress: () => onPick(s.id)),
          ],
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.chosen, required this.onPress, this.icon, this.count, this.unread = false});
  final String label;
  final LucideIcon? icon;
  final int? count;
  final bool unread;
  final bool chosen;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color(chosen ? 'app-paper' : 'app-ink-2');
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: '$label${count == null ? '' : ', $count'}${chosen ? ', chosen' : ''}',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('full'),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space(3)),
          decoration: BoxDecoration(
            color: chosen ? t.color('app-ink') : t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
            borderRadius: BorderRadius.circular(t.radius('full')),
            border: Border.all(color: chosen ? t.color('app-ink') : t.color('app-rule')),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[AppIcon(icon!, size: 14, strokeWidth: 2.2, wash: false, color: ink), SizedBox(width: t.space(1))],
              Text(label, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: ink)),
              if (count != null) ...[
                SizedBox(width: t.space(1)),
                Text('$count', style: pageText(t, t.fontSize('sm'), color: chosen ? ink : t.color('app-ink-3'))),
              ],
              if (unread) ...[
                SizedBox(width: t.space(1)),
                Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('#4f5bd5'))),
              ],
            ]),
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
        child: face.mark != null
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
