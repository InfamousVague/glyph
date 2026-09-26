# Notion and GitHub

_Four plugins come with Ghost.md. Two of them carry a note's list items to where the work is tracked, and keep each item and its task agreeing._

## The four plugins

| Plugin | In a line |
| --- | --- |
| **Notion** | List items become tasks on a Notion board, and a ticked box and a finished task agree. |
| **GitHub** | List items become issues on a repo, and the repo is read into a short briefing for the model on your phone. |
| **Marks** | Ghost.md's own formatting on top of Markdown: the spoiler, the highlight, the aside and the rest, and the five effects. |
| **Claude** | A page with the way to let Claude read and write your notes ([[Claude on your notes]]). |

All four live in **Settings › Plugins**, a card each with a switch, and all four start on. A plugin switched off offers nothing anywhere, at once: no rows on a note's More sheet, no swipe, no page in Settings, nothing for the model. What it kept stays where it was, so switching it on again brings it all back. With Marks off, its marks read as plain text.

Each card says in one line what the plugin may reach, and **Why** opens the reason for each part:

| Plugin | What it may reach |
| --- | --- |
| Notion | Your notes · The internet (api.notion.com, attack.fm) · Voice commands · Built-in app commands |
| GitHub | Your notes · The internet (api.github.com) · The model on your phone |
| Marks | Nothing. Its line is empty. |
| Claude | Your notes · The internet (attack.fm) |

**Local only** (Settings › Formatting) holds off every plugin that uses the internet, whatever its switch says. Notion, GitHub and Claude go quiet, and their cards say "Off while Local only is on". Marks carries on.

## Notion

### Signing in

Notion works in the Ghost.md app, on Android or the Mac, not in the web version. Open **Settings › Notion** and tap **Sign in**. Notion opens in your browser and asks which pages and boards Ghost.md may use. Tick the boards you want, then come back. Ghost.md collects the sign-in by itself.

Signing in needs a secret that no app can carry, so that one step goes through Ghost.md's server. The server holds the answer in memory for up to ten minutes, until your device collects it, and only the device that started the sign-in can collect it. After that the sign-in is kept on the device, in the app's own files, where no page can read it. Your notes never pass through.

The page then lists the boards Notion shared with Ghost.md. For more boards, sign in again and tick them.

### Linking a note to a board

Open the note's **More** sheet, from the three dots in its tools. Under **Linked to**, tap **Notion board** and choose one. The note now wears a small mark at its top with the board's name, and a tap on it opens the More sheet again. **Don't send this note to Notion** takes the link away.

### Sending items

There are four ways, all from the note:

- **Swipe an item left.** The line follows your finger and a tile behind it says Notion. Let go past the point where it counts, and it sends.
- **Tap the quiet word** _Notion_ at the end of an item not sent yet.
- **Press and hold the line**, or right-click it on a Mac, and choose **Notion** from its menu.
- **Send list to Notion**, on the More sheet, sends every item not sent yet. Ticked to-dos stay behind: a done thing is not a task to make.

Each item becomes a task named by its words. The line keeps its words and gains a mark at its end, which the note draws as a small pill:

```
- [ ] Book the ferry [notion](https://www.notion.so/…)
```

Pressing twice does not make two tasks. The same words, sent from the same note to the same board within five minutes, are marked with the task already made.

### The pill, and done both ways

The pill reads the task back from Notion: its status, and a priority and a due date where the board has them. A note opened offline shows what it last read. Tap the pill for its drawer: **Open in Notion**, **Mark done in Notion** or **Reopen in Notion**, **Use these words as its title** when the two differ, **Refresh**, and **Unlink**, which takes the link off and leaves the words.

A linked to-do and its task agree on done, both ways:

- Tick the box, and the task moves to the board's first done status, or its Done box is ticked.
- Finish the task in Notion, and the box ticks itself the next time the note reads it: when you open the note, when you come back to the app, and once a minute while the note is on screen.

A box you set by hand stays as you set it until the task itself changes again, so the note never argues with you. A board with no status and no checkbox has nothing to write to, and the box stays as you set it.

### Not by voice, at this version

The Notion card still lists voice commands, but a finished recording no longer runs them. Said while recording, "send that to Notion" sends nothing. On its own it stays in the note as words. After Hey Ghost, in a note you are adding to, it is taken as an ask of the AI. The recorder can still suggest it in a pause, but the suggestion is out of date. Send from the note instead.

## GitHub

### Linking a repo

On the More sheet, under **Linked to**, tap **GitHub repo**. Type the repo as `github.com/owner/repo` and tap **Read and link**. A public repo needs nothing else. For a private one, tap **Private repo?** and add a token that can read it.

### The briefing

Ghost.md reads the repo on your device: its description, the shape of its folders, and up to eight files that say what it is. Those are the README, notes written for AI tools such as `AGENTS.md`, a few docs, and a manifest such as `package.json` or `Cargo.toml`. The model on your phone then writes a short briefing of the project's names, parts and terms. Where there is no model, on the web or before one is downloaded, the README's opening stands in.

Whenever the model on your phone works on the note, the briefing goes with it: every run on its More sheet, a spoken ask, and the review. So names come out spelled right. The model is told to use it and not to add it to the note. **Settings › GitHub** lists every repo read, what wrote its briefing and when, with **Forget**.

### Issues

Sending needs a token. Add one in **Settings › GitHub**, under Token, and tap **Keep it**. It stays on the device.

Then items go as issues the same four ways: the swipe, the quiet word _GitHub_, the press-and-hold menu, and **Send list to GitHub**. An issue carries the item's words as its title, and nothing else of the note. The line gains its mark:

```
- [ ] Ship the page [github](https://github.com/owner/repo/issues/12)
```

From then on the item and the issue are one thing. Tick the box and the issue closes as completed. Close it on GitHub and the box ticks itself. The pill says whether it is open, with up to two short facts: who it is on, a label, its milestone. Its drawer lists them all, and offers **Close issue** or **Open again**.

A note linked to both a board and a repo sends a swipe, and the press-and-hold menu's row, to Notion. The quiet word _GitHub_ and Send list to GitHub still reach the repo.

## Read next

- [[Lists and to-dos]]
- [[Claude on your notes]]
- [[The plugin seam]]
