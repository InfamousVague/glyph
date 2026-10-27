/// The walkthrough's last page. A port of `src/app/guide/pages/Start.tsx`, with `.learn` of `Guide.module.css`.
///
/// The walkthrough has said what Ghost.md is, a section a page, and hands over: everything else, the marks, the
/// words you can say, boards, canvases, journals, is the Academy's, short lessons inside the app, so this page offers
/// it and otherwise gets out of the way. Start, in the dock, closes the guide.
///
/// Since 2026-10-27 (Matt: "build an onboarding flow with vivid colors and iconography") it is "You're ready", with
/// the ghost seeing the person off in the band above it, and it asks the one thing the walkthrough asked first
/// before: light or dark, the last choice before writing.
///
/// What differs: the picture is the band's (band.dart), and the theme row is new.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app/widgets.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/preferences.dart';
import '../narration.dart';
import '../pages.dart';
import 'parts.dart';
import 'theme.dart';

class GuideStart extends StatelessWidget {
  const GuideStart({super.key, required this.onAcademy, this.store});

  /// The page's other way out: the Academy, for the rest.
  final VoidCallback onAcademy;

  /// The preferences the theme row sets; the app's own when null.
  final ValueNotifier<Preferences>? store;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const GuideTitle('You’re ready.'),
        GuideLead(narration[GuidePage.start]!),
        GuideThemeChoices(store: store),
        Padding(
          padding: EdgeInsets.only(top: t.space(6)),
          child: AppPill(onPressed: onAcademy, icon: AppIcon(Lucide.graduationCap, size: 18, strokeWidth: 2.2, color: t.color('app-paper')), child: const Text('Take the Ghost.md Academy')),
        ),
      ],
    );
  }
}
