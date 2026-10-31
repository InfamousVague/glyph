//! Git inside the core, for "Back up to git" (Matt, 2026-10-31): the library's folder committed and pushed to a
//! remote from the phone and the Mac, and brought back by cloning. A SPIKE, to learn whether gitoxide (`gix`) can
//! carry it: the operations behind the core's dispatch, their errors told apart, and tests against a bare repository
//! on disk. What the app will show, and which folder is the repository, is the design's to say; every command here
//! names the repository it works on and needs no library open.
//!
//! | command | takes | answers |
//! | --- | --- | --- |
//! | `git_init` | `{repo}` | `{created}`: a repository at that folder, made if there was none, its first branch `main` |
//! | `git_status` | `{repo}` | `{head, branch, changes: [{path, kind}]}`: the worktree against HEAD, `kind` one of added, removed, modified, renamed, typechange, conflict |
//! | `git_commit` | `{repo, message, author: {name, email}, alsoParent?, keep?}` | `{id}`, or `{id: null}` when nothing changed. Every file in the folder (`.gitignore` honoured) is the commit; `alsoParent` names a second parent, the merge the app made; `keep` names folders taken from HEAD's tree as they were, whether or not they are on disk |
//! | `git_remote_set` | `{repo, url, name?}` | `null`: the remote (`origin`) and `main`'s tracking of it, written to the repository's config |
//! | `git_remote` | `{repo}` | `{name, url}` or `null` |
//! | `git_clone` | `{url, into, token?, user?, shallow?}` | `{head, files}`: a clone with its files checked out, shallow (depth 1) when asked |
//! | `git_fetch` | `{repo, token?, user?}` | the divergence (below) after `origin` is fetched |
//! | `git_divergence` | `{repo}` | `{local, remote, base, state, ahead, behind}`: `main` against `origin/main`; `state` is empty, same, ahead, behind or diverged |
//! | `git_push` | `{repo, token?, user?}` | `{old, new, upToDate}`: `main` to `origin`, fast-forward only |
//! | `git_merge_base` | `{repo, a, b}` | the merge base's id, or `null` |
//! | `git_blob` | `{repo, commit, path}` | the file's text at that commit, or `null` where the commit has no such file |
//! | `git_three_way` | `{repo, path}` | `{base, ours, theirs}`: one file's text at the merge base, at `main` and at `origin/main`, for lib/core/merge_words.dart to put together |
//! | `git_log` | `{repo, count?}` | `[{id, time, message, name}]`: the last commits of HEAD, newest first, `time` in seconds since the epoch (the plugin's page: when the last backup was) |
//! | `git_diff` | `{repo, from?, to}` | `[{path, kind, from?}]`: what `to`'s tree has over `from`'s (everything added when `from` is null), `kind` added, removed, modified or renamed (`from` the old path): what the remote changed since the merge base, for the plugin's merge |
//! | `git_write_blob` | `{repo, commit, path, into}` | `{bytes}` with the file's bytes at that commit written to the file `into`, or `null` where the commit has no such file: a picture the remote has, taken as it is |
//!
//! The plugin's slice (2026-10-31) added the last three, `shallow` to `git_status`'s answer and `deepen` to
//! `git_fetch` (a shallow clone brought to its whole history, as `git fetch --unshallow` does).
//!
//! **Errors.** Each is a sentence (ffi.rs's `err`), and the sentence begins with a word the app can match on:
//! `No repository:`, `Sign-in refused:`, `Not fast-forward:`, `No connection:`, or none of those for everything
//! else. gix's errors are classified by the words in them (gix-error's classes do not cover the transport's
//! HTTP answers), which is the one place this leans on text.
//!
//! **What gix has and has not.** Init, commit, status, diff, fetch, clone (shallow too), merge bases and reading
//! objects are gix's own. PUSH IS NOT: gitoxide has no push in 0.90, only the `push.default` config enum. `push`
//! below is written here over gix's plumbing, the git-receive-pack handshake (gix-protocol), the pack writer
//! (gix-pack's `generate` feature) and the raw request writer (gix-transport), about a hundred lines: one branch,
//! `report-status`, no side-band, no thin packs, fast-forward only (which is all the app needs, since it merges
//! before it pushes). A tag or a second branch would need the same lines again.
//!
//! **The transport.** HTTPS through reqwest with rustls, a token as the password of HTTP basic auth (GitHub,
//! GitLab, Gitea and Codeberg take one so). The ciphers are ring's, the one provider the core already carries
//! (native/Cargo.toml says how aws-lc-rs is kept out), and the roots are webpki's, since rustls's platform verifier
//! wants a Kotlin half on Android. `file://` works too and the tests use it, but it spawns `git upload-pack` and
//! `git receive-pack`, which a phone does not have. **No SSH**: gix's ssh transport spawns the `ssh` program, which
//! a phone has not either; SSH from a phone would mean a Rust ssh client (russh) under a transport of our own, and
//! a key kept in the keystore. Not here.
//!
//! **The index.** gix has no `git add`: a commit here hashes every file of the folder into blobs and trees itself
//! (`snapshot`), then writes the index from the committed tree with each file's stat, so the next status is git's
//! quick one (a stat per file, content read only where the stat changed).
//!
//! **Measured, 2026-10-31**, on the Mac (M-series), release, `tests::timings`: a 500-file, 20 MB library commits in
//! 155 ms and pushes in 160 ms (its objects are 4.5 MB); a clean status is 2 to 14 ms; a cold clone of it is 80 ms
//! and a shallow one 90 ms, both over `file://`, so the network is not in those; a one-file commit is 26 ms, its
//! push 32 ms, the other clone's fetch of it 16 ms. A phone is three to five times slower at the file work and
//! bound by the connection for the rest. What gix adds to the libraries (stripped release, by tool/build-native.sh):
//! the phone's arm64 .so with the engines 14.4 MB to 23.2 MB (+8.9 MB), without them 4.9 MB to 15.6 MB (+10.7 MB,
//! +8.9 MB under fat LTO, 11.6 MB in all at opt-level s with LTO); the Mac's universal dylib 9.4 MB to 29.5 MB
//! (the arm64 slice 4.6 MB to 14.4 MB); the iPhone's static library 27 MB to 64 MB a slice, of which the app's
//! link keeps what it reaches. All three targets build as the script builds them, nothing added to the toolchain.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use gix::bstr::{BString, ByteSlice};
use gix::objs::Exists as _;
use gix::ObjectId;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const COMMANDS: &[&str] = &["git_init", "git_status", "git_commit", "git_remote_set", "git_remote", "git_clone", "git_fetch", "git_divergence", "git_push", "git_merge_base", "git_blob", "git_three_way", "git_log", "git_diff", "git_write_blob"];

/// The one branch this spike works on: the app's library has no reason for a second.
const BRANCH: &str = "main";
const REMOTE: &str = "origin";

/// Whether `command` is one of this file's. None needs the library: each names the repository it works on.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

/// What went wrong, by kind, so the app can say the right thing and know whether trying again could help.
#[derive(Debug, PartialEq)]
pub enum Fail {
    /// No repository at the path given.
    NoRepo(String),
    /// The remote refused the token (or there was none to offer).
    Auth(String),
    /// The remote's branch has commits this repository has not: fetch, merge, then push again.
    NonFastForward(String),
    /// DNS, the connection, TLS, or an HTTP answer that is not the remote's refusal.
    Network(String),
    /// Everything else, said as it is.
    Other(String),
}

impl Fail {
    /// The sentence the app reads, its first word the kind.
    pub fn said(&self) -> String {
        match self {
            Fail::NoRepo(s) => format!("No repository: {s}"),
            Fail::Auth(s) => format!("Sign-in refused: {s}"),
            Fail::NonFastForward(s) => format!("Not fast-forward: {s}"),
            Fail::Network(s) => format!("No connection: {s}"),
            Fail::Other(s) => s.clone(),
        }
    }
}

/// gix's error with every cause behind it on one line, which is where the words that classify it are.
fn chain(err: &gix::Error) -> String {
    let mut said: Vec<String> = Vec::new();
    for cause in err.iter_errors() {
        let s = cause.to_string();
        if said.last() != Some(&s) {
            said.push(s);
        }
    }
    said.join(": ")
}

impl From<gix::Error> for Fail {
    fn from(err: gix::Error) -> Fail {
        use gix::error::Class;
        let text = chain(&err);
        let lower = text.to_lowercase();
        // gix-error's classes first (the transport marks a 401 unauthenticated and a refused connection retryable),
        // the words second, for what reaches here unclassified.
        if err.classify().has(Class::Unauthenticated) || err.classify().has(Class::PermissionDenied) {
            Fail::Auth(text)
        } else if err.classify().has(Class::Retryable) {
            Fail::Network(text)
        } else if lower.contains("credential") || lower.contains("unauthenticated") || lower.contains("401") || lower.contains("403") || lower.contains("permission denied") || lower.contains("authentication") {
            Fail::Auth(text)
        } else if lower.contains("dns") || lower.contains("connect") || lower.contains("timed out") || lower.contains("tls") || lower.contains("certificate") || lower.contains("http status") || lower.contains("network") || lower.contains("could not resolve") {
            Fail::Network(text)
        } else {
            Fail::Other(text)
        }
    }
}

impl From<std::io::Error> for Fail {
    fn from(err: std::io::Error) -> Fail {
        Fail::Other(err.to_string())
    }
}

type Result<T> = std::result::Result<T, Fail>;

// What each command takes.

#[derive(Deserialize)]
struct AtRepo {
    repo: PathBuf,
}

#[derive(Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct Who {
    pub name: String,
    pub email: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Commit {
    repo: PathBuf,
    message: String,
    author: Who,
    #[serde(default)]
    also_parent: Option<String>,
    /// Folders taken from HEAD's tree rather than the working folder, as `orgs/Acme`: whatever the last commit had
    /// of them, whether or not the folder is there now (the plugin's excluded organizations, and the team's notes
    /// held aside after a restore: never deleted from the repository by a device that does not carry them).
    #[serde(default)]
    keep: Vec<String>,
}

#[derive(Deserialize)]
struct RemoteSet {
    repo: PathBuf,
    url: String,
    #[serde(default)]
    name: Option<String>,
}

/// A token as the password of HTTP basic auth; `user` is what the host wants beside it (GitHub takes anything).
#[derive(Deserialize, Clone, Default)]
pub struct Auth {
    #[serde(default)]
    pub user: Option<String>,
    #[serde(default)]
    pub token: Option<String>,
}

#[derive(Deserialize)]
struct Clone {
    url: String,
    into: PathBuf,
    #[serde(flatten)]
    auth: Auth,
    #[serde(default)]
    shallow: bool,
}

#[derive(Deserialize)]
struct WithAuth {
    repo: PathBuf,
    #[serde(flatten)]
    auth: Auth,
    /// `git_fetch` only: a shallow repository brought to its whole history.
    #[serde(default)]
    deepen: bool,
}

#[derive(Deserialize)]
struct Log {
    repo: PathBuf,
    #[serde(default)]
    count: Option<usize>,
}

#[derive(Deserialize)]
struct Diff {
    repo: PathBuf,
    #[serde(default)]
    from: Option<String>,
    to: String,
}

#[derive(Deserialize)]
struct WriteBlob {
    repo: PathBuf,
    commit: String,
    path: String,
    into: PathBuf,
}

#[derive(Deserialize)]
struct MergeBase {
    repo: PathBuf,
    a: String,
    b: String,
}

#[derive(Deserialize)]
struct Blob {
    repo: PathBuf,
    commit: String,
    path: String,
}

#[derive(Deserialize)]
struct ThreeWay {
    repo: PathBuf,
    path: String,
}

/// One changed file, as the status lists it.
#[derive(Debug, Serialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct Change {
    pub path: String,
    pub kind: &'static str,
}

/// One file two commits differ in, as `git_diff` lists it; `from` is the old path of a rename.
#[derive(Debug, Serialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct TreeChange {
    pub path: String,
    pub kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from: Option<String>,
}

/// One commit, as `git_log` lists it.
#[derive(Debug, Serialize, PartialEq)]
pub struct Logged {
    pub id: String,
    /// Seconds since the epoch, the committer's.
    pub time: i64,
    pub message: String,
    /// The author's name.
    pub name: String,
}

/// `main` against `origin/main`.
#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Divergence {
    pub local: Option<String>,
    pub remote: Option<String>,
    pub base: Option<String>,
    /// `empty` (neither has a commit), `same`, `ahead`, `behind` or `diverged`.
    pub state: &'static str,
    pub ahead: usize,
    pub behind: usize,
}

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Pushed {
    pub old: Option<String>,
    pub new: String,
    pub up_to_date: bool,
}

pub fn call(command: &str, args: Value) -> std::result::Result<Value, String> {
    let answer = |value: Result<Value>| value.map_err(|fail| fail.said());
    match command {
        "git_init" => {
            let AtRepo { repo } = crate::dispatch::read(command, args)?;
            answer(init(&repo).map(|created| json!({ "created": created })))
        }
        "git_status" => {
            let AtRepo { repo } = crate::dispatch::read(command, args)?;
            answer((|| {
                let repo = open(&repo)?;
                let head = head_id(&repo).map(|id| id.to_string());
                Ok(json!({ "head": head, "branch": BRANCH, "shallow": repo.is_shallow()?, "changes": status(&repo)? }))
            })())
        }
        "git_commit" => {
            let Commit { repo, message, author, also_parent, keep } = crate::dispatch::read(command, args)?;
            answer((|| {
                let repo = open(&repo)?;
                let also = also_parent.map(|hex| parse_id(&hex)).transpose()?;
                Ok(json!({ "id": commit(&repo, &message, &author, also, &keep)?.map(|id| id.to_string()) }))
            })())
        }
        "git_remote_set" => {
            let RemoteSet { repo, url, name } = crate::dispatch::read(command, args)?;
            answer(open(&repo).and_then(|repo| set_remote(&repo, name.as_deref().unwrap_or(REMOTE), &url)).map(|()| Value::Null))
        }
        "git_remote" => {
            let AtRepo { repo } = crate::dispatch::read(command, args)?;
            answer(open(&repo).map(|repo| match remote_url(&repo) {
                Some((name, url)) => json!({ "name": name, "url": url }),
                None => Value::Null,
            }))
        }
        "git_clone" => {
            let Clone { url, into, auth, shallow } = crate::dispatch::read(command, args)?;
            answer(clone(&url, &into, &auth, shallow).map(|(head, files)| json!({ "head": head.map(|id| id.to_string()), "files": files })))
        }
        "git_fetch" => {
            let WithAuth { repo, auth, deepen } = crate::dispatch::read(command, args)?;
            answer((|| {
                let repo = open(&repo)?;
                fetch(&repo, &auth, deepen)?;
                serde_json::to_value(divergence(&repo)?).map_err(|e| Fail::Other(e.to_string()))
            })())
        }
        "git_divergence" => {
            let AtRepo { repo } = crate::dispatch::read(command, args)?;
            answer(open(&repo).and_then(|repo| divergence(&repo)).and_then(|d| serde_json::to_value(d).map_err(|e| Fail::Other(e.to_string()))))
        }
        "git_push" => {
            let WithAuth { repo, auth, .. } = crate::dispatch::read(command, args)?;
            answer(open(&repo).and_then(|repo| push(&repo, &auth)).and_then(|p| serde_json::to_value(p).map_err(|e| Fail::Other(e.to_string()))))
        }
        "git_merge_base" => {
            let MergeBase { repo, a, b } = crate::dispatch::read(command, args)?;
            answer((|| {
                let repo = open(&repo)?;
                Ok(json!(merge_base(&repo, parse_id(&a)?, parse_id(&b)?)?.map(|id| id.to_string())))
            })())
        }
        "git_blob" => {
            let Blob { repo, commit, path } = crate::dispatch::read(command, args)?;
            answer((|| {
                let repo = open(&repo)?;
                Ok(json!(blob_text(&repo, parse_id(&commit)?, &path)?))
            })())
        }
        "git_three_way" => {
            let ThreeWay { repo, path } = crate::dispatch::read(command, args)?;
            answer((|| {
                let repo = open(&repo)?;
                let d = divergence(&repo)?;
                let at = |hex: &Option<String>| -> Result<Option<String>> {
                    match hex {
                        Some(hex) => blob_text(&repo, parse_id(hex)?, &path),
                        None => Ok(None),
                    }
                };
                Ok(json!({ "base": at(&d.base)?, "ours": at(&d.local)?, "theirs": at(&d.remote)? }))
            })())
        }
        "git_log" => {
            let Log { repo, count } = crate::dispatch::read(command, args)?;
            answer(open(&repo).and_then(|repo| log(&repo, count.unwrap_or(20))).and_then(|l| serde_json::to_value(l).map_err(|e| Fail::Other(e.to_string()))))
        }
        "git_diff" => {
            let Diff { repo, from, to } = crate::dispatch::read(command, args)?;
            answer((|| {
                let repo = open(&repo)?;
                let from = from.map(|hex| parse_id(&hex)).transpose()?;
                serde_json::to_value(diff(&repo, from, parse_id(&to)?)?).map_err(|e| Fail::Other(e.to_string()))
            })())
        }
        "git_write_blob" => {
            let WriteBlob { repo, commit, path, into } = crate::dispatch::read(command, args)?;
            answer((|| {
                let repo = open(&repo)?;
                match blob_at(&repo, parse_id(&commit)?, &path)? {
                    Some(bytes) => {
                        if let Some(parent) = into.parent() {
                            std::fs::create_dir_all(parent)?;
                        }
                        std::fs::write(&into, &bytes)?;
                        Ok(json!({ "bytes": bytes.len() }))
                    }
                    None => Ok(Value::Null),
                }
            })())
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

fn parse_id(hex: &str) -> Result<ObjectId> {
    ObjectId::from_hex(hex.as_bytes()).map_err(|e| Fail::Other(format!("{hex} is not a commit id: {e}")))
}

/// The repository at `path`, isolated: nothing of the Mac's own git configuration (credential helpers, hooks, the
/// user's name) is read, so a device behaves as the phone does.
pub fn open(path: &Path) -> Result<gix::Repository> {
    gix::open_opts(path, gix::open::Options::isolated()).map_err(|e| Fail::NoRepo(format!("{} holds no git repository ({})", path.display(), chain(&e))))
}

/// A repository at `path` with its first branch `main`: `true` when one was made, `false` when one was there.
pub fn init(path: &Path) -> Result<bool> {
    if gix::open_opts(path, gix::open::Options::isolated()).is_ok() {
        return Ok(false);
    }
    std::fs::create_dir_all(path)?;
    let repo = gix::ThreadSafeRepository::init_opts(path, gix::create::Kind::WithWorktree, gix::create::Options { destination_must_be_empty: None, fs_capabilities: None, object_hash: None }, gix::open::Options::isolated())?;
    drop(repo);
    Ok(true)
}

/// HEAD's commit, or `None` while the branch is unborn.
fn head_id(repo: &gix::Repository) -> Option<ObjectId> {
    repo.head_id().ok().map(|id| id.detach())
}

fn branch_ref(name: &str) -> String {
    format!("refs/heads/{name}")
}

fn remote_ref(remote: &str, name: &str) -> String {
    format!("refs/remotes/{remote}/{name}")
}

/// A reference's commit, or `None` when there is no such reference.
fn ref_id(repo: &gix::Repository, full_name: &str) -> Result<Option<ObjectId>> {
    match repo.try_find_reference(full_name)? {
        Some(mut reference) => Ok(Some(reference.peel_to_id()?.detach())),
        None => Ok(None),
    }
}

/// The worktree against HEAD: what the index says of the tree, and the files of the folder against the index,
/// untracked files listed one by one.
pub fn status(repo: &gix::Repository) -> Result<Vec<Change>> {
    use gix::status::index_worktree::iter::Summary;
    use gix::status::{Item, UntrackedFiles};
    let mut changes = Vec::new();
    let iter = repo.status(gix::progress::Discard)?.untracked_files(UntrackedFiles::Files).into_iter(Vec::<BString>::new())?;
    for item in iter {
        let item = item?;
        let (path, kind) = match &item {
            Item::IndexWorktree(item) => {
                let kind = match item.summary() {
                    Some(Summary::Added) => "added",
                    Some(Summary::Removed) => "removed",
                    Some(Summary::Modified) => "modified",
                    Some(Summary::TypeChange) => "typechange",
                    Some(Summary::Renamed) => "renamed",
                    Some(Summary::Copied) => "added",
                    Some(Summary::IntentToAdd) => "added",
                    Some(Summary::Conflict) => "conflict",
                    None => continue,
                };
                (item.rela_path().to_str_lossy().into_owned(), kind)
            }
            Item::TreeIndex(change) => {
                use gix::diff::index::ChangeRef;
                let kind = match change {
                    ChangeRef::Addition { .. } => "added",
                    ChangeRef::Deletion { .. } => "removed",
                    ChangeRef::Modification { .. } => "modified",
                    ChangeRef::Rewrite { .. } => "renamed",
                };
                (change.location().to_str_lossy().into_owned(), kind)
            }
        };
        changes.push(Change { path, kind });
    }
    changes.sort();
    changes.dedup_by(|a, b| a.path == b.path);
    Ok(changes)
}

/// What a snapshot takes from HEAD rather than the folder: the folders `keep` names (relative, `/`-separated, as
/// `orgs/Acme`), looked up in HEAD's tree.
struct Kept<'a> {
    folders: &'a [String],
    head: Option<gix::Tree<'a>>,
}

impl Kept<'_> {
    fn names(&self, rela: &str) -> bool {
        self.folders.iter().any(|k| k.trim_matches('/') == rela)
    }

    /// HEAD's entry at `rela`, where HEAD has one.
    fn entry(&self, rela: &str) -> Result<Option<gix::objs::tree::Entry>> {
        let Some(head) = &self.head else { return Ok(None) };
        Ok(head.lookup_entry_by_path(rela)?.map(|found| gix::objs::tree::Entry { mode: found.mode(), filename: found.filename().to_owned(), oid: found.oid().to_owned() }))
    }

    /// The kept folders whose parent is `dir_rela` ("" for the root) and that are not among `present`: HEAD's
    /// entries for them, so a folder gone from disk stays in the commit.
    fn missing(&self, dir_rela: &str, present: &[String]) -> Result<Vec<gix::objs::tree::Entry>> {
        let mut out = Vec::new();
        for folder in self.folders {
            let folder = folder.trim_matches('/');
            let (parent, name) = match folder.rfind('/') {
                Some(at) => (&folder[..at], &folder[at + 1..]),
                None => ("", folder),
            };
            if parent != dir_rela || name.is_empty() || present.iter().any(|p| p == name) {
                continue;
            }
            if let Some(entry) = self.entry(folder)? {
                out.push(entry);
            }
        }
        Ok(out)
    }
}

fn rela_text(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

/// Every file of the folder as blobs and trees in the object store, `.git` left out and `.gitignore` honoured, the
/// `keep` folders taken from HEAD: the root tree's id, the empty tree's for a folder with nothing in it.
fn snapshot(repo: &gix::Repository, keep: &[String]) -> Result<ObjectId> {
    let workdir = repo.workdir().ok_or_else(|| Fail::Other("the repository is bare and has no files to commit".into()))?.to_path_buf();
    let index = repo.index_or_empty()?;
    let mut excludes = repo.excludes(&index, None, gix::worktree::stack::state::ignore::Source::WorktreeThenIdMappingIfNotSkipped)?;
    let head = match head_id(repo) {
        Some(id) if !keep.is_empty() => Some(repo.find_commit(id)?.tree()?),
        _ => None,
    };
    let kept = Kept { folders: keep, head };
    Ok(tree_of(repo, &workdir, &workdir, &mut excludes, &kept)?.unwrap_or_else(|| gix::ObjectId::empty_tree(repo.object_hash())))
}

/// `dir` as a tree object, or `None` when it holds nothing a commit keeps (git has no empty trees).
fn tree_of(repo: &gix::Repository, workdir: &Path, dir: &Path, excludes: &mut gix::AttributeStack<'_>, kept: &Kept<'_>) -> Result<Option<ObjectId>> {
    use gix::objs::tree::{Entry, EntryKind};
    let mut names: Vec<_> = std::fs::read_dir(dir)?.collect::<std::io::Result<Vec<_>>>()?;
    names.sort_by_key(|entry| entry.file_name());
    let dir_rela = rela_text(dir.strip_prefix(workdir).expect("under the worktree"));
    let present: Vec<String> = names.iter().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
    let mut entries = kept.missing(&dir_rela, &present)?;
    for entry in names {
        let name = entry.file_name();
        if dir == workdir && name == ".git" {
            continue;
        }
        let path = entry.path();
        let meta = std::fs::symlink_metadata(&path)?;
        let rela = path.strip_prefix(workdir).expect("under the worktree");
        let filename = gix::path::into_bstr(Path::new(&name))?.into_owned();
        if meta.is_dir() && kept.names(&rela_text(rela)) {
            // As HEAD has it, or not at all.
            if let Some(from_head) = kept.entry(&rela_text(rela))? {
                entries.push(from_head);
            }
            continue;
        }
        if meta.file_type().is_symlink() {
            // A link is kept as git keeps one: its target's bytes.
            let target = std::fs::read_link(&path)?;
            let oid = repo.write_blob(gix::path::into_bstr(&target)?.as_ref())?.detach();
            entries.push(Entry { mode: EntryKind::Link.into(), filename, oid });
            continue;
        }
        let mode = if meta.is_dir() { Some(gix::index::entry::Mode::DIR) } else { Some(gix::index::entry::Mode::FILE) };
        if excludes.at_path(rela, mode)?.is_excluded() {
            continue;
        }
        if meta.is_dir() {
            if let Some(oid) = tree_of(repo, workdir, &path, excludes, kept)? {
                entries.push(Entry { mode: EntryKind::Tree.into(), filename, oid });
            }
        } else if meta.is_file() {
            let data = std::fs::read(&path)?;
            let oid = repo.write_blob(&data)?.detach();
            #[cfg(unix)]
            let executable = {
                use std::os::unix::fs::PermissionsExt;
                meta.permissions().mode() & 0o111 != 0
            };
            #[cfg(not(unix))]
            let executable = false;
            let kind = if executable { EntryKind::BlobExecutable } else { EntryKind::Blob };
            entries.push(Entry { mode: kind.into(), filename, oid });
        }
    }
    if entries.is_empty() {
        return Ok(None);
    }
    entries.sort();
    Ok(Some(repo.write_object(gix::objs::Tree { entries })?.detach()))
}

/// The index written as `tree` with each file's stat, so the next status compares stats and not contents.
fn write_index(repo: &gix::Repository, tree: ObjectId) -> Result<()> {
    let workdir = repo.workdir().ok_or_else(|| Fail::Other("the repository is bare".into()))?.to_path_buf();
    let mut state = gix::index::State::from_tree(&tree, &repo.objects, Default::default())?;
    for (entry, path) in state.entries_mut_with_paths() {
        if let Ok(meta) = gix::index::fs::Metadata::from_path_no_follow(&workdir.join(gix::path::from_bstr(path)?)) {
            if let Ok(stat) = gix::index::entry::Stat::from_fs(&meta) {
                entry.stat = stat;
            }
        }
    }
    let mut file = gix::index::File::from_state(state, repo.index_path());
    file.write(Default::default())?;
    Ok(())
}

/// A commit of everything in the folder, with `also` as a second parent when the app merged, and the `keep` folders
/// as HEAD has them (see `Kept`); `None` when the folder is what HEAD already holds and there is no merge to record.
pub fn commit(repo: &gix::Repository, message: &str, author: &Who, also: Option<ObjectId>, keep: &[String]) -> Result<Option<ObjectId>> {
    let tree = snapshot(repo, keep)?;
    let head = head_id(repo);
    let head_tree = match head {
        Some(id) => Some(repo.find_commit(id)?.tree_id()?.detach()),
        None => None,
    };
    if head_tree == Some(tree) && also.is_none() {
        return Ok(None);
    }
    let signature = gix::actor::Signature { name: author.name.as_str().into(), email: author.email.as_str().into(), time: gix::date::Time::now_local_or_utc() };
    let mut time = gix::date::parse::TimeBuf::default();
    let signature = signature.to_ref(&mut time);
    let reference = match repo.head_name()? {
        Some(name) => name.to_string(),
        None => branch_ref(BRANCH),
    };
    let parents: Vec<ObjectId> = head.into_iter().chain(also.filter(|also| Some(*also) != head)).collect();
    let id = repo.commit_as(signature, signature, reference.as_str(), message, tree, parents)?.detach();
    write_index(repo, tree)?;
    Ok(Some(id))
}

/// The remote and `main`'s tracking of it, in the repository's own config file.
pub fn set_remote(repo: &gix::Repository, name: &str, url: &str) -> Result<()> {
    let path = repo.git_dir().join("config");
    let mut file = gix::config::File::from_path_no_includes(path.clone(), gix::config::Source::Local)?;
    file.set_raw_value_by("remote", Some(name.into()), "url", url)?;
    file.set_raw_value_by("remote", Some(name.into()), "fetch", format!("+refs/heads/*:refs/remotes/{name}/*").as_str())?;
    file.set_raw_value_by("branch", Some(BRANCH.into()), "remote", name)?;
    file.set_raw_value_by("branch", Some(BRANCH.into()), "merge", branch_ref(BRANCH).as_str())?;
    std::fs::write(&path, file.to_bstring())?;
    Ok(())
}

/// The remote `origin` points at, if it is configured.
pub fn remote_url(repo: &gix::Repository) -> Option<(String, String)> {
    let remote = repo.find_remote(REMOTE).ok()?;
    let url = remote.url(gix::remote::Direction::Fetch)?;
    Some((REMOTE.to_string(), url.to_bstring().to_string()))
}

/// rustls with ring's ciphers and webpki's roots: the one TLS set-up the core uses on every platform.
fn tls() -> rustls::ClientConfig {
    static CONFIG: OnceLock<rustls::ClientConfig> = OnceLock::new();
    CONFIG
        .get_or_init(|| {
            // The process's default provider too, in case any path builds a ClientConfig without naming one.
            let _ = rustls::crypto::ring::default_provider().install_default();
            let roots = rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
            rustls::ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
                .with_safe_default_protocol_versions()
                .expect("ring supports TLS 1.2 and 1.3")
                .with_root_certificates(roots)
                .with_no_client_auth()
        })
        .clone()
}

/// What the HTTP transport is told before its first request: the TLS above, through reqwest's `configure_client`.
/// `None` for a URL that is not HTTP.
fn transport_options(url: &gix::Url) -> Option<Box<dyn std::any::Any>> {
    use gix::protocol::transport::client::blocking_io::http;
    if !matches!(url.scheme, gix::url::Scheme::Http | gix::url::Scheme::Https) {
        return None;
    }
    let mut options = http::Options::default();
    let backend = http::reqwest::Options {
        // reqwest's builder is not named here: the core has no reqwest of this version of its own (the voice
        // downloads use 0.12), so the closure's type is the transport's.
        configure_client: Some(Box::new(|builder| Ok(builder.use_preconfigured_tls(tls())))),
        configure_request: None,
    };
    options.backend = Some(Arc::new(Mutex::new(backend)));
    Some(Box::new(options))
}

/// The credentials closure gix calls when a remote answers 401: the token as the password, once. A second asking
/// means the token was refused, and nothing is offered again.
fn authenticate(auth: Auth) -> impl FnMut(gix::credentials::helper::Action) -> gix::Result<Option<gix::credentials::protocol::Outcome>> {
    use gix::credentials::helper::Action;
    move |action| match action {
        Action::Get(context) => match &auth.token {
            Some(token) => Ok(Some(gix::credentials::protocol::Outcome {
                identity: gix::sec::identity::Account { username: auth.user.clone().unwrap_or_else(|| "x-access-token".to_string()), password: token.clone(), oauth_refresh_token: None },
                next: context.into(),
            })),
            None => Ok(None),
        },
        Action::Store(_) | Action::Erase(_) => Ok(None),
    }
}

/// A clone of `url` into `into`, checked out; the HEAD commit and how many files were written.
pub fn clone(url: &str, into: &Path, auth: &Auth, shallow: bool) -> Result<(Option<ObjectId>, usize)> {
    let parsed = gix::url::parse(url.as_bytes().as_bstr())?;
    let mut prepare = gix::clone::PrepareFetch::new(parsed.clone(), into, gix::create::Kind::WithWorktree, gix::create::Options { destination_must_be_empty: Some(true), fs_capabilities: None, object_hash: None }, gix::open::Options::isolated())?;
    if shallow {
        prepare = prepare.with_shallow(gix::remote::fetch::Shallow::DepthAtRemote(std::num::NonZeroU32::new(1).expect("one")));
    }
    let auth = auth.clone();
    prepare = prepare.configure_connection(move |connection| {
        connection.set_credentials(authenticate(auth.clone()));
        if let Some(options) = transport_options(&parsed) {
            connection.set_transport_options(options);
        }
        Ok(())
    });
    let (mut checkout, _fetched) = prepare.fetch_then_checkout(gix::progress::Discard, &gix::interrupt::IS_INTERRUPTED)?;
    let (repo, outcome) = checkout.main_worktree(gix::progress::Discard, &gix::interrupt::IS_INTERRUPTED)?;
    Ok((head_id(&repo), outcome.files_updated))
}

/// `origin` fetched into `refs/remotes/origin/*`; with `deepen`, a shallow repository is brought to its whole history
/// (git's own `--unshallow` is a deepen by 2^31-1, and that is what is asked here).
pub fn fetch(repo: &gix::Repository, auth: &Auth, deepen: bool) -> Result<()> {
    // Without reflog lines for the remote-tracking refs it moves: those want a committer, which an isolated
    // repository has not, and the app records nothing in reflogs.
    let mut repo = repo.clone();
    repo.refs.write_reflog = gix::refs::store::WriteReflog::Disable;
    let remote = repo.find_remote(REMOTE).map_err(|e| Fail::Other(format!("no remote is configured: {}", chain(&e))))?;
    let url = remote.url(gix::remote::Direction::Fetch).ok_or_else(|| Fail::Other("the remote has no URL".into()))?.clone();
    let mut connection = remote.connect(gix::remote::Direction::Fetch)?;
    connection.set_credentials(authenticate(auth.clone()));
    if let Some(options) = transport_options(&url) {
        connection.set_transport_options(options);
    }
    let mut prepared = connection.prepare_fetch(gix::progress::Discard, Default::default())?;
    if deepen && repo.is_shallow()? {
        prepared = prepared.with_shallow(gix::remote::fetch::Shallow::Deepen(i32::MAX as u32));
    }
    prepared.receive(gix::progress::Discard, &gix::interrupt::IS_INTERRUPTED)?;
    Ok(())
}

/// The last `count` commits of HEAD, newest first; none while the branch is unborn.
pub fn log(repo: &gix::Repository, count: usize) -> Result<Vec<Logged>> {
    let Some(head) = head_id(repo) else { return Ok(Vec::new()) };
    let mut out = Vec::new();
    for info in repo.rev_walk([head]).all()?.take(count) {
        let info = info?;
        let commit = repo.find_commit(info.id)?;
        let time = commit.time().map(|t| t.seconds).unwrap_or(0);
        let name = commit.author().map(|a| a.name.to_string()).unwrap_or_default();
        out.push(Logged { id: info.id.to_string(), time, message: commit.message_raw_sloppy().to_str_lossy().trim_end().to_string(), name });
    }
    Ok(out)
}

/// What `to`'s tree has over `from`'s, file by file; everything `to` holds, as added, when `from` is `None`.
pub fn diff(repo: &gix::Repository, from: Option<ObjectId>, to: ObjectId) -> Result<Vec<TreeChange>> {
    use gix::object::tree::diff::ChangeDetached;
    let to_tree = repo.find_commit(to)?.tree()?;
    let from_tree = match from {
        Some(id) => Some(repo.find_commit(id)?.tree()?),
        None => None,
    };
    let changes = repo.diff_tree_to_tree(from_tree.as_ref(), Some(&to_tree), None)?;
    let mut out = Vec::new();
    for change in changes {
        let (path, kind, from) = match change {
            ChangeDetached::Addition { location, entry_mode, .. } => {
                if entry_mode.is_tree() {
                    continue;
                }
                (location, "added", None)
            }
            ChangeDetached::Deletion { location, entry_mode, .. } => {
                if entry_mode.is_tree() {
                    continue;
                }
                (location, "removed", None)
            }
            ChangeDetached::Modification { location, entry_mode, .. } => {
                if entry_mode.is_tree() {
                    continue;
                }
                (location, "modified", None)
            }
            ChangeDetached::Rewrite { source_location, location, entry_mode, .. } => {
                if entry_mode.is_tree() {
                    continue;
                }
                (location, "renamed", Some(source_location.to_str_lossy().into_owned()))
            }
        };
        out.push(TreeChange { path: path.to_str_lossy().into_owned(), kind, from });
    }
    out.sort();
    Ok(out)
}

pub fn merge_base(repo: &gix::Repository, a: ObjectId, b: ObjectId) -> Result<Option<ObjectId>> {
    Ok(repo.merge_base(a, b)?.map(|id| id.detach()))
}

/// Commits reachable from `tip` and not from `not`.
fn count_from(repo: &gix::Repository, tip: ObjectId, not: Option<ObjectId>) -> Result<usize> {
    let mut walk = repo.rev_walk([tip]);
    if let Some(not) = not {
        walk = walk.with_hidden([not]);
    }
    Ok(walk.all()?.count())
}

/// `main` against `origin/main`, as last fetched.
pub fn divergence(repo: &gix::Repository) -> Result<Divergence> {
    let local = ref_id(repo, &branch_ref(BRANCH))?;
    let remote = ref_id(repo, &remote_ref(REMOTE, BRANCH))?;
    let base = match (local, remote) {
        (Some(a), Some(b)) => merge_base(repo, a, b)?,
        _ => None,
    };
    let state = match (local, remote) {
        (None, None) => "empty",
        (Some(a), Some(b)) if a == b => "same",
        (Some(_), None) => "ahead",
        (None, Some(_)) => "behind",
        (Some(_), Some(b)) if base == Some(b) => "ahead",
        (Some(a), Some(_)) if base == Some(a) => "behind",
        _ => "diverged",
    };
    let ahead = match local {
        Some(tip) => count_from(repo, tip, remote.filter(|_| base.is_some()))?,
        None => 0,
    };
    let behind = match remote {
        Some(tip) => count_from(repo, tip, local.filter(|_| base.is_some()))?,
        None => 0,
    };
    Ok(Divergence { local: local.map(|id| id.to_string()), remote: remote.map(|id| id.to_string()), base: base.map(|id| id.to_string()), state, ahead, behind })
}

/// `path`'s bytes at `commit`, or `None` when the commit has no such file.
pub fn blob_at(repo: &gix::Repository, commit: ObjectId, path: &str) -> Result<Option<Vec<u8>>> {
    let tree = repo.find_commit(commit)?.tree()?;
    match tree.lookup_entry_by_path(path)? {
        Some(entry) if entry.mode().is_blob() => Ok(Some(entry.object()?.data.clone())),
        _ => Ok(None),
    }
}

fn blob_text(repo: &gix::Repository, commit: ObjectId, path: &str) -> Result<Option<String>> {
    Ok(blob_at(repo, commit, path)?.map(|bytes| String::from_utf8_lossy(&bytes).into_owned()))
}

/// `main` to `origin`, fast-forward only: gix has no push, so this is the receive-pack protocol over its plumbing.
pub fn push(repo: &gix::Repository, auth: &Auth) -> Result<Pushed> {
    use gix::protocol::transport::client::{MessageKind, TransportWithoutIO, WriteMode};
    use gix::protocol::transport::{Protocol, Service};
    let remote = repo.find_remote(REMOTE).map_err(|e| Fail::Other(format!("no remote is configured: {}", chain(&e))))?;
    let url = remote.url(gix::remote::Direction::Push).ok_or_else(|| Fail::Other("the remote has no URL".into()))?.clone();
    let full_name = branch_ref(BRANCH);
    let local = ref_id(repo, &full_name)?.ok_or_else(|| Fail::Other("there is nothing to push: no commit yet".into()))?;

    // The handshake: the remote's refs, with the token offered when it asks.
    let mut transport = gix::protocol::transport::client::blocking_io::connect::connect(url.clone(), gix::protocol::transport::client::blocking_io::connect::Options { version: Protocol::V1, ..Default::default() })?;
    if let Some(options) = transport_options(&url) {
        transport.configure(&*options)?;
    }
    let handshake = gix::protocol::handshake(&mut transport, Service::ReceivePack, authenticate(auth.clone()), Vec::new(), &mut gix::progress::Discard)?;
    if !handshake.capabilities.contains("report-status") {
        return Err(Fail::Other("the remote does not report the status of a push".into()));
    }
    let old = handshake.refs.unwrap_or_default().iter().find_map(|r| {
        let (name, object, _) = r.unpack();
        (name == full_name.as_bytes()).then(|| object.map(|o| o.to_owned()))
    });
    let old = old.flatten();
    if old == Some(local) {
        return Ok(Pushed { old: old.map(|id| id.to_string()), new: local.to_string(), up_to_date: true });
    }
    if let Some(old) = old {
        if !repo.objects.exists(&old) {
            return Err(Fail::NonFastForward(format!("the remote's {BRANCH} is at {old}, which this device has not fetched")));
        }
        if merge_base(repo, local, old)? != Some(old) {
            return Err(Fail::NonFastForward(format!("the remote's {BRANCH} has commits this device's has not; fetch and merge first")));
        }
    }

    // The pack: every commit the remote lacks, each with what its tree adds over its parent's.
    let mut walk = repo.rev_walk([local]);
    if let Some(old) = old {
        walk = walk.with_hidden([old]);
    }
    let ids: Vec<ObjectId> = walk.all()?.map(|info| info.map(|info| info.id)).collect::<gix::Result<_>>()?;
    // The handle under the repository's proxy: the pack code wants gix-pack's `Find`, which the proxy does not have.
    let mut objects = repo.objects.clone().into_inner();
    // The pack code reads objects on threads of its own and asks that no pack be unloaded under them meanwhile.
    objects.prevent_pack_unload();
    let (counts, _) = gix_pack::data::output::count::objects(objects.clone(), Box::new(ids.into_iter().map(Ok)), &gix::progress::Discard, &gix::interrupt::IS_INTERRUPTED, gix_pack::data::output::count::objects::Options { input_object_expansion: gix_pack::data::output::count::objects::ObjectExpansion::TreeAdditionsComparedToAncestor, ..Default::default() })?;
    let total = counts.len() as u32;
    let entries = gix_pack::data::output::entry::iter_from_counts(counts, objects, Box::new(gix::progress::Discard), gix_pack::data::output::entry::iter_from_counts::Options { version: gix_pack::data::Version::V2, allow_thin_pack: false, ..Default::default() })?;
    let in_order = gix::parallel::InOrderIter::from(entries);
    let mut pack = Vec::new();
    let mut writer = gix_pack::data::output::bytes::FromEntriesIter::new(in_order, &mut pack, total, gix_pack::data::Version::V2, repo.object_hash());
    for written in &mut writer {
        written?;
    }
    drop(writer);

    // The request: one command line, a flush, the pack; then the report.
    let request = transport.request(WriteMode::Binary, MessageKind::Flush, false).map_err(|e| Fail::Network(format!("the push request could not be opened: {e}")))?;
    let (mut out, mut reader) = request.into_parts();
    let zero = ObjectId::null(repo.object_hash());
    let line = format!("{} {} {}\0report-status", old.unwrap_or(zero), local, full_name);
    gix::protocol::transport::packetline::blocking_io::encode::data_to_write(line.as_bytes(), &mut out)?;
    gix::protocol::transport::packetline::blocking_io::encode::flush_to_write(&mut out)?;
    out.write_all(&pack)?;
    out.flush()?;
    drop(out);
    let mut lines = Vec::new();
    while let Some(line) = reader.readline() {
        let line = line?.map_err(|e| Fail::Other(format!("the remote's answer could not be read: {e}")))?;
        match line {
            gix::protocol::transport::packetline::PacketLineRef::Data(data) => lines.push(data.to_str_lossy().trim().to_string()),
            gix::protocol::transport::packetline::PacketLineRef::Flush => break,
            _ => {}
        }
    }
    drop(reader);
    let unpacked = lines.iter().any(|l| l == "unpack ok");
    let ok = lines.iter().any(|l| l == &format!("ok {full_name}"));
    if !(unpacked && ok) {
        let reason = lines.iter().find(|l| l.starts_with("ng ") || l.starts_with("unpack ")).cloned().unwrap_or_else(|| lines.join("; "));
        if reason.contains("non-fast-forward") || reason.contains("fetch first") {
            return Err(Fail::NonFastForward(format!("the remote refused: {reason}")));
        }
        return Err(Fail::Other(format!("the remote refused the push: {reason}")));
    }
    // What the remote now has, remembered as git remembers it. Without a reflog line: that would want a committer,
    // and a push has none to give.
    let mut quiet = repo.clone();
    quiet.refs.write_reflog = gix::refs::store::WriteReflog::Disable;
    quiet.reference(remote_ref(REMOTE, BRANCH).as_str(), local, gix::refs::transaction::PreviousValue::Any, "push")?;
    Ok(Pushed { old: old.map(|id| id.to_string()), new: local.to_string(), up_to_date: false })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    fn who() -> Who {
        Who { name: "Ghost".into(), email: "ghost@example.com".into() }
    }

    fn write(dir: &Path, rela: &str, text: &str) {
        let path = dir.join(rela);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn read(dir: &Path, rela: &str) -> String {
        std::fs::read_to_string(dir.join(rela)).unwrap()
    }

    fn git(args: &[&str], cwd: &Path) -> String {
        let out = std::process::Command::new("git").args(args).current_dir(cwd).output().expect("git on the Mac");
        assert!(out.status.success(), "git {args:?}: {}", String::from_utf8_lossy(&out.stderr));
        String::from_utf8_lossy(&out.stdout).trim().to_string()
    }

    /// A bare repository the tests push to and clone from, by its file URL.
    fn bare(root: &Path) -> String {
        let path = root.join("remote.git");
        git(&["init", "--bare", "-b", BRANCH, path.to_str().unwrap()], root);
        format!("file://{}", path.display())
    }

    #[test]
    fn init_commit_clone_diverge_merge_push() {
        let root = TempDir::new("git");
        let url = bare(&root);

        // init, two files, a commit.
        let a = root.join("a");
        assert_eq!(init(&a), Ok(true));
        assert_eq!(init(&a), Ok(false));
        let repo_a = open(&a).unwrap();
        write(&a, "Notes/first.md", "# First\n\nline one\nline two\nline three\n");
        write(&a, "Notes/second.md", "# Second\n");
        write(&a, ".gitignore", "*.sqlite\n");
        write(&a, "index.sqlite", "not committed");
        let status_before = status(&repo_a).unwrap();
        assert_eq!(status_before.iter().map(|c| c.path.as_str()).collect::<Vec<_>>(), [".gitignore", "Notes/first.md", "Notes/second.md"]);
        assert!(status_before.iter().all(|c| c.kind == "added"));
        let first = commit(&repo_a, "two notes", &who(), None, &[]).unwrap().expect("a commit");
        assert_eq!(commit(&repo_a, "nothing", &who(), None, &[]).unwrap(), None, "nothing changed, nothing committed");
        assert_eq!(status(&repo_a).unwrap(), Vec::<Change>::new());
        assert_eq!(head_id(&repo_a), Some(first));
        // git agrees with what was written.
        assert_eq!(git(&["ls-files"], &a), ".gitignore\nNotes/first.md\nNotes/second.md");
        assert_eq!(git(&["status", "--porcelain"], &a), "");

        // The remote, a push, a clone.
        set_remote(&repo_a, REMOTE, &url).unwrap();
        // A repository reads its config when opened: the remote is seen by the next open, as every command opens anew.
        assert_eq!(remote_url(&repo_a), None);
        let repo_a = open(&a).unwrap();
        assert_eq!(remote_url(&repo_a), Some((REMOTE.to_string(), url.clone())));
        let pushed = push(&repo_a, &Auth::default()).unwrap();
        assert_eq!(pushed, Pushed { old: None, new: first.to_string(), up_to_date: false });
        assert_eq!(push(&repo_a, &Auth::default()).unwrap().up_to_date, true);
        assert_eq!(git(&["rev-parse", BRANCH], &root.join("remote.git")), first.to_string());
        let b = root.join("b");
        let (head, files) = clone(&url, &b, &Auth::default(), false).unwrap();
        assert_eq!((head, files), (Some(first), 3));
        assert_eq!(read(&b, "Notes/first.md"), "# First\n\nline one\nline two\nline three\n");
        let repo_b = open(&b).unwrap();
        assert_eq!(status(&repo_b).unwrap(), Vec::<Change>::new(), "a fresh clone is clean");
        assert_eq!(divergence(&repo_b).unwrap().state, "same");

        // A change on each side; b pushes first.
        write(&b, "Notes/first.md", "# First\n\nline one\nline two (b)\nline three\n");
        let on_b = commit(&repo_b, "b's line", &who(), None, &[]).unwrap().unwrap();
        push(&repo_b, &Auth::default()).unwrap();
        write(&a, "Notes/first.md", "# First (a)\n\nline one\nline two\nline three\n");
        write(&a, "Notes/third.md", "# Third\n");
        let on_a = commit(&repo_a, "a's title and a third note", &who(), None, &[]).unwrap().unwrap();
        let refused = push(&repo_a, &Auth::default()).unwrap_err();
        assert!(matches!(refused, Fail::NonFastForward(_)), "{refused:?}");
        assert!(refused.said().starts_with("Not fast-forward: "));

        // a fetches and sees the divergence, with the three texts of the note both changed.
        fetch(&repo_a, &Auth::default(), false).unwrap();
        let d = divergence(&repo_a).unwrap();
        assert_eq!((d.state, d.ahead, d.behind), ("diverged", 1, 1));
        assert_eq!(d.local.as_deref(), Some(on_a.to_string().as_str()));
        assert_eq!(d.remote.as_deref(), Some(on_b.to_string().as_str()));
        assert_eq!(d.base.as_deref(), Some(first.to_string().as_str()));
        let base = blob_text(&repo_a, first, "Notes/first.md").unwrap().unwrap();
        let ours = blob_text(&repo_a, on_a, "Notes/first.md").unwrap().unwrap();
        let theirs = blob_text(&repo_a, on_b, "Notes/first.md").unwrap().unwrap();
        assert_eq!(base, "# First\n\nline one\nline two\nline three\n");
        assert_eq!(ours, "# First (a)\n\nline one\nline two\nline three\n");
        assert_eq!(theirs, "# First\n\nline one\nline two (b)\nline three\n");
        assert_eq!(blob_text(&repo_a, on_a, "Notes/nowhere.md").unwrap(), None);
        let three = call("git_three_way", json!({ "repo": a.to_str().unwrap(), "path": "Notes/first.md" })).unwrap();
        assert_eq!(three["base"], base);
        assert_eq!(three["theirs"], theirs);

        // The merge is the app's (merge_words.dart); here its result is written and committed with both parents.
        write(&a, "Notes/first.md", "# First (a)\n\nline one\nline two (b)\nline three\n");
        let merged = commit(&repo_a, "merge", &who(), Some(on_b), &[]).unwrap().unwrap();
        let parents = git(&["log", "-1", "--format=%P", &merged.to_string()], &a);
        assert_eq!(parents, format!("{on_a} {on_b}"));
        let pushed = push(&repo_a, &Auth::default()).unwrap();
        assert_eq!(pushed.old.as_deref(), Some(on_b.to_string().as_str()));
        assert_eq!(divergence(&repo_a).unwrap().state, "same");
        assert_eq!(git(&["rev-parse", BRANCH], &root.join("remote.git")), merged.to_string());
        // The other clone takes it, and git finds the remote whole and sound.
        fetch(&repo_b, &Auth::default(), false).unwrap();
        let d = divergence(&repo_b).unwrap();
        assert_eq!((d.state, d.ahead, d.behind), ("behind", 0, 2));
        assert_eq!(git(&["fsck", "--strict"], &root.join("remote.git")), "");
        assert_eq!(git(&["show", &format!("{merged}:Notes/first.md")], &root.join("remote.git")), "# First (a)\n\nline one\nline two (b)\nline three");
        assert_eq!(git(&["show", &format!("{merged}:Notes/third.md")], &root.join("remote.git")), "# Third");
    }

    /// The plugin's slice: the log the page reads, the tree diff the merge walks, a blob written to a file, and a
    /// shallow clone deepened to the whole history.
    #[test]
    fn log_diff_write_blob_and_deepen() {
        let root = TempDir::new("git-log-diff");
        let url = bare(&root);
        let a = root.join("a");
        init(&a).unwrap();
        let repo_a = open(&a).unwrap();
        assert_eq!(log(&repo_a, 5).unwrap(), Vec::<Logged>::new(), "an unborn branch has no log");
        write(&a, "Inbox/one.md", "# One\n");
        write(&a, "image/p.jpg", "\u{ff}\u{d8}bytes");
        let first = commit(&repo_a, "New: One", &who(), None, &[]).unwrap().unwrap();
        write(&a, "Inbox/one.md", "# One\n\nmore\n");
        write(&a, "Inbox/two.md", "# Two\n");
        std::fs::remove_file(a.join("image/p.jpg")).unwrap();
        let second = commit(&repo_a, "2 notes changed: One, Two", &who(), None, &[]).unwrap().unwrap();

        let logged = log(&repo_a, 5).unwrap();
        assert_eq!(logged.len(), 2);
        assert_eq!((logged[0].id.as_str(), logged[0].message.as_str(), logged[0].name.as_str()), (second.to_string().as_str(), "2 notes changed: One, Two", "Ghost"));
        assert_eq!(logged[1].message, "New: One");
        assert!(logged[0].time > 1_700_000_000, "{}", logged[0].time);
        assert_eq!(log(&repo_a, 1).unwrap().len(), 1);
        let by_call = call("git_log", json!({ "repo": a.to_str().unwrap(), "count": 1 })).unwrap();
        assert_eq!(by_call[0]["message"], "2 notes changed: One, Two");

        let changes = diff(&repo_a, Some(first), second).unwrap();
        assert_eq!(changes, vec![TreeChange { path: "Inbox/one.md".into(), kind: "modified", from: None }, TreeChange { path: "Inbox/two.md".into(), kind: "added", from: None }, TreeChange { path: "image/p.jpg".into(), kind: "removed", from: None }]);
        let all = diff(&repo_a, None, first).unwrap();
        assert_eq!(all.iter().map(|c| (c.path.as_str(), c.kind)).collect::<Vec<_>>(), [("Inbox/one.md", "added"), ("image/p.jpg", "added")], "against nothing, everything is added; folders are not listed");
        let by_call = call("git_diff", json!({ "repo": a.to_str().unwrap(), "from": first.to_string(), "to": second.to_string() })).unwrap();
        assert_eq!(by_call[2]["kind"], "removed");
        assert!(by_call[2].get("from").is_none(), "no old path unless renamed");

        let into = root.join("out").join("p.jpg");
        let written = call("git_write_blob", json!({ "repo": a.to_str().unwrap(), "commit": first.to_string(), "path": "image/p.jpg", "into": into.to_str().unwrap() })).unwrap();
        assert_eq!(written["bytes"], 9, "two two-byte characters and five ASCII");
        assert_eq!(std::fs::read(&into).unwrap(), "\u{ff}\u{d8}bytes".as_bytes());
        assert_eq!(call("git_write_blob", json!({ "repo": a.to_str().unwrap(), "commit": second.to_string(), "path": "image/p.jpg", "into": into.to_str().unwrap() })).unwrap(), Value::Null, "removed by then");

        // A shallow clone sees one commit; deepened, both.
        set_remote(&repo_a, REMOTE, &url).unwrap();
        let repo_a = open(&a).unwrap();
        push(&repo_a, &Auth::default()).unwrap();
        let b = root.join("b");
        clone(&url, &b, &Auth::default(), true).unwrap();
        let repo_b = open(&b).unwrap();
        assert!(repo_b.is_shallow().unwrap());
        assert_eq!(log(&repo_b, 5).unwrap().len(), 1);
        let status = call("git_status", json!({ "repo": b.to_str().unwrap() })).unwrap();
        assert_eq!(status["shallow"], true);
        fetch(&repo_b, &Auth::default(), true).unwrap();
        let repo_b = open(&b).unwrap();
        assert!(!repo_b.is_shallow().unwrap(), "deepened to the whole history");
        assert_eq!(log(&repo_b, 5).unwrap().len(), 2);
        assert_eq!(git(&["rev-list", "--count", "HEAD"], &b), "2");
        assert_eq!(call("git_status", json!({ "repo": b.to_str().unwrap() })).unwrap()["shallow"], false);
    }

    /// `keep`: a folder taken from HEAD as it was, whether the folder changed on disk or is gone, and left out
    /// where HEAD never had it.
    #[test]
    fn kept_folders_come_from_head() {
        let root = TempDir::new("git-keep");
        let a = root.join("a");
        init(&a).unwrap();
        let repo = open(&a).unwrap();
        write(&a, "Inbox/one.md", "# One\n");
        write(&a, "orgs/Acme/plan.md", "# Plan\n");
        write(&a, "orgs/Beta/b.md", "# B\n");
        // Beta kept before any HEAD has it: not committed at all.
        let first = commit(&repo, "first", &who(), None, &["orgs/Beta".to_string()]).unwrap().unwrap();
        assert_eq!(git(&["ls-files"], &a), "Inbox/one.md\norgs/Acme/plan.md");
        // Acme changed and Beta added on disk; both kept: the commit has Acme as it was and still no Beta.
        write(&a, "orgs/Acme/plan.md", "# Plan\n\nchanged on this device\n");
        write(&a, "orgs/Acme/new.md", "# New\n");
        write(&a, "Inbox/one.md", "# One\n\nmore\n");
        let second = commit(&repo, "second", &who(), None, &["orgs/Acme".to_string(), "orgs/Beta/".to_string()]).unwrap().unwrap();
        assert_eq!(git(&["show", &format!("{second}:orgs/Acme/plan.md")], &a), "# Plan");
        assert_eq!(git(&["ls-tree", "-r", "--name-only", &second.to_string()], &a), "Inbox/one.md\norgs/Acme/plan.md");
        // Acme gone from disk and kept: still in the commit; nothing else changed, so nothing to commit.
        std::fs::remove_dir_all(a.join("orgs/Acme")).unwrap();
        assert_eq!(commit(&repo, "third", &who(), None, &["orgs/Acme".to_string(), "orgs/Beta".to_string()]).unwrap(), None);
        // Not kept: Acme's removal and Beta's arrival are the commit.
        let fourth = commit(&repo, "fourth", &who(), None, &[]).unwrap().unwrap();
        assert_eq!(git(&["ls-tree", "-r", "--name-only", &fourth.to_string()], &a), "Inbox/one.md\norgs/Beta/b.md");
        let by_call = call("git_commit", json!({ "repo": a.to_str().unwrap(), "message": "x", "author": {"name": "G", "email": "g@x"}, "keep": ["orgs/Beta"] })).unwrap();
        assert_eq!(by_call["id"], Value::Null, "nothing changed");
        assert_eq!(diff(&repo, Some(first), fourth).unwrap().iter().map(|c| (c.path.as_str(), c.kind)).collect::<Vec<_>>(), [("Inbox/one.md", "modified"), ("orgs/Acme/plan.md", "removed"), ("orgs/Beta/b.md", "added")]);
    }

    #[test]
    fn a_shallow_clone_has_one_commit() {
        let root = TempDir::new("git-shallow");
        let url = bare(&root);
        let a = root.join("a");
        init(&a).unwrap();
        let repo_a = open(&a).unwrap();
        write(&a, "one.md", "1\n");
        commit(&repo_a, "one", &who(), None, &[]).unwrap();
        write(&a, "two.md", "2\n");
        let second = commit(&repo_a, "two", &who(), None, &[]).unwrap().unwrap();
        set_remote(&repo_a, REMOTE, &url).unwrap();
        let repo_a = open(&a).unwrap();
        push(&repo_a, &Auth::default()).unwrap();
        let b = root.join("b");
        let (head, files) = clone(&url, &b, &Auth::default(), true).unwrap();
        assert_eq!((head, files), (Some(second), 2));
        assert_eq!(git(&["rev-list", "--count", "HEAD"], &b), "1");
        assert!(b.join(".git/shallow").exists());
    }

    #[test]
    fn the_errors_are_told_apart() {
        let root = TempDir::new("git-errors");
        assert!(matches!(open(&root.join("nowhere")), Err(Fail::NoRepo(_))));
        assert!(call("git_status", json!({ "repo": root.join("nowhere").to_str().unwrap() })).unwrap_err().starts_with("No repository: "));
        let a = root.join("a");
        init(&a).unwrap();
        let repo = open(&a).unwrap();
        assert!(matches!(fetch(&repo, &Auth::default(), false), Err(Fail::Other(_))), "no remote yet");
        set_remote(&repo, REMOTE, "https://127.0.0.1:9/nobody/nothing.git").unwrap();
        let repo = open(&a).unwrap();
        let err = fetch(&repo, &Auth { user: None, token: Some("x".into()) }, false).unwrap_err();
        assert!(matches!(err, Fail::Network(_)), "{err:?}");
        assert!(err.said().starts_with("No connection: "));
        write(&a, "one.md", "1\n");
        commit(&repo, "one", &who(), None, &[]).unwrap();
        let err = push(&repo, &Auth::default()).unwrap_err();
        assert!(matches!(err, Fail::Network(_)), "{err:?}");
    }

    /// The spike's timings (Matt, 2026-10-31): a 500-file, 20 MB library committed and pushed, a cold clone of it,
    /// a status, and a one-file commit and push, each timed. Not a test of anything: run by hand, in release.
    ///
    ///     cargo test --release --features test-hooks git::tests::timings -- --ignored --nocapture
    #[test]
    #[ignore]
    fn timings() {
        use std::time::Instant;
        let root = TempDir::new("git-timings");
        let url = bare(&root);
        let a = root.join("a");
        init(&a).unwrap();
        // Five hundred notes of forty kilobytes: prose-like lines, each file different, so deflate works as it would
        // on real notes (about 2:1) and no two blobs are one.
        let words = ["meeting", "notes", "the", "ghost", "wrote", "while", "Matt", "spoke", "about", "tables", "canvas", "voice", "and", "a", "plan", "for", "Tuesday", "with", "numbers", "like"];
        let mut total = 0usize;
        for n in 0..500 {
            let mut text = format!("# Note {n}\n\n");
            let mut seed = n as u64 * 2654435761 + 1;
            while text.len() < 40 * 1024 {
                for _ in 0..12 {
                    seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
                    text.push_str(words[(seed >> 33) as usize % words.len()]);
                    text.push(' ');
                }
                text.push_str(&format!("{}\n", seed % 10_000));
            }
            total += text.len();
            write(&a, &format!("Notes/{:03}/note-{n}.md", n % 20), &text);
        }
        let repo = open(&a).unwrap();
        let t = Instant::now();
        let first = commit(&repo, "the library", &who(), None, &[]).unwrap().unwrap();
        let commit_all = t.elapsed();
        set_remote(&repo, REMOTE, &url).unwrap();
        let repo = open(&a).unwrap();
        let t = Instant::now();
        push(&repo, &Auth::default()).unwrap();
        let push_all = t.elapsed();
        let t = Instant::now();
        assert_eq!(status(&repo).unwrap(), Vec::<Change>::new());
        let status_clean = t.elapsed();

        let b = root.join("b");
        let t = Instant::now();
        let (head, files) = clone(&url, &b, &Auth::default(), false).unwrap();
        let cold_clone = t.elapsed();
        assert_eq!((head, files), (Some(first), 500));
        let c = root.join("c");
        let t = Instant::now();
        clone(&url, &c, &Auth::default(), true).unwrap();
        let shallow_clone = t.elapsed();

        write(&a, "Notes/000/note-0.md", "# Note 0\n\nchanged\n");
        let t = Instant::now();
        let second = commit(&repo, "one line", &who(), None, &[]).unwrap().unwrap();
        let commit_one = t.elapsed();
        let t = Instant::now();
        push(&repo, &Auth::default()).unwrap();
        let push_one = t.elapsed();
        let repo_b = open(&b).unwrap();
        let t = Instant::now();
        fetch(&repo_b, &Auth::default(), false).unwrap();
        let fetch_one = t.elapsed();
        assert_eq!(divergence(&repo_b).unwrap().remote.as_deref(), Some(second.to_string().as_str()));
        let pack_bytes: u64 = walkdir(&root.join("remote.git").join("objects")).into_iter().map(|p| std::fs::metadata(p).map(|m| m.len()).unwrap_or(0)).sum();
        println!("timings: 500 files, {} bytes of notes; the remote's objects take {} bytes", total, pack_bytes);
        println!("timings: commit of all 500 files {commit_all:?}, their push {push_all:?}, a clean status {status_clean:?}");
        println!("timings: cold clone {cold_clone:?}, shallow clone {shallow_clone:?}");
        println!("timings: one-file commit {commit_one:?}, its push {push_one:?}, the other clone's fetch of it {fetch_one:?}");
    }

    fn walkdir(dir: &Path) -> Vec<PathBuf> {
        let mut out = Vec::new();
        if let Ok(read) = std::fs::read_dir(dir) {
            for entry in read.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    out.extend(walkdir(&path));
                } else {
                    out.push(path);
                }
            }
        }
        out
    }
}
