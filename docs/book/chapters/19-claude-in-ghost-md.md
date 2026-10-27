# Claude in Ghost.md

Claude can work with your notes in two ways. Inside Ghost.md, with your own Anthropic API key, you ask in a chat and watch Claude write into the note. From Claude's own apps, you add Ghost.md as a connector, and Claude reads and writes your notes from there. You can use either, or both.

Both are part of the **Claude** plugin, which is on unless you remove it in the Market. Its page is **Settings › Claude**, with two parts: **In the app** and **From Claude's own app**. Claude in the app is part of Advanced mode: in Simple mode the docks have no Claude. See [[Simple and Advanced]].

## In the app, with your own key

Works on: Android, iPhone and the Mac. Anthropic bills your key.

1. Make an API key at console.anthropic.com.
2. Open **Settings › Claude**, paste it under **API key** in the **Ask Claude** card, and tap **Keep it**. The app checks it with Anthropic before keeping it, so a mistyped key is said at once.
3. Choose a **Model**: Sonnet 5.5 (the one to start with), Opus 5.5 (the most careful, slower and dearer) or Haiku 5.5 (the fastest and cheapest).

Once kept, the card shows the key's start and end, with **Check** to try it again.

The key is kept in the device's secure storage. While **Keep keys and connections in sync** is on, in Settings › Account's **Sync** card, it is sealed and carried to your other signed-in devices too, iPhone included, with the model, the effort, the spending limit and the Ask Claude note's switch. The server can't read them. **Forget the key**: tap **Forget**, then **Tap again**. With sync on, your other devices forget it too at their next sync.

What you ask, and the notes Claude reads to answer, go from your device to Anthropic and nowhere else.

### The chat

Claude sits at the head of the dock on every page, a ring in Claude's orange. Tap it to open the chat. On a note, the chat starts with the note's `[[Title]]` already in the field, so you can ask about it. You can also open it with **Ask Claude** in the command palette.

Ask in words: "Turn this into a checklist", "Make a note called Standup with these three points", "Which notes mention the cabin?" Claude's thinking streams in as it goes, with a line for each note it reads or changes; tap a line to open its note. **New chat** starts again. The conversation is never written anywhere: it lasts until New chat or until the app closes.

On a phone the chat covers the screen; on a wide window it is a panel down the right.

**Model and effort.** The line under Claude's name, at the top of the chat, says which model and effort are in use. Tap it to change either: the model, and the **Effort**, how hard Claude thinks before answering, from **Low** to **Max**. Lower is quicker and cheaper. Each choice is kept at once.

### Following along

When Claude starts writing, the chat makes way and the note opens. Claude's words arrive at its own caret, word by word, and the page follows them. A bar under the top bar says what Claude is doing, with **Stop**.

Type or tap in the note and the following stops. Claude's words keep landing where it was. **Watch** takes you back to where Claude is typing.

Claude can list, search and read your notes, make a note, add to one, change a passage or rewrite one, and open one for you. It can also list, make, rename, move and delete folders, and file notes into them. It can't delete a note, move one to the Trash, share one, or move a note into or out of an organization: it tells you to do that from the note's Workspace setting.

### Talk to Claude

Under Claude on the dock is a microphone: **Talk to Claude**. Press it and say what you want. A card shows your words as they are heard. A tap, or a two-second pause, sends them; listening stops after a minute at most. The words are heard on the device, and no audio is kept. The microphone is open only while you talk, never waiting for a word.

The card shows Claude thinking. Once Claude writes in a note, the card shrinks to a strip at the top, with **Stop**, and the note opens so you can watch. The answer lands on the strip, which goes by itself a few seconds later. What you said is in the chat afterwards. Without a key, your words go into the "Ask Claude" note instead.

Works on: Android and the Mac.

On Android, **Phone assistant** lets you make Ghost.md the phone's digital assistant. Switch on **Ghost.md as the phone's assistant**, and Android's screen opens: pick Ghost.md under Default digital assistant app. The row under the switch says whether it is chosen, with **Choose** or **Change**. Holding the side key, or your phone's assistant gesture, then talks to Claude. Without a key on the device, it records a voice note instead.

### The "Ask Claude" note

Write a to-do in a note titled **Ask Claude**:

```
- [ ] Add the ferry times to my Trip plan
```

With **Do requests as they are written** on, Claude does it a few seconds after you stop typing, writes a line under it saying what it did, and ticks it. Without a key, what you type in the chat goes into this note, for Claude's own apps to work through.

### A spending limit

The **Spending limit** card sets a monthly limit, in US dollars, on what Claude in the app spends with your key. Switch on **Spending limit**, then pick $5, $10, $25 or $50 a month, or type **Another amount** and tap **Set**. It is off to begin with.

Once the limit is reached, Claude isn't asked until the 1st of next month or until you raise it, and meeting write-ups wait until then. **Warn me at 80%** puts a line in the chat, once a month, when you pass it. The row under them says what this month has cost so far and how many requests it took, with **Reset count**. The count is kept on each device, from what Claude reports for each request, and doesn't include other apps or devices using the same key.

### Meetings by Claude

With a key kept and the plugin on, meetings are written up by Claude instead of the device's model, in the same shape: what was decided, and the to-dos. The transcript goes to Anthropic with your key, and nowhere else. A long voice note is still summarised on the device. With Local only on, a meeting's write-up waits for Claude rather than going to the device's model.

A meeting filed on a device that can't write it up, say a Mac with no key and no model, waits there: "Waiting for a summary: turn on Claude or download the summary model on this Mac, or open Ghost.md on your phone." Any of your devices that can write it takes it on, and the waiting one says "Being summarized on your phone." until it is done. Only one device writes each meeting up. Since the key follows your account, putting it in on your phone is enough for the Mac to write meetings up too.

Sorting follows the same AI. Once a meeting is written up, Claude reads it and files it into the Meetings folder of the workspace it is about. Meetings you filed yourself stay put. Turn this off with **Sort meetings into workspaces**, on the **Meetings** card in Settings › Recording.

## From Claude's own apps

The connector lets claude.ai, Claude Desktop and Claude Code reach your notes. It works with every version of Ghost.md, and needs a Ghost.md account. Claude sees what has synced, and what it writes reaches your devices at their next sync.

### Connecting

In claude.ai or Claude Desktop, open **Settings › Connectors › Add custom connector**, with this address:

```
https://ghostmarkdown.com/api/mcp
```

In Claude Code, one line in a terminal:

```
claude mcp add --transport http glyph https://ghostmarkdown.com/api/mcp
```

A Ghost.md page opens in your browser. Sign in with your handle and password, and you're back in Claude with the tools ready. Your password stays in the browser. Your account key goes to Ghost.md's server, which holds it while the connection lasts, so the server can read your notes while Claude is connected.

To end it, disconnect the server in Claude. A week without using it ends it too. To end every connection at once, every Claude account and computer signed in to yours, ask Claude to sign out everywhere; each then signs in again on the Ghost.md page.

### On your own computer

To keep your key on your machine, run the connector yourself. You need Node.js 20 or newer:

```
curl -fsSL https://ghostmarkdown.com/mcp/glyph-mcp.mjs -o ~/glyph-mcp.mjs
node ~/glyph-mcp.mjs login <your handle>
claude mcp add glyph -- node ~/glyph-mcp.mjs
```

For Claude Desktop, add it in Settings › Developer › Edit Config, with the full path to the file, and restart. `node ~/glyph-mcp.mjs logout` signs that computer out. **How to connect** and **On your own computer** in Settings › Claude have these steps with Copy buttons.

### What Claude can do

- List, read and search your notes, your organizations' included.
- Make a note, rewrite one, or add to one. A task joins the note's list in its own style.
- Add a picture from the web, or write a journal entry.
- Pin or archive a note.
- Move notes to the Trash, and restore them. Emptying the Trash is yours alone.
- List, make, rename, move and delete folders, and file notes into them. Deleting a folder never deletes a note.
- Read a note's comments, add one, reply and resolve.
- Keep your standing instructions in a note called **Claude rules**. Say "always do this from now on" and Claude adds a rule there.

Filing a note into an organization shares it with the team. Claude won't move a note into or out of an organization: it tells you to do that from the note's Workspace setting.

Claude reads fresh before every change. If another device changed the note in between, the write is refused and Claude tries again, so your edit is never written over. In a team's note, Claude's edits merge with everyone else's.

While it works, Claude shows as online, a small dot on the dock's Claude. Follow takes you to the note it is in, and you can watch its caret move.

A note Claude makes or changes through the connector lists Claude among its authors, after you: `authors: yourname, Claude`.

See also: [[AI on your device]] · [[Meetings and the Meet bot]] · [[Organizations and shared notes]] · [[Plugins, one by one]] · [[Privacy]]
