# Canvases

A canvas is a page you lay out by hand: cards anywhere you like, with lines between them. Use one to plan a trip, map out an idea, or see how the pieces of a project connect.

Canvases are in Advanced. In Simple, they're behind **More** on the **+** sheet.

## Making a canvas

Tap **+** and choose **Canvas**. A new canvas opens, called Untitled canvas. Give it a name under **Name** in its More sheet.

You can also make a canvas as a page of a notebook, with **Add as a canvas** in the notebook's index.

## Cards

Tap **Add a card**, at the bottom left, or double-tap any empty space. Choose what kind:

| Card | What it holds |
|---|---|
| **Words** | Text you write in the card, in Markdown |
| **A note** | One of your notes, shown on the card. Ghost.md asks **Which note?** |
| **A link** | A web page. Ghost.md asks **Which address?** |
| **A picture** | A picture from your device |
| **A chart** | A diagram, written in Mermaid |
| **A table** | Rows and columns |
| **A group** | A named box that holds other cards |

Pictures can't be dragged onto a canvas from your computer. Use **A picture** instead.

## Working with a card

Tap a card to pick it. A bar of tools comes up:

- **Write in this card** (or **Name this group**)
- **Open the note** or **Open the address**, for a note card or a link card
- **Draw a line from this card**
- **Comment on this card**
- **Colour:** Rose, Ember, Amber, Moss, Sea or Violet, or **No colour**
- **Make a copy**
- **Take this card off the canvas.** For a group, its cards stay.

Press and hold a card to lift it and move it. Drag one of the handles round a picked card to change its size. **Snap to the grid** keeps cards lined up.

## Lines

Tap **Draw a line**, then tap the card it starts from and the card it goes to. Or pick a card and choose **Draw a line from this card**.

Tap a line to give it **Words on the line**, or to take it off the canvas.

## Getting around

- **On a phone:** one finger pans, two fingers pinch to zoom.
- **With a mouse:** the wheel, the middle button, or Space and drag pans.
- **On a trackpad:** two fingers pan, and a pinch zooms.
- **Fit the whole canvas on the screen** shows everything at once (Shift+1). **Zoom to the card** fits the one you picked (Shift+2). On a wide screen there are **Zoom out** and **Zoom in** buttons too.
- **The minimap**, in the bottom right corner once there are two cards or more, shows the whole canvas. Press it to grow it, drag on it to move around, and tap the grown map to go there.

On a keyboard: Delete removes what's picked, the arrows move it (with Alt, a pixel at a time), ⌘D or Ctrl+D copies it, and Escape lets go.

## Comments

Any card can have comments, as a note can. Pick the card and choose **Comment on this card**. A round on the card says how many there are. See [[Links, tags and footnotes]].

## A canvas inside a note

Put a link to a canvas, with `!` in front, on a line of its own:

```
![[Cabin weekend, laid out]]
```

The note draws the canvas in a frame. You can pan and zoom in it, but not change it. **Open** takes you to the canvas.

## What a canvas is, underneath

A canvas is a note too. Its file starts with a `title:` line, then the cards and lines in **JSON Canvas**, the open format Obsidian's canvases use. The switch at the top of a canvas flips between **Canvas** and **JSON**, if you want to see or edit it as text.

Importing from Obsidian turns your `.canvas` files into canvas notes.

## Examples to explore

Settings › Examples has two canvases to look at:

- **Add the example canvas** makes "Cabin weekend, laid out": one of everything a canvas can hold.
- **Add the "How Ghost.md works" canvas** makes a canvas that walks from a note to everywhere it can go.

Each press makes a new copy, so you can take one apart without worrying.

**Works on:** every app. On a phone, a big canvas is easier to work on with the minimap.

See also: [[Notebooks and journals]], [[Links, tags and footnotes]], [[Pictures, files and voice memos]], [[Workspaces, folders and search]]
