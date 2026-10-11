import 'dart:ui' show SemanticsRole;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// Port of the web app's src/app/settings/choiceCard.module.css, with the radio group every card that composes it
/// sits in: a card that is a choice (Settings › Appearance), holding a picture of what choosing it gives. The theme
/// cards, the home page and top bar cards, the interface-size cards and the typeface cards are each a group of
/// these. The hairline, the stronger line under a pointer, the accent ring when chosen and the focus ring when the
/// card has the keyboard are here; each card's size, corner and picture are its own.
///
/// On the page each card is a `<label>` over a hidden radio, the radios sharing a name, which is what gives the
/// keyboard its manners: one Tab stop for the group, on the chosen card, and the arrow keys moving the choice round
/// the group and the focus with it. Those are kept here by hand.
///
/// What differs from the web original: Enter chooses the focused card as well as Space (`GlacierPressable` gives
/// every control both), and the left and right arrows follow the text direction.
class ChoiceCards<T> extends StatefulWidget {
  const ChoiceCards({
    super.key,
    required this.label,
    required this.values,
    required this.value,
    required this.onValueChange,
    required this.nameOf,
    required this.radius,
    required this.card,
    required this.layout,
  });

  /// `aria-label` of the group.
  final String label;
  final List<T> values;
  final T value;
  final ValueChanged<T> onValueChange;

  /// Each radio's name in words: "85%", not "0.85".
  final String Function(T value) nameOf;

  /// The card's corner (`border-radius`).
  final double radius;

  /// What a card holds, inside its hairline.
  final Widget Function(BuildContext context, T value, bool selected) card;

  /// Arranges the cards: the grid of the stylesheet that composes this one. The cards are in [values]' order.
  final Widget Function(BuildContext context, List<Widget> cards) layout;

  @override
  State<ChoiceCards<T>> createState() => _ChoiceCardsState<T>();
}

class _ChoiceCardsState<T> extends State<ChoiceCards<T>> {
  final List<FocusNode> _nodes = [];

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ChoiceCards<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _sync() {
    while (_nodes.length > widget.values.length) {
      _nodes.removeLast().dispose();
    }
    while (_nodes.length < widget.values.length) {
      final index = _nodes.length;
      _nodes.add(FocusNode(debugLabel: '${widget.label} $index', onKeyEvent: (node, event) => _onKey(index, event)));
    }
    final chosen = widget.values.indexOf(widget.value);
    for (var i = 0; i < _nodes.length; i++) {
      // Radios of one name: the group is one Tab stop, on the chosen one, or on the first while none is.
      _nodes[i].skipTraversal = i != (chosen < 0 ? 0 : chosen);
    }
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyUpEvent || index >= widget.values.length) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final int step;
    if (key == LogicalKeyboardKey.arrowDown || key == (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      step = 1;
    } else if (key == LogicalKeyboardKey.arrowUp || key == (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)) {
      step = -1;
    } else {
      return KeyEventResult.ignored;
    }
    final count = widget.values.length;
    final next = ((index + step) % count + count) % count;
    widget.onValueChange(widget.values[next]);
    _nodes[next].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hairline = t.len('glacier-hairline');
    final accent = t.color('glacier-accent-solid');
    final duration = t.reducedMotion ? Duration.zero : t.duration('glacier-duration-fast');
    final curve = t.curve('glacier-ease-out');
    final cards = <Widget>[
      for (var i = 0; i < widget.values.length; i++)
        Builder(builder: (context) {
          final value = widget.values[i];
          final selected = value == widget.value;
          return Semantics(
            container: true,
            inMutuallyExclusiveGroup: true,
            checked: selected,
            label: widget.nameOf(value),
            child: GlacierPressable(
              onPressed: () => widget.onValueChange(value),
              haptic: HapticKind.selection,
              focusNode: _nodes[i],
              excludeSemantics: true,
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                radius: widget.radius,
                child: AnimatedContainer(
                  duration: duration,
                  curve: curve,
                  // The hairline takes its own room, as a border does: the picture starts inside it.
                  decoration: BoxDecoration(
                    color: t.color('glacier-surface-raised'),
                    borderRadius: BorderRadius.circular(widget.radius),
                    // `.card:hover`, then `.card[data-selected]`, which comes after it and wins.
                    border: Border.all(
                      color: selected ? accent : t.color(state.hovered ? 'glacier-border-strong' : 'glacier-border-subtle'),
                      width: hairline,
                    ),
                    // `box-shadow: 0 0 0 1px var(--glacier-accent-solid)`
                    boxShadow: [BoxShadow(color: selected ? accent : accent.withValues(alpha: 0), spreadRadius: selected ? 1 : 0)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular((widget.radius - hairline).clamp(0, double.infinity)),
                    child: ExcludeSemantics(child: widget.card(context, value, selected)),
                  ),
                ),
              ),
            ),
          );
        }),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.radioGroup,
      label: widget.label,
      child: widget.layout(context, cards),
    );
  }
}

/// `display: grid; grid-template-columns: repeat(n, minmax(0, 1fr)); gap`: [children] in rows of [columns], every
/// card in a row as tall as the tallest of them, as a grid's row is. [leadSpan] true gives the first child a row of
/// its own (`grid-column: 1 / -1`). Every card is given its row's height, so a card may fill it ([ChoiceCardBody]).
class ChoiceGrid extends StatelessWidget {
  const ChoiceGrid({super.key, required this.columns, required this.gap, this.rowGap, this.leadSpan = false, required this.children});

  final int columns;
  final double gap;
  final double? rowGap;
  final bool leadSpan;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <List<Widget>>[];
    var rest = children;
    if (leadSpan && children.isNotEmpty) {
      rows.add([children.first]);
      rest = children.sublist(1);
    }
    for (var i = 0; i < rest.length; i += columns) {
      rows.add(rest.sublist(i, i + columns > rest.length ? rest.length : i + columns));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: rowGap ?? gap),
          if (leadSpan && r == 0)
            // Alone in its row, it is as tall as it needs: a height all the same, as every card in a grid has.
            IntrinsicHeight(child: rows[r].single)
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) SizedBox(width: gap),
                    Expanded(child: c < rows[r].length ? rows[r][c] : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// The tick in a ring at the end of a choice card's words (`.indicator`): a hairline ring, filled with the accent
/// when its card is chosen.
class ChoiceTick extends StatelessWidget {
  const ChoiceTick({super.key, required this.selected, required this.size, required this.border, required this.borderWidth, required this.tick, required this.child});

  final bool selected;

  /// The ring's side.
  final double size;

  /// The ring at rest; chosen, it is the accent.
  final Color border;
  final double borderWidth;

  /// The tick's colour when chosen; at rest it is `transparent`.
  final Color tick;

  /// The tick itself.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = t.color('glacier-accent-solid');
    return AnimatedContainer(
      duration: t.reducedMotion ? Duration.zero : t.duration('glacier-duration-fast'),
      curve: t.curve('glacier-ease-out'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? accent : accent.withValues(alpha: 0),
        border: Border.all(color: selected ? accent : border, width: borderWidth),
      ),
      child: IconTheme.merge(data: IconThemeData(color: selected ? tick : tick.withValues(alpha: 0)), child: child),
    );
  }
}

/// A choice card's two rows, a picture over its words, as the page's grid lays them out when the card is stretched
/// to its row's height (`display: grid` with two `auto` rows, which share what is left over equally): the picture
/// keeps to the top of its row, and the words are centred in theirs, so of the room to spare three quarters end up
/// above the words and a quarter below.
class ChoiceCardBody extends StatelessWidget {
  const ChoiceCardBody({super.key, required this.picture, required this.words});

  final Widget picture;
  final Widget words;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          picture,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const Spacer(flex: 3), words, const Spacer()],
            ),
          ),
        ],
      );
}
