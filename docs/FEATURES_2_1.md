# What 2.1 adds

Append-only: one section per piece of work, headed with who did it.

## files: attachments, the PDF viewer, scanning and the words read in pictures (branch `feat/files`, 2026-10-16)

### Where a person finds it

- **A file** and **Scan a document** on the first page of the + beside an empty line (and the `/` palette), after A video.
  A file opens Android's own document picker (no permission) or the Mac's open panel. Scan a document opens Google's
  ML Kit document scanner (Android with Google Play services only; its own screen, so the app never holds the camera).
- **The card** under the file's line: the file's mark (a PDF's first page, drawn), its name, "PDF · 2.4 MB · 12 pages",
  or "Not on this device yet." / "It stays on the device it was added on." A tap opens a PDF in the viewer and anything
  else in another app ("Open with"); the mark at its end hands any file over.
- **The PDF viewer**: pages swiped across, drawn on asking by Android's own PdfRenderer; pinch zoom to 5x (redrawn
  sharper once the pinch settles), double tap back; Page n of N (tap: Go to page); Find (the device's places on
  Android 15+, else the pages whose words hold the query, from the PDF's own words or the words read in it); Copy the
  words on this page; Share; Open with. The back gesture closes it.
- **Search**: a note is found by the words read in its pictures, scans and PDFs, and its row's line says where:
  "Rent is due monthly on the first in Lease 2026.pdf, page 2", "TOTAL 42.10 in a picture".
- **Copy the words in it**, under a picture whose line holds the caret, where words were read in it.
- **Settings › Library folder › Files and scans**: Read words in pictures (on by default, kept on this device), Read
  what is already in notes (now, with "Reading, 12 of 40" / "Waiting while Battery saver is on."), and Files in notes
  ("3 files, 12 MB"), with the 25 MB sync limit said under it.

### How it is kept

- **The line** (lib/core/attachment_refs.dart): `[Lease 2026.pdf](file/<uuid>.<ext> "2.4 MB")`, alone on its line: the
  file's own name as the words, its kept name under `file/`, its size as the link's title. Plain Markdown; any app shows
  a link.
- **The file** (lib/files/attachment_store.dart): `<data>/images/files/<uuid>.<ext>`, kept by Dart, whole or not at
  all (a `.part` and a rename). Inside the pictures' folder so the core's Export (`images/files/…`), Backup
  (`Attachments/Pictures/files/…`) and Erase everything carry it with NO change to the Rust core; the core's picture
  commands only ever name files directly under `images/`. At most 512 MB a file.
- **The words read** (lib/files/read_text.dart): a sidecar beside the thing, `<name>.ocr.txt` (`images/<picture>.ocr.txt`,
  `images/files/<file>.ocr.txt`), UTF-8, a form feed between a PDF's pages as `pdftotext` writes them; empty means read
  and nothing found. Read in at launch on a worker isolate and held in memory for the search.
- **The one door** for anything that brings a file in: `storeAttachment(AttachmentSource, name:)` in
  lib/files/attachment_store.dart (sources `AttachmentBytes`, `AttachmentPath(path, move:)`, `AttachmentCopy(copyTo)`),
  answering a `KeptAttachment` whose `.ref` is `file/<name>` and `.markdown` the note's line. It reads the words in it
  soon after. The share-import branch's `storeSharedFile` maps onto it one to one.
- **Deleting**: taking the line out keeps the file (Undo, older versions). A note deleted for good removes the files
  only it linked, with their words, after the core's `delete_note` (the pictures' own rule), from
  `CoreLibrary.destroy` and sync's `LibraryNotes.remove` through `tellNoteGone`.

### Sync (what changed)

- `FileKind` gained `attachment` (`a-<ext>-<stem>`) and `text` (`t-i-<ext>-<stem>` for a picture's words,
  `t-a-<ext>-<stem>` for a file's), on the same `recordings` route, sealed with `file:<id>` like every other file.
- A note's payload names its files (`files`) and the things whose words went (`texts`); the other device fetches what it
  lacks. The settling at the end of a pass makes files whole on both sides as it does pictures (with the same
  ask-again wait), and sends words held here that the account lacks.
- A file over 25 MB (the pictures' own limit, the core's `kept/images.rs` `MAX_BYTES`) is never read or sent, is left
  out of the payload, and its line's size keeps the other devices from asking. **The service is unchanged**: one sealed
  file may be 64 MB there (`RECORDING_LIMIT`, server/src/sync.rs) and any base64url id of up to 64 characters.
- Words read after a note went owe the note again (`glyph-words-owed`, `KeptFiles.owed()`), so the others hear of
  them by the note's next revision, as a versions file kept by hand does.
- `LocalFiles` gained `lengthOf` (a file's size without reading it) and `keepsMedia` (an iPhone, which keeps no files
  yet, fetches and sends none).
- Team notes carry `files` and `texts` in their rows the same way.

### The phone's half

- android/…/ghost_md/Documents.kt over `ghost_md/documents`: `pick`, `canScan`, `scan`, `read`, `readerReady`,
  `pdfOpen`/`pdfPage`/`pdfText`/`pdfFind`/`pdfClose`, `openWith`, `share`, `saving`. PdfRenderer is the system's
  (PDFium inside Android, nothing added to the APK); its words and search need Android 15. Reading words runs on a
  background-priority thread. Files are handed over as copies under their own names in `cacheDir/open/` through a
  FileProvider of their own (`AttachmentFiles`, authority `<id>.attachments`, res/xml/ghost_attachment_paths.xml).
- Gradle: `com.google.android.gms:play-services-mlkit-document-scanner:16.0.0` and
  `com.google.android.gms:play-services-mlkit-text-recognition:19.0.1`. The text recognition is the Play-services
  one, not the bundled `com.google.mlkit:text-recognition`: measured in this app's build, the bundled one is 11.1 MB of
  native library and 1.3 MB of models on arm64 alone (and 18.4 MB more for armeabi-v7a and x86_64, which ship unless
  the ABIs are filtered). The model is fetched once by Play services (asked for with ModuleInstallClient the first
  time, and with the manifest's `com.google.mlkit.vision.DEPENDENCIES = ocr` on a Play install), then reads offline.
- No new permission. The scanner and the reader need Google Play services.
- The Mac (macos/Runner/GhostChannels.swift): `pick` (open panel) and `openWith` (the workspace). It reads no words
  and draws no PDF in the app: a PDF opens in the Mac's own app.

### Not done

- iPhone: nothing (no kit is made there; a file's line is the link it always was, and sync neither fetches nor sends
  files). VisionKit's scanner would need `NSCameraUsageDescription`, which the store build does not have.
- Words are not read on the Mac or an iPhone (Apple's Vision would do it; not built). They do arrive there by sync.
- A home-screen quick action for scanning is not wired here (the launcher's shortcuts are `feat/reminders`'). Its entry
  point is `scanToNewNote()` in lib/files/plus_files.dart: it opens the scanner and answers the words of a new note
  (`# Scan 2026-10-16 14.05` and the PDF's line), or null; the caller makes the note and opens it.
- A shared page (a share's reader) carries no files: a file's card there says it is not on this device.
- The PDF viewer shows one page at a time (swiped), not a continuous scroll; text selection in a PDF is not offered.
