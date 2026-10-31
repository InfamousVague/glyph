/// A ticket's labels drawn as coloured chips (lib/tickets/labels.dart says which colour), and its component as a
/// quiet one: on a board's card, a list's row, a table's cell, the ticket's panel, My tickets and Triage, so a label
/// wears one colour wherever it is seen.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../home/home_text.dart' show pageText;
import '../labels.dart';

/// One label: its words in its hue's ink on its hue's wash, rounded right off.
class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.label, required this.hue, this.size, this.strong = false});

  final String label;

  /// One of [labelHues].
  final String hue;

  /// The type it stands in; the kit's extra small where none is given.
  final double? size;

  /// Drawn with a ring of its ink: a label chosen in a picker.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final px = size ?? t.fontSize('xs');
    final ink = t.color('glacier-$hue-11');
    return Semantics(
      label: 'Label $label',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('label-chip-$label'),
        padding: EdgeInsets.symmetric(horizontal: 0.5 * px, vertical: 0.08 * px),
        decoration: BoxDecoration(
          color: t.color('glacier-$hue-3'),
          border: strong ? Border.all(color: ink, width: t.len('glacier-hairline')) : null,
          borderRadius: BorderRadius.circular(px),
        ),
        child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, px, weight: 'medium', color: ink, height: 1.35)),
      ),
    );
  }
}

/// A dot of a label's colour: a picker's mark for it.
class LabelDot extends StatelessWidget {
  const LabelDot({super.key, required this.hue, this.size = 10});

  final String hue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('glacier-$hue-9')));
  }
}

/// A ticket's component, quieter than a label: its words on a plain ground with a rule round them.
class ComponentChip extends StatelessWidget {
  const ComponentChip({super.key, required this.component, this.size});

  final String component;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final px = size ?? t.fontSize('xs');
    return Semantics(
      label: 'Component $component',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 0.45 * px, vertical: 0.08 * px),
        decoration: BoxDecoration(border: Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline')), borderRadius: BorderRadius.circular(0.3 * px)),
        child: Text(component, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, px, color: t.color('app-ink-2'), height: 1.35)),
      ),
    );
  }
}

/// A ticket's labels side by side, wrapping, each in its colour by [colours] (its notebook's `label-colours:`).
class LabelChips extends StatelessWidget {
  const LabelChips({super.key, required this.labels, this.colours = const {}, this.component, this.size});

  final List<String> labels;
  final Map<String, String> colours;
  final String? component;
  final double? size;

  /// Whether there is anything to draw.
  static bool has(List<String> labels, String? component) => labels.isNotEmpty || (component != null && component.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: t.space(1),
      runSpacing: t.space(1),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (component != null && component!.isNotEmpty) ComponentChip(component: component!, size: size),
        for (final label in labels) LabelChip(label: label, hue: labelHue(label, colours), size: size),
      ],
    );
  }
}
