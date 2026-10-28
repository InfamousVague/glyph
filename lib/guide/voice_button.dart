/// The speaker that switches a voice-over off and on: the walkthrough's (guide.dart) and the Academy's
/// (lib/academy/academy_screen.dart), one switch for both, remembered on the device (narrator.dart [guideMutedKey]).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';

/// The speaker in a bar: the voice on, or crossed out and off. Remembered on the device (narrator.dart).
class VoiceButton extends StatelessWidget {
  const VoiceButton({super.key, required this.off, required this.onPressed, this.side, this.icon = 24});
  final bool off;
  final VoidCallback onPressed;

  /// The square it can be pressed in; the bar's own action size, `--glacier-space-12`, unless told.
  final double? side;

  /// The speaker's own size.
  final double icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      toggled: !off,
      label: 'Read aloud',
      excludeSemantics: true,
      onTap: onPressed,
      child: GlacierPressable(
        onPressed: onPressed,
        builder: (context, state) {
          final ink = state.pressed ? t.color('glacier-text') : t.color('glacier-text-muted');
          return GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('sm'),
            child: SizedBox.square(
              dimension: side ?? t.space(12),
              child: Center(
                child: SizedBox.square(
                  dimension: icon,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AppIcon(Lucide.volume2, size: icon, strokeWidth: 2.2, color: ink),
                      // Off is the speaker struck through, edged in the page's ground so the stroke reads over it.
                      if (off)
                        Transform.rotate(
                          angle: math.pi / 4,
                          child: Container(
                            width: 3,
                            height: icon * 1.25,
                            decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(2), border: Border.symmetric(vertical: BorderSide(color: t.color('glacier-bg'), width: 0.8))),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
