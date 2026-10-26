# Sharing and published sites

There are three ways to share from Ghost.md:

- **A read-only link** to a note or a notebook, which follows your edits.
- **A published site**: a note or a notebook as a small website, which changes when you publish it again.
- **An organization**: notes filed in a team's workspace, which every member reads and edits.

Links and sites need an account, because each is kept with the account that made it. All three are end-to-end encrypted: the server stores them and cannot read them.

## A read-only link

Open the note and tap **Share** in the note's toolbar, or **More for this note** and look under **Sharing**. Choose **Share a read-only link**. The link is made and copied.

From then on, the Sharing section has:

| Row | What it does |
|---|---|
| **Copy the link** | Copies it again. |
| **Send the link** | Opens your device's share sheet. |
| **Stop sharing** | Takes the share down. The link reads nothing from then on. |

Signed out, the row says: "Sign in under Settings › Account first: a share is kept with your account."

### What the link holds

A link looks like `https://ghostmarkdown.com/read.html#…`. The part after the `#` holds the share's id and the key that opens it. A browser never sends the part after `#` to a server, so the server holds your share sealed and can't read it.

**The link is the whole permission.** Anyone who has it can read the share until you stop it. You can't narrow it after it is sent. Sharing the same note again later makes a new link.

### Your edits follow

A few seconds after you save, the share is sealed again and sent, under the same link. Every device you're signed in on keeps your shares up to date and can stop them.

Deleting a note doesn't stop its link, and neither does emptying the trash. Stop it first, or later from **Settings › Account › Shared links**.

### Sharing a notebook

Share a notebook from its index's More sheet. Every page that has a note goes with it, in order. To share one page alone, share that page's note. A journal is shared an entry at a time: open an entry to share it.

### Where it was written, and places

A note's location stays out of its link until you tick **Share where it was written**, under Sharing. Places written in the note's words stay out until you tick **Share the places in it**. Each tick shows only when the note has that kind of place. Ticking one never ticks the other.

### Pictures

The pictures a page shows travel inside the share, since a reader has no account to fetch them from. If they don't fit, they are drawn smaller as reading copies.

### What a reader sees

The link opens a small reading page in any browser. The reader needs no account and no app. A note reads as it does in Ghost.md, and nothing on it can be changed. A notebook opens on its index, with **Previous** and **Next** on each page. The page follows the reader's light or dark setting and asks search engines not to index it.

The reader can download it as Markdown, a `.md` file or a `.zip` with its pictures, or save a copy into Ghost.md.

### Keeping a copy of something shared with you

In Ghost.md, tap **+**, choose **From a shared link**, paste the link, and tap **Save a copy**. The copy is yours to change; the shared one stays as it is.

## Published sites

A shared link reads as a page from Ghost.md. A site reads as a small website: the notebook's title across the top, its pages in order down the side, each page at an address of its own, and Previous and Next at each page's foot.

To publish, open a note or a notebook's index, tap **More for this note**, and look under **Site**, below the link's rows:

| Row | What it does |
|---|---|
| **Publish as a site** | Publishes it, and copies the site's link. |
| **Copy the site's link** | Copies it again, and says when it was last published. |
| **Publish again** | Puts your changes since on the site, at the same address. |
| **Unpublish** | Takes the site down. Its link reads nothing from then on. |

**A site changes only when you publish it again.** A shared link follows every save; a site doesn't.

A site's link looks like `https://ghostmarkdown.com/s/…#…`, and each page has its own, such as `https://ghostmarkdown.com/s/…/the-coast#…`. The key is after the `#`, as with a shared link, so anyone with the link can read the site and nobody else, the server included. One thing does reach the web server as written: **a page's name**, from its title, is in its address.

`[[Links]]` between pages of the site go to those pages. Pictures travel inside the site. A site never carries where a page was written, nor the places in it.

**No search engine can list a site.** Each page asks not to be indexed, and an indexer couldn't read one anyway, since the key is in the part of the address it never sees. So there is no setting for it.

Every site your account has published is listed in **Settings › Account › Published sites**, from whichever device published it, each with **Copy** and **Unpublish**. An account keeps up to 100 sites.

Works on: Android and Mac. Not on the iPhone yet. A journal has no site.

## Shared links, all in one place

**Settings › Account › Shared links** lists every note and notebook you've shared, from any of your devices, each with **Copy** and **Stop**. It appears once you've shared something. A note that isn't on this device is listed as "A note not on this device".

If a link ever drops out of your list (two devices changing settings at the same moment can do it), the page finds it on the server, calls it "A link no device lists", and offers **Take down**.

An account keeps up to 500 shared links. Deleting your account takes every link and site down with it.

## Sharing with an organization

To share notes with a team for them to edit, not just read, file them in the organization's workspace. Open **More for this note**, then **Workspace**, and pick the organization's. The picker says what it means: filed there, the note is the team's, and everyone in it reads and edits it. Members who have it open at once see each other's typing.

Taking a note out of the organization's workspace takes it away from everyone in it, so the picker asks you to press twice.

Team notes are encrypted with a key only the organization's members hold. See [[Organizations and shared notes]].

## What the server knows

For a link or a site, the server keeps the sealed copy with the account it belongs to, its size, and when it was made and last written. Anyone can fetch the sealed copy by its id; only the key after the `#` opens it.

See also: [[Notebooks and journals]] · [[Organizations and shared notes]] · [[Accounts, sync and encryption]] · [[Privacy]]
