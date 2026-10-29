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

/// Words shown as captions and never said (Matt, 2026-10-29: the AI providers' setups, "leave voice clips out,
/// captions only"; docs/AI_PROVIDERS.md): the same `<plugin>-<step>` names as [setupVoice], kept apart so the clips'
/// test (test/plugins/onboarding/setup_voice_test.dart) asks no clip of them and the sheet plays none.
const Map<String, String> setupCaptions = {
  // ---- OpenAI (lib/plugins/openai/openai.dart) -----------------------------------------------------------------------
  'openai-intro': 'OpenAI’s models answer with your own OpenAI API key, and OpenAI bills the key for what you ask. In Ghost they answer from the dock on any page, write into your notes as you watch, and can write your meetings up.',
  'openai-intro-simple': 'OpenAI’s models answer with your own OpenAI API key, and OpenAI bills the key.',
  'openai-account': 'First, an OpenAI account for its API: open the OpenAI platform and sign up, or sign in. The API is billed apart from ChatGPT: add credit under Billing before it can answer.',
  'openai-key': 'Now a key. Open API keys, press Create new secret key, and give it a name, such as Ghost. Copy it straight away: it is shown only once.',
  'openai-paste': 'Paste the key here. It starts with sk-. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync.',
  'openai-paste-simple': 'Paste the key here. It starts with sk-, and it’s kept safely on this device.',
  'openai-check': 'Ghost asks OpenAI whether the key works, with the list of models it may use, and nothing is billed for it. That list is where the model is chosen from.',
  'openai-done': 'You’re set. Two settings matter most, and both can be changed any time on OpenAI’s page; which AI answers the dock is chosen in Settings › AI.',
  'openai-done-simple': 'You’re set. OpenAI answers from the dock when no other AI is set up.',
  // ---- Gemini (lib/plugins/gemini/gemini.dart) -----------------------------------------------------------------------
  'gemini-intro': 'Google’s Gemini models answer with your own Gemini API key. In Ghost they answer from the dock on any page, write into your notes as you watch, and can write your meetings up. Google bills the key once its project has billing on; without it, the free tier has a daily limit.',
  'gemini-intro-simple': 'Google’s Gemini models answer with your own Gemini API key, from Google AI Studio.',
  'gemini-account': 'First, Google AI Studio: open it and sign in with your Google account.',
  'gemini-key': 'Now a key. Open API keys in AI Studio, press Create API key, and pick or make a project for it. Copy it.',
  'gemini-paste': 'Paste the key here. It starts with AIza. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync.',
  'gemini-paste-simple': 'Paste the key here. It starts with AIza, and it’s kept safely on this device.',
  'gemini-check': 'Ghost asks Google whether the key works, with the list of models it may use, and nothing is billed for it. That list is where the model is chosen from.',
  'gemini-done': 'You’re set. Two settings matter most, and both can be changed any time on Gemini’s page; which AI answers the dock is chosen in Settings › AI.',
  'gemini-done-simple': 'You’re set. Gemini answers from the dock when no other AI is set up.',
  // ---- Custom AI model (lib/plugins/custom_ai/custom_ai.dart) -----------------------------------------------------
  'custom-ai-intro': 'Any model with an OpenAI-compatible endpoint, which most providers offer: OpenRouter, Mistral, Groq or DeepSeek, or LM Studio and Ollama on your own computer. You need its address, a key if it asks for one, and the model’s name.',
  'custom-ai-intro-simple': 'Any model with an OpenAI-compatible endpoint: its address, a key if it needs one, and the model’s name.',
  'custom-ai-paste': 'Paste the endpoint’s address, which usually ends in /v1, and its key if it has one. On your own computer, LM Studio’s is http://localhost:1234/v1 and Ollama’s http://localhost:11434/v1, with no key.',
  'custom-ai-check': 'Ghost asks the endpoint for its list of models. Nothing is billed for it, and the list is where the model is chosen from. An endpoint with no list is fine: type the model’s name next.',
  'custom-ai-done': 'Choose the model, or type its name as the endpoint knows it. Meeting summaries can be turned on or off here too.',
};

/// The words for [name] (`lovart-paste`): Simple's shorter ones where [simple] and there are some, from [setupVoice]
/// or [setupCaptions]. Empty for a name with none, which the tests do not let ship.
String setupWords(String name, {bool simple = false}) =>
    (simple ? setupVoice['$name-simple'] ?? setupCaptions['$name-simple'] : null) ?? setupVoice[name] ?? setupCaptions[name] ?? '';

/// Where [name]'s voice would be, once tool/plugin_setup_voice.py has made it.
String setupVoiceAsset(String name) => 'assets/plugin-setup/$name.mp3';
