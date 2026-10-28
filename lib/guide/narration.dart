/// What the walkthrough says aloud, page by page, and the same words on the page as its captions (Matt, 2026-10-27:
/// "build an onboarding flow with vivid colors and iconography as well as a friendly elevenlabs v4 voice explaining
/// each section").
///
/// This file is the one place the words live. The page shows each one under its title, and
/// tool/onboarding_voice.py reads them from here, has ElevenLabs say them, and writes `assets/onboarding/<page>.mp3`
/// with a line in assets/onboarding/narration.json saying which words each file says. The voice is made once, at
/// build time, and shipped: a new person needs no key and no network to hear it. A script changed here and not
/// spoken again fails test/guide/narration_test.dart, so the voice and the captions cannot drift apart.
///
/// Keep each entry on one line, in single quotes, with typographic quotes and apostrophes inside (“ ” ’): that is
/// what the tool reads.
library;

import 'pages.dart';

/// Each page's words, said and shown.
const Map<GuidePage, String> narration = {
  GuidePage.welcome: 'Hi, and welcome. Ghost is a home for your notes, written in plain Markdown. They’re ordinary files, kept on your own devices, and they’re yours.',
  GuidePage.speak: 'Tap the microphone and talk. On a phone, you can hold the side key, too. Ghost writes it down as you speak. Say “bullet point” for a list, or “add bread to Groceries”, and it lands in that note.',
  GuidePage.meetings: 'Invite Ghost to a Google Meet or a Zoom call, and it joins by itself. It listens, and afterwards a write-up lands in your notes: what was said, what was decided, and what happens next.',
  GuidePage.ai: 'There’s an AI built in, and it runs on your own device. It tidies what you said, names your notes, and answers questions about them, without sending them anywhere. When you want more, connect Claude.',
  GuidePage.sync: 'Sign in, and your notes follow you to every device. They’re encrypted before they leave, so only your devices can read them. Start an organization to share notes with your team, with the same lock on every one.',
  GuidePage.market: 'The Market has plugins, themes, fonts and icon packs, all built in. Adding one is a switch, and so is taking it away. Make Ghost look and work the way you like.',
  GuidePage.mode: 'Now, how much of it would you like? Simple keeps to notes, lists and to-dos, with the rest behind More. Advanced is the whole app from day one. You can change this any time in Settings.',
  GuidePage.model: 'Pick the model the AI runs on this device. A bigger one is more careful, and slower. Whichever you choose, nothing leaves your device.',
  GuidePage.start: 'That’s the tour, and you’re ready. Pick a look below, then start writing. The Academy has short lessons on everything else, whenever you want them.',
};

/// Where [page]'s voice is in the app's assets.
String narrationAsset(GuidePage page) => 'assets/onboarding/${page.name}.mp3';
