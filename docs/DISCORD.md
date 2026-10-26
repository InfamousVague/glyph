# Discord

Matt, 2026-10-26: "Add a new plugin to post notes to discord chats as well as join discord calls to summarize
meetings."

This file is the **posting** half: `lib/plugins/discord/`. Ghost joining a Discord call to write it up is Ghost in
meetings' work (`meet/`, `server/`, docs/MEET.md) and is not here: it is docs/DISCORD_CALLS.md, the bot in
`discord/bot/`, its page Discord calls on this plugin's page (`lib/plugins/discord/calls_section.dart`).

The plugin is built in, off until added in the Market (category Connections). It is the Slack plugin
(`lib/plugins/slack/`) for Discord, file for file:

| Discord | Slack | What it is |
| --- | --- | --- |
| `manifest.dart` | `manifest.dart` | id `discord`, hosts `discord.com`, `discordapp.com`; storage and the secret prefix |
| `channels.dart` | `channels.dart` | the channels, the webhook's shape, the post, Discord's answers and its 429 |
| `markdown.dart` | `mrkdwn.dart` | a note as Discord's Markdown, and the cut to one message |
| `meetings.dart` | `meetings.dart` | the meeting's message, the setting, the once-per-account mark, the queue of tries |
| `meetings_section.dart` | `meetings_section.dart` | Settings › Meetings › Post to Discord, and the page's Automations line |
| `discord_pane.dart` | `slack_pane.dart` | the plugin's page in Settings |
| `marks.dart` | `marks.dart` | the mark on a note's More sheet |
| `discord.dart` | `slack.dart` | the plugin, its two note actions, its seams |

What it leaves out of Slack's: an organization's news. Notes and meetings were asked for; news can follow.

## Channels: incoming webhooks

A channel is a Discord **incoming webhook**: in Discord, a channel's Edit › Integrations › Webhooks › New Webhook ›
Copy Webhook URL (it needs Manage Webhooks on the server). Pasted on the plugin's page under a name the person gives
it. No sign-in, no bot, nothing on our server: each post goes straight from the device.

- **The URL is held to Discord's shapes** (`allowedDiscordWebhook`), when it is typed, kept and posted to:
  `https://` + `discord.com` or `discordapp.com` (also `ptb.` and `canary.`) + `/api/` + optional `v<n>/` +
  `webhooks/<snowflake>/<token>`, and nothing after: no `?wait=` or `?thread_id=`, no fragment, no `..`, no user
  before the host, no `/slack` or `/github` (Discord's look-alike endpoints, which take other bodies).
- **The URL is a secret**: kept in the secure store as `glyph-discord-webhook:<id>`; the plugin's storage holds only
  `glyph-discord-channels` (`[{id, name}]`). No page shows a webhook again once kept.
- **A reset** forgets them by name (`lib/root/reset_wiring.dart` `discordSecretNames`).
- **Not on an iPhone**, as Slack is not (`lib/core/iphone_app.dart` `notOnIPhone('discord')`): no rows, no section,
  nothing synced in, and the Market says "Android · Desktop".

## Sync

The channels follow the account, sealed, exactly as Slack's do (`lib/sync/connections.dart`, a674e242's sealed keys,
`lib/sync/sealed_keys.dart`): each `glyph-discord-webhook:<id>` sealed on its own under the account key, the list
`glyph-discord-channels`, Settings › Meetings › Post to Discord `glyph-discord-meetings` (switch, channel, share
link), and the plugin's switch `plugin:discord`. A channel added on the Fold posts from the Mac; one forgotten anywhere
is forgotten everywhere. What stays on each device: the queue of meeting posts still to try,
`glyph-discord-meeting-queue`.

That a meeting is posted once is the synced preference `discordMeetingPosts` (`lib/sync/prefs.dart`), merged an entry
at a time: its own mark, beside Slack's `slackMeetingPosts`, so a meeting set to go to both goes once to each.

## Posting a note

On a note's More sheet, once a channel is added: **Post to Discord** (the whole note) and, on a note with a meeting's
summary, **Post the summary to Discord**. More than one channel opens them to choose from.

### Discord's Markdown

Discord reads Markdown, so most of a note goes as written: `**bold**`, `*italic*`, `_italic_`, `~~struck~~`, code
spans and fences, `>` quotes, `-` and `1.` lists, and `[words](https://…)` links. What is turned:

| In the note | In Discord | Why |
| --- | --- | --- |
| title line | `## Title` | Discord's `#` is a shout in a chat |
| `#`, `##` | `###` | the note's own headings under the title |
| `###` and deeper | `**bold line**` | Discord has three heading sizes |
| `__bold__` | `**bold**` | `__` is underline in Discord |
| `- [ ]`, `- [x]` | `- ☐`, `- ☑` | Discord draws no boxes |
| `*` / `+` bullets | `-` | |
| `---` | `———` | Discord draws no rule |
| a table | the same rows in a ``` block | Discord draws no tables; the columns at least line up |
| `~~~` fence | ``` fence | Discord reads backticks only |
| `[words](note/…)`, a picture on the phone | the words / nothing | nobody in the channel can open them |
| `![alt](https://…)` | `[alt](https://…)` | |
| `@@secret@@` | `▇▇▇▇` | a spoiler is one tap from the clear |
| `\|\|x\|\|`, `==x==`, `%%x%%`, `^^x^^`, emoji looks | their words | `\|\|` would be a spoiler |
| a line starting `-# ` | `\-# ` | Discord's small print |

Every post sends `allowed_mentions: {"parse": []}`, so `@everyone`, `@here` and `<@id>` in a note ping nobody, and
`flags: 4` (SUPPRESS_EMBEDS), so links do not unfurl into preview cards.

### Length: one message, cut, with a link to the rest

Discord takes 2000 characters in a message's `content`. **A note is always one message.** A longer one is cut at a
line a little before 2000 (a fence it leaves open is closed, a surrogate pair never split; lengths are counted in
UTF-16 units, never fewer than Discord's characters) and ends:

```
…
**[Read the rest in Ghost.md](https://ghostmarkdown.com/read.html#<id>.<key>)**
```

The link is the note's share link, made by the app's own share (the link the note's Share sheet copies). The row says
so before it is pressed ("…with a share link to the rest of the note, which anyone with the link can read"), since
pressing it shares the note. Signed out, or with no share to make, the cut ends *"The rest is in Ghost.md: it is longer
than one Discord message."*

Why not embeds (description 4096, ten of them, 6000 in all): an embed is a boxed card in small type where a heading is
not drawn as one in every client, so a long note would read as something other than a short one; and 6000 moves the
cut, it does not remove it. Why not several messages: a webhook takes a few posts a second before Discord answers 429,
and a note half-posted when one lands is worse than a note cut where it says so.

### Rate limits

Discord answers a post over its limits with **429** and `retry_after` (seconds, in the JSON body; also the
`Retry-After` header). A wait of up to 5 seconds is waited and the post tried again, twice at most. A longer one is not
waited by someone holding a phone: the post fails with *"Discord asked for fewer posts. Try again in 43 seconds."* A
meeting's post then waits in the queue for the next run or Try now.

Other answers: 204 (or 200) is posted; 404 / 401 / code 10015 / 50027 *"Discord no longer knows this webhook…"*; 403
*"Discord refused the post…"*; 400 / 413 / 50035 *"Discord couldn't read the message."*; 5xx *"Discord had a
problem…"*; a timeout or no network in a sentence of its own.

## Meetings

Settings › Meetings has **Post to Discord**, its own section under Post to Slack, drawn only with the plugin on and a
channel on the device: the switch (off until a channel is chosen), the channel, Include a share link (on unless turned
off, with Slack's warning), and any meeting not posted with Discord's reason, Try now and Don't post. In Simple, the
channel and the share link are behind More. A section of its own rather than one "Post meetings to" list: each chat has
its own switch, channel and share link, a meeting can go to both, and a person with one chat (or none) sees the page as
before.

The root makes `MeetingDiscordPoster` beside Slack's in `lib/root/root_voice.dart`, and the meeting-summarized
closure calls the sorter, then Slack, then Discord, then Lovart, each in its own try. On launch the queue is tried
again (`resume`).

The message is Slack's content, made from the same reading of the summary (`meetingPostOf`):

```
## Launch sync
<t:1792591200:f> · 45 min · HelloTrade
*A call that fixed the launch date and who does what next.*

**Action items**
- **@matt**: First pass at the site copy by Friday
- **@dana**: Book the venue *(due Sat, Oct 31)*
- **Sam**: the press list
- **@matt**: ~~Send the invite~~

**Decisions**
- No paid ads until the beta closes.

[Read the notes and transcript](https://ghostmarkdown.com/read.html#…)
-# In Ghost.md: `ghostmd://note/…`
```

- `<t:…:f>` is Discord's timestamp: each reader sees the time in their own zone. A due day stays words: it is a day,
  not a moment.
- **`ghostmd://` is not clickable in Discord.** Discord links only `http`/`https`: a `[words](ghostmd://…)` is drawn as
  the raw brackets and a bare `ghostmd://…` is plain text, in the desktop, web and phone clients. So the app link goes
  as copyable code on a small-print line, and the share link is the one to press. (Not checked in a live client from
  here: no Discord account was used and nothing was posted. Worth a look on the first real post.)
- It fits one message with the links kept: past 2000 the decisions go first, then action items from the end,
  replaced by *"and 3 more in Ghost.md"*.

## Tests

`test/plugins/discord/` (channels, markdown, actions, meetings, meetings_section), and Discord's cases in
`test/sync/sealed_keys_test.dart`, `test/root/reset_test.dart`, `test/core/iphone_app_test.dart`,
`test/plugins/registry_test.dart`, `test/plugins/plugins_pane_test.dart`, `test/market/market_screen_test.dart`. Every
HTTP call is answered by a fake (`test/plugins/discord/support.dart` `FakeDiscord`); none reaches Discord.

Pictures: `flutter test --update-goldens test/plugins/discord/discord_shots_test.dart` writes
`build/feature-shots/discord/discord-{page,meetings}-{phone,mac}-{light,dark}.png`.
