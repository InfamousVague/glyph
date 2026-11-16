# Ghost Messaging's Discord presence bot

Lets the app show a linked Discord server's voice channels as **spaces**, with who is in each. Presence only: the
bot never joins voice and carries no audio (yet). One Node program (discord.js 14.27.0) holding one gateway
connection to Discord with the `Guilds` and `GuildVoiceStates` intents (nothing privileged), answering the app over
HTTP on `127.0.0.1:18788`. On the box the web server passes `https://ghost-sms.com/discord/*` (and
`https://gogho.st/discord/*`) to it with the `/discord` prefix kept.

This is a separate bot from Ghost.md's Discord notetaker (`discord/bot` at the repository root, service
`glyph-discord`), which records calls. They share nothing.

```sh
npm ci                      # discord.js and what it needs
npm test                    # node --test: codes, tokens, the state JSON, the HTTP routes (no Discord needed)
DISCORD_TOKEN=… DISCORD_APP_ID=… npm start   # a real bot; logs the invite link
```

## How linking works

1. Someone with **Manage Server** runs `/ghost link` in the Discord server. The bot answers only them
   (ephemeral): *"Your code is ABC123. In Ghost Messaging open Spaces › Add a Discord server and enter it. It works
   once, for 10 minutes."*
2. The app sends the code to `POST /discord/claim` and gets back a token for that server.
3. The app asks `GET /discord/state?token=…` whenever it wants the server's voice channels and who is in them.
4. `/ghost unlink` (Manage Server) revokes every token for the server. `/ghost status` says how many links it has.

Discord sets permissions per command, not per subcommand, so all of `/ghost` is Manage Server by default
(`default_member_permissions` = ManageGuild); a server can open it to more people under Server Settings ›
Integrations, and `link`/`unlink` still check Manage Server themselves.

## The contract

All answers are JSON, with `Access-Control-Allow-Origin: *` (GET, POST and OPTIONS preflights from any origin) and
`Cache-Control: no-store`. Request bodies are capped at 4 KB (`413 {"error":"too large"}`). Every route also answers
without the `/discord` prefix (`/claim`, `/state`, `/invite`).

**`POST /discord/claim`** with `{"code":"ABC123"}`

- `200 {"token":"<32 lowercase hex>","guild":{"id":"…","name":"…","icon":"https://cdn.discordapp.com/icons/<id>/<hash>.png" | null}}`
- `404 {"error":"unknown code"}` for an unknown, expired or already-used code. A code works once, for 10 minutes;
  case and surrounding spaces don't matter. Each claim makes a new token.
- `429 {"error":"slow down"}` (with `Retry-After`) past 10 attempts a minute from one address, or 300 a minute
  overall, so codes can't be guessed. The address is the last `X-Forwarded-For` entry when the request comes from
  loopback (Caddy), else the socket's.
- `410 {"error":"gone"}` if the code was right but the bot has since left that server; `400 {"error":"bad json"}`.

**`GET /discord/state?token=<token>`**

```json
{
  "guild": { "id": "…", "name": "…", "icon": "https://cdn.discordapp.com/icons/…/….png" },
  "channels": [
    {
      "id": "…", "name": "Lounge", "kind": "voice", "position": 0,
      "members": [
        { "id": "…", "name": "Casper", "avatar": "https://cdn.discordapp.com/avatars/…/….png",
          "muted": false, "deafened": true, "video": false, "streaming": false, "bot": false }
      ]
    },
    { "id": "…", "name": "Talks", "kind": "stage", "position": 1, "members": [] }
  ],
  "at": 1763251200000
}
```

- Every voice (`"voice"`) and stage (`"stage"`) channel the bot can see, empty ones included, in Discord's sidebar
  order: channels outside a category first, then each category in its order, and by position within. `position` is
  the channel's index in that order (0, 1, 2, …).
- Members within a channel are sorted by name. `name` is their nickname on the server, else their display name,
  else their username. `avatar` is their server avatar, else their own, else `null`. `muted` and `deafened` are
  true for self or server mute/deafen. A voice state without a cached member is fetched over REST first (no
  privileged intent needed); one that still can't be found shows as `"Unknown"`.
- `401 {"error":"not linked"}` for an unknown or revoked token; `410 {"error":"gone"}` when the bot has been removed
  from the server (the links are kept, so they work again if it's added back); `503 {"error":"starting"}` while the
  bot is still connecting to Discord, or Discord reports the server unavailable.

**`GET /discord/invite`** → `200 {"url":"https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot%20applications.commands&permissions=1024"}`.
No token needed; the app shows it as "Add the bot to your server". `permissions=1024` is View Channels only.

**`GET /discord/`** → `200 {"ok":true,"service":"ghost-discord"}` (the deploy's health check).

## What it keeps

- **Links**: `links.json` in `DISCORD_DATA`, holding the server id and the SHA-256 of each token, never the token
  itself. Written to a temporary file and renamed over the old one. Tokens are checked by comparing the hash against
  every stored hash in constant time.
- **Codes**: in memory only. A restart forgets codes not yet used (run `/ghost link` again). At most five waiting
  per server.
- **Logs**: outcomes, server ids and counts. Never a token, a code or a member's name.

## Environment

| Name             | What                                                                 |
| ---------------- | -------------------------------------------------------------------- |
| `DISCORD_TOKEN`  | The bot's token (required).                                          |
| `DISCORD_APP_ID` | The application's id (required: the invite link and the commands).   |
| `PORT`           | Default `18788`. It always listens on `127.0.0.1` only.              |
| `DISCORD_DATA`   | Where `links.json` lives. Default `./data` (on the box: `/var/lib/ghost-discord`). |

`/ghost` is registered globally each time the bot starts. Global commands can take a little while to show up in a
server the first time.

## Code layout

- `src/bot.js`: the only file that imports discord.js. The client, the commands, and the adapter that hands
  servers to the HTTP side.
- `src/http.js`: the routes, CORS, the body cap, the rate limits.
- `src/state.js`: builds the `/state` JSON from a guild-like object (the fields of discord.js's `Guild` it reads are
  listed at the top).
- `src/codes.js`, `src/store.js`, `src/ratelimit.js`, `src/commands.js`: link codes, tokens, limits, and what
  `/ghost` answers.
- `test/`: `node --test` with fake guild, channel and member objects.

## On the box

`node tool/deploy-discord.mjs` (from `messaging/`) installs it as the `ghost-discord` user (no shell), with its own
Node 22 in `/opt/ghost-discord/node`, the program in `/opt/ghost-discord/app`, links in `/var/lib/ghost-discord`,
and the token in `/etc/ghost-discord/env` (root only). The systemd service `ghost-discord` restarts it if it stops,
can write nowhere else, and is capped at 200 MB and half a CPU. `tool/deploy-site.mjs --caddy` passes `/discord/*`
to it.

## Matt's one-time setup

1. Create an application at <https://discord.com/developers/applications>, open **Bot**, and press **Reset Token**
   to copy its token. Copy the **Application ID** from **General Information**. No privileged intents are needed:
   leave Presence, Server Members and Message Content off.
2. Put both in a file on the Mac, for example `~/.config/mattssoftware/ghost-discord.env`:

   ```
   DISCORD_TOKEN=...
   DISCORD_APP_ID=...
   ```

   Then, from `messaging/`, run:

   ```sh
   node tool/deploy-discord.mjs --env ~/.config/mattssoftware/ghost-discord.env --glyph ~/Development/Apps/glyph --keep-connection \
     && node tool/deploy-site.mjs --caddy --glyph ~/Development/Apps/glyph
   ```

   The token goes to the box on the ssh session's stdin, never in a command line or a chat. The second command tells
   the web server about `/discord/*`; it's needed only once. Run both from a checkout where this folder is merged with
   the latest site, because `deploy-site.mjs` also ships `site/` from whatever checkout it runs in. Later deploys are just `node tool/deploy-discord.mjs`
   (the values on the box are kept).
3. Open the invite link to add the bot to a server. The deploy prints it, the service logs it, and
   `https://ghost-sms.com/discord/invite` returns it. The template is
   `https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot%20applications.commands&permissions=1024`.
   Then run `/ghost link` in that server and enter the code in the app.
