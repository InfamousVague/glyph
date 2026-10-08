# Sharing a note or a notebook

_A read-only link to one note or a whole notebook. Anyone with the link can read it, and nobody else can, the server included._

## Making a link

Open the note and tap the three dots, **More for this note**. Under **Sharing**, choose **Share a read-only link**. The link is made and copied, and the sheet says "The link is copied." From then on the section holds three rows.

| Row | What it does |
|---|---|
| **Copy the link** | Copies it again. |
| **Send the link** | Opens the device's share sheet, where it has one. |
| **Stop sharing** | Takes the share down. The link reads nothing from then on. |

Sharing needs an account, because the server keeps a share with the account that made it. Signed out, the row says: "Sign in under Settings › Account first: a share is kept with your account."

## What the link holds

A link looks like `https://ghostmarkdown.com/read.html#<id>.<key>`.

- **The id** names the share on the server.
- **The key** opens it. It sits after the `#`, and a browser never sends that part to a server. The server holds the share sealed, and cannot read it.
- **The link is the whole grant.** Anyone who has it can read the share until you stop it, and it cannot be narrowed after it is sent. Stopping deletes the share. Sharing the same note again later makes a new link.

Links made before the move, on attack.fm/glyph/read.html, still open.

## Your edits follow

A few seconds after you save, the share is sealed again and sent, under the same link. A notebook's share follows any of its pages. The list of what you have shared, with each link's key, lives in your synced settings, sealed like the rest. So every device you are signed in on keeps your shares up to date and can stop them, and a change made on another device reaches the share too. Local only does not stop a share following your edits; stop the share for that.

Deleting a note does not stop its link, and nor does emptying the trash. Stop it first, or later from Settings › Account › Shared links. A note in the trash keeps its title there; one deleted for good is listed as "A note not on this device".

## Sharing a notebook

Share a notebook from its index's More sheet, where the row says every page goes with it. The share holds the index and every page that has a note, in order. A page not written yet is left out, and the reader sees it marked as not written yet. To share one page alone, share that page's note.

## Pictures

The pictures a page shows travel inside the share, because a reader has no account to fetch them from. A share holds about 4.4 MB.

1. If the pictures fit as they are, they go as they are.
2. If not, each is redrawn smaller, at most 1024 pixels on its long side, as a reading copy.
3. If those still do not fit, as many go as fit, in the order the pages show them.

A picture this device does not have yet is left out, and the share goes again once it arrives. A share whose words alone are too big is refused: "That is more than a share can hold, even with its pictures drawn smaller. Share a page, or fewer of them."

## Where it was written, and the places in it

A note that says where it was written keeps that out of its link until you tick **Share where it was written**, under Sharing. Ticked, the shared page shows the place and its map.

The places written in a note's words, the ones the + beside the line adds, have a tick of their own, **Share the places in it**. Until it is ticked every place leaves the link, however it was written: a line that is only a place goes, and a place inside a sentence keeps its name and loses its address. Each tick shows only when the pages hold that kind of place, in the note or in any page of a notebook, and the hint under **Copy the link** says in one sentence what the link carries. Ticking one never ticks the other, so a tick given for where a note was written never carries a place added later.

## What a reader sees

The link opens a small reading page in any browser. The reader needs no account and no app. The page is built from Ghost.md's own parts, so a note reads as it does in the app, and nothing on it can be changed. A notebook opens on its index, under a banner that says it is a shared notebook; a page carries the notebook's bar at the top and **Previous** and **Next** at its foot. A canvas is drawn as a canvas. The page follows the reader's light or dark setting, and asks search engines not to index it.

A banner across the top offers **Get the app** and two buttons.

| Button | What it does |
|---|---|
| **Save a copy** | Opens the ways to keep a copy, below. |
| **.md** or **.zip** | Downloads it as Markdown: a note as its `.md` file; a notebook, or a note with pictures, as a `.zip` of its pages with the pictures in an `image` folder beside them. |

**Save a copy** offers **Open in the Ghost.md app**, which saves the copy in the app on a phone or a Mac and opens it, and **Save it in Ghost.md on the web**, which saves it in the web app at attack.fm/glyph, in that browser. If the app does not open, it may be an older one: the panel says to paste the link under **+ › From a shared link** instead, and offers **Copy this page's link**.

## A copy of your own

In the app, tap **+**, choose **From a shared link**, paste the link (any text with the link inside will do), and tap **Save a copy**. The copy opens. It is yours to change, and it does not follow the original. A title you already have is saved as "Title (shared)", then "Title (shared 2)". A copied notebook's index points at its copied pages. The pictures come with it, and sync with your notes like any others.

## Every link in one place

Settings › Account › **Shared links** lists every note and notebook you have shared, from whichever device shared it, each with **Copy** and **Stop**. The section appears once you have shared something.

Settings sync as one set, so if two devices change them at the same moment, a link can drop out of the list. The page asks the server, counts any such link as "A link no device lists", still readable by anyone who has it, and offers **Take down**.

Deleting your account takes every link down with it.

## What the server knows

It holds each share sealed, with the account it belongs to, its size, when it was made and when it was last written. Anyone can fetch the sealed copy by its id; only the key after the `#` opens it. An account keeps up to 500 shares at once.

## Read next

- [[Notebooks, and reading one through]]
- [[Accounts, sync and the key you hold]]
- [[What stays on your phone]]
