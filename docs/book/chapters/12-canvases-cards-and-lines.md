# Canvases, cards and lines

A canvas is a page you lay out by hand: cards anywhere you like, with lines between them. Use one to plan a trip, map out an idea, or see how the pieces of a project connect.

Canvases are in Advanced. In Simple, **Canvas** is behind **More…** on the **+** sheet.

## Making a canvas

Tap **+** and choose **Canvas**. A new canvas opens, called Untitled canvas. Give it a name under **Name** in its More sheet.

You can also make a canvas as a page of a notebook, with **Add as a canvas** in the notebook's index.

## Cards

Tap **Add a card**, at the bottom left, or double-tap any empty space. A double-tap makes a card of words right there, ready to type. **Add a card** lets you choose what kind:

| Card | What it holds |
|---|---|
| **Words** | Text you write in the card, in Markdown |
| **A note** | One of your notes, shown on the card. Ghost.md asks **Which note?** |
| **A link** | A web page. Ghost.md asks **Which address?** |
| **A picture** | A picture from your device |
| **A chart** | A diagram, written in Mermaid and drawn on the card |
| **A table** | Rows and columns to fill in |
| **A group** | A named box that holds other cards |

A note card draws that note small, as it is now, and changes when the note does. Pictures can't be dragged onto a canvas from your computer, and notes can't be dragged in from the sidebar. Use **A picture** or **A note** instead.

## Working with a card

Tap a card to pick it, and tap it again to open it. A picked card has a ring with handles and a bar of tools:

- **Write in this card** (or **Name this group**). **Done writing** or **Done naming** finishes.
- **Open the note** or **Open the address**, for a note card or a link card
- **Draw a line from this card** (not for a group)
- **Comment on this card**
- **Colour:** Rose, Ember, Amber, Moss, Sea or Violet, or **No colour**
- **Make a copy** (for a group, **Copy this group's box**)
- **Take this card off the canvas.** For a group, its cards stay.

**Moving and sizing.**

- On a touch screen, press and hold a card to lift it, then move it. A card that's already picked moves with a plain drag.
- With a mouse, just drag it.
- A group is taken by its name or its border, and carries every card wholly inside it.
- Drag one of the handles round a picked card to change its size.
- **Snap to the grid**, the magnet, lands what you move, size or make on the grid's dots, with a small tick on a phone. It stays on until you turn it off.

## Lines

Tap **Draw a line** in the tools, then tap the card it starts from and the card it goes to. Or pick a card and choose **Draw a line from this card**, then tap the other card. **Stop drawing a line** lets go.

Tap a line to pick it: give it **Words on the line**, or **Take this line off the canvas**. Lines curve out of a card's side, keep apart where they share one, and put their words over open canvas rather than over a card.

## Getting around

- **On a phone:** one finger pans, two fingers pinch to zoom.
- **With a mouse:** the wheel, the middle button, or Space and drag pans.
- **On a trackpad:** two fingers pan, and a pinch zooms.
- **Fit the whole canvas on the screen** shows everything at once (Shift+1). **Zoom to the card** fits the one you picked (Shift+2), and so does a tap on a card's title. On a wide screen there are **Zoom out** and **Zoom in** buttons too.
- **The minimap**, in the bottom right corner once there are two cards or more, shows the whole canvas. Press it to grow it, drag on it to move around, and tap the grown map to go there.

On a keyboard: Delete removes what's picked, the arrows move it (ten pixels, or a grid dot with snapping on; with Alt, a pixel at a time), ⌘D or Ctrl+D copies it, and Escape lets go.

## Comments

Any card can have comments, as a note can. Pick the card and choose **Comment on this card**. A round on the card says how many there are. Moving or changing a card keeps its comments. See [[Links, tags and footnotes]].

## Canvases in a team

A canvas filed in an organization is shared like any note, and two people can work on it at once: moving different cards, or typing in the same one, both keep what they did. While others have it open, you see their pointers on it, each in their colour with their name, and a card someone is writing in says so. See [[Organizations and shared notes]].

## A canvas inside a note

Put a link to a canvas, with `!` in front, on a line of its own. Or use the **+** beside an empty line: **A canvas** (under **More**), then **Which canvas?**

```
![[Cabin weekend, laid out]]
```

The note draws the canvas in a frame, the note's width and a third of the screen tall, fitted to begin with and with its minimap in the corner. You can pan and zoom in it, but not change it. The canvas's name and **Open** sit over the frame; **Open** takes you to the canvas. With the caret on the line, the frame steps aside and the link shows as you typed it. In any other Markdown app it's just a link.

## What a canvas is, underneath

A canvas is a note too. Its file starts with a `title:` line, then the cards and lines in **JSON Canvas**, the open format Obsidian's canvases use. The switch at the top of a canvas flips between **Canvas** and **JSON**, if you want to see or edit it as text. In Simple, the switch is a row in the canvas's More sheet.

Importing from Obsidian turns your `.canvas` files into canvas notes.

## Examples to explore

Settings › About › **Examples** (under Help, in Advanced) has two canvases to look at:

- **Add the example canvas** makes "Cabin weekend, laid out": one of everything a canvas can hold.
- **Add the "How Ghost.md works" canvas** makes a canvas that walks from a note to everywhere it can go.

Each press makes a new copy, so you can take one apart without worrying.

**Works on:** Android, iPhone and the Mac. On a phone, a big canvas is easier to work on with the minimap.

See also: [[Notebooks and journals]], [[Links, tags and footnotes]], [[Pictures, files and voice memos]], [[Workspaces, folders and search]]
