# Features added for 2.1

Each section is one feature agent's, headed with its name, added to and never rewritten by another.

## clipper: the Ghost.md web clipper

**What it is.** A browser extension in `clipper/` (its own `package.json`, built with esbuild into `clipper/dist/chrome`
and `clipper/dist/firefox`, Manifest V3, one source) that saves what is on a web page into the person's Ghost.md:
Article (Readability), Selection, Full page, Bookmark (link, description, preview picture) and Screenshot (the visible
tab). The popup edits the title, adds tags, files the note in a personal workspace or a notebook, takes a comment, and
saves; a context menu item "Save selection to Ghost.md" and two shortcuts (Alt+Shift+G opens the clipper, Alt+Shift+S
saves the selection or the article straight away). `clipper/README.md` is the whole of it: modes, note format,
permissions and why each, the session ("Stay signed in"), how to build, load unpacked and test, and what each store
would need.

**Sealed in the browser.** It is a device of the account made of the web app's own code (`tauri/src/app/core`:
`derive`/`unwrap`, `call`, `seal`, the sync's `sendFile`), mirroring the connector's `GlyphAccount`. The service sees
the login half of the password and sealed blobs, as from any device; the e2e proof searches every request body for
the page's words and the password and finds neither.

**The note** is plain Markdown: front matter `source:` and `clipped:` (and `tags: [..]`, the one list form the app's
front matter rule and its queries both read), the title as the first heading, the comment, a rule, the page's words,
and pictures as `![alt](image/clip-<id>.jpg)`, stored sealed through the app's file route as the app stores a picture
(1600 px JPEG). A picture that cannot be stored stays a link.

**In the app.** `lib/editor/media/source_line.dart` (new) draws a note's `source:` as one quiet line under its title,
"From field.example/art…tml" (shortened as every address is), whose tap opens the page; the front matter itself stays
folded to "source · clipped · tags". Hooked by one line in `lib/root/note_desk.dart`'s editor extensions. Tests:
`test/clipper/source_line_test.dart`, and `test/clipper/clipped_note_test.dart`, which opens two notes the clipper's
end-to-end run saved (an article with two pictures; a page of tables, code and to-dos) in the app put together and
draws them, phone size and the Fold's inner size.

**Not done.** No store listing or publishing (Chrome Web Store, Edge, AMO, Safari: `clipper/README.md` says what each
needs; Safari needs an Xcode wrapper app). Not offered: an organization's workspace (a team's notes go through the
team's channel, `mcp/team.ts`, which the clipper does not carry) and journals (their pages are named by the minute).
Not verified: Firefox (built, never loaded), a real toolbar click and the real context menu and shortcut keys (the
proof presses the button through Chrome's DevTools command `Extensions.triggerAction`, which grants the same
`activeTab`, and calls the menu's and shortcut's handler directly), real sites (only fixture pages), and the phone
receiving a clip through sync (proven against a local glyph-api and through the connector's and the web app's sync
code, not on the Fold).

**Found beside, not the clipper's:** on a home of two cards across (the Fold opened, 669 and 900 wide), a note card
whose picture is drawn fails its row's layout: `lib/home/note_card.dart` `CardRow` asks for the intrinsic height of a
card holding a `LayoutBuilder` ("LayoutBuilder does not support returning intrinsic dimensions"). Any note with a
picture does it, clipped or not; a phone-width home (one card a row) does not.
