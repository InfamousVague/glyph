// The docs' sections and pages, in reading order (tool/build-docs.mjs). Each page is docs-src/pages/<slug>.html.
// `soon` marks a page about something not out yet (Matt, 2026-11-19: "Mark them Coming soon").
export const sections = [
  {
    title: 'Getting started',
    pages: [
      { slug: 'index', icon: 'ghost', title: 'Welcome', summary: 'What Ghost Messaging is, and where to start.' },
      { slug: 'alpha', icon: 'flask-conical', title: 'Join the alpha', summary: 'Try Ghost Messaging before it launches: what to install, and how to join the testers\' circle.' },
      { slug: 'install', icon: 'download', title: 'Install the app', summary: 'Get Ghost Messaging on an Android phone, a Mac or a Windows PC.' },
      { slug: 'first-run', icon: 'rocket', title: 'The first time you open it', summary: 'The welcome, texting with Ghost or beside Google Messages, and picking a look.' },
      { slug: 'account', icon: 'key-round', title: 'Your account', summary: 'Create an account, keep your recovery words safe, and sign in on another device.' },
      { slug: 'how-accounts-work', icon: 'badge-check', title: 'How your account works', summary: 'Recovery words, your password, the account address, and being the same you on every device.' },
      { slug: 'profile', icon: 'circle-user', title: 'Your profile and number', summary: 'Your name, picture, status and username, and verifying your phone number.' },
    ],
  },
  {
    title: 'Circles, spaces and calls',
    pages: [
      { slug: 'circles', icon: 'users', title: 'Make a circle and invite people', summary: 'A circle is a group of people with a sidebar of spaces. Make one, invite people, and join one.' },
      { slug: 'spaces', icon: 'message-circle', title: 'Spaces', summary: 'The four kinds of space, polls, mentions, and spaces of your own.' },
      { slug: 'roles', icon: 'shield-check', title: 'Roles and permissions', summary: 'Who can do what in a circle, and changing it space by space.' },
      { slug: 'sms-spaces', icon: 'smartphone', title: 'SMS spaces', summary: 'A space that people without the app are in by text.' },
      { slug: 'calls', icon: 'headphones', title: 'Calls', summary: 'Joining voice, the call\'s controls, each person\'s volume, and guests from a browser.' },
      { slug: 'files', icon: 'folder', title: 'Files spaces', summary: 'Share files with a circle, sealed end to end, and play videos in the app.' },
    ],
  },
  {
    title: 'Plugins',
    pages: [
      { slug: 'plugins', icon: 'puzzle', title: 'About plugins', summary: 'Add features you want, for yourself or for a whole circle.' },
      { slug: 'record-call', icon: 'circle-dot', title: 'Record call', summary: 'Record a call to one file with a named track for each voice.' },
      { slug: 'scribe', icon: 'file-text', title: 'Scribe', summary: 'Turn a recorded call into words, on your device.' },
      { slug: 'live-captions', icon: 'type', title: 'Live captions', summary: 'See what everyone in a call says, as they say it.' },
      { slug: 'watch-together', icon: 'film', title: 'Watch together', summary: 'Play a video or song for everyone in a call, in step.' },
      { slug: 'translate', icon: 'languages', title: 'Translate', summary: 'Read texts in other languages, translated on your phone.' },
      { slug: 'codes', icon: 'key-round', title: 'Codes', summary: 'Sign-in codes in a tab of their own, a tap to copy.' },
      { slug: 'spam', icon: 'ban', title: 'Spam filter', summary: 'Texts that look like spam, kept out of your way.' },
      { slug: 'kinds', icon: 'list-filter', title: 'Kinds of text', summary: 'Texts from strangers sorted by what they are about.' },
      { slug: 'unknown-numbers', icon: 'user-round-search', title: 'Unknown numbers', summary: 'What a number you don\'t know likely is, with Save and Block.' },
      { slug: 'quiet-hours', icon: 'clock', title: 'Quiet hours', summary: 'Silence for strangers at night, and never a sound for spam.' },
      { slug: 'link-previews', icon: 'link', title: 'Link previews', summary: 'Links shown as cards with their picture and title.' },
      { slug: 'quick-actions', icon: 'calendar-plus', title: 'Quick actions', summary: 'Dates, addresses, tracking numbers and phone numbers become buttons.' },
      { slug: 'replies', icon: 'reply', title: 'Replies', summary: 'Suggested replies, and reminders to follow up.' },
      { slug: 'cleaner', icon: 'brush-cleaning', title: 'Cleaner', summary: 'Delete conversations in bulk by kind.' },
      { slug: 'discord', icon: 'bot', title: 'Discord servers', summary: 'Link a Discord server, see who is in its voice channels, and talk in them from Ghost.' },
    ],
  },
  {
    title: 'Messaging',
    pages: [
      { slug: 'texts', icon: 'message-square', title: 'Texts and conversations', summary: 'Sending, reactions, edits, ticks, stickers, effects and conversation settings.' },
      { slug: 'google-messages', icon: 'message-circle', title: 'Beside Google Messages', summary: 'Keep Google Messages for RCS and use Ghost for everything else.' },
      { slug: 'friends', icon: 'user-plus', title: 'Friends', summary: 'Add friends by username, and friends by number.' },
      { slug: 'networks', icon: 'send', title: 'Telegram, Signal and more', summary: 'Your other chats in one inbox: linking Telegram, Signal, WhatsApp and Matrix.' },
      { slug: 'encryption', icon: 'lock', title: 'Encrypted texts', summary: 'Seal texts with one person end to end, and check it is really them.' },
    ],
  },
  {
    title: 'Computers',
    pages: [
      { slug: 'computers', icon: 'laptop', title: 'Mac and Windows apps', summary: 'Ghost Messaging on a computer, with or without your phone.' },
      { slug: 'pairing', icon: 'qr-code', title: 'Pair a computer with your phone', summary: 'Your texts on your computer: scan, match the six digits, and keep it connected.' },
    ],
  },
  {
    title: 'Privacy and settings',
    pages: [
      { slug: 'privacy', icon: 'eye', title: 'Privacy and safety', summary: 'What is sealed, what the server sees, blocking, and signing out.' },
      { slug: 'settings', icon: 'settings', title: 'Settings, at a glance', summary: 'Every section of Settings, and what it holds.' },
      { slug: 'routes', icon: 'globe', title: 'Routes', summary: 'How messages travel between Ghost apps: the relay, texts, and testing them.' },
      { slug: 'coming-soon', icon: 'clock', title: 'Coming soon', summary: 'What is built but not out yet.', soon: true },
      { slug: 'developer', icon: 'braces', title: 'Developer API', summary: 'Control the app from a script or another program, through its API.' },
    ],
  },
];
