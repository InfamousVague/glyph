# Ghost in a Discord call

Matt, 2026-10-26: "Add a new plugin to post notes to discord chats as well as join discord calls to summarize
meetings." This page is the **call** half: someone in a Discord voice channel runs `/ghost join`, Ghost joins the
channel, records it, and the call reaches their Ghost.md account sealed, is filed as a note and written up on their
device with who said what, exactly as a Google Meet is (docs/MEET.md). The posting half is docs/DISCORD.md. Both are
the Discord plugin's (Matt, the same day: Discord calls belong to the Discord plugin, with their own switch and the
linking on its page; and "I want settings / meetings to be broken up into three plugins where each zoom, Google meets
and discord handle their own meetings").

| Where | What |
|---|---|
| `discord/bot/` | the bot: a Node service on the box, one gateway connection, the voice connections, the mix |
| `discord/box/glyph-discord.service` | its unit |
| `scripts/setup-discord-box.mjs` | installs it on the box, and registers `/ghost` |
| `server/src/discord.rs`, `server/src/store/discord.rs` | the routes: linking, the switch, calls as bookings |
| `lib/plugins/discord/calls.dart`, `calls_section.dart` | the plugin page's Discord calls |
| `lib/meet/` | the take filed and written up, as a Meet's (`gmt.dart` reads its kind and its turns) |

## Setting it up (Matt)

Each step once. Nothing here is done by an agent: the bot's token is Matt's, and the box's logins are few.

1. **The application.** Open <https://discord.com/developers/applications>, **New Application**, name it `Ghost`,
   accept the terms, **Create**. On **General Information** copy the **Application ID** into `tauri/.env` as
   `DISCORD_APP_ID=<the digits>`. An app icon here is what people see beside Ghost's messages.
2. **The bot's token.** **Bot** in the left column. **Reset Token**, confirm, **Copy**, and put it in `tauri/.env` as
   `DISCORD_BOT_TOKEN=<the token>`. Discord shows it once; a new reset makes the old one stop working. While on this
   page: leave **Public Bot** on if other people's servers may add Ghost, off if only Matt's may. Leave **Requires
   OAuth2 Code Grant** off.
3. **Intents.** Still on **Bot**, under **Privileged Gateway Intents**: leave all three **off**. Ghost needs only
   the non-privileged Guilds and Guild Voice States intents, which need no switch: a member in a voice channel comes
   with their nickname in their voice state, so **Server Members** is not needed for names, and slash commands carry
   their own words, so **Message Content** is not needed either. **Presence** is never needed.
4. **The bot's key to glyph-api.** A second, separate secret: `openssl rand -hex 32`, into `tauri/.env` as
   `GLYPH_DISCORD_TOKEN=<64 hex>`. This is not Discord's; it is what the bot shows glyph-api on loopback, as
   `GLYPH_MEET_TOKEN` is the Meet bot's.
5. **Optional, for trying it first:** your server's id as `DISCORD_GUILD_ID` (Discord › User Settings › Advanced ›
   Developer Mode on, then right-click the server › Copy Server ID). With it, `/ghost` is registered in that one
   server and shows at once; without it, globally.
6. **The invite link.** **OAuth2** › **OAuth2 URL Generator**. Scopes: `bot` and `applications.commands`. Bot
   permissions: **View Channels**, **Send Messages** and **Connect**. Not **Speak** (Ghost never talks; it joins
   muted) and not **Use Voice Activity** (that is about sending sound, which Ghost does not). Integration type: Guild
   Install. Copy the generated URL; it is
   `https://discord.com/oauth2/authorize?client_id=<DISCORD_APP_ID>&scope=bot%20applications.commands&permissions=1051648`.
7. **Into your server.** Open that URL, choose your server (you need **Manage Server** on it), **Authorize**. Ghost
   shows in the member list, offline until the bot runs.
8. **Deploy**, in the order below ("Deploying").
9. **Try it.** In Ghost.md: the Market › Discord › Add, then Settings › Discord › Discord calls › **Link Discord**.
   In your server, any channel: `/ghost link <the code>`. Join a voice channel, `/ghost join`, talk, `/ghost leave`.
   The call shows under Your Discord calls, and once written up, opens its note.

To let Ghost.md's own builds show an "Add Ghost" button on the plugin page, build with
`--dart-define=GHOST_DISCORD_APP_ID=<DISCORD_APP_ID>`; without it the step says to use the invite link.

## Deploying

1. `node scripts/deploy-server.mjs`: glyph-api with the Discord routes, and `GLYPH_DISCORD_TOKEN` in its env file.
   Without the token in `.env` the routes are not mounted, and the app draws "Discord calls are not on this service
   yet".
2. `node scripts/setup-discord-box.mjs --register-commands`: the bot, its Node, its user and unit, its env file, and
   `/ghost` registered. One login. Prints the OS, glibc, Node, the DAVE library's load, and the unit's state.
3. The app: an OTA (or a build) with `lib/plugins/discord/calls*.dart`.

A later bot change is `node scripts/setup-discord-box.mjs` again (one login): the code shipped, the previous kept as
`/opt/glyph-discord/app.prev`, restarted unless a call is being recorded (then `sudo systemctl restart
glyph-discord` after it). `--print` shows what would run without logging in or reading `.env`; `--register-only`
registers `/ghost` and installs nothing. Rollback: `sudo rm -rf /opt/glyph-discord/app && sudo mv
/opt/glyph-discord/app.prev /opt/glyph-discord/app && sudo systemctl restart glyph-discord`. Logs: `journalctl -u
glyph-discord` (ids, states, counts; never a name, a title or a word).

## Linking, and the switch

- **A code.** Settings › Discord › Link Discord: the device sees to the account's encryption key (a call is sealed to
  it), then `POST /api/v1/discord/link-code` answers eight letters and digits from an alphabet with no look-alikes
  (no 0, O, 1, I, L or U), shown `K7QM-2XRP`, good once and for ten minutes; only its SHA-256 is kept. The page shows
  it with the two steps and Copy for `/ghost link K7QM-2XRP`, and reads the link every four seconds while it shows.
- **Redeemed** by the bot: `/ghost link <code>` → `POST /api/internal/discord/link {code, user, name}`. Any case,
  with or without the dash. A Discord user may try ten codes an hour, and everyone together sixty a minute: a
  guesser against 6.5 × 10^11 codes gets nowhere.
- **One each way.** A Discord user is linked to one account (linked again with another account's code, the link moves
  there); an account to one Discord user (a new one takes the old one's place).
- **Join Discord calls**, on the plugin page once linked: on from the linking, kept on the link on the service
  (`PUT /api/v1/discord/calls {on}`), since the bot reads it and has no key. Off, `/ghost join` answers where to turn
  it on. A sync pass on a device where the Discord plugin is off turns it off on the service, once
  (`discordCallsFollowPlugin`), so taking the plugin out in the Market stops Ghost joining calls too; it is turned on
  again by hand. Its own flag, because the per-account meeting kinds the Meet and Zoom plugins are getting were not
  on main when this was written; it can move into them.
- **Unlink** asks first, in the card, then `DELETE /api/v1/discord/link`: the link and any code go; recorded calls
  stay.

## A call

1. **`/ghost join`**, run by someone in a voice channel. The bot answers privately (ephemeral) and refuses: outside
   a server; not in a voice channel; a Stage channel; Ghost already recording in this server ("One call a server at a
   time": Discord gives a bot one voice connection a server); four calls at once across all servers; no View Channel
   or Connect there.
2. `POST /api/internal/discord/session {user, guild, channel, title}`: not linked is 404 (answered with how to link),
   the switch off 403, no encryption key yet 409, too many 429 (twenty calls a Discord user an hour, and the 100
   meetings to come a Meet account may have). Otherwise a booking like any meeting's (`meet_bookings`): uid
   `discord:<id>`, its url the channel's (`https://discord.com/channels/<guild>/<channel>`), its title "General in
   Ghost HQ", from now for 3 h 15, `joining`. So the device lists it, "Leave now" sets `leave`, the hourly sweep
   blanks and forgets it, and nothing is kept in the clear that a Meet's booking does not keep, nor for longer.
3. **Joining**: the voice connection (self-muted, not deafened), 30 s to be ready, else `failed: join_failed`. Then
   `in_call`, and **the notice** in the voice channel's own chat (below).
4. **Recording**: each person in the channel subscribed on the receiver (and anyone who joins, or speaks); every
   packet to the recorder. Every 5 s the people are counted; every 20 s `GET /api/internal/discord/due` tells the bot
   of a device's Leave now.
5. **Leaving**, on the first of: `/ghost leave` (anyone in the call, the person who asked, or someone who may Manage
   Channels); the device's Leave now; alone for 2 minutes; after a big group (5 at once, Ghost counted), down to Ghost
   and one more for 2 minutes; three hours; Ghost moved or put out of the channel, or its connection gone for good;
   the service stopping. These are the Meet bot's own rules (`meet/bot/lib/decide.mjs` `leaveReason`, imported, not
   copied), with Discord's exact member count read as the Meet bot reads the People button. A line in the chat says
   why Ghost left.
6. **The take**: `PUT /api/internal/discord/{id}/take`, as the Meet bot's (multipart `audio`, `captions`, `startedAt`,
   `endedAt`; five tries; deleted when taken, or when refused with 409; else kept in `work/failed/` and `failed:
   upload`). glyph-api seals it on arrival with meet.rs's own `put_take`, and the call's end is moved to now. A call
   in which nobody was heard has no take: `failed: nothing_heard`.

The bot restarted in a call cannot finish it: on start it moves leftover files to `work/failed/` and posts each call
the service still has as under way `failed: restarted`.

## Recording people needs their knowledge

- **The notice**, as Ghost starts recording, in the voice channel's chat (or, where Ghost may not post there, in the
  channel `/ghost join` was run from): "**Ghost is taking notes for Sam Lee.** This call is being recorded from now
  on, for Sam Lee's Ghost.md, where it is written up with who said what. The recording is sealed to their account as
  it arrives. Anyone here can stop it with `/ghost leave`."
- **Someone joining later** is told by name, once: "Ali, Ghost is recording this call for Sam Lee's Ghost.md.
  `/ghost leave` stops it."
- **Anyone in the call can stop it**, not only the person who asked.
- Every message is sent with no mentions allowed: a name is text, never a ping, and `@everyone` in a nickname pings
  nobody.
- Discord itself shows Ghost in the channel's member list while it is there.

## The recording

Discord hands a bot each speaker's Opus packets apart, a stream a person, and only while they speak. The device
writes a meeting up from one recording, so the bot makes one (`discord/bot/lib/`):

- **Decoded** per speaker (`codec.mjs`: opusscript, libopus in WebAssembly, mono 48 kHz; Discord's stereo folded).
- **Laid on one timeline** (`mixer.mjs`) in 20 ms frames from the recording's start: a burst of speech placed where
  its first packet arrived and then by count, so network jitter does not smear a voice; a packet more than 200 ms
  behind its count (a pause, lost packets) starts the count again where it arrived, keeping the silence between; an
  early rush keeps its count. A frame is mixed 400 ms after its time; a packet later than that is dropped and
  counted. Voices summed and clipped to 16 bits; nobody speaking is silence.
- **Encoded** again, Opus VOIP at 32 kbit/s, and **written as WebM** (`webm.mjs`: the EBML header, a Segment of
  unknown size, one mono Opus track, a Cluster every 5 s written whole), the container the device reads for a Meet
  (`lib/meet/webm.dart`), to `/var/lib/glyph-discord/work/<id>.webm`. About 15 MB an hour.
- **Who spoke when** (`turns.mjs`): each person's speaking intervals (a packet that is not Discord's silence frame,
  until 600 ms quiet), kept as they close in `<id>.speech.ndjson`; at the end, the floor: at each moment, of those
  speaking, the one who began last, and when they stop, the one still speaking who began last before them; an
  interval under 400 ms (a cough, an "mm") never takes it. A line each time it passes, `{at, speaker, text: ""}`,
  the speaker the person's server nickname, else their display name. `at` is written a second late, because the
  device moves every caption turn a second earlier for Meet's captions' lag (`lib/meet/speakers.dart`
  `captionLagMs`; a test holds the two equal).

`node --test` in `discord/bot` tests the mixing (jitter, pauses, rushes, late packets, overlap, clipping), the turns,
the WebM read back element by element, a real call's worth of Opus through the whole recorder decoded again to find
each voice where it spoke, the API client against a stand-in (paths, token, no proxy headers, the take's multipart,
every answer `/ghost link` and `/ghost join` can get), the leaving rules, the upload's keep-or-delete, and the
words. With `GHOST_WRITE_FIXTURE=1` it writes `test/meet/fixtures/discord_mix.webm`, which the device's own test
reads with `readWebmOpus`.

## On the device

The meet pass files a Discord take as a Meet's (docs/MEET.md, "On the device"): opened with the account's key, the
sound decoded to the note's recording, written up by Whisper, the speakers named, summarised, sorted, and posted to
Slack or Discord where those are set. What is Discord's own:

- **Its kind.** A booking and a take of a Discord call say `kind: "discord"` (server/src/meet.rs `kind_of`, read from
  the uid, so it outlives the sweep blanking the link); `MeetService.discord` in the app, "Discord" on a row.
- **Its turns** have no words. `readCaptions` keeps a line with a speaker and no text (and still drops one with
  neither); `captionsSection` keeps such a turn as `**Sam Lee (0:01):**`; `turnsOf` reads it back; `withSpeakers`
  and `phraseSpeakers` name every phrase from them.
- **Filed without its sound** (an iPhone, after a day for a device that can keep it): "The recording could not be
  kept on this device, and Discord shows no captions: who spoke when is below.", and a `## Who spoke` list.
- **Settings › Discord › Discord calls** (the plugin's page; nothing in Settings › Meetings): not linked, Link
  Discord, the code, the two steps and Copy; linked, "Linked as sam_lee" with Unlink (asked first), **Join Discord
  calls**, and how to start one. Then **Your Discord calls**: this account's meetings of kind `discord`, those going
  on first then by day, each with where it stands ("In the meeting", "Written up", "Couldn't join: Ghost heard nobody
  in the call"), Leave now on one going on, and one written up opening its note. The shared meetings list filtered by
  kind that the Meet and Zoom plugin pages are getting was not on main when this was written; this is the same rows
  built the same way (`meetListed`, `meetWhen`, `meetStateWords`, `meetingNoteFor`), to move onto it.

## The bot and the box

| | |
|---|---|
| user | `glyph-discord`, a system user of its own (no shell, home `/var/lib/glyph-discord`, 0700): it needs no screen, no sound server and no browser profile, and shares nothing with the Meet bot but the loopback port |
| Node | `/opt/glyph-discord/node`, the official v22.23.4 for linux-x64 fetched on the box from nodejs.org and checked against its SHA-256 before it is unpacked. `@discordjs/voice` 0.19 needs Node 22.12 or newer; the box's `/usr/bin/node` is Ubuntu's 18, which glyph-mcp and the Meet bot keep |
| code | `/opt/glyph-discord/app/discord/bot` and the three Meet bot files it imports (`meet/bot/lib/decide.mjs`, `api.mjs`, `log.mjs`) at the same relative paths; dependencies installed on the Mac for linux-x64 (`npm ci --os=linux --cpu=x64 --libc=glibc --ignore-scripts`), so the DAVE library's prebuilt binary comes and nothing is compiled on the box (it has no npm) |
| env | `/opt/glyph-discord/glyph-discord.env`, root:glyph-discord 0640: `DISCORD_BOT_TOKEN`, `GLYPH_DISCORD_TOKEN`, `DISCORD_APP_ID`, `DISCORD_GUILD_ID`. The tokens go over ssh's stdin, shape-checked, never in an argument list, never printed |
| unit | `glyph-discord.service`: `MemoryMax=1G`, `CPUQuota=100%`, `Nice=5`, `ProtectSystem=strict`, `PrivateTmp`, `PrivateDevices`, `RestrictNamespaces`, no `MemoryDenyWriteExecute` (V8 and WebAssembly are JITs) |

## The limits

- **Voice receive is not an official Discord API.** Discord documents sending voice for bots; receiving works because
  a bot in a channel is sent everyone's packets, and libraries decode them, but Discord makes no promise and has
  changed it before. @discordjs/voice's maintainers call receive "it may work". It may break with a Discord change,
  and the fix is then a library upgrade.
- **DAVE.** Discord's end-to-end encryption for voice (the DAVE protocol, MLS for the keys, each frame encrypted by
  the speaker) became mandatory for voice channels, DMs and Go Live on 2026-03-01: Discord no longer accepts a voice
  connection that does not speak it. **It does not shut bots out**: a bot in the channel is a member of the call's
  MLS group like any client, and decrypts what it receives. @discordjs/voice does this since 0.19.0 with
  `@snazzah/davey` (the only DAVE library it supports). But **receive was broken in 0.19.0 and 0.19.1**
  (discord.js issue #11419, Feb-Mar 2026: reconnect loops, `DecryptionFailed(UnencryptedWhenPassthroughDisabled)` on
  the first packets, no audio captured); the fix (PR #11449, merged 2026-03-13: RTP padding stripped before the DAVE
  layer, and guards on what is parsed) is in **0.19.2** (2026-03-17), which this bot pins, with davey 0.1.12; its
  dist was read to confirm both. What remains: some packets fail to decrypt while the group changes (someone joins or
  leaves, a key rotates); the library drops them (`null`), and the mixer leaves silence there, so a word or two can
  be lost at each change. One report after the fix (issue #11441) measured lost packets; that is not known to be
  closed. A stream the library gives up on after too many failures is closed, and the bot subscribes the person again
  when they next speak. `daveEncryption: false` is no way round: Discord requires DAVE. What the bot does about it:
  it logs packets, speakers, late and broken packets each minute and at the end; a call in which nobody was heard is
  `failed: nothing_heard` rather than an empty take, which is what a broken receive will look like.
- **Not yet tried against Discord.** No agent may log in to Discord or the box, so the gateway, the voice
  connection and DAVE receive are untested end to end; everything around them is tested. Matt's step 9 is the first
  real call. If no sound comes, `journalctl -u glyph-discord` shows `packets=0` (nothing received: permissions, or
  receive broken) or `packets=N speakers=0` (only silence frames), and the version to try next is the newest
  @discordjs/voice.
- **Stage channels** are refused. A bot in a Stage is in the audience, and who may speak changes by request; untested,
  so not offered.
- **One call a server at a time**, four in all (the box's CPU: each speaker decoded and the mix encoded in
  WebAssembly).
- **Names** are Discord's at the moment of the call; two people with the same nickname read as one speaker.
- **The recording leaves Discord's end-to-end encryption**: Ghost is a participant, as a person recording on their
  phone would be. It is sealed to the account on arrival on Ghost.md's server, and the notice says so.

## Dependencies (discord/bot/package.json, exact)

| Package | Version | Licence | Why |
|---|---|---|---|
| discord.js | 14.27.0 | Apache-2.0 | the gateway: slash commands, voice states, members, messages |
| @discordjs/voice | 0.19.2 | Apache-2.0 | the voice connection, the receiver's per-user Opus streams, DAVE; 0.19.2 for the receive fix |
| @snazzah/davey | 0.1.12 | MIT | DAVE (MLS and frame decryption), a prebuilt native binary per platform (linux-x64-gnu on the box) |
| opusscript | 0.1.1 | MIT | Opus decode per speaker and encode of the mix, libopus in WebAssembly: nothing to compile |
| @noble/ciphers | 2.4.0 | MIT | XChaCha20-Poly1305 for voice transport, should Discord pick it over AES-256-GCM (which Node's own crypto does) |

With what they bring (all MIT, Apache-2.0 or 0BSD): ws, undici, prism-media, discord-api-types, @sapphire/*,
@discordjs/{builders,collection,formatters,rest,util,ws}, @vladfrangu/async_event_emitter, lodash, lodash.snakecase,
magic-bytes.js, fast-deep-equal, ts-mixer, tslib, @types/*. About 30 MB installed.
