//! The boot wager, as decisions over `state.json`: which bundle a launch runs
//! and stakes, what a mount report settles, and what a quarantine or a revert
//! leaves behind. The module header's four numbered rules are these functions;
//! the commands in `ota.rs` only take the lock, read the state, call one of
//! them and write the state back.
//!
//! Everything here takes the bundle root as a path and the state as a value,
//! so the wager is tested against real directories with no Tauri running -
//! all but `embedded_manifest`, which asks the binary's own assets.

use std::path::{Path, PathBuf};

use tauri::{AppHandle, Runtime};

use super::manifest::{build_number, validate, Manifest, MANIFEST_FILE};
use super::disk::{bundle_manifest, record_installed, remove_bundle, Stored};
use super::{OtaState, NATIVE_GENERATION};
use crate::lock::lock;

/// Consecutive launches that ran a bundle and never mounted it before it is quarantined.
const STRIKES_TO_QUARANTINE: u32 = 2;

/// The frontend compiled into this binary, read from its assets once and kept.
/// `None` for a build with no `ota.json` among them (a dev build).
pub(super) fn embedded_manifest<R: Runtime>(app: &AppHandle<R>, state: &OtaState) -> Option<Manifest> {
    let mut cached = lock(&state.embedded);
    if let Some(known) = cached.as_ref() {
        return known.clone();
    }
    // The resolver answers a missing path with index.html, so a parse failure
    // here is how "this build has no ota.json" reads - e.g. a dev build.
    let found = app
        .asset_resolver()
        .get(MANIFEST_FILE.to_string())
        .and_then(|asset| serde_json::from_slice::<Manifest>(&asset.bytes).ok())
        .filter(|m| validate(m).is_ok());
    *cached = Some(found.clone());
    found
}

/// What this launch runs, decided against the bundles under `root`, and staked:
/// the chosen bundle's manifest and directory, with its build left in
/// `stored.pending`, or `None` for the embedded frontend.
///
/// Rules 1 to 3 of the module header, in order. A stake the last launch left
/// standing is a strike, and the second quarantines that build if it is still
/// the active one. Then an active bundle this binary should not run is dropped
/// and the one before it tried, until one will do. `installed.json` is moved up
/// to the embedded build on the way, so the background alert never offers what
/// the APK already has.
pub(super) fn claim(root: &Path, stored: &mut Stored, embedded: Option<&Manifest>) -> Option<(Manifest, PathBuf)> {
    // 1. The last launch staked a bundle and nothing ever said it mounted.
    if let Some(failed) = stored.pending.take() {
        stored.strikes += 1;
        if stored.strikes >= STRIKES_TO_QUARANTINE && stored.active.as_deref() == Some(failed.as_str()) {
            quarantine(root, stored, &failed);
        }
    }

    // 2. Drop an active bundle this binary should not run: incomplete on disk,
    //    needing a newer native layer, or no newer than the frontend compiled
    //    in. The last case is a new APK installed over an old OTA bundle - the
    //    APK's own frontend is the fresher one, and a stale download must not
    //    hide it (AttackFM's `reclaimEmbeddedIfNewer`).
    let embedded_build = embedded.and_then(|m| build_number(&m.build)).unwrap_or(0);
    let mut chosen = None;
    while let Some(active) = stored.active.clone() {
        let dir = root.join(&active);
        match bundle_manifest(&dir) {
            Some(m) if m.native <= NATIVE_GENERATION && build_number(&m.build).unwrap_or(0) > embedded_build => {
                chosen = Some((m, dir));
                break;
            }
            _ => {
                remove_bundle(root, &active);
                stored.active = stored.previous.take();
                stored.strikes = 0;
            }
        }
    }

    if let Some(embedded) = embedded {
        record_installed(root, &embedded.build);
    }

    // 3. Stake it.
    if let Some((manifest, _)) = &chosen {
        stored.pending = Some(manifest.build.clone());
    }
    chosen
}

/// The frontend that mounted reports in - `ran` is its build, `None` the
/// embedded frontend - and answers whether that changed the state.
///
/// Rule 2: a matching build clears the stake and its strikes. The embedded
/// frontend mounting clears the stake WITHOUT a strike: the loader fell back
/// before the bundle was tried, which is no evidence against it. A report
/// about any other build leaves the stake standing. (Making these arms
/// symmetric is AttackFM's bug; see the module header.)
pub(super) fn settle(stored: &mut Stored, ran: Option<&str>) -> bool {
    match (ran, stored.pending.as_deref()) {
        (Some(ran), Some(pending)) if ran == pending => {
            stored.pending = None;
            stored.strikes = 0;
        }
        // The embedded frontend mounted: the staked bundle was never tried,
        // which is neither a pass nor a strike.
        (None, Some(_)) => stored.pending = None,
        _ => return false,
    }
    true
}

/// Rule 4, and the end of rule 3: `build` never runs again. It is remembered as
/// quarantined, stepped back from if it was active (to the previous bundle, or
/// the embedded frontend), forgotten as previous or pending, and removed.
pub(super) fn quarantine(root: &Path, stored: &mut Stored, build: &str) {
    if !stored.quarantined.iter().any(|q| q == build) {
        stored.quarantined.push(build.to_string());
    }
    if stored.active.as_deref() == Some(build) {
        stored.active = stored.previous.take().filter(|p| p != build);
    }
    if stored.previous.as_deref() == Some(build) {
        stored.previous = None;
    }
    if stored.pending.as_deref() == Some(build) {
        stored.pending = None;
    }
    stored.strikes = 0;
    remove_bundle(root, build);
}

/// Every downloaded bundle forgotten and removed, so the next load runs the
/// embedded frontend. What is quarantined stays quarantined.
pub(super) fn revert(root: &Path, stored: &mut Stored) {
    for build in [stored.active.take(), stored.previous.take(), stored.pending.take()].into_iter().flatten() {
        remove_bundle(root, &build);
    }
    stored.strikes = 0;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ota::disk::read_installed;
    use crate::ota::test_support::{bundle, manifest, temp};

    const OLDER: &str = "20260911000000";
    const NEWER: &str = "20260912221530";

    /// A root holding two complete bundles, `NEWER` active over `OLDER`.
    fn two_bundles() -> (PathBuf, Stored) {
        let root = temp("boot");
        bundle(&root, &manifest(OLDER));
        bundle(&root, &manifest(NEWER));
        (root, Stored { active: Some(NEWER.into()), previous: Some(OLDER.into()), ..Stored::default() })
    }

    fn chosen(found: Option<(Manifest, PathBuf)>) -> Option<String> {
        found.map(|(manifest, _)| manifest.build)
    }

    #[test]
    fn quarantine_steps_back_to_the_previous_bundle() {
        let dir = temp("quarantine");
        let mut stored = Stored {
            active: Some("20260912221530".into()),
            previous: Some("20260911000000".into()),
            pending: Some("20260912221530".into()),
            strikes: 1,
            quarantined: vec![],
        };
        quarantine(&dir, &mut stored, "20260912221530");
        assert_eq!(stored.active.as_deref(), Some("20260911000000"));
        assert_eq!(stored.previous, None);
        assert_eq!(stored.pending, None);
        assert_eq!(stored.strikes, 0);
        assert_eq!(stored.quarantined, vec!["20260912221530".to_string()]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_claim_runs_the_active_bundle_and_stakes_it() {
        let (root, mut stored) = two_bundles();
        let (found, dir) = claim(&root, &mut stored, None).unwrap();
        assert_eq!((found.build.as_str(), dir), (NEWER, root.join(NEWER)));
        assert_eq!(stored.pending.as_deref(), Some(NEWER), "staked until the page says it mounted");
        assert_eq!(stored.strikes, 0);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_stake_left_standing_twice_quarantines_the_bundle_and_falls_back() {
        let (root, mut stored) = two_bundles();
        assert_eq!(chosen(claim(&root, &mut stored, None)).as_deref(), Some(NEWER));
        // The phone killing the app in its first second is ordinary: one strike is not enough.
        assert_eq!(chosen(claim(&root, &mut stored, None)).as_deref(), Some(NEWER));
        assert_eq!(stored.strikes, 1);
        // The second launch that never mounted it is.
        assert_eq!(chosen(claim(&root, &mut stored, None)).as_deref(), Some(OLDER));
        assert_eq!(stored.quarantined, [NEWER]);
        assert_eq!((stored.active.as_deref(), stored.previous.as_deref()), (Some(OLDER), None));
        assert_eq!(stored.pending.as_deref(), Some(OLDER), "the bundle fallen back to is staked in its turn");
        assert!(!root.join(NEWER).exists(), "a quarantined bundle is removed");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_launch_that_mounted_clears_its_stake_and_its_strikes() {
        let (root, mut stored) = two_bundles();
        claim(&root, &mut stored, None);
        claim(&root, &mut stored, None);
        assert_eq!(stored.strikes, 1);
        assert!(settle(&mut stored, Some(NEWER)));
        assert_eq!((stored.pending.as_deref(), stored.strikes), (None, 0));
        // So the next launch starts the count again rather than quarantining.
        claim(&root, &mut stored, None);
        assert_eq!(chosen(claim(&root, &mut stored, None)).as_deref(), Some(NEWER));
        assert!(stored.quarantined.is_empty());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn the_embedded_frontend_mounting_is_neither_a_pass_nor_a_strike() {
        let (root, mut stored) = two_bundles();
        claim(&root, &mut stored, None);
        claim(&root, &mut stored, None);
        assert!(settle(&mut stored, None), "the stake goes");
        assert_eq!((stored.pending, stored.strikes), (None, 1), "and the strike it had stays: no pass either");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_report_about_another_build_leaves_the_stake_standing() {
        let mut stored = Stored { pending: Some(NEWER.into()), strikes: 1, ..Stored::default() };
        assert!(!settle(&mut stored, Some(OLDER)));
        assert_eq!((stored.pending.as_deref(), stored.strikes), (Some(NEWER), 1));
        let mut nothing_staked = Stored::default();
        assert!(!settle(&mut nothing_staked, Some(NEWER)));
        assert!(!settle(&mut nothing_staked, None), "nothing to write when nothing was staked");
    }

    #[test]
    fn a_download_no_newer_than_the_apks_own_frontend_is_dropped() {
        let (root, mut stored) = two_bundles();
        let embedded = manifest("20260913000000");
        assert_eq!(chosen(claim(&root, &mut stored, Some(&embedded))), None, "the APK's own frontend is the fresher one");
        assert_eq!((stored.active.as_deref(), stored.pending.as_deref()), (None, None));
        assert!(!root.join(NEWER).exists() && !root.join(OLDER).exists());
        assert_eq!(read_installed(&root).as_deref(), Some("20260913000000"), "the alert check learns what is already here");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_bundle_needing_a_newer_binary_is_dropped_for_the_one_before_it() {
        let root = temp("native");
        bundle(&root, &manifest(OLDER));
        let mut needs_more = manifest(NEWER);
        needs_more.native = NATIVE_GENERATION + 1;
        bundle(&root, &needs_more);
        let mut stored = Stored { active: Some(NEWER.into()), previous: Some(OLDER.into()), ..Stored::default() };
        assert_eq!(chosen(claim(&root, &mut stored, None)).as_deref(), Some(OLDER));
        assert_eq!(stored.active.as_deref(), Some(OLDER));
        assert!(stored.quarantined.is_empty(), "dropped, not quarantined: a newer APK may run it");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn an_incomplete_bundle_is_dropped_for_the_one_before_it() {
        let (root, mut stored) = two_bundles();
        std::fs::remove_file(root.join(NEWER).join("assets/index.js")).unwrap();
        assert_eq!(chosen(claim(&root, &mut stored, None)).as_deref(), Some(OLDER));
        assert!(!root.join(NEWER).exists());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_revert_forgets_every_bundle_but_not_what_was_quarantined() {
        let (root, mut stored) = two_bundles();
        stored.pending = Some(NEWER.into());
        stored.strikes = 1;
        stored.quarantined = vec!["20260901000000".into()];
        revert(&root, &mut stored);
        assert_eq!((stored.active, stored.previous, stored.pending, stored.strikes), (None, None, None, 0));
        assert_eq!(stored.quarantined, ["20260901000000"]);
        assert!(!root.join(NEWER).exists() && !root.join(OLDER).exists());
        let _ = std::fs::remove_dir_all(&root);
    }
}
