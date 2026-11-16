import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show TextCapitalization, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../kit/settings_type.dart';
import '../backgrounds.dart' show lookCorner, lookRim;
import 'dialup/dialup.dart';

/// The box a message is written in, everywhere one is: a conversation of texts (lib/ui/thread.dart) and a chat on
/// Telegram or Bluesky (lib/ui/inbox_ui.dart), so the two read and work the same (Matt, 2026-11-15: "Also use the
/// same composer for telegram").
///
/// Empty, [plus] sits at its start and [ends] at its end, on the words' line; once there are words ([typing]) they
/// take the whole width and the buttons go to a row under them: [plus] at its start, [below] at its end (Matt,
/// 2026-11-15: "Put the plus symbol inside thr compose input and animate them below when typijg just like this
/// screenshot").
///
/// The buttons are held to the box's bottom corners, and the box grows by a row under the words, so they travel
/// straight down with it and back up (Matt, 2026-11-15: "the buttons don't slide straight down they move out
/// first"); the words' room widens to the box's edges as they go. [field] keeps its place in the tree throughout,
/// so the keyboard stays up.
class ComposerBox extends StatefulWidget {
  const ComposerBox({super.key, required this.field, required this.typing, this.plus, this.ends = const [], this.below = const []});
  final Widget field;
  final bool typing;
  final Widget? plus;
  final List<Widget> ends;
  final List<Widget> below;

  static const move = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  @override
  State<ComposerBox> createState() => _ComposerBoxState();
}

class _ComposerBoxState extends State<ComposerBox> {
  /// How wide the buttons beside the words are, as last laid out: the room the words leave them on one line.
  double _plusWidth = 0, _endsWidth = 0;

  void _measured(bool plus, Size size) {
    final w = size.width;
    if (plus ? _plusWidth == w : _endsWidth == w) return;
    // Told during layout: taken up for the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => plus ? _plusWidth = w : _endsWidth = w);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (isBevelChrome(t)) return _dialup(context, t);
    final typing = widget.typing;
    final plus = widget.plus;
    final row = t.lenOf('2.25rem');
    final gap = t.space(1);
    final words = t.space(3);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space(1)),
      child: Container(
        constraints: BoxConstraints(minHeight: t.lenOf('2.75rem')),
        padding: EdgeInsets.all(t.lenOf('0.25rem')),
        // Its corners under the look's radius scale, and a rule round it where the look draws them (Sharp's paper-2
        // field on white was 1.2:1 and all but vanished beside its ruled search field).
        decoration: BoxDecoration(color: t.color('app-paper-2'), border: lookRim(t), borderRadius: BorderRadius.circular(lookCorner(t, '1.375rem', most: 1))),
        child: Stack(children: [
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AnimatedPadding(
              duration: ComposerBox.move,
              curve: ComposerBox.curve,
              padding: EdgeInsets.only(
                left: typing || plus == null ? words : _plusWidth + gap,
                right: typing || widget.ends.isEmpty ? words : _endsWidth,
              ),
              child: widget.field,
            ),
            // The row the buttons come down into.
            AnimatedContainer(duration: ComposerBox.move, curve: ComposerBox.curve, height: typing ? row + gap : 0),
          ]),
          if (plus != null) Positioned(left: 0, bottom: 0, child: _Measure(onSize: (s) => _measured(true, s), child: plus)),
          Positioned(
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: ComposerBox.move,
              // The buttons going fade out in the first half and the ones coming in fade in over the second, so the
              // two sets are never drawn over each other.
              switchInCurve: const Interval(0.5, 1, curve: Curves.easeOut),
              switchOutCurve: const Interval(0.5, 1, curve: Curves.easeIn),
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomRight, children: [...previous, ?current]),
              child: typing
                  ? Row(key: const ValueKey('below'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: widget.below)
                  : _Measure(
                      key: const ValueKey('ends'),
                      onSize: (s) => _measured(false, s),
                      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: widget.ends),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

extension on _ComposerBoxState {
  /// Dial-Up's composer, on the silver panel along the page's foot (GhostPage): one raised + at the left in place of
  /// a toolbar row (the design's critique: "Drop the toolbar row by default and put one '+' RetroButton left of the
  /// field"), a white box sunk into the panel that is never under 44 high and grows with the words, and the buttons
  /// at its right, raised, Send among them with its word on it (IconTap draws it so). Nothing moves: what is at the
  /// right is what [ComposerBox.ends] or, once there are words, [ComposerBox.below] holds, at once. The field keeps
  /// its place by its key, so the keyboard stays up as the buttons change.
  Widget _dialup(BuildContext context, Tokens t) {
    final gap = SizedBox(width: t.space(1));
    final plus = widget.plus;
    final end = widget.typing ? widget.below : widget.ends;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space(1)),
      child: RetroIcons(
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (plus != null) ...[plus, gap],
          Expanded(
            key: const ValueKey('composer-field'),
            child: Padding(
              // On the buttons' line: they are 48 to the finger, their faces 40 inside that, the box 44.
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Sunken(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(alignment: Alignment.centerLeft, child: widget.field),
                ),
              ),
            ),
          ),
          for (final b in end) ...[if (b is! SizedBox) gap, b],
        ]),
      ),
    );
  }
}

/// Says the size its child was laid out at.
class _Measure extends SingleChildRenderObjectWidget {
  const _Measure({super.key, required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasure renderObject) => renderObject.onSize = onSize;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onSize);
  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}

/// The words' line of a [ComposerBox]: [hint] while it is empty, the words centred on the buttons' middle.
TextStyle composerTextStyle(Tokens t) => pageText(t, t.fontSize('md'), color: t.color('app-ink'), height: 1.3);
StrutStyle composerStrutStyle(Tokens t) => StrutStyle.fromTextStyle(composerTextStyle(t), forceStrutHeight: true, leadingDistribution: TextLeadingDistribution.even);
const composerLeading = TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even);

/// The words' line of a [ComposerBox] where nothing more is wanted of it (a Telegram chat, a space's chat): the words,
/// [hint] while there are none, and Enter as Settings › Messages › Enter sends says. A conversation of texts has its
/// own, with more in it (lib/ui/thread.dart).
class ComposerField extends StatefulWidget {
  const ComposerField({super.key, required this.controller, required this.focusNode, required this.hint, required this.onSubmitted, this.enterSends = false});
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmitted;
  final bool enterSends;

  @override
  State<ComposerField> createState() => _ComposerFieldState();
}

/// The keyboard is asked for on a press, and again on coming back to the app with the cursor in the field: Android hides
/// it on leaving while the field keeps its focus, and asking for focus it has does nothing (Matt, 2026-11-16: "Tabbing
/// out and into thr app doesnt clear the focus on the signal convo so the keyboard can't be toggled open").
class _ComposerFieldState extends State<ComposerField> with WidgetsBindingObserver {
  final _field = GlobalKey<EditableTextState>();
  Offset? _down;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _field.currentState?.requestKeyboard());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = composerTextStyle(t);
    final strut = composerStrutStyle(t);
    final controller = widget.controller, focusNode = widget.focusNode, hint = widget.hint, enterSends = widget.enterSends;
    // A finger down and up close by (a tap gesture here loses to the field's own).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _down = e.position,
      onPointerUp: (e) {
        final down = _down;
        _down = null;
        if (down == null || (e.position - down).distance >= 18) return;
        focusNode.requestFocus();
        _field.currentState?.requestKeyboard();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: t.lenOf('2.25rem')),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: t.lenOf('0.3rem')),
            child: Stack(children: [
              if (controller.text.isEmpty) IgnorePointer(child: Text(hint, style: style.copyWith(color: t.color('app-ink-3')), strutStyle: strut, textHeightBehavior: composerLeading)),
              EditableText(
                key: _field,
                controller: controller,
                focusNode: focusNode,
                style: style,
                strutStyle: strut,
                textHeightBehavior: composerLeading,
                cursorColor: t.color('app-ink'),
                backgroundCursorColor: t.color('app-ink-3'),
                minLines: 1,
                maxLines: 6,
                keyboardType: enterSends ? TextInputType.text : TextInputType.multiline,
                textInputAction: enterSends ? TextInputAction.send : TextInputAction.newline,
                onSubmitted: (_) => widget.onSubmitted(),
                onEditingComplete: enterSends ? () {} : null,
                textCapitalization: TextCapitalization.sentences,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
