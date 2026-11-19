// The docs' sections and pages, in reading order (tool/build-docs.mjs). Each page is docs-src/pages/<slug>.html.
// `soon` marks a page about something not out yet (Matt, 2026-11-19: "Mark them Coming soon").
export const sections = [
  {
    title: 'Getting started',
    pages: [
      { slug: 'index', title: 'Welcome', summary: 'What Ghost Messaging is, and where to start.' },
      { slug: 'alpha', title: 'Join the alpha', summary: 'Try Ghost Messaging before it launches: what to install, and how to join the testers\' circle.' },
      { slug: 'install', title: 'Install the app', summary: 'Get Ghost Messaging on an Android phone, a Mac or a Windows PC.' },
      { slug: 'first-run', title: 'The first time you open it', summary: 'The welcome, texting with Ghost or beside Google Messages, and picking a look.' },
      { slug: 'account', title: 'Your account', summary: 'Create an account, keep your recovery words safe, and sign in on another device.' },
      { slug: 'how-accounts-work', title: 'How your account works', summary: 'Recovery words, your password, the account address, and being the same you on every device.' },
      { slug: 'profile', title: 'Your profile and number', summary: 'Your name, picture, status and username, and verifying your phone number.' },
    ],
  },
  {
    title: 'Circles, spaces and calls',
    pages: [
      { slug: 'circles', title: 'Make a circle and invite people', summary: 'A circle is a group of people with a sidebar of spaces. Make one, invite people, and join one.' },
      { slug: 'spaces', title: 'Spaces', summary: 'The four kinds of space, polls, mentions, and spaces of your own.' },
      { slug: 'roles', title: 'Roles and permissions', summary: 'Who can do what in a circle, and changing it space by space.' },
      { slug: 'sms-spaces', title: 'SMS spaces', summary: 'A space that people without the app are in by text.' },
      { slug: 'calls', title: 'Calls', summary: 'Joining voice, the call\'s controls, each person\'s volume, and guests from a browser.' },
      { slug: 'files', title: 'Files spaces', summary: 'Share files with a circle, sealed end to end, and play videos in the app.' },
    ],
  },
  {
    title: 'Plugins',
    pages: [
      { slug: 'plugins', title: 'About plugins', summary: 'Add features you want, for yourself or for a whole circle.' },
      { slug: 'record-call', title: 'Record call', summary: 'Record a call to one file with a named track for each voice.' },
      { slug: 'scribe', title: 'Scribe', summary: 'Turn a recorded call into words, on your device.' },
      { slug: 'live-captions', title: 'Live captions', summary: 'See what everyone in a call says, as they say it.' },
      { slug: 'watch-together', title: 'Watch together', summary: 'Play a video or song for everyone in a call, in step.' },
      { slug: 'translate', title: 'Translate', summary: 'Read texts in other languages, translated on your phone.' },
      { slug: 'codes', title: 'Codes', summary: 'Sign-in codes in a tab of their own, a tap to copy.' },
      { slug: 'spam', title: 'Spam filter', summary: 'Texts that look like spam, kept out of your way.' },
      { slug: 'kinds', title: 'Kinds of text', summary: 'Texts from strangers sorted by what they are about.' },
      { slug: 'unknown-numbers', title: 'Unknown numbers', summary: 'What a number you don\'t know likely is, with Save and Block.' },
      { slug: 'quiet-hours', title: 'Quiet hours', summary: 'Silence for strangers at night, and never a sound for spam.' },
      { slug: 'link-previews', title: 'Link previews', summary: 'Links shown as cards with their picture and title.' },
      { slug: 'quick-actions', title: 'Quick actions', summary: 'Dates, addresses, tracking numbers and phone numbers become buttons.' },
      { slug: 'replies', title: 'Replies', summary: 'Suggested replies, and reminders to follow up.' },
      { slug: 'cleaner', title: 'Cleaner', summary: 'Delete conversations in bulk by kind.' },
      { slug: 'discord', title: 'Discord servers', summary: 'Link a Discord server, see who is in its voice channels, and talk in them from Ghost.' },
    ],
  },
  {
    title: 'Messaging',
    pages: [
      { slug: 'texts', title: 'Texts and conversations', summary: 'Sending, reactions, edits, ticks, stickers, effects and conversation settings.' },
      { slug: 'google-messages', title: 'Beside Google Messages', summary: 'Keep Google Messages for RCS and use Ghost for everything else.' },
      { slug: 'friends', title: 'Friends', summary: 'Add friends by username, and friends by number.' },
      { slug: 'networks', title: 'Telegram, Signal and more', summary: 'Your other chats in one inbox: linking Telegram, Signal, WhatsApp and Matrix.' },
      { slug: 'encryption', title: 'Encrypted texts', summary: 'Seal texts with one person end to end, and check it is really them.' },
    ],
  },
  {
    title: 'Computers',
    pages: [
      { slug: 'computers', title: 'Mac and Windows apps', summary: 'Ghost Messaging on a computer, with or without your phone.' },
      { slug: 'pairing', title: 'Pair a computer with your phone', summary: 'Your texts on your computer: scan, match the six digits, and keep it connected.' },
    ],
  },
  {
    title: 'Privacy and settings',
    pages: [
      { slug: 'privacy', title: 'Privacy and safety', summary: 'What is sealed, what the server sees, blocking, and signing out.' },
      { slug: 'settings', title: 'Settings, at a glance', summary: 'Every section of Settings, and what it holds.' },
      { slug: 'routes', title: 'Routes', summary: 'How messages travel between Ghost apps: the relay, texts, and testing them.' },
      { slug: 'coming-soon', title: 'Coming soon', summary: 'What is built but not out yet.', soon: true },
      { slug: 'developer', title: 'Developer API', summary: 'Control the app from a script or another program, through its API.' },
    ],
  },
];
