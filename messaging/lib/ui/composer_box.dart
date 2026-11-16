import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show TextCapitalization, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../kit/settings_type.dart';

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
        decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.lenOf('1.375rem'))),
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
class ComposerField extends StatelessWidget {
  const ComposerField({super.key, required this.controller, required this.focusNode, required this.hint, required this.onSubmitted, this.enterSends = false});
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmitted;
  final bool enterSends;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = composerTextStyle(t);
    final strut = composerStrutStyle(t);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: focusNode.requestFocus,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: t.lenOf('2.25rem')),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: t.lenOf('0.3rem')),
            child: Stack(children: [
              if (controller.text.isEmpty) IgnorePointer(child: Text(hint, style: style.copyWith(color: t.color('app-ink-3')), strutStyle: strut, textHeightBehavior: composerLeading)),
              EditableText(
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
                onSubmitted: (_) => onSubmitted(),
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
