/// Lovart's mark at the bottom right of a picture Lovart made (Matt, 2026-10-26: "please also include the lovart logo
/// on the bottom right of generated images"). A picture is Lovart's by its name, `lovart-<id>.png`
/// (lib/plugins/lovart/keep.dart), so the mark is drawn wherever the note is read, on a device with the plugin off or
/// none of its keys: in the editor's figures (images.dart [KeptPicture]), a note embedded in another, and a picture
/// card on a canvas.
///
/// The mark sits on a small dark ground, white, a hair of light round its edge, so it reads on a white sketch and on a
/// night photograph alike; inset from the corner by [lovartBadgeInset].
library;

import 'package:flutter/widgets.dart';

import '../../plugins/lovart/keep.dart' show madeByLovart;
import '../../plugins/lovart/lovart_mark.dart';

/// The badge's side, and how far it stands in from the picture's corner.
const double lovartBadgeSize = 20;
const double lovartBadgeInset = 8;

/// The mark on its ground, "Made with Lovart" to a screen reader.
class LovartBadge extends StatelessWidget {
  const LovartBadge({super.key, this.size = lovartBadgeSize});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Made with Lovart',
      image: true,
      child: Container(
        key: const ValueKey<String>('lovart-badge'),
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.15),
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: const Color(0x40FFFFFF), width: 0.5),
        ),
        child: LovartMark(size: size * 0.7, color: const Color(0xFFFFFFFF)),
      ),
    );
  }
}

/// [child], a picture named [name], with the badge on its corner where Lovart made it; [child] alone otherwise.
class LovartBadged extends StatelessWidget {
  const LovartBadged({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!madeByLovart(name)) return child;
    // Passed through, so the picture is laid out as it would be alone.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        const Positioned(right: lovartBadgeInset, bottom: lovartBadgeInset, child: LovartBadge()),
      ],
    );
  }
}
