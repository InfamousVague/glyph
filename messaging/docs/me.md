# Me, and friends joining

Matt, 2026-11-14: "Add a 'me' section to settings and allow linking popular social like telegram, discord, x, etc to
be notified when one of your friends or followers joins ghost messaging". Asked how, he chose: a watch list plus the
networks whose follow lists are open; proof by signing in with each network; and nothing kept on the server unless
the person opts in.

| Part | Where | What |
| --- | --- | --- |
| The server's keeper of handles | `relay/lib/handles.dart` (`relay/test/handles_test.dart`) | Links, listing, watch lists, the sign-in pages under `/link/`, reading public profiles |
| Its place in the relay | `relay/lib/hub.dart`, `relay.dart`, `bin/relay.dart` | A connection's `{"dir": …}` messages go to it; `/link/*` is its pages; its settings come from the environment |
| The phone's half | `lib/me/me.dart` (`test/me_test.dart`: two installs and the real relay) | What is linked, watched and joined, kept on the phone; the conversation with the server |
| The screens | `lib/ui/me.dart` | Settings › Me, Settings › Friends joining, linking by code, adding handles |

## What it does

- **Settings › Me**: your number and key; **Linked accounts** (Discord, Telegram, X, Bluesky, Mastodon, GitHub);
  **Tell friends I'm here**, off until switched on; **Remove everything about me**.
- **Settings › Friends joining**: who of the people you watch for is on Ghost Messaging, the newest first and marked
  New until the page is opened; **Add handles**; **Bring in who I follow** for a linked Bluesky, Mastodon or GitHub
  account; the list by network, each handle taken off by a press. The Settings ring on the navigation pill wears the
  number of new ones.

## Why a watch list

Discord, Telegram and X do not let an app read someone's friends or followers (X sells it; Discord and Telegram do
not offer it at all). So nothing can say "your Discord friends" by itself. What works on every network is the other
way round: you say which handles you care about, and you are told when one of them proves the account is theirs and
chooses to be found. Bluesky, Mastodon and GitHub publish who an account follows, so for those the list fills itself.

## Proving an account

A handle is never typed and believed: someone could say they are anyone.

| Network | How | Needs on the server |
| --- | --- | --- |
| Discord | Sign in with Discord (OAuth 2, scope `identify`): the server asks Discord who signed in | `GHOST_DISCORD_ID`, `GHOST_DISCORD_SECRET` |
| X | Sign in with X (OAuth 2 with PKCE, scopes `users.read tweet.read`) | `GHOST_X_ID`, and `GHOST_X_SECRET` if the app is a confidential client |
| Telegram | Telegram's login widget, which signs who it is with our bot's token | `GHOST_TELEGRAM_BOT` (the bot's username, no @), `GHOST_TELEGRAM_TOKEN` |
| Bluesky, Mastodon, GitHub | A code the server makes up (`ghost-` and ten hex digits), put in the account's public profile and read back through the network's public API | Nothing. `GHOST_GITHUB_TOKEN` is optional and lets the server read GitHub more often |

A network whose values are not set is **off**: its row in Settings › Me says signing in is not set up on the relay
server yet, and everything else works. So this can go out with none of the three set, and each is switched on by
adding its values and restarting the relay.

## What the server keeps, and what it can see

`handles.json`, beside the pairings' `channels.json`:

- For each install that linked something, per network: **the SHA-256 of the handle, the SHA-256 of the network's own
  number for the account, and the day.** Never the handle, a name, a token, or anything else the network said.
- Which installs are **listed** (told to watchers). Off until the person turns it on.
- Each install's **watch list, as the same hashes**, and which of them it has yet to be told about.
- A secret the proof codes are made from.

An install is the hub's own name for it (made from its key, proved by a signature as it connects: `hub.dart`), so
only the install itself links, lists and watches for itself.

What that lets the server see beyond what the hub already saw: that an install has some account on a network, and
how many handles another is watching for. Someone who already knows a handle can hash it and find it in the file;
nobody can read a handle out of it. It holds no number, key or name, so it cannot tell a watcher how to reach the
person who joined: the watcher is told the handle is on Ghost Messaging and asks them for their number where they
already talk.

**Nothing is said to the server about any of this until the person links an account, adds a handle, or opens
Settings › Me.** An install that never does is exactly what it was to the hub.

"Remove everything about me" deletes the install's links, listing, watch list and anything waiting for it.

## Setting up the three sign-ins (Matt's to do: they are accounts in his name)

All three want the address a sign-in comes back to. With the relay behind ghost-sms.com that is:

    https://ghost-sms.com/link/discord/callback
    https://ghost-sms.com/link/x/callback
    https://ghost-sms.com/link/telegram/callback   (Telegram asks only for the domain: ghost-sms.com)

1. **Discord.** discord.com/developers/applications › New Application ("Ghost Messaging") › OAuth2. Add the redirect
   above. Copy the Client ID and reset and copy the Client Secret.
2. **X.** developer.x.com › a Project and an App (the free tier is enough: it only asks who signed in). User
   authentication settings › OAuth 2.0, type "Web App" (confidential), callback as above, website
   `https://ghost-sms.com`. Copy the OAuth 2.0 Client ID and Client Secret.
3. **Telegram.** Message @BotFather: `/newbot` (name "Ghost Messaging", a username ending in `bot`), keep the token;
   then `/setdomain`, choose the bot, send `ghost-sms.com`.

Then on the box, as root, a file only root reads, and the relay started again:

    install -m 600 /dev/null /etc/ghost-relay/env     # mkdir -p /etc/ghost-relay first
    cat > /etc/ghost-relay/env <<'EOF'
    GHOST_DISCORD_ID=…
    GHOST_DISCORD_SECRET=…
    GHOST_X_ID=…
    GHOST_X_SECRET=…
    GHOST_TELEGRAM_BOT=…
    GHOST_TELEGRAM_TOKEN=…
    EOF
    systemctl restart ghost-relay

The relay says which sign-ins it has as it starts (`journalctl -u ghost-relay -n 5`). These are secrets: they go in
that file and nowhere in the repository.

## Putting it on the server

From `messaging/`, on the Mac (the box's account is Ghost.md's `tauri/.env`):

    node tool/deploy-relay.mjs --keep-connection && node tool/deploy-site.mjs --caddy

`deploy-relay.mjs` builds and installs the relay with the keeper of handles in it; its service now reads
`/etc/ghost-relay/env` where there is one. `deploy-site.mjs --caddy` adds `/link/*` to what ghost-sms.com's block
passes to the relay. A restart drops whoever is connected to the hub; the apps connect again by themselves.

**Done on 2026-11-14, both on one login at 18:02:03 UTC** (Matt, asked whether to deploy the server's half: "deploy
both yes"). The relay was up again at 18:03:52 and the block at 18:04:14, with every other site on the box
answering after as it had before, and `/apk.json` and `/mac.json` still served. `https://ghost-sms.com/link/`
answers from the relay; `tool/net/live_hub_test.dart` against `wss://ghost-sms.com/hub` passed after it (signed in,
a packet held and handed over, one answered, a room). There is no `/etc/ghost-relay/env` on the box yet: Discord,
X and Telegram are off in the app until their apps are registered and their values put there (above), which is
Matt's to do. The first run stopped before changing anything: the script's check that the port is the relay's own
went by the name `ss` prints, which is cut short ("dart:ghost-rela"), so the running relay looked like a stranger.
It now goes by the service's own process, and the second run went through on the same connection. What the hub
was holding in memory for people who were away at that moment was lost with the restart, as every restart loses it.

## Not yet

- **Not run against the real networks.** `handles_test.dart` and `me_test.dart` stand in for Discord, X, Telegram,
  Bluesky, Mastodon and GitHub with what their documentation says they answer. The first real sign-in on each is
  the test of that, X's token exchange most of all (a public client and a confidential one differ).
- **Told only while the app is open, or as it next opens.** The hub is the phone's Dart side; there is no push.
- **Joining does not start a conversation.** The watcher learns the handle is here, not the number. A friend
  request sent through the hub to someone found this way would close that gap, and needs the key exchange that is
  now done by text to be able to go by the hub.
- A paired computer shows the pages and cannot link or add (it speaks through the phone).
- X's follow list (its paid API), and Discord's and Telegram's friends (not offered to apps at all).
- Instagram, Threads, Signal, WhatsApp, Reddit and the rest: a network is one entry in `networks` (lib/me/me.dart) and
  one way of proving it in `handles.dart`.
