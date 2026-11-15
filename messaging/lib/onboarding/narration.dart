/// What the walkthrough says on each page (lib/onboarding/onboarding.dart): shown as the page's words, and spoken
/// aloud in a friendly voice where the app can play it. The voice is ElevenLabs', made once at build time by
/// tool/onboarding_voice.py from these very lines (one a line, in single quotes, as the tool reads them), and kept as
/// `assets/onboarding/<page>.mp3`. Change a line, run the tool, and that page alone is spoken again.
library;

const Map<String, String> narration = {
  'welcome': 'Hi, and welcome to Ghost Messaging. It\'s your texts and picture messages, in a calm, simple place, with a few things texting has always been missing.',
  'texts': 'First, let\'s bring your texts here. Android lets one app send and keep them, so make Ghost your texting app. Or, if you\'d rather keep Google Messages, Ghost can work right beside it. Either way, nothing is deleted.',
  'people': 'Next, names and notifications. Let Ghost see your contacts, so you see names and faces instead of numbers. And allow notifications, so you can reply right from them, without opening the app.',
  'private': 'When the person you\'re texting has Ghost too, your messages can be encrypted, so only your two phones can read them. Look for the lock. Everyone else still gets an ordinary text.',
  'sorted': 'Ghost keeps things tidy. Codes from banks and apps get a tab of their own, ready to copy. Sales texts are set aside, and the ones that need a reply are easy to find.',
  'calls': 'Every group has a voice channel you can drop in and out of, any time. Share a link, and anyone can join a hangout from their browser. Turn on video whenever you like.',
  'computer': 'Ghost is on your Mac and your Windows computer, too. Open it there, scan the code with this phone, and your conversations follow you, sent from your own number.',
  'look': 'Pick a look. Light, dark, or follow your phone. Then choose a colour for your bubbles.',
  'start': 'That\'s the tour, and you\'re ready. Everything you\'ve seen is in Settings, whenever you want it. Happy texting.',
};

/// Where a page's voice is kept.
String narrationAsset(String page) => 'assets/onboarding/$page.mp3';
