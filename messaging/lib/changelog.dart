/// What each release brought, as people read it (Matt, 2026-11-19: "Implement a changelog that pops up ever time a new
/// update is released with release notes").
///
/// The newest first. Each release adds its entry here before it goes out: tool/release.mjs, release-mac.mjs and
/// release-windows.mjs refuse a version with no entry (tool/lib/notes.mjs). Write for the people using the app: what
/// they can now do or what now works, a line each, in plain words, no file names. The first time the app opens after
/// updating, the entries it has not shown yet come up in What's new (lib/ui/whats_new.dart); Settings › About shows
/// them again.
library;

import 'package:flutter/foundation.dart';

/// One release's entry: its version, its day, and a line for each thing it brought.
@immutable
class ReleaseNotes {
  const ReleaseNotes(this.version, this.date, this.notes);

  /// "0.9.22", as pubspec.yaml's version has it before the "+".
  final String version;

  /// When it went out, "2026-11-19".
  final String date;
  final List<String> notes;
}

/// Every release's entry, the newest first.
const List<ReleaseNotes> changelog = [
  ReleaseNotes('0.12.26', '2026-11-24', [
    'Calls are easier on a phone\'s battery: the ripple on a face is measured in a lighter way, nothing is measured while the app is out of sight, and a phone left alone in a space with its screen off no longer keeps its microphone and sound running.',
    'A paired computer no longer has the phone send every space, circle and friend again every few seconds: the phone says nothing changed until something has.',
    'On a computer, a call over its chat has a Chat button beside Leave: press it to hide the chat and give the call the whole pane, and again to bring it back.',
    'Who is in a voice space\'s call is listed under the space in its circle, each with their picture and name, and a green ring on whoever is talking while you\'re in the call too.',
    'Unread conversations are at the top of the list, the newest first, then everything you\'ve read. Pinned ones stay above both.',
    'Performance, a new plugin in the Marketplace: a small bar under the title bar with how much of the processor and memory the app is using, a count of spikes, and a log you can copy.',
  ]),
  ReleaseNotes('0.12.25', '2026-11-23', [
    'Mark as read for a whole circle: open the circle\'s menu (its name, a long press or a right click) and choose Mark as read, and every space in it is read at once.',
  ]),
  ReleaseNotes('0.12.24', '2026-11-23', [
    'Voice spaces on a computer: in a call, the space shows the call in the top two thirds and its chat with the message box under it, and the circle\'s list beside it stays as it was, so you can move between spaces without leaving the call. Drag the line between them to make either bigger.',
    'Open spaces: the circle\'s list stays beside the floor, and the call\'s buttons are there once, at the floor\'s left foot. The box for the chat is at the right and looks like every other message box; New group is at the top right. The walls take the colour you chose for the app (purple where you chose none), shaded so they stand up, with a fainter glow on the floor.',
    'My files: a private drive for your Ghost account, under the search. Every device signed in to your account shows the same files, sealed so the server can\'t open them. Press and hold a file to send it into a space\'s chat.',
    'Sign in on a new computer or browser by scanning a code with your Android phone: choose Phone on the sign-in screen, then Settings › Me › Sign in a new device on the phone. Check the six digits match and unlock your phone, and the new device signs in with nothing to type.',
    'On a computer, My files can keep a folder of yours in step: new and changed files go both ways while the app is open. Syncing never removes anything, so a file you delete on one side comes back for now.',
    'Send souls to a friend: press + in a chat with a friend by username and choose Send souls. A card in the chat shows what was sent once the relay confirms it.',
    'Recording a call on a Mac can include video: everyone\'s cameras in a grid, or a shared screen shown large with cameras beside it. Everyone is asked once about voice and video, and anyone who agreed to voice only is shown by name, never on camera. New tonight and not yet tried in a long call: Record voice only is in the call\'s menu.',
  ]),
  ReleaseNotes('0.12.23', '2026-11-23', [
    'Open spaces show the chat on the floor: what people write comes up as bubbles for a few seconds, over the group its writer stands in or at the side, fainter the further away they are. A box at the foot of the floor writes to the chat.',
    'Open spaces stay in their own page: joining one leaves the list beside it as it was, with the call\'s controls over the foot of the floor. The walls take your accent colour, and the words saying how to walk fade once you have.',
    'Recording a call: opening a recording from a Files space or a space\'s chat now shows the mixer, with a track for each voice, instead of the video player. The player is one button away.',
    'Share screen on a Mac and a PC: its list of screens and windows now opens, and says what to do when there is nothing to share.',
  ]),
  ReleaseNotes('0.12.22', '2026-11-23', [
    'Open spaces have walls: the floor is a room now, with see-through walls in colour round its edges. The view stops at a wall, so you never look past the room, and you walk on up to it.',
    'Signing in on another phone, computer or browser now brings your conversations with friends from your other devices, the newest 300 messages of each, once one of them is open. Settings › Devices says when they went to a device, and which.',
  ]),
  ReleaseNotes('0.12.21', '2026-11-23', [
    'Calls connect faster between people on different versions: two people joining a space at the same moment, or one on 0.12.19, now connect in a couple of seconds instead of up to half a minute, and someone whose connection drops for a moment is connected again by itself.',
    'Open spaces open as their floor everywhere: on a computer, from the call\'s banner and from the Spaces page on a phone, and with any call layout chosen, where they showed as a normal call. The floor is there the moment you join, saying it is connecting until the call is in, and an open space\'s invite link now opens it.',
  ]),
  ReleaseNotes('0.12.20', '2026-11-23', [
    'Video in calls is squarer: on a computer every camera is shown 4:3, in every call layout, and the tiles grow to fill the window instead of coming out wide and short. A shared screen keeps its own shape.',
    'Open spaces: a new kind of space you walk around in. Everyone stands somewhere on a floor seen from above, and you hear people louder the nearer they stand. Walk with W A S D or the arrow keys on a computer, or press where you want to go. Make groups on the floor (a game, a chat, a film): inside one you hear everyone in it, and its circle grows as people step in. Choose Open space when you make a space.',
    'Microphones and speakers: the one you choose in Settings › Voice and video, or from the call\'s own buttons, is now the one a call uses, from its start and when you switch in the middle of it. Before, on a Mac every call took the system\'s own whatever you chose, and Settings listed only that one until you had been in a call; on Android a chosen microphone was never used. Choosing "The system\'s own" again now goes back to it, a chosen device that isn\'t plugged in says so while the call uses the system\'s own, and on a Mac the ring and the app\'s other sounds play through the speaker you chose.',
    'Lock the app: Settings › Lock the app sets a PIN, with your fingerprint or face where the device has it, and how soon the app locks. While it is locked, notifications hide their words.',
    'Flip camera: on a phone, a button beside the camera in a call switches between the front and the back camera.',
    'A call that moved to another of your devices: the device you left shows a note that stays, with Bring it back here.',
    'Recording a call: someone who says Include me while a recording is running is now in the mixer and in the file.',
    'Video in a call on a computer fills the call panel, where one person\'s video was a thin strip.',
    'Muting in a space: a lock marks someone muted for everyone and a crossed speaker someone muted for you, the locked microphone says why, and a moderator\'s mute holds for people who join later.',
    'One window on Windows and Linux: starting the app a second time shows the window already open, and two windows no longer take a call from each other.',
    'Replies on Discord, X, Messenger and Instagram show who and what they answer.',
    'Recording started and stopped lines show the app\'s icons everywhere they appear.',
    'Fixes: the iPhone player keeps its audio and subtitle choices, the auto leveler reaches the level it is aiming for, and the docs\' search handles a few words it used to garble.',
  ]),
  ReleaseNotes('0.12.19', '2026-11-23', [
    'Sign-ins synced from the browser extension now reach your other devices: the relay\'s answers were never passed on, so no device signed in with what the extension synced, and synced plugins never ran either (thanks, Kevin).',
    'Calls mend themselves: someone whose connection drops for a moment is connected again by itself, a connection that fails or gets stuck is offered again every couple of seconds, and two people joining at once no longer miss each other. Nobody has to leave and come back.',
    'Read stays read: a conversation read on a computer paired with your phone, or a chat on another network, no longer comes back unread after the app starts again.',
    'Your own conversations reach a device that has just opened: messages your other devices sent while it was closed are no longer dropped.',
    'Host a relay on this device (Settings › Routes, on a Mac, Windows or Linux computer, and on Android while the app is open): the same relay server gogho.st runs, for people on your network or over Direct, with an optional pass phrase. Off until you switch it on, and it says what whoever runs it can see.',
  ]),
  ReleaseNotes('0.12.18', '2026-11-23', [
    'Human check on computers: on a Mac, Windows or Linux computer, a first message from someone new on the networks you chose for it now waits out of Messages until they answer its question, as it does on a phone. Before, only phones asked, so strangers and bots got straight through on a computer.',
    'Direct, in Settings › Routes: your devices and your friends\' can link straight to each other, as a second route beside the relay server and a way to check what the relay says. It is off until you switch it on, and the page says how each link stands. Routes also lists the people you have reached this session and which route carried each.',
    'Your account key: Profile shows the key your account is known by, written as a did:key, with Copy and Share; a friend\'s profile shows theirs. Sign a statement turns a few words into a signed block you can paste anywhere to show an account elsewhere is yours, and Check a statement says whose a pasted one is. Anyone can check one with standard tools, without asking us.',
    'Vouch for a friend: on a friend\'s profile, Vouch for them to say the account is really them. A vouch lasts a year and can be renewed, or taken back whenever you like. A profile shows how many of your own friends vouch for someone, with their names on a tap, and never a count of everyone. You can hide the vouches you hold in Profile.',
  ]),
  ReleaseNotes('0.12.17', '2026-11-23', [
    'Remove a device: an iPhone or a computer with an account of its own now deletes everything of the account from itself when it is removed from the account (conversations, keys, recordings and the other networks\' sign-ins), and only when the removal carries the account\'s own signature: never because a relay was changed or lost what it kept. Where a relay doesn\'t know the device, Settings › Me says so and offers to list it again. Signing out says what stays on the device and offers to delete it all. Android phones, and computers paired with one, are as they were.',
    'Safer starts: if an iPhone or a computer with an account of its own can\'t read what it keeps when it starts, it now says so and starts nothing, instead of starting empty and later writing over your messages.',
    'Spaces: a message deleted while your device is catching up on a space\'s history now stays deleted, even when the deletion arrives before the message.',
    'Friends on other relays: each account now signs which relay is its home, so once relays pass messages to each other, people on different relays can be friends, added as @maya@relay.example. Our relay doesn\'t pass messages on yet; the add-friend screen and Settings › Routes say what crosses relays today.',
  ]),
  ReleaseNotes('0.12.16', '2026-11-23', [
    'Checking the relay: once a day, your devices ask the relay again who each friend\'s username belongs to, and check your own at sign-in. If the relay ever gives a friend\'s username to a different account, their card says so, calmly, and they\'re told: you\'re still talking to the friend you added. Settings › Routes shows what was checked.',
    'Add-me links carry the friend\'s key, so a link only ever adds the person who made it, whatever the relay says.',
  ]),
  ReleaseNotes('0.12.15', '2026-11-23', [
    'Friends are told apart by their keys: who a message is from, and where yours go, now come only from the key your records hold for that friend, never from the address someone else wrote. A group\'s admin could list a member under one of your friends\' numbers or usernames; their messages no longer land in your friend\'s conversation, and yours no longer go to them.',
    'Friend requests by username are checked with the relay\'s directory before they can be accepted, so a request can\'t borrow someone else\'s name; group members show under who your phone knows them to be.',
  ]),
  ReleaseNotes('0.12.14', '2026-11-23', [
    'Friends by username: when a message to one can\'t go (no connection, or a picture, which can\'t be sent to a friend by username yet), the conversation now says why and keeps what you wrote. Before, on Android, it was handed to texting, which kept the words unsealed with your texts and couldn\'t deliver them.',
    'Steadier connections: the relay no longer takes compressed messages, which closes a way one message could have stopped it.',
  ]),
  ReleaseNotes('0.12.13', '2026-11-22', [
    'Your own relay server: Settings › Routes can point the app at a relay you run yourself. It checks the address answers before switching, shows which relay is in use, and goes back to ours in one tap. People on different relays can\'t reach each other, and the docs say what else changes. The guide to running one is in the docs.',
    'Make it yours: build your own look from four colours in Settings › Appearance and share it as a short code, or paste a friend\'s. There\'s a Readable font for easier reading, too.',
    'Keyboard shortcuts: Cmd/Ctrl+K jumps to any conversation, Option/Alt+Up and Down move through the list, and Cmd/Ctrl+B, I and E format what you write. Search is now Cmd/Ctrl+F. Change any of them in Settings › Keyboard shortcuts.',
    'Voice messages from your computer: the Mac and Windows apps record voice messages in chats, spaces and the networks\' chats, no phone needed, and Windows plays them too. On Linux, the app now updates itself (install this version once by hand).',
    'Forward secrecy: messages between friends, and the copies your devices send each other, are now sealed with keys that each device changes daily and deletes after about two weeks. Someone who recorded them can\'t open them later, even with your recovery words. Friends on older versions still get your messages the earlier way. Circles aren\'t covered yet.',
  ]),
  ReleaseNotes('0.12.12', '2026-11-22', [
    'Stages in spaces: whoever manages a space can make its call a stage, where newcomers listen until brought up to speak. Listeners raise a hand to ask, the menu counts listeners and hands, and a stage holds far more people than an ordinary call.',
    'Formatting in messages: **bold**, *italic*, ~~strikethrough~~, `code`, quotes with "> " and ||spoilers|| that stay hidden until tapped. Choose words in a chat with a friend to make them bold, italic or code.',
    'Report a person or a message: press and hold a message, or open someone\'s profile card, choose a reason and add a note if you like. The report is sealed so only the reviewer can read it, and you can block them at the same time. Settings › Privacy lists the reports you\'ve made. Nothing you send is ever scanned.',
  ]),
  ReleaseNotes('0.12.11', '2026-11-22', [
    'Show me as: in Profile, choose Online, Away, Busy or Invisible. Friends see a green dot, an amber moon for Away or a red mark for Busy on your picture; Invisible shows you as offline while you keep chatting.',
    'Your add-me link: Profile has a gogho.st/add link and QR code of your own. Anyone who opens it or scans it is asked whether to send you a friend request.',
    'Threads in spaces and circles: long-press a message and choose Reply in thread to talk about it on its own page. A line under the message shows how many replies and who wrote last.',
    'Snooze a conversation: long-press it in Messages and choose Snooze…. It leaves the list until the time you pick, then comes back at the top with a notification.',
    'Export a conversation: a conversation\'s settings, or a space\'s, can save every message as a Markdown file.',
  ]),
  ReleaseNotes('0.12.10', '2026-11-22', [
    'Dress your profile: in Profile › Look, choose an avatar decoration, a border for your picture, a banner, an effect on your name and an effect over your whole profile card. Friends and people in your spaces see them when they open your profile.',
    'Calls: call a friend directly. A friend\'s chat has Voice call and Video call; their phone, Mac and PC ring with Answer and Decline, full screen on a locked Android phone. Missed, declined and unanswered calls are noted in the chat.',
  ]),
  ReleaseNotes('0.12.9', '2026-11-22', [
    'Share your screen in a call: on a Mac, Windows or Linux pick a whole screen or one window; on Android the phone asks. Everyone else sees it large and whole, with Back to call to put it away and View to bring it back.',
  ]),
  ReleaseNotes('0.12.8', '2026-11-22', [
    'Messages with friends by username reach every device on your Ghost account: what you send from your phone shows on your Mac and PC too, and what they send reaches all of them, even a device that was closed.',
    'Emoji shortcodes: type :joy: and it becomes 😂; start typing :jo and matching emoji show over the box, to pick with the arrow keys and Enter, or a tap.',
    'New plugin, Human check: on the networks you choose, someone new is held out of Messages and notifications until they answer a small question your app sends them, which weeds out bots and spam. You can let anyone in or block them from the Held list.',
  ]),
  ReleaseNotes('0.12.7', '2026-11-22', [
    'Messages and circles show how many are unread: a count on the Messages icon, and on each circle in place of its dot (red where you are mentioned).',
    'Notifications: a text the filter hides (a kind you have switched off in Messages, such as political texts or sales, or Spam) no longer notifies, even when the app is closed. It still arrives.',
    'Calls on the Mac: testing your microphone in Settings › Voice and video starts and stops without the spinning wait.',
  ]),
  ReleaseNotes('0.12.6', '2026-11-22', [
    'Calls: the red handle over a call no longer stays on screen after a recording stops, or when the soundboard or voice changer has nothing to show.',
  ]),
  ReleaseNotes('0.12.5', '2026-11-21', [
    'Sign in once, signed in everywhere: a network plugin you sign in to on one device, in the app or with the browser extension, signs in on every device on your Ghost account, the Mac and Windows apps included. Each sign-in page also offers Use the sign-in from your browser.',
    'Plugins you turn on or off reach your other devices within a couple of minutes, even a computer that stays open.',
    'Network plugins on Windows: Messenger, Instagram, Discord, X and Slack now work in the Windows app too.',
  ]),
  ReleaseNotes('0.12.4', '2026-11-21', [
    'Discord, X and Slack plugins in the Marketplace: your Discord direct messages and group chats, your X direct messages and a Slack workspace, read and answered in Messages. They sign in with your browser\'s session; the browser extension does it for every device. None of them allows other apps, so you agree to a warning first.',
    'X\'s messages are end-to-end encrypted: Ghost asks once for your 4-digit X Chat passcode to open them, and doesn\'t keep it.',
    'Browser extension: an account with a verified phone number can sign in. Enter the number, choose Text me a code, then type the code.',
  ]),
  ReleaseNotes('0.12.3', '2026-11-21', [
    'Chat bubbles on Android: a conversation can float on the side of your screen, like Google Messages and Messenger. Turn them on or off in Settings › Notifications.',
    'Plugins sync across your devices: turn one on, or add one from the Marketplace, and your other devices on the same Ghost account follow. Network plugins switch on and offer their sign-in; your sign-ins never leave a device. Settings › Plugins has the switch.',
    'Google Messages in a tap: the browser extension can now sign in to Google for you, in a private window of its own, and Ghost pairs with it from Google Messages\' setup. No copying from the browser\'s developer tools. You still tap Google\'s emoji on your phone.',
    'RCS messages on a computer: one paired with your phone now shows when RCS already comes through the phone, rather than asking you to set it up again.',
    'Test your microphone and speaker in Settings › Voice and video: a live level bar, and Hear yourself through the speaker you chose.',
    'In a call, each face shows when someone is still connecting, reconnecting, on a slow connection, or can\'t connect.',
    'Reply to a message in circle and space chats: press and hold it, then Reply.',
    'Sign up: your 12 recovery words can wait. Choose Later, and a reminder stays in your conversations until you see them.',
  ]),
  ReleaseNotes('0.12.2', '2026-11-21', [
    'Messenger, Instagram and LinkedIn: sign in once, on every device. A new browser extension captures your sign-in for each from a browser you\'re already signed in to and syncs it, sealed, to your Ghost account; your other devices then sign in on their own, so you no longer copy a login onto each one. The relay only ever holds it sealed and cannot read it.',
    'Calls: turning your video off no longer leaves your last frame frozen in your tile on the other side.',
    'Calls: the lines over a call — the recording\'s, a plugin\'s — can be dragged out of the way and folded down to a chip.',
    'Files: a large upload no longer makes the app stutter during a call.',
    'Windows: you can pick files again — a plugin to load, and files and pictures anywhere the app asks for one.',
    'The Archive ring counts only unread archived conversations now, so reading them clears it.',
    'Signal: the code you share to another screen shows properly, or says why it can\'t, instead of a blank bar.',
  ]),
  ReleaseNotes('0.12.1', '2026-11-21', [
    'Record call: open a saved recording in the mixer. In Recordings, tap one and choose Open in the mixer: every voice is a track with its waveform, meter, mute, solo and fader, as during the call. Play it to hear the mix as you set it, tap the tracks to jump around, and Save mix to keep it as a new recording beside the first.',
    'Souls: when you\'re given souls or a badge, you\'re told why ("Bug bounty", say). Straight away if the app is open; if it isn\'t, a card shows what you were given and why the next time you open it.',
  ]),
  ReleaseNotes('0.12.0', '2026-11-21', [
    'Videos from Files spaces can go full screen on your phone too: press the full-screen button and the bars hide and the phone turns to fit the video (upright for a tall one). Back, or the button again, leaves full screen.',
  ]),
  ReleaseNotes('0.11.7', '2026-11-21', [
    'Record call: everyone\'s voice is recorded again, not just yours. Since calls can start through the relay and then reconnect, a person\'s sound could move to a new connection part way, and the recording kept listening to the old one.',
  ]),
  ReleaseNotes('0.11.6', '2026-11-21', [
    'Files spaces: files over 4 GB show in the space again. A big film or backup could finish uploading and still not appear in the list.',
    'Calls: video now shows on both ends. Until now each side saw only their own camera, never the other person\'s. Calls also connect through Ghost\'s relay first, which gets through almost any network, and only try a direct path if the relay can\'t be reached; a call that hasn\'t connected after 15 seconds tries the other way by itself.',
    'Windows: the microphone you pick in a call or in Settings › Voice and video is the one used. Windows used the first microphone it found, whatever you chose.',
    'Windows: calls no longer turn your other sounds down (music, videos, games). If you liked that, switch on Lower other sounds in calls in Settings › Voice and video.',
  ]),
  ReleaseNotes('0.11.5', '2026-11-21', [
    'Files spaces: an upload that stopped part way and can\'t carry on now shows at the top of the space as Unfinished upload, with how much got there and who started it. It held the space\'s room without a word before; now whoever started it or the space\'s owner can remove it to free that room. An upload that does carry on after the app opens again shows how far it had got, and says it is checking the file before going on rather than looking stopped.',
    'Voice changer in calls is instant now: your voice is changed on your own device as you speak, with no delay and nothing sent anywhere. Pick Feminine, Masculine, Deeper, Higher, Child, Older, Monster, Chipmunk, Robot or Radio in the plugin\'s settings: each moves your pitch and the size of your voice separately, so it sounds like a real person of that kind rather than a sped-up recording. ElevenLabs is still there under How calls are changed, for a realistic voice a second or two behind.',
    'Windows: Record call, Live captions and Scribe now work on Windows. Captions and Scribe need Windows\' speech recognition for your language (Settings › Time & language › Speech).',
  ]),
  ReleaseNotes('0.11.4', '2026-11-21', [
    'Calls: when you and someone else can\'t reach each other directly, on a mobile network or a strict workplace, school or hotel network, the call now goes through Ghost\'s relay by itself instead of never connecting. It stays encrypted between you: the relay can\'t hear or see it.',
    'Files spaces: "Getting it ready" is far quicker for a big file, and shows a percentage. Checking a 26 GB file took over twenty minutes; it now takes seconds on a Mac or iPhone and about four minutes on Android and Windows. Checking a download is quicker the same way.',
  ]),
  ReleaseNotes('0.11.3', '2026-11-21', [
    'LinkedIn is no longer a network here: LinkedIn kept signing people out of their own browsers when Ghost used the sign-in. It is gone from the Marketplace and from Settings › Connections, and its saved sign-in and chats are deleted from this device the next time the app starts.',
  ]),
  ReleaseNotes('0.11.2', '2026-11-21', [
    'Networks: one you added (Instagram, LinkedIn and the others) no longer shows as removed after the app starts again while another network is slow to start. Each network now starts on its own.',
  ]),
  ReleaseNotes('0.11.1', '2026-11-20', [
    'Voice changer, live in calls: turn on "Change my voice in calls, live" and everyone in a space\'s call hears you in the voice you chose, a second or two behind as each phrase is changed by ElevenLabs. Your own voice is never heard while it\'s on, nothing is sent while you\'re muted, and a line over the call shows whose voice you have, with a way back to your own.',
    'Record call: the recording no longer floats over the app as a pill. Your red recording line over the call has a Mixer button beside Stop, which opens the tracks, meters and faders full screen.',
  ]),
  ReleaseNotes('0.11.0', '2026-11-20', [
    'Marketplace: WhatsApp, Matrix, Microsoft Teams, Google Chat, Messenger, Instagram and LinkedIn are listed as plugins, on a Networks shelf. Add one and it is switched on in Settings › Connections too, ready to sign in to; remove it and it is signed out.',
  ]),
  ReleaseNotes('0.10.8', '2026-11-20', [
    'Auto leveler: a new plugin that brings everyone in a call to about the same loudness on your device. Quiet voices come up and loud ones come down, a few seconds after each person starts talking, never more than about 9 dB either way. Nothing is sent and nobody else hears a difference. Add it from the Marketplace, or turn it on for a whole circle; press and hold someone in a call to see what it is doing to them.',
    'Soundboard: a new plugin that puts pads in a call. Press one and everyone in the call hears it: an air horn, applause, a sad trombone and nine more. A circle\'s owner and admins can add sounds of the circle\'s own. Add it from the Marketplace, or turn it on for a whole circle in its Settings › Plugins; you choose how loud it is for you, or to hear none of it.',
    'Voice changer: a new plugin that sends your voice messages in another voice, keeping how you said them: your timing, your tone, a laugh or a whisper. It uses your own ElevenLabs account, so each recording goes to ElevenLabs to be changed; if one can\'t be changed it isn\'t sent. In spaces and in chats on other networks, on an Android phone. Add it from the Marketplace, then paste your key and choose a voice in Settings › Voice changer.',
    'Recording a call: the recording\'s pill, with its tracks, meters and mixer, now shows over the call itself (the call\'s page was covering it), and the red line over the call counts the time.',
  ]),
  ReleaseNotes('0.10.7', '2026-11-20', [
    'Connections: Telegram and Signal are Ghost\'s official networks, there and ready to sign in to. The others — WhatsApp, Matrix, Microsoft Teams, Google Chat, Messenger, Instagram and LinkedIn — are now plugins under Connections › Plugins: off until you switch one on, and not run until then. Anything you\'d already connected stays on. Your texts, through Google Messages, are unchanged.',
  ]),
  ReleaseNotes('0.10.6', '2026-11-20', [
    'Spaces and circles: react to messages. Press and hold a message (or right-click on a computer) and pick an emoji; tap a reaction in a circle to add yours or take it off. Everyone can react in read-only spaces.',
    'Circles: a welcome message for new members and a welcome space they land in, read-only spaces where only the owner and admins post, and a system space that shows who joined, was kicked or banned, or became an admin. Set them in a circle\'s Settings › Welcome.',
    'Messenger, Instagram and LinkedIn: your chats on each, among your messages, on a Mac and an Android phone. Connect one in Settings › Connections. None of the three supports other apps, so each asks you to read a warning first; you sign in with the session of a browser signed in to your account.',
    'Faster and smoother everywhere, most of all on Linux: the chat list, long conversations and pictures do far less work, saving chats no longer pauses the screen, changing a setting no longer redraws the whole app, and the call banner no longer keeps the window drawing after a call has ended.',
  ]),
  ReleaseNotes('0.10.5', '2026-11-20', [
    'Game activity: a new plugin that shows friends and the spaces you\'re in which game you\'re playing on your Mac or Windows computer, and for how long. Add it from the Marketplace; it\'s off until you do, and you choose who is told.',
    'Recording a call: every track has a real meter now, with its peaks, its average and a lamp that lights if a voice clips.',
    'Recording a call: a mixer. Press Mixer in the recording to set how loud each voice is in the mix, or mute or solo one, while it records. Each person\'s own track stays as it was recorded.',
    'Recording a call: mark a moment with the flag, and find it again in Recordings.',
    'Signing up is a username and a password. The recovery words\' check can be skipped and done later.',
    'On an Android phone the walkthrough is the texts step, then your username and password.',
    'Circles: owners and admins can kick someone, or ban them so an invite won\'t let them back.',
    'Schedule a message: press and hold Send, or right-click it, to choose when it goes.',
    'Calls: push to talk, and keyboard commands you can set in Settings › Keyboard shortcuts.',
    'On a computer, photos and videos that weren\'t coming through now do, and you can paste a picture into any message field on a Mac.',
  ]),
  ReleaseNotes('0.10.4', '2026-11-20', [
    'Marketplace: plugins have a place of their own now, a storefront on the rail and the dock between Archive and Settings. Settings no longer lists them, and searching Settings for a plugin opens it there.',
    'Plugins from other developers: browse, add and remove reviewed plugins in the Marketplace. Each one says what it can do before you add it, and it only ever sees texts from numbers not in your contacts, on this device.',
    'Make your own: Marketplace › Submit a plugin sends a plugin you\'ve made for review, with its icon, description and tags, and My submissions shows where each one stands.',
    'Developer mode: Settings › Developer › Plugins in development loads a plugin you\'re making from a file, a link or the clipboard, to try it before you submit it.',
    'Report a plugin from its page if something\'s wrong with it.',
    'Profile pictures are sharp: a picture you choose is kept 256 pixels across, not 72. Choose yours again to send friends the sharp one.',
    'Messages: the filter\'s menu stays on the screen on a small phone or in a short window, opening where there\'s room and scrolling its list.',
  ]),
  ReleaseNotes('0.10.3', '2026-11-20', [
    'Messages: Mark all read, Share feedback and the Messages and Codes toggle scroll away with your conversations, so the search stays at the top and the list has more room.',
    'Messages: Clean up is one of those rows now, not a button over the search, so the bar above the search is gone.',
  ]),
  ReleaseNotes('0.10.2', '2026-11-20', [
    'Texts are optional on a phone: Skip this step in the walkthrough, and Ghost works with friends, circles, Telegram and Signal. Turn texts on any time in Settings › Texts.',
    'Circles: a circle\'s picture fills its round in the rail, with only the halo round the open one.',
    'Messages: Mark all read\'s count is a small circle.',
    'Sign up with Discord opens your browser on a computer or an iPhone.',
    'On a Mac or Windows, sign up and sign in are in a small window of their own, as Discord\'s is.',
    'On a Mac or Windows the app keeps your settings and your username across restarts again: since 0.10.0 it forgot them each time it opened, and could send you back to sign up after signing in.',
  ]),
  ReleaseNotes('0.10.1', '2026-11-20', [
    'Circles: give a circle an invite word, so gogho.st/c/bookclub opens it in place of the long link. Set it in its Settings › Invites.',
    'Messages: edit your own messages in spaces and circles, from any of your devices. Edited ones say so.',
    'Profiles: a card like Discord\'s, with a banner in their colour, their badges in a tray and by name, and their status as a bubble.',
    'Badges: choose the one shown beside your name, in your souls. It sits level with the name now.',
    'Messages: Mark all read and Share feedback are a list of rows under the search.',
    'Recording a call: a pill you can move anywhere, opening into each voice\'s track and waveform as it records, like a video editor\'s timeline.',
  ]),
  ReleaseNotes('0.10.0', '2026-11-20', [
    'On a Mac or Windows the app opens on a small splash that checks for updates first, brings one down and restarts into it, then loads the app.',
    'Developer mode: tap Version in Settings › About twelve times to turn it on, on the phone or a computer. Settings › Developer stays hidden until then.',
    'Icons: every icon is Phosphor\'s now, in duotone, in the app and the docs.',
    'Share feedback is in the rail now, just above Settings, on a phone.',
    'Friends: a friend request that didn\'t arrive is sent again until it\'s answered.',
    'Souls: the flame is a soul\'s ghostly white-green now.',
    'Messages: no Circles tab under the rail, which shows your circles; circle invites wait at the top of Messages.',
    'Circles: the rail marks the open circle with a halo in its colour, and something unread with a dot.',
    'Circles: the back arrow sits level with the circle\'s name in its banner.',
    'Circles: less room above the circle\'s name in its banner.',
    'Circles: on a computer, the rail\'s buttons are a little smaller.',
  ]),
  ReleaseNotes('0.9.37', '2026-11-20', [
    'Souls: points with a flame beside Share feedback, a thank-you for reporting bugs. They can\'t be spent yet. Tap them to see yours and your badges.',
    'Badges: some people have a badge or two beside their name, like Bug hunter or Alpha tester.',
    'Circles: a circle\'s picture fills its round in the rail, with no edge of colour round it.',
    'Circles: names in a circle\'s chat take the colour of their highest role, and change as roles are given.',
    'Circles: the back arrow sits in the banner\'s corner, and there\'s a little room before the name\'s arrow.',
  ]),
  ReleaseNotes('0.9.36', '2026-11-20', [
    'Share feedback: report a bug, suggest a feature or tell us anything, with up to three screenshots. Include your username to be in line for bug bounties. On a Mac it\'s in the window\'s top bar, elsewhere beside the search in Messages.',
    'On a Mac the window has its own top bar in the app\'s colours, a little taller, that you drag the window by.',
    'Codes: the tab shows only where codes can come from, your texts or a linked network like Telegram.',
    'Messages: the bar over the search goes when it has nothing in it. Mark all read shows while something is unread, and the cleaner while there\'s something to clean.',
  ]),
  ReleaseNotes('0.9.35', '2026-11-20', [
    'An emoji picker of Ghost\'s own, from the smiley button in any chat: search by name, pick a skin tone, and your recent ones come first. It stays open while you pick a few.',
    'Contacts: Blocked is a button beside Add, not a row of its own.',
  ]),
  ReleaseNotes('0.9.34', '2026-11-19', [
    'Help and docs: step-by-step guides for everything at gogho.st/docs, from Settings › About, and a ? on Pair a computer and Add a Discord server.',
    'Settings › Network is called Routes now, so it isn\'t mixed up with Connections (your linked accounts).',
    'Add a Discord server says what pressing a channel does now: you join it from Ghost, sound and chat both ways.',
  ]),
  ReleaseNotes('0.9.33', '2026-11-19', [
    'Verified numbers: a badge beside the names of people who verified their phone number, in spaces, circles and profiles.',
    'Slow mode: in a circle\'s space settings, let each person write only once in so many seconds. Those who manage spaces don\'t wait.',
    'Recording a call shows as cards in the chat, with icons: who started it, and when it stops, how long it ran, how many voices are in it and where it was saved.',
    'Contacts: tapping a friend you added by username opens your chat with them again.',
  ]),
  ReleaseNotes('0.9.32', '2026-11-19', [
    'Polls in spaces and circles: ask one from the +, with two to ten answers. Tap an answer to vote, tap again to take it back.',
    'A circle\'s back arrow stays inside its banner when you point at it or press it.',
  ]),
  ReleaseNotes('0.9.31', '2026-11-19', [
    'On a computer, Emoji in a space\'s or circle\'s chat opens your computer\'s emoji panel.',
    'A circle\'s name, picture and back arrow sit inside its banner picture, clear of its rounded edges.',
    'Sign up with Discord, Telegram or Signal: your username, name, picture and status are filled in from that account, and it\'s connected to Ghost as you go. Change anything before you continue.',
    'Scrolling down a circle\'s spaces shrinks its banner to just the name and picture as you go, and it grows back at the top.',
  ]),
  ReleaseNotes('0.9.30', '2026-11-19', [
    'Mac download: Ghost Messaging for the Mac is a disk image now, signed and checked by Apple. Open it and drag the app to Applications; it opens on any Mac without a warning.',
    'Friends show once each in Contacts and when you choose people to invite, not twice.',
    'A circle\'s banner starts below your phone\'s clock and battery, not behind them.',
    'A profile\'s message box lines up with the choices under it.',
  ]),
  ReleaseNotes('0.9.29', '2026-11-19', [
    'Profile pictures show by people\'s messages in spaces and circles, and in a space\'s members list.',
    'On a computer, Enter sends in a space\'s or circle\'s chat; Shift+Enter starts a new line.',
    'A circle\'s banner sits a little in from the edges, with rounded corners.',
    'Mentions: an @name\'s highlight sits evenly round its letters.',
  ]),
  ReleaseNotes('0.9.28', '2026-11-19', [
    'Windows: the app and its installer are signed under Matt Wisniewski\'s name, so Windows no longer warns about an unknown publisher when you download or install it.',
  ]),
  ReleaseNotes('0.9.27', '2026-11-19', [
    'When someone new joins a circle you\'re in, you\'re told: a notification on your phone, or a note in the app with a way to the circle. Turn it off in Settings › Notifications › Joins in circles.',
    'A circle\'s invite link works for people without the app: its page offers the right download, and once the app is set up it opens the circle for you. With the app already there, Open in Ghost Messaging opens it, on a computer too.',
  ]),
  ReleaseNotes('0.9.26', '2026-11-19', [
    'The Messages, Codes and Circles tabs are all there the moment the app opens, without Circles jumping along.',
    'Your phone number is set once, with your profile in Settings › Me › Number: the separate Your number setting is gone.',
    'Record call: Record and Stop are in a space\'s header while you\'re in its call. In a circle, recordings are saved to a folder in one of its Files spaces; choose which in Circle settings › Plugins.',
    'A circle\'s banner is softly blurred and shaded behind its name, so the name reads on any picture.',
  ]),
  ReleaseNotes('0.9.25', '2026-11-19', [
    'Pictures in a space\'s or circle\'s chat, and on Telegram and Signal, open full screen over the chat: pinch or scroll to zoom, tap or press Escape to go back.',
    'SMS spaces list their members, you first: who gets the space\'s messages by text, at which number, and who reads them in the app.',
  ]),
  ReleaseNotes('0.9.24', '2026-11-19', [
    'SMS spaces: members whose phone number is linked get the space\'s messages by text by themselves, and what they text back comes into the space. Text STOP to leave.',
    'Tap someone\'s picture or name in a space, or in a members list, to open their profile. Write to a friend right from it, Send inside the box as everywhere else.',
    'Circles: the owner or an admin can remove someone from a circle. Tap them in the members list: their card has their roles to change, admin, and Remove.',
    'Your profile can show friends your number and linked accounts, if you switch it on in Settings › Me › Profile.',
    'Plugins meant for circles have their own section on the Plugins page.',
    'Circles can have a banner across the top of their sidebar: choose one in Circle settings › Overview.',
  ]),
  ReleaseNotes('0.9.23', '2026-11-19', [
    'What\'s new: after each update, a short list of what changed, like this one. Find it again in Settings › About.',
    'Profiles: set a picture and a status in Settings › Me › Profile. Tap an @ anywhere to see someone\'s card, with what you can do from there.',
    'Live captions: in a call, see what everyone says written out as they talk, translated where you have Translate. Turn them on from the call\'s menu.',
    'Watch together: play a video or song from a Files space for everyone in the call, kept in step on each device.',
  ]),
  ReleaseNotes('0.9.22', '2026-11-19', [
    'Record call: record a space\'s call to one video file with a sound track for each person, named for them. Everyone in the call is asked, and only those who say yes are recorded. Add it in Plugins, or turn it on for a whole circle.',
    'Scribe: a recorded call written out on your device, each line with who said it and when, with a summary where your phone can make one.',
    'SMS spaces: a circle\'s texting space that friends without the app join by text, from one member\'s phone.',
    'Circle plugins: whoever can change a circle can turn a plugin on for everyone in it, in Circle settings › Plugins.',
    'A picture or voice message you send always shows what it is, not just "Delivered".',
  ]),
  ReleaseNotes('0.9.21', '2026-11-19', [
    'Names no longer start with "@". Someone without a display name now goes by their username, the same as everyone else\'s name.',
  ]),
  ReleaseNotes('0.9.20', '2026-11-19', [
    'Mentions: type @ in a space or a circle to mention someone. They get a notification, and messages that mention you stand out.',
    'Unread marks show @ when something unread mentions you.',
    'The Codes tab is always there, even before your first code.',
    'Contacts lists friends by username and by number together, under On Ghost Messaging.',
  ]),
];

/// Whether [a] is a later version than [b] ("0.9.10" is later than "0.9.9"); anything unreadable is earliest.
bool laterVersion(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? -1];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p > q;
  }
  return false;
}

/// The entries after [seen] up to and including [current], newest first, [most] at the most.
List<ReleaseNotes> notesSince(String seen, String current, {List<ReleaseNotes> from = changelog, int most = 5}) => [
      for (final r in from)
        if (laterVersion(r.version, seen) && !laterVersion(r.version, current)) r,
    ].take(most).toList();
