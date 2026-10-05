//! The backup's doors (backup.rs; docs/DESIGN.md §204). Native generation 26.
//!
//! - `backup_drives`: the Mac's removable drives under `/Volumes`, each with its room and the last backup it holds. A
//!   drive is one `diskutil` calls neither internal nor a disk image, and that can be written; it is asked once per
//!   drive while it stays mounted. The page asks every two seconds while Backup is open, so a drive plugged in shows
//!   up by itself. Android's drives are the activity's (files/BackupDrives.kt), not Rust's: nothing here on a phone.
//! - `backup_last`: the last backup a drive holds, by its path on the Mac or its tree on Android.
//! - `backup_run`: the backup, onto a Mac drive's path or an Android drive's granted tree, with `backup://progress`
//!   a few times a second. One at a time.
//! - `backup_cancel` stops it between files; `backup_eject` puts a Mac drive away once it is done.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};

use crate::backup::{self, Backed, Last, Media, Progress, Target};

#[derive(Default)]
pub struct BackupState {
    running: AtomicBool,
    cancel: AtomicBool,
}

pub fn install(app: &tauri::App) {
    app.manage(BackupState::default());
}

/// A drive a backup can go to.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Drive {
    /// Its path on the Mac, `/Volumes/<name>`.
    pub id: String,
    pub name: String,
    pub free: Option<u64>,
    pub total: Option<u64>,
    pub last: Option<Last>,
}

/// Where the page asks a backup to go: a Mac drive's path or an Android drive's tree, and what it writes there.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRequest {
    #[serde(default)]
    pub drive: Option<String>,
    #[serde(default)]
    pub tree: Option<String>,
    pub backed_up_at: String,
    pub readme: String,
}

/// The drive a request names, as a `Target`, with its room where it is known.
fn target_of(drive: Option<&str>, tree: Option<&str>) -> Result<(Box<dyn Target>, Option<u64>), String> {
    if let Some(path) = drive {
        let root = mac_drive(path)?;
        let free = free_bytes(&root);
        return Ok((Box::new(backup::FolderTarget { root }), free));
    }
    if let Some(tree) = tree {
        return android_tree(tree);
    }
    Err("Choose a drive to back up to.".into())
}

#[cfg(target_os = "android")]
fn android_tree(tree: &str) -> Result<(Box<dyn Target>, Option<u64>), String> {
    let target = crate::saf::TreeTarget::new(tree)?;
    Ok((Box::new(target), None))
}

#[cfg(not(target_os = "android"))]
fn android_tree(_tree: &str) -> Result<(Box<dyn Target>, Option<u64>), String> {
    Err("Only the Android app backs up through a drive's tree.".into())
}

/// A path the page names as a drive: one of `/Volumes`'s, and one `backup_drives` would list.
fn mac_drive(path: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(path);
    let inside = path.parent() == Some(Path::new("/Volumes")) && path.file_name().is_some();
    if !inside || !is_removable(&path) {
        return Err("That drive isn’t plugged in any more.".into());
    }
    Ok(path)
}

/// Claims the one backup that may run; the guard lets it go however it ends.
struct Running<'a>(&'a BackupState);

impl<'a> Running<'a> {
    fn claim(state: &'a BackupState) -> Result<Self, String> {
        if state.running.swap(true, Ordering::SeqCst) {
            return Err("A backup is already under way.".into());
        }
        state.cancel.store(false, Ordering::SeqCst);
        Ok(Self(state))
    }
}

impl Drop for Running<'_> {
    fn drop(&mut self) {
        self.0.running.store(false, Ordering::SeqCst);
    }
}

/// The failure as the page says it: a sentence of the backup's own, or the system's words for what went wrong.
fn said(error: std::io::Error) -> String {
    match error.kind() {
        std::io::ErrorKind::StorageFull | std::io::ErrorKind::Interrupted => error.to_string(),
        std::io::ErrorKind::PermissionDenied => "Ghost.md can’t write to that drive. It may be locked or read-only.".into(),
        _ => format!("The backup could not be written: {error}"),
    }
}

/// Every removable drive the Mac has mounted, with its room and the last backup it holds.
#[tauri::command(async)]
pub fn backup_drives() -> Vec<Drive> {
    let Ok(entries) = std::fs::read_dir("/Volumes") else { return Vec::new() };
    let mut drives: Vec<Drive> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| is_removable(path))
        .map(|path| {
            let target = backup::FolderTarget { root: path.clone() };
            Drive {
                id: path.to_string_lossy().into_owned(),
                name: path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
                free: free_bytes(&path),
                total: total_bytes(&path),
                last: backup::last(&target),
            }
        })
        .collect();
    drives.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    drives
}

/// The last backup a drive holds: by its path on the Mac, or its tree on Android.
#[tauri::command(async)]
pub fn backup_last(drive: Option<String>, tree: Option<String>) -> Result<Option<Last>, String> {
    let (target, _) = target_of(drive.as_deref(), tree.as_deref())?;
    Ok(backup::last(target.as_ref()))
}

/// The backup: every note and versions file in the library, and the pictures, films and recordings, onto the drive.
#[tauri::command(async)]
pub fn backup_run(app: AppHandle, state: State<'_, BackupState>, request: BackupRequest) -> Result<Backed, String> {
    let _running = Running::claim(&state)?;
    let (target, free) = target_of(request.drive.as_deref(), request.tree.as_deref())?;
    let texts = {
        let store = app.state::<crate::commands::NotesStore>();
        let library = store.lock();
        library.texts().map_err(|e| format!("The notes could not be read: {e}"))?
    };
    let data = crate::paths::data_dir(&app)?;
    let media = [
        Media { dir: data.join(crate::paths::IMAGES), name: "Pictures" },
        Media { dir: data.join(crate::paths::VIDEO), name: "Films" },
        Media { dir: data.join(crate::paths::RECORDINGS), name: "Recordings" },
    ];
    let items = backup::plan(texts, &media).map_err(|e| format!("The notes could not be listed: {e}"))?;
    let emitter = app.clone();
    backup::run(target.as_ref(), &items, &request.readme, &request.backed_up_at, free, &state.cancel, move |progress: Progress| {
        let _ = emitter.emit("backup://progress", progress);
    })
    .map_err(said)
}

/// Stops the backup under way, between files; it answers "The backup was stopped."
#[tauri::command]
pub fn backup_cancel(state: State<'_, BackupState>) {
    state.cancel.store(true, Ordering::SeqCst);
}

/// A Mac drive put away, so it can be pulled out: `diskutil eject`. Refused while a backup runs.
#[tauri::command(async)]
pub fn backup_eject(state: State<'_, BackupState>, drive: String) -> Result<(), String> {
    if state.running.load(Ordering::SeqCst) {
        return Err("Wait for the backup to finish.".into());
    }
    let path = mac_drive(&drive)?;
    let out = std::process::Command::new("/usr/sbin/diskutil").arg("eject").arg(&path).output().map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        Err("The drive could not be ejected. Close anything that has it open, then try again.".into())
    }
}

// ---- the Mac's drives --------------------------------------------------------------------------

/// What `diskutil` said of each mounted volume, by its path and device, so it is asked once while it stays mounted.
#[cfg(target_os = "macos")]
static SEEN: std::sync::Mutex<Option<std::collections::HashMap<PathBuf, (u64, bool)>>> = std::sync::Mutex::new(None);

/// Whether `path` is a removable drive mounted under `/Volumes`: a mount of its own (not the boot volume's link to
/// `/`), which `diskutil` calls neither internal nor a disk image, and writable. A USB stick, an SD card, an external
/// disk; never a mounted .dmg, the Recovery volume or a network share.
#[cfg(target_os = "macos")]
fn is_removable(path: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    let Ok(link) = std::fs::symlink_metadata(path) else { return false };
    if link.file_type().is_symlink() || !link.is_dir() {
        return false;
    }
    let Ok(volumes) = std::fs::metadata("/Volumes") else { return false };
    if link.dev() == volumes.dev() {
        // Not a mount: a folder left in /Volumes.
        return false;
    }
    let device = link.dev();
    let mut seen = SEEN.lock().unwrap_or_else(|e| e.into_inner());
    let known = seen.get_or_insert_with(Default::default);
    if let Some((was, removable)) = known.get(path) {
        if *was == device {
            return *removable;
        }
    }
    let removable = diskutil_says_removable(path);
    known.insert(path.to_path_buf(), (device, removable));
    removable
}

#[cfg(target_os = "macos")]
fn diskutil_says_removable(path: &Path) -> bool {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let Ok(info) = Command::new("/usr/sbin/diskutil").arg("info").arg("-plist").arg(path).output() else { return false };
    if !info.status.success() {
        return false;
    }
    // The plist read as JSON by the Mac's own plutil: no plist crate for five keys.
    let Ok(mut child) = Command::new("/usr/bin/plutil").args(["-convert", "json", "-o", "-", "-"]).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn() else { return false };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(&info.stdout);
    }
    let Ok(out) = child.wait_with_output() else { return false };
    let Ok(said) = serde_json::from_slice::<serde_json::Value>(&out.stdout) else { return false };
    removable_by(&said)
}

/// What `diskutil info -plist` says, read as a removable drive a backup can write: not a disk image, not internal or
/// else removable media (a Mac's own SD card slot), and writable.
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
fn removable_by(said: &serde_json::Value) -> bool {
    let yes = |key: &str| said.get(key).and_then(serde_json::Value::as_bool).unwrap_or(false);
    let bus = said.get("BusProtocol").and_then(serde_json::Value::as_str).unwrap_or("");
    if bus == "Disk Image" {
        return false;
    }
    let outside = !said.get("Internal").and_then(serde_json::Value::as_bool).unwrap_or(true) || yes("RemovableMedia") || yes("Removable") || yes("Ejectable");
    outside && yes("WritableVolume")
}

#[cfg(not(target_os = "macos"))]
fn is_removable(_path: &Path) -> bool {
    false
}

#[cfg(unix)]
fn statvfs(path: &Path) -> Option<libc::statvfs> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let c_path = CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    // SAFETY: `c_path` is a valid NUL-terminated string and `stat` is a properly sized, writable statvfs to fill.
    let rc = unsafe { libc::statvfs(c_path.as_ptr(), &mut stat) };
    (rc == 0).then_some(stat)
}

/// The room left on the drive, for the person and for the backup's check before it writes.
#[cfg(unix)]
#[allow(clippy::unnecessary_cast)]
fn free_bytes(path: &Path) -> Option<u64> {
    statvfs(path).map(|stat| stat.f_bavail as u64 * stat.f_frsize as u64)
}

#[cfg(unix)]
#[allow(clippy::unnecessary_cast)]
fn total_bytes(path: &Path) -> Option<u64> {
    statvfs(path).map(|stat| stat.f_blocks as u64 * stat.f_frsize as u64)
}

#[cfg(not(unix))]
fn free_bytes(_path: &Path) -> Option<u64> {
    None
}

#[cfg(not(unix))]
fn total_bytes(_path: &Path) -> Option<u64> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_usb_drive_or_an_sd_card_is_removable_and_a_disk_image_or_the_mac_itself_is_not() {
        let usb = json!({ "Internal": false, "Removable": true, "RemovableMedia": true, "Ejectable": true, "BusProtocol": "USB", "WritableVolume": true });
        let card = json!({ "Internal": true, "RemovableMedia": true, "BusProtocol": "Secure Digital", "WritableVolume": true });
        let dmg = json!({ "Internal": false, "Removable": true, "Ejectable": true, "BusProtocol": "Disk Image", "WritableVolume": true });
        let boot = json!({ "Internal": true, "Removable": false, "RemovableMedia": false, "Ejectable": false, "BusProtocol": "Apple Fabric", "WritableVolume": true });
        let locked = json!({ "Internal": false, "Ejectable": true, "BusProtocol": "USB", "WritableVolume": false });
        assert!(removable_by(&usb));
        assert!(removable_by(&card));
        assert!(!removable_by(&dmg));
        assert!(!removable_by(&boot));
        assert!(!removable_by(&locked));
    }

    #[test]
    fn names_only_a_drive_under_volumes() {
        assert!(mac_drive("/Users/matt").is_err());
        assert!(mac_drive("/Volumes").is_err());
        assert!(mac_drive("/Volumes/Nothing plugged in here").is_err());
    }
}
