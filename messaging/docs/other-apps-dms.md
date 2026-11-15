# Other apps' direct messages in Ghost

Matt, 2026-11-15: "pick up the other sessions question about proxying direct messages from other apps like discord,
slack, telegram through our app and being able to reply via an API, i'm not sure which services allow this so look
into it and do some research". Research only: nothing here is built. Read on 2026-11-15; anything marked
**unverified** wants a look at the source before building on it.

## The short answer

There are two ways in, and they cover different apps:

1. **The phone's own notifications (any app, no API).** Android lets an app with *notification access* read the
   notifications other apps post and press their **Reply** action (the same `RemoteInput` that Wear OS, Android Auto
   and the shade's inline reply use). Discord, Slack, WhatsApp, Instagram, Messenger, Signal, Teams and Telegram
   all post a message notification with a Reply action. Ghost would show those messages and send replies through
   the other app itself, signed in as you, with no keys, no servers and nothing against those apps' terms (no token
   is taken, no client is faked). Limits below.
2. **Real APIs, where a service allows a third-party client.** Telegram, Mastodon, Bluesky and Matrix do, fully.
   Slack does, awkwardly. X does, for money. Discord, WhatsApp, Instagram/Messenger, Signal and iMessage do not.

**Recommendation:** build (1) first: one feature that brings most apps at once, and the only lawful way to Discord,
WhatsApp and Instagram. Then add (2) for **Telegram** (full history, media, works with the phone away) and
**Mastodon/Bluesky** (small, open APIs, and already in Settings › Me). Leave Slack, X and the rest out unless asked.

## Service by service

| Service | Read and reply to *your* DMs via an API? | How | Catch |
| --- | --- | --- | --- |
| **Telegram** | **Yes, fully** | TDLib (Telegram's own client library) with our own `api_id` from my.telegram.org; it is a complete client: history, media, groups, live updates | Must follow the API Terms; accounts on unofficial clients are "put under observation"; one `api_id` per phone number; the sample id is refused for releases |
| **Mastodon** | **Yes** | REST API: direct messages are statuses with `visibility: direct`; `/api/v1/conversations`; streaming for live | Per instance OAuth app (registered on the fly); fine |
| **Bluesky** | **Yes** | `chat.bsky.convo.*` (listConvos, getMessages, sendMessage) through the chat service proxy; OAuth, or an app password made **with DM access ticked** | Text only (images not in DMs); the `bluesky` Dart package already has `BlueskyChat` |
| **Matrix** | **Yes** | Client-server API; any homeserver | Few people Matt knows are on it, except via bridges |
| **Slack** | **Yes, but** | A Slack app with *user* token scopes (`im:history`, `im:read`, `chat:write`); Events API `message.im` for live messages | Each workspace must allow the app (many admins block it); since 2025 a non-Marketplace app gets `conversations.history` at about **1 request a minute, 15 messages a time** (existing installs from 3 March 2026), so history is crippled unless the app is approved for the Marketplace; live events are not throttled the same way |
| **X** | Yes, **paid** | DM endpoints need the top permission level; pay-per-use since February 2026 | About $0.005 a DM call reported (**unverified**); the free tier is gone for new developers |
| **Discord** | **No** | Bots see only DMs sent *to the bot*; using a person's account ("self-bot", user token) is forbidden and gets accounts banned | Notifications (1) are the only way |
| **WhatsApp** | **No** (for us) | No personal-account API (the Business API is for business numbers). EU interoperability under the DMA exists since November 2025, but only for services Meta signs as partners (BirdyChat, Haiket), in the EU, with their encryption requirements | Unofficial libraries (whatsmeow etc.) break the terms and get numbers banned. Notifications (1) |
| **Instagram / Messenger** | **No** | Messenger Platform and the Instagram API are for business pages and accounts | Notifications (1) |
| **Signal** | **No** | No API. `signal-cli` can link as a device using Signal's own protocol, unofficially | Notifications (1) is cleaner |
| **iMessage** | **No** | Nothing official | n/a on Android anyway |
| **Google Chat / Teams** | Yes, in work accounts | Google Chat API / Microsoft Graph with delegated scopes | The organisation's admin must consent; not a personal-chat thing |

## How (1), notifications, would work

- A `NotificationListenerService` in the Android app; the person turns on notification access once (Android's own
  switch, not a runtime permission), and chooses which apps Ghost may read.
- A posted notification with `MessagingStyle` gives the sender, the conversation, the recent messages and whether
  it is a group. Each conversation becomes a row in Ghost marked with the app it came from.
- **Reply**: the notification's action with a `RemoteInput` is filled in and sent (`RemoteInput.addResultsToIntent`
  and the action's `PendingIntent`). **Mark read** is the action too, where the app gives one. The other app sends
  it, as you.
- The Mac gets these through the existing desk link, as it gets texts.

What it cannot do, and must say plainly:

- **Only what arrives as a notification**: no history before Ghost was set up, nothing from a muted chat, nothing
  while the other app's notifications are off or it is open on screen.
- **Reply only while the notification is there**: once it is dismissed (or read elsewhere) there is no Reply action
  until the next message. Ghost can still show the conversation; replying then means opening the other app.
- **Pictures and voice** mostly do not come through; some apps put a picture in the notification, most only "Photo".
- **Phone only**: the phone must be on and have the other apps installed and signed in.
- **Google Play**: notification access is a sensitive capability, and a Play listing must justify it as a core
  feature (**unverified** which declaration it needs today; check Play Console's permissions declaration before a
  Play build). The sideloaded and Mac builds are not affected.
- Ghost already reads its own SMS; this reads *other* apps' messages, so it should be off by default, per app, with
  a clear page saying what is read and that nothing leaves the phone except to the paired Mac.

## How (2) would fit

- Run each client **on the phone, not on the relay server**: TDLib, Mastodon and Bluesky all work from the device,
  so tokens and messages never touch ghost-sms.com, matching how Settings › Me keeps nothing on the server. The
  relay only matters if the Mac is to work with the phone away, which can come later.
- Telegram: TDLib has to be built for Android (and macOS) and wrapped (there are Dart bindings, e.g. `tdlib`
  packages, **unverified** which is maintained). Our `api_id` is Matt's to register (my.telegram.org, his number);
  it is not the bot token that Settings › Me's Telegram sign-in uses.
- Mastodon and Bluesky can reuse the accounts already linked in Settings › Me, asking for more scope (DMs) when
  the person turns the inbox on.

## Questions for Matt

1. Notifications first (most apps, today's messages only), or Telegram first (one app, done properly)?
2. Should other apps' conversations mix into the main list, or sit in their own section (as Codes and the plugins
   do), marked with each app's logo?
3. Is a Play-store build in scope for this (it decides how careful the notification-access page must be)?

## Sources

- Slack rate limits for non-Marketplace apps: https://docs.slack.dev/changelog/2025/05/29/rate-limit-changes-for-non-marketplace-apps
  and https://api.slack.com/changelog/2025-05-terms-rate-limit-update-and-faq
- Slack user-token scopes (im:history): https://dev.to/sapotacorp/slack-bot-token-vs-user-token-scopes-least-privilege-in-practice-gj4
- X pay-per-use: https://opentermsarchive.org/en/memos/x-replaces-its-dollar200-entry-level-api-plan-with-a-pay-per-use-model/
  and https://postproxy.dev/blog/x-api-pricing-2026
- WhatsApp interoperability: https://about.fb.com/news/2025/11/messaging-interoperability-whatsapp-enables-third-party-chats-for-users-in-europe/
- Discord on self-bots: https://support.discord.com/hc/articles/115002192352
- Bluesky DMs: https://atp.readthedocs.io/en/latest/dm.html and https://pub.dev/documentation/bluesky/2.15.5/
- Telegram API terms and api_id: https://core.telegram.org/api/terms and https://core.telegram.org/api/obtaining_api_id
- Android notification listener and direct reply: https://developer.android.com/reference/android/service/notification/NotificationListenerService
  and https://android-developers.googleblog.com/2016/06/notifications-in-android-n.html
