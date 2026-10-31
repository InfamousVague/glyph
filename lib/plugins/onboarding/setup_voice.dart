/// What each plugin's setup says, step by step (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-28: "For each of
/// the plugins add a small onboarding flow"): the words under each step's title, shown as its captions, and the words
/// the voice reads aloud.
///
/// This file is the one place they live, as lib/guide/narration.dart is the walkthrough's and lib/academy/voice.dart
/// the Academy's. tool/plugin_setup_voice.py makes the voice with the walkthrough's tool (tool/onboarding_voice.py:
/// Eleven v4, the Jessica voice, mono at 64 kbps, and its SAID for a name the voice would misread), reading the entries
/// here and writing `assets/plugin-setup/<name>.mp3` ([setupVoiceAsset]) with a narration.json beside them; the sheet
/// plays the step's clip as it shows (setup_sheet.dart), and test/plugins/onboarding/setup_voice_test.dart holds every
/// entry to a clip made from its words as they are now. Every plugin's setup is voiced (Matt, 2026-10-29: "add the
/// voiceover onboarding for the rest of the plugins"), the AI providers' too, whose words had been captions only.
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
  // ---- OpenAI (lib/plugins/openai/openai.dart) -----------------------------------------------------------------------
  'openai-intro': 'OpenAI’s models answer with your own OpenAI API key, and OpenAI bills the key for what you ask. In Ghost they answer from the dock on any page, write into your notes as you watch, and can write your meetings up.',
  'openai-intro-simple': 'OpenAI’s models answer with your own OpenAI API key, and OpenAI bills the key.',
  'openai-account': 'First, an OpenAI account for its API: open the OpenAI platform and sign up, or sign in. The API is billed apart from ChatGPT: add credit under Billing before it can answer.',
  'openai-key': 'Now a key. Open API keys, press Create new secret key, and give it a name, such as Ghost. Copy it straight away: it is shown only once.',
  'openai-paste': 'Paste the key here. It starts with sk-. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync.',
  'openai-paste-simple': 'Paste the key here. It starts with sk-, and it’s kept safely on this device.',
  'openai-check': 'Ghost asks OpenAI whether the key works, with the list of models it may use, and nothing is billed for it. That list is where the model is chosen from.',
  'openai-done': 'You’re set. Two settings matter most, and both can be changed any time on OpenAI’s page; which AI answers the dock is chosen in Settings, under AI.',
  'openai-done-simple': 'You’re set. OpenAI answers from the dock when no other AI is set up.',
  // ---- Gemini (lib/plugins/gemini/gemini.dart) -----------------------------------------------------------------------
  'gemini-intro': 'Google’s Gemini models answer with your own Gemini API key. In Ghost they answer from the dock on any page, write into your notes as you watch, and can write your meetings up. Google bills the key once its project has billing on; without it, the free tier has a daily limit.',
  'gemini-intro-simple': 'Google’s Gemini models answer with your own Gemini API key, from Google AI Studio.',
  'gemini-account': 'First, Google AI Studio: open it and sign in with your Google account.',
  'gemini-key': 'Now a key. Open API keys in AI Studio, press Create API key, and pick or make a project for it. Copy it.',
  'gemini-paste': 'Paste the key here. It starts with AIza. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync.',
  'gemini-paste-simple': 'Paste the key here. It starts with AIza, and it’s kept safely on this device.',
  'gemini-check': 'Ghost asks Google whether the key works, with the list of models it may use, and nothing is billed for it. That list is where the model is chosen from.',
  'gemini-done': 'You’re set. Two settings matter most, and both can be changed any time on Gemini’s page; which AI answers the dock is chosen in Settings, under AI.',
  'gemini-done-simple': 'You’re set. Gemini answers from the dock when no other AI is set up.',
  // ---- Custom AI model (lib/plugins/custom_ai/custom_ai.dart) -----------------------------------------------------
  'custom-ai-intro': 'Any model with an OpenAI-compatible endpoint, which most providers offer: OpenRouter, Mistral, Groq or DeepSeek, or LM Studio and Ollama on your own computer. You need its address, a key if it asks for one, and the model’s name.',
  'custom-ai-intro-simple': 'Any model with an OpenAI-compatible endpoint: its address, a key if it needs one, and the model’s name.',
  'custom-ai-paste': 'Paste the endpoint’s address, which usually ends in /v1, and its key if it has one. On your own computer, LM Studio’s is http://localhost:1234/v1 and Ollama’s http://localhost:11434/v1, with no key.',
  'custom-ai-check': 'Ghost asks the endpoint for its list of models. Nothing is billed for it, and the list is where the model is chosen from. An endpoint with no list is fine: type the model’s name next.',
  'custom-ai-done': 'Choose the model, or type its name as the endpoint knows it. Meeting summaries can be turned on or off here too.',
  // ---- Aster (lib/plugins/aster/aster.dart) -----------------------------------------------------------------------
  'aster-intro': 'Aster’s models answer with your own Aster API key, through its OpenAI-compatible API, and Aster bills the key for what you ask. In Ghost they answer from the dock on any page, write into your notes as you watch, and can write your meetings up. What you ask, and the notes it reads, go to Aster and nowhere else.',
  'aster-intro-simple': 'Aster’s models answer with your own Aster API key, and Aster bills the key. Your notes’ words go to Aster, and nowhere else.',
  'aster-account': 'First, an Aster account: open the Aster console and sign up, or sign in. Add credits there before it can answer; the plans and their prices are on Aster’s pricing page.',
  'aster-key': 'Now a key. In the console, create an API key and give it a name, such as Ghost. Copy all of it.',
  'aster-paste': 'Paste the key here. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync.',
  'aster-paste-simple': 'Paste the key here. It’s kept safely on this device.',
  'aster-check': 'Ghost asks Aster whether the key works, with the list of models it may use, and nothing is billed for it. If Aster has no list, Ghost asks the model for a single word instead, which costs a fraction of a cent.',
  'aster-done': 'You’re set. Choose the model, or type its name as Aster gives it. Meeting summaries can be turned on or off here too; which AI answers the dock is chosen in Settings, under AI.',
  'aster-done-simple': 'You’re set. Aster answers from the dock when no other AI is set up.',
  // ---- Notion (lib/plugins/notion/notion_setup.dart) -----------------------------------------------------------------
  'notion-intro': 'Notion turns the list items in your notes into tasks on your Notion boards. Link a note to a board, then swipe an item, or send the whole list, and each becomes a task, its words a link to it. Only the items you send go to Notion.',
  'notion-intro-simple': 'Notion turns the list items in your notes into tasks on your Notion boards. Only the items you send go there.',
  'notion-signin': 'Now sign in. Notion opens in your browser and asks which pages and boards Ghost may use: tick the boards you want tasks to go to, and press Allow. Then come back here.',
  'notion-signin-simple': 'Sign in with Notion in your browser, tick the boards you want, press Allow, and come back here.',
  'notion-check': 'Ghost collects the sign-in and asks Notion which boards it may see. Nothing in your workspace changes.',
  'notion-done': 'You’re set. Open a note with a list, tap its cog, and choose Notion board. Then swipe a list item left, and it becomes a task on that board.',
  'notion-done-simple': 'You’re set. Link a note to a board from its cog, then swipe a list item left to send it.',
  // ---- GitHub (lib/plugins/github/github_setup.dart) -----------------------------------------------------------------
  'github-intro': 'GitHub links a note to a repo. The repo is read on your phone, so its names and terms come out right as the note is formatted, and the note’s list items can become issues, ticked off from either side. Public repos are read without a token; issues and private repos need one.',
  'github-intro-simple': 'GitHub links a note to a repo, and its list items become issues. For that, it needs a token from your GitHub account.',
  'github-account': 'First, a GitHub account. Open GitHub and sign up, or sign in if you have one already. Come back here once you’re in.',
  'github-key': 'Now a token. On GitHub, make a fine-grained token for the repos you’ll link, with Issues set to read and write, and Contents to read only. Copy it straight away: GitHub shows it only once.',
  'github-paste': 'Paste the token here. It starts with github_pat_. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync.',
  'github-paste-simple': 'Paste the token here. It’s kept safely on this device.',
  'github-check': 'Ghost asks GitHub whose token it is. Nothing in your repos changes.',
  'github-done': 'You’re set. Open a note, tap its cog, and choose GitHub repo to link one. Then swipe a list item left, and it becomes an issue.',
  'github-done-simple': 'You’re set. Link a repo to a note from its cog, and send its list items as issues.',
  // ---- Slack (lib/plugins/slack/slack_setup.dart) --------------------------------------------------------------------
  'slack-intro': 'Slack posts a note, or a meeting’s summary, to a Slack channel when you say so, and each meeting’s action items once it’s written up. There’s no sign-in: each channel has a webhook, an address that posts only there, and the post goes straight from this device.',
  'slack-intro-simple': 'Slack posts a note, or a meeting’s summary, to a Slack channel, straight from this device.',
  'slack-webhook': 'Now a webhook. Open Slack’s apps, create an app for your workspace, and turn on Incoming Webhooks. Then add a new webhook, pick the channel, and copy the address it gives you.',
  'slack-paste': 'Give the channel a name of your own, such as its name in Slack, and paste the webhook. It’s kept in this device’s secure storage, and no page can read it back.',
  'slack-paste-simple': 'Name the channel, and paste the webhook. It’s kept safely on this device.',
  'slack-check': 'Ghost posts a short test message to the channel, to be sure the webhook works. Look for it in Slack.',
  'slack-done': 'You’re set. Open a note, tap its cog, and choose Post to Slack. Meetings can go to a channel by themselves too: choose one on this page.',
  'slack-done-simple': 'You’re set. Post a note from its cog, with Post to Slack.',
  // ---- Discord (lib/plugins/discord/discord_setup.dart) --------------------------------------------------------------
  'discord-intro': 'Discord posts a note, or a meeting’s summary, to a Discord channel when you say so. There’s no sign-in and no bot: each channel has a webhook, and the post goes straight from this device, pinging nobody.',
  'discord-intro-simple': 'Discord posts a note, or a meeting’s summary, to a Discord channel, straight from this device.',
  'discord-webhook': 'Now a webhook. In Discord, open the channel’s settings with Edit Channel, then Integrations, then Webhooks. Press New Webhook, then Copy Webhook URL.',
  'discord-paste': 'Give the channel a name of your own, and paste the webhook. It’s kept in this device’s secure storage, and sealed to your other devices.',
  'discord-paste-simple': 'Name the channel, and paste the webhook. It’s kept safely on this device.',
  'discord-check': 'Ghost posts a short test message to the channel, to be sure the webhook works. Look for it in Discord.',
  'discord-done': 'You’re set. Open a note, tap its cog, and choose Post to Discord. To bring Ghost into your Discord calls, use Link Discord on this page.',
  'discord-done-simple': 'You’re set. Post a note from its cog, with Post to Discord.',
  // ---- ElevenLabs (lib/plugins/elevenlabs/elevenlabs_setup.dart) -----------------------------------------------------
  'elevenlabs-intro': 'ElevenLabs reads your notes aloud, in a voice you choose, and keeps the voice-over at the top of the note, to play where it sits. It uses your own ElevenLabs account and its credits: a credit a character.',
  'elevenlabs-intro-simple': 'ElevenLabs reads your notes aloud in a voice you choose, with your own ElevenLabs credits.',
  'elevenlabs-account': 'First, an ElevenLabs account. Open ElevenLabs and sign up, or sign in if you have one already. Come back here once you’re in.',
  'elevenlabs-key': 'Now a key. In ElevenLabs, open your profile, then API Keys, and make one that may use Text to Speech and read Voices. Copy it.',
  'elevenlabs-paste': 'Paste the key here. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync.',
  'elevenlabs-paste-simple': 'Paste the key here. It’s kept safely on this device.',
  'elevenlabs-check': 'Ghost asks ElevenLabs whether the key works, by reading your account. No credits are spent.',
  'elevenlabs-done': 'You’re set. Open a note, tap its cog, and choose Voice-over. Each voice can be heard first on this page, before you pick one.',
  'elevenlabs-done-simple': 'You’re set. Choose Voice-over on a note’s cog, and it’s read aloud.',
  // ---- Calendar, for Google Calendar (lib/plugins/calendar/calendar_setup.dart) -------------------------------------
  'calendar-intro': 'Calendar shows your events in Ghost: on the home page’s Today, and in queries. With Google Calendar connected, it can put your dated to-dos on a calendar too. Any calendar’s iCal address works as well, pasted on this page.',
  'calendar-intro-simple': 'Calendar shows your events on the home page’s Today, from Google Calendar.',
  'calendar-signin': 'Now connect Google Calendar. Google opens in your browser and asks what Ghost may see: allow it, then come back here.',
  'calendar-check': 'Ghost collects the sign-in and lists your calendars. Nothing on them changes.',
  'calendar-done': 'You’re set. Your events show on the home page’s Today and in queries. To put your dated to-dos on Google’s calendar, turn on To-dos on the calendar, on this page.',
  'calendar-done-simple': 'You’re set. Your events show on the home page’s Today.',
  // ---- Contacts (lib/plugins/contacts/contacts_setup.dart) -----------------------------------------------------------
  'contacts-intro': 'Contacts matches the people named on your to-dos to the contacts on your phone: their picture on the chip, and a tap to call, text or email them. Your contacts are read on this device only, and nothing of them is kept or sent anywhere.',
  'contacts-intro-simple': 'Contacts shows the people on your to-dos as your contacts, read on this device only.',
  'contacts-allow': 'Now allow Ghost to read your contacts. Your phone asks: choose Allow.',
  'contacts-check': 'Ghost reads your contacts, here on this device, to be sure it may.',
  'contacts-done': 'You’re set. Write @sam on a to-do, and Sam’s chip shows their picture. Or tap the plus beside a line, and choose A person.',
  'contacts-done-simple': 'You’re set. Write @sam on a to-do, and Sam’s chip shows their picture.',
  // ---- Place reminders (lib/plugins/places/places_setup.dart) --------------------------------------------------------
  'place-reminders-intro': 'Place reminders remind you of a to-do when your phone arrives somewhere. Hold a to-do and choose Remind me at a place, and when you come within about 150 metres, it rings, even with the app closed. Where you are stays on your phone.',
  'place-reminders-intro-simple': 'Place reminders ring when your phone arrives at a place on one of your to-dos.',
  'place-reminders-allow': 'Now your location. A reminder rings while Ghost is closed, so Android has to let it know where your phone is all the time. Allow the precise location, then choose Allow all the time.',
  'place-reminders-allow-simple': 'Allow your location, then choose Allow all the time.',
  'place-reminders-check': 'Ghost asks the phone whether it may know where it is, all the time.',
  'place-reminders-done': 'You’re set. Hold a to-do and choose Remind me at a place: search for one, pick a place the note already has, or use where you are.',
  'place-reminders-done-simple': 'You’re set. Hold a to-do, and choose Remind me at a place.',
  // ---- Google Meet (lib/plugins/meetings/meeting_setup.dart) ---------------------------------------------------------
  'google-meet-intro': 'Ghost joins your Google Meet meetings as a guest, records them, and files each as a note in your Inbox, written up on your device with who said what. The recording comes back sealed to your account.',
  'google-meet-intro-simple': 'Ghost joins your Google Meet meetings, and files each as a note, written up on your device.',
  'google-meet-done': 'To invite Ghost, put your Email to a note address on the meeting’s calendar invite, as a guest. Or paste a Meet link on this page and press Join, and Ghost comes in now. The address is turned on in Settings, under Account.',
  'google-meet-done-simple': 'Invite Ghost with your Email to a note address on a calendar invite, or paste a Meet link on this page and press Join.',
  // ---- Zoom (lib/plugins/meetings/meeting_setup.dart) ----------------------------------------------------------------
  'zoom-intro': 'Ghost joins your Zoom calls as a guest from its browser, records them, and files each as a note in your Inbox, written up on your device with who said what.',
  'zoom-intro-simple': 'Ghost joins your Zoom calls, and files each as a note, written up on your device.',
  'zoom-host': 'Whether Ghost gets in is up to the host’s settings. Guests who aren’t signed in to Zoom must be let in, with Join from your browser on, and the passcode in the invite link. Someone lets Ghost in from the waiting room within ten minutes, and with captions on, the note says who said what.',
  'zoom-host-simple': 'The host must let guests in from a browser, with the passcode in the link, and let Ghost out of the waiting room.',
  'zoom-done': 'To invite Ghost, put your Email to a note address on the call’s calendar invite, as a guest. Or paste a Zoom link on this page and press Join. The address is turned on in Settings, under Account.',
  'zoom-done-simple': 'Invite Ghost with your Email to a note address on a calendar invite, or paste a Zoom link on this page and press Join.',
  // ---- Todoist (lib/plugins/todoist/todoist_setup.dart) --------------------------------------------------------------
  'todoist-intro': 'Todoist brings your Todoist projects in as notes: each project a note, its sections headings, and its tasks to-dos, with their dates, priorities and labels. It reads your account with a token you paste for the one import, and doesn’t keep it.',
  'todoist-intro-simple': 'Todoist brings your Todoist projects in as notes, with a token used once and not kept.',
  'todoist-key': 'Now the token. In Todoist, open Settings, then Integrations, then Developer, and copy your API token.',
  'todoist-done': 'Paste the token into Import from Todoist on this page, and press it. Each project comes in, in a workspace of the import’s own. A project’s CSV export works too, with no token at all.',
  'todoist-done-simple': 'Paste the token into Import from Todoist on this page, and press it.',
  // ---- Back up to git (lib/plugins/git_backup/git_backup_setup.dart) -------------------------------------------------
  'git-backup-intro': 'Back up to git commits your Library folder to a git repository you own, two minutes after your last change, and pushes it. Every note, its history and its pictures, as plain files, on GitHub, GitLab, Codeberg or any git host. A fresh device opens the library again by cloning it. One thing to know: the repository is plain text, so anyone who can read it can read your notes. Make it private.',
  'git-backup-intro-simple': 'Back up to git copies your notes to a git repository you own, a little after each change. Make the repository private: anyone who can read it can read your notes.',
  'git-backup-token': 'First, a token from your git host. On GitHub, make a fine-grained token with Contents set to read and write for the repository you’ll use. GitLab and Codeberg have their own token pages. Copy it straight away: most hosts show it only once.',
  'git-backup-reuse': 'If the GitHub plugin already has a token, Ghost can ask GitHub whether it may push. If it may, it’s used here too; if not, paste a token on the next step.',
  'git-backup-paste': 'Paste the token here. It’s kept in this device’s secure storage, and sealed to your other devices while keys and connections sync. It never goes into the repository.',
  'git-backup-paste-simple': 'Paste the token here. It’s kept safely on this device.',
  'git-backup-create': 'Now the repository. Ghost can make a private one on GitHub for you, called ghost-notes, with the token you pasted. Or skip this and paste the address of one you made yourself.',
  'git-backup-repository': 'Paste the repository’s HTTPS address, the one that ends in dot git. If Ghost just made one for you, leave this empty and go on.',
  'git-backup-check': 'Ghost makes the repository where your Library is, reaches the remote with your token, and says how big the first backup will be. Nothing is pushed yet.',
  'git-backup-done': 'You’re set. Tap Back up to make the first backup now; after that, Ghost commits two minutes after your last change and pushes when you’re online. Recordings and your teams’ notes are left out until you switch each on, on the plugin’s page.',
  'git-backup-done-simple': 'You’re set. Tap Back up for the first backup; after that, Ghost backs up by itself a little after each change.',
};

/// The words for [name] (`lovart-paste`): Simple's shorter ones where [simple] and there are some. Empty for a name
/// with none, which the tests do not let ship.
String setupWords(String name, {bool simple = false}) => (simple ? setupVoice['$name-simple'] : null) ?? setupVoice[name] ?? '';

/// Where [name]'s voice is, as tool/plugin_setup_voice.py makes it.
String setupVoiceAsset(String name) => 'assets/plugin-setup/$name.mp3';
