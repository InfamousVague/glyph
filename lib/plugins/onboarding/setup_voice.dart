/// What each plugin's setup says, step by step (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-28: "For each of
/// the plugins add a small onboarding flow"): the words under each step's title, shown as its captions, and the words a
/// voice would read aloud.
///
/// This file is the one place they live, as lib/guide/narration.dart is the walkthrough's and lib/academy/voice.dart
/// the Academy's. There is no voice yet: the steps are read, not heard. tool/plugin_setup_voice.py is ready to make one
/// with the walkthrough's tool (tool/onboarding_voice.py: Eleven v4, the Jessica voice, mono at 64 kbps), reading the
/// entries here and writing `assets/plugin-setup/<name>.mp3` ([setupVoiceAsset]) with a narration.json beside them.
/// Until it is run, and the folder added to pubspec.yaml's assets, nothing plays and nothing is missed.
///
/// Each entry is `'<plugin>-<step>'`, and `'<plugin>-<step>-simple'` for the shorter words Simple shows instead
/// ([setupWords]). Keep each on one line, in single quotes, with typographic quotes and apostrophes inside (“ ” ’):
/// that is what the tool reads. Spell out what a voice must say: "about 6 credits", not a sum worked out in code
/// (test/plugins/onboarding/setup_flow_test.dart holds the number to lovartCreditsPerImage).
library;

/// Every step's words, by `<plugin>-<step>`.
const Map<String, String> setupVoice = {
  // ---- Lovart (lib/plugins/lovart/lovart_setup.dart) -----------------------------------------------------------------
  'lovart-intro': 'Lovart is a design agent that makes images. With it, Ghost draws a header for a note, a moodboard for a design meeting, or a picture wherever you ask for one in a note. It uses your own Lovart account and its credits: about 6 credits an image.',
  'lovart-intro-simple': 'Lovart makes images for your notes. It uses your own Lovart account and its credits: about 6 credits an image.',
  'lovart-account': 'First, a Lovart account. Open Lovart’s site and sign up, or sign in if you already have one. Come back here once you’re in.',
  'lovart-keys': 'Now the keys. In Lovart, click your profile, then Lovart Agent, then OpenClaw. Your access key and secret key are there: keep that page open to copy them.',
  'lovart-paste': 'Paste the access key and the secret key here. They’re kept in this device’s secure storage, and follow your account, sealed, to your other devices.',
  'lovart-paste-simple': 'Paste the access key and the secret key here. They’re kept safely on this device.',
  'lovart-check': 'Ghost asks Lovart whether the keys work. Nothing in your account changes, and no credits are spent.',
  'lovart-done': 'You’re set. Write a picture’s cue anywhere in a note, like the one below, then tap Lovart’s mark beside it, and the picture takes its place. Nothing is made until you ask, but for one thing: while Header images for notes is on, leaving a longer note draws a banner for its top, with your credits.',
  'lovart-done-simple': 'You’re set. Write a picture’s cue like the one below in a note, tap Lovart’s mark beside it, and Lovart draws it with your credits.',
  // ---- Claude (lib/plugins/claude/claude_setup.dart) -----------------------------------------------------------------
  'claude-intro': 'Claude answers with your own Anthropic API key, and Anthropic bills the key for what you ask. In Ghost, Claude writes into your notes as you watch, from the dock on any page; it writes your meetings up; and it does the to-dos in your Ask Claude note.',
  'claude-intro-simple': 'Claude answers with your own Anthropic API key, and Anthropic bills the key. Ask it from any page, and it writes into your notes as you watch.',
  'claude-account': 'First, an Anthropic account. Open the Claude Console and sign up, or sign in. A new account has no credit: add some under Billing before Claude can answer.',
  'claude-key': 'Now a key. Open API keys in the Console, press Create Key, and give it a name, such as Ghost. Copy it straight away: the Console shows it only once.',
  'claude-paste': 'Paste the key here. It starts with sk-ant. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync.',
  'claude-paste-simple': 'Paste the key here. It starts with sk-ant, and it’s kept safely on this device.',
  'claude-check': 'Ghost asks Anthropic whether the key works, with the smallest request there is: the list of models it may use. Nothing is billed for it.',
  'claude-done': 'You’re set. Two settings matter most, and both can be changed any time on Claude’s page.',
  'claude-done-simple': 'You’re set. Claude is on the dock of every page now.',
};

/// The words for [name] (`lovart-paste`): Simple's shorter ones where [simple] and there are some. Empty for a name
/// with none, which the tests do not let ship.
String setupWords(String name, {bool simple = false}) => (simple ? setupVoice['$name-simple'] : null) ?? setupVoice[name] ?? '';

/// Where [name]'s voice would be, once tool/plugin_setup_voice.py has made it.
String setupVoiceAsset(String name) => 'assets/plugin-setup/$name.mp3';
