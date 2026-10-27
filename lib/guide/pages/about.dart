/// The walkthrough's pages that only say something: speaking a note, meetings, the AI, sync and privacy, and the
/// Market (Matt, 2026-10-27: "build an onboarding flow with vivid colors and iconography as well as a friendly
/// elevenlabs v4 voice explaining each section"). Each is a headline and the words the voice says, shown as they are
/// said (narration.dart); the colour and the pictures are the band's above or beside it (band.dart).
///
/// Nothing is asked here and nothing is switched on: each page names where the thing lives, and the app has it there.
library;

import 'package:flutter/widgets.dart';

import '../narration.dart';
import '../pages.dart';
import 'parts.dart';

/// Each saying page's headline: short, the promise in a few words.
const Map<GuidePage, String> aboutTitles = {
  GuidePage.speak: 'Say it, and it’s written.',
  GuidePage.meetings: 'Ghost joins your meetings.',
  GuidePage.ai: 'An AI that stays with you.',
  GuidePage.sync: 'Yours, on every device.',
  GuidePage.market: 'Make it yours.',
};

class GuideAbout extends StatelessWidget {
  const GuideAbout({super.key, required this.page});
  final GuidePage page;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [GuideTitle(aboutTitles[page]!), GuideLead(narration[page]!)],
  );
}
