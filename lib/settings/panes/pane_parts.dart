import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../kit/settings_kit.dart';

/// Port of `HueMark` (src/app/settings/OrganizationsPane.tsx, `.hue` in OrganizationsPane.module.css): a small round
/// of a workspace's or an organization's hue where a row's icon goes, the one its pill wears (ink.css `[data-hue]`
/// sets `--app-space`; without one it is the third ink).
///
/// What differs from the web original: it stands in the middle of a box the size of a row's glyph (1.05rem), since
/// the kit's row fits whatever it is given to that box and the round is smaller than it (0.8em).
class HueMark extends StatelessWidget {
  const HueMark({super.key, this.hue});

  /// One of the workspace hues; null is ink.
  final String? hue;

  static const Key roundKey = ValueKey<String>('hue-mark');

  @override
  Widget build(BuildContext context) => GlacierScope(
        attrs: {'hue': hue ?? 'ink'},
        child: Builder(
          builder: (context) {
            final t = context.tokens;
            // `0.8em` of the icon slot's text, which is the page's 16px whatever the interface's size.
            const side = 0.8 * 16;
            return SizedBox.square(
              dimension: t.lenOf('1.05rem'),
              child: Center(
                child: Container(
                  key: roundKey,
                  width: side,
                  height: side,
                  decoration: BoxDecoration(color: t.colorOf('var(--app-space, var(--app-ink-3))'), shape: BoxShape.circle),
                ),
              ),
            );
          },
        ),
      );
}

/// `.settingsScreen__actions` (settings.css): the words under a card that act on it, in a line that wraps, a
/// `--glacier-space-5` apart and in from the card's edge as its title is.
class PaneActions extends StatelessWidget {
  const PaneActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space(2)),
      child: DefaultTextStyle(
        style: t.textAt(t.lenOf('1rem')),
        child: Align(alignment: AlignmentDirectional.centerStart, child: Wrap(spacing: t.space(5), children: children)),
      ),
    );
  }
}

/// How long a second tap is waited for (`ARMED_MS`): a reset, a removal.
const Duration armedFor = Duration(seconds: 5);

/// A word that has to be tapped twice (DeveloperPane.tsx `ResetRow`, RecordingPane.tsx's Remove, ModelCard.tsx's):
/// the first tap arms it for five seconds and it says "Tap again", the second does it. While the doing runs it says
/// [busyWord] and cannot be pressed.
class ArmedAction extends StatefulWidget {
  const ArmedAction({super.key, required this.word, required this.busyWord, required this.onDo, this.disabled = false, this.onFailed});

  final String word;
  final String busyWord;

  /// What the second tap does; null leaves the word there and unpressable.
  final Future<void> Function()? onDo;
  final bool disabled;

  /// Told what went wrong, as words.
  final ValueChanged<String>? onFailed;

  @override
  State<ArmedAction> createState() => _ArmedActionState();
}

class _ArmedActionState extends State<ArmedAction> {
  bool _armed = false;
  bool _busy = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _press() async {
    if (!_armed) {
      setState(() => _armed = true);
      HapticsProvider.of(context)(HapticKind.warning);
      _timer?.cancel();
      _timer = Timer(armedFor, () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    _timer?.cancel();
    setState(() {
      _busy = true;
      _armed = false;
    });
    try {
      await widget.onDo!();
    } catch (failure) {
      widget.onFailed?.call(failureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => RowAction(
        onPress: () => unawaited(_press()),
        disabled: widget.disabled || _busy || widget.onDo == null,
        child: Text(_busy ? widget.busyWord : (_armed ? 'Tap again' : widget.word)),
      );
}

/// A failure as a page says it (core/failure.ts `failureText`): the words it was thrown as, or the error's own.
String failureText(Object failure) {
  if (failure is String) return failure;
  final text = failure.toString();
  return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
}
