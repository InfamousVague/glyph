# Back up to git

The "Back up to git" plugin (Matt, 2026-10-31: "add a plugin to backup on git, spend a lot of time on this") commits the
Library folder to a git repository the person owns and pushes it, so the notes are backed up as plain files with their
history on GitHub, GitLab, Codeberg, Gitea or any git host that speaks HTTPS, and a fresh device opens the library again
by cloning it. The design it follows is docs/MARKDOWN_FIRST.md §10, with Matt's decisions in §11 and the critic's
findings in §12 folded in. The code is `lib/plugins/git_backup/`, the git itself `native/src/git.rs`.

## How it works

**The repository is the Library folder** (decision 3): `.git` sits inside it, so a Mac can run git on it directly and
any other Markdown app opens it as it is. The plugin refuses to make one where the Library is inside iCloud Drive,
Dropbox, OneDrive or Google Drive (told by the path on the Mac, place.dart `syncingFolder`), since those sync `.git`
object by object and corrupt it; the sentence says to choose a folder outside it or Ghost.md's own. On an Android
folder picked in the system's picker (a SAF tree, which has no filesystem path for git) the repository is a **mirror** at
`<app data>/git/library/`, written from the library's notes before each commit (backup.dart `writeMirror`), and the
page says so. The web client has no Library folder and the plugin does not run there.

**Git is gitoxide in the core**, pure Rust (native/src/git.rs; the spike's header has what was measured). Fifteen
commands behind `dispatch::invoke`: `git_init`, `git_status` (with `shallow`), `git_commit` (with `alsoParent` for a
merge and `keep` folders taken from HEAD), `git_remote_set`, `git_remote`, `git_clone` (shallow optional), `git_fetch`
(with `deepen`), `git_divergence`, `git_push` (fast-forward only, HTTPS basic auth with a token; written over gix's
plumbing since gix has no push), `git_merge_base`, `git_blob`, `git_three_way`, `git_log`, `git_diff`, `git_write_blob`.
Errors begin with a word the app matches on: `No repository:`, `Sign-in refused:`, `Not fast-forward:`, `No connection:`.
TLS is rustls with ring and webpki's roots, the one set-up the core carries everywhere. No SSH (the page says so).

**What is committed** (files.dart): every `.md`, `.versions`, `.canvas`; `.glyph/config.json`, `.glyph/library.json`,
`.glyph/notes/*.json`; `image/` and `file/` at the names the notes link; `.trash/` when a note lands there; the
generated `.gitignore` and `README.txt` (never `README.md`: a `.md` at the root would be indexed as a note). Pictures
live under the Library now (the attachments slice); files and recordings are still written beside the app's data and
read from both places, so the plugin asks the core where each kind is (`attachment_places`) and copies what is not yet
under the Library into the repository at `file/` and `recordings/`. `recordings/` is off by default with a 50 MB
per-file cap (decision 11; a file over it is left out and named). `video/` never. `orgs/<Org>/` is excluded by
default with a switch per organization (decision 12): a team's notes are the team's. An excluded organization is a
`keep` folder: the commit takes it from HEAD as it was, so switching one off never deletes the team's notes from the
repository, and a device that does not carry them never commits their removal. The index (`.glyph/index.sqlite*`),
temp files and `.DS_Store` are ignored. The `git` key of `.glyph/config.json` carries the remote, the branch and the
switches, so a clone knows its own settings; it carries no secret, and a guard refuses one.

**Cadence** (backup.dart): a commit two minutes after the library's last change (the root hands the plugin the
library's `touched`), a floor of one commit an hour while anything waits, and Back up now (the page, the command
palette). One commit per quiet spell. Messages: `Edit: <title>` for one note, `<n> notes changed: <first two>…` for
several, `New:`, `Moved:`, `Trashed:`, `Deleted:` where that is the whole change, `A picture`, `Library settings`.
Author and committer are the account's handle (`<handle>@users.ghostmarkdown.com`) or `Ghost.md <ghost@localhost>`
signed out. A push follows each commit when online. On an iPhone, which suspends the app behind another, commits and
pushes run in the foreground only and whatever waited runs on resume. On Android a push holds the device through the
foreground service (lib/core/background_jobs.dart). A phone does not push more than 100 MB in one go; the row says to
use a Mac.

**One pusher** (decision 13, claim.dart): of an account's devices the one holding the pusher claim pushes; the others
commit locally and show "Backing up from your Mac". The claim is the ticket sweep's shape (`{by, name, at}` under
`gitPusher` in the synced preferences), confirmed by reading the account's copy after a sync, live a day, renewed every
ten minutes; a phone waits five minutes with no claim in sight before taking one, so an awake desktop gets there first;
`chosenPusherClaim` in lib/sync/prefs.dart keeps another device's live claim over this device's in a merge.

**Before every push** (merge.dart): a fetch. Where the remote moved, the merge, file by file over what the remote
changed since the merge base:

- a note both sides changed: three-way with lib/core/merge_words.dart over `git_three_way`'s texts; where that gives up,
  ours stays and theirs is written as a NEW note beside it, `<Title> (conflict from git).md`, with a FRESH `id:` in its
  front matter and no sidecar, so no id-keyed ledger ever points at the copy (the critic's high finding);
- `.versions`: both sides' versions once, in order (lib/core/versions_file.dart `mergeFiles`);
- a binary both changed: theirs wins, ours kept as `<name>.conflict.<ext>`;
- `.glyph/config.json`: key by key, last writer where both changed;
- a note the remote deleted and this device did not touch: moved to `.trash/<path>` (out of the app, never lost);
  any other file the remote removed: removed.

Then a commit with two parents and the push. Never a force push; a push still refused is a red row.

**Restore** (restore.dart): "Open library from git" on the plugin's page and on Settings › Library folder, and "I have a
backup" on the first-run screen: a shallow clone into `<app data>/git/clone-<time>/`, the organizations' folders held
aside at `<app data>/git/held/<Org>/` (team notes come from the team's channel after sign-in, not from the repository;
the held folders stay in the repository as HEAD had them through `keep`), the attachments copied to where the app
reads them, `.glyph/config.json` read for the remote and switches, then the folder opened as the library (the same
`library_inspect` + `library_move` as choosing a folder), which rebuilds the index; the history is deepened in the
background. "Import from a repo folder" on the Mac opens a clone made by hand the same way. On an iPhone, with no
folder picker, restore is the clone alone.

**Publish as a website** (publish.dart; decision 4): with the switch on, for a GitHub remote, the publisher
(tauri/publish/, vendored into the app's assets by tool/publish-assets.sh before a release) is committed as
`.glyph/publish/` (bin, dist, templates), rewritten only when its version changes, with the publisher's workflow at
`.github/workflows/ghost-pages.yml` and a `publish.json` (title, baseUrl, `orgs: false`) written once. The page says
where the site will be (`https://<owner>.github.io/<repo>/`). A build without the assets writes a workflow that says so.

**Remotes and auth** (git_backup_setup.dart, github_api.dart): HTTPS with a token as basic auth's password, the user
`x-access-token` for GitHub, `oauth2` for GitLab, `git` otherwise. The token is the plugin's own secret
(`glyph-git-token`), sealed to the account's other devices like GitHub's. In Advanced, the GitHub plugin's token is
reused where GitHub says it has the `repo` scope (a fine-grained token says nothing of its scopes and is taken on the
person's word, the first push being the check). "Create a private repository on GitHub" makes `ghost-notes` through
the API. SSH is not in this version.

**The record**: each backup is a job on the activity record with the plugin's git glyph (no brand's mark: any host
does), done quietly when nothing changed, a red row with Retry on a failure, its cause plain: the git host didn't accept
the token (Sign in again), someone pushed changes this device hasn't merged, the git host couldn't be reached, more than
a phone pushes, a file over the cap left out and named.

**The page** (git_backup_pane.dart): the remote and branch, last commit and push, ahead/behind, who pushes, conflict
copies with Open, the sizes (committed, repository, recordings and organizations left out, films never), the switches
(recordings, each organization, Publish) behind More in Simple, Back up now, Open library from git, Import from a repo
folder, Remove (asks twice, keeps the files, deletes `.git`). The setup: intro with the plaintext warning → token →
(Advanced) reuse the GitHub token → paste → make the repository or paste its address → check (the repository made where
the Library is or refused, the remote reached, the size said, the cost ask over 200 MB) → first backup.

## Limits

- No SSH; HTTPS with a token only.
- No LFS: a recording over the cap is left out.
- Pushes over 100 MB are a desktop's until resumable uploads exist.
- The web client has no Library folder; its backup is the export or a device of the account.
- On an Android SAF tree the mirror carries the notes the library lists; `.versions` and sidecars are not in the mirror
  (the SAF library has no path for them), so a mirror backup is notes without their fine history.
- Team notes are never restored from the repository; they come from the team after sign-in. The team sync's own guard
  against pushing a note the server holds as deleted is lib/team/sync.dart's and unchanged here.
- Case-insensitive filesystems: a repository written on Android may hold two names a Mac folds into one; the plugin
  does not yet refuse such a commit (docs/MARKDOWN_FIRST.md §12).

## Tests

- `native/src/git.rs` tests: init, commit, clone, diverge, merge, push, shallow, log, diff, write_blob, deepen, keep.
- `test/plugins/git_backup/pure_test.dart`: places and refusals, the generated files, attachments and sizes, messages,
  settings and the config guard, the merge's pure rules, the pusher claim on two devices, publish.
- `test/plugins/git_backup/backup_test.dart` (the Mac's core, bare repositories on disk): the first backup, the quiet
  commit and the floor, the iPhone's foreground-only cadence, messages, the two-device merge, the conflict copy with a
  fresh id, binaries, the pusher held elsewhere, organizations and recordings, publish, failures as red rows, the phone
  cap, restore from a clone and from a folder.
- `test/plugins/git_backup/setup_test.dart`, `pane_test.dart`: the setup's steps and words, the GitHub API as asked,
  the check's sentences, the page's rows and pictures (`build/feature-shots/git-backup/` with `--update-goldens`).
