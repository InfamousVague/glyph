import { describeBuild, sourceHost, STAGING, type ApkPhase, type Updates } from '../core/ota.ts';
import { isTauri } from '../core/tauri.ts';

/**
 * The sentences About says about this build: where its updates stand, on the page (`updatesStatus`) and in the list
 * of sections (`updatesSummary`), and what the build is (`buildLine`, under the version).
 *
 * Plain functions of the updates and of where the page runs, apart from the page (AboutPane.tsx, AboutUpdates.tsx)
 * so each rung of the ladder can be read and tested without drawing it. Where the page runs is a parameter with the
 * real answer as its default, so a test says which it is and the page never has to.
 *
 * The page's line and the list's are two ladders, not one said two ways: the list's is shorter and has no rung for
 * an app downloading, so while one downloads it says what it would have said without it.
 */

/** Where the page is running, as these lines need it. */
export interface BuildPlace {
  /** In the app, rather than in a browser. */
  native: boolean;
  /** This page arrived over the air rather than being built into the app (the boot script says so). */
  overTheAir: boolean;
  /** A staging build, whose updates are off. */
  staging: boolean;
}

/** The place this page is actually running. */
export function hereAndNow(): BuildPlace {
  return { native: isTauri(), overTheAir: Boolean(window.__glyphBoot?.build), staging: STAGING };
}

/** The Updates card's one row in the app: the first of these that is true. The web and the App Store have cards of their own. */
export function updatesStatus(updates: Updates): string {
  const { ready, apk, checking, lastError, lastChecked } = updates;
  if (checking) return 'Checking for updates.';
  if (apk.kind === 'downloading') return `Downloading Ghost.md ${apk.info.version}.`;
  if (apk.kind === 'available') return `Ghost.md ${apk.info.version} is ready to install.`;
  if (ready) return 'A new version is downloaded.';
  if (lastError) return `Couldn't check for updates: ${lastError}`;
  if (lastChecked) return 'Up to date.';
  return 'Not checked yet.';
}

/** An app the Updates card offers to install: one found, or one whose install stopped short. */
export type InstallableApk = Extract<ApkPhase, { kind: 'available' | 'failed' | 'needs-permission' }>;

/** Whether there is an app to offer to install (`InstallableApk`). */
export function installable(apk: ApkPhase): apk is InstallableApk {
  return apk.kind === 'available' || apk.kind === 'failed' || apk.kind === 'needs-permission';
}

/** About's reading in the list of sections, after the version: the same ladder, shorter. */
export function updatesSummary(updates: Updates, native = isTauri()): string {
  if (!native) return 'Web version';
  if (updates.checking) return 'Checking';
  if (updates.apk.kind === 'available') return `${updates.apk.info.version} ready to install`;
  if (updates.ready) return 'New version downloaded';
  if (updates.lastError) return "Couldn't check";
  return updates.lastChecked ? 'Up to date' : 'Not checked yet';
}

/**
 * The line under the version: how this page got here, when it was built, the app it runs in, and where its updates
 * come from - "Updated over the air · (when) · app 1.8.0 · updates from attack.fm", the when as `describeBuild` says
 * it. In a browser, only when it was built.
 */
export function buildLine(updates: Updates, place: BuildPlace = hereAndNow()): string {
  if (!place.native) return describeBuild(updates.build);
  const { status } = updates;
  const host = sourceHost(status?.sources?.[0]);
  return [
    place.overTheAir ? 'Updated over the air' : 'Built into the app',
    describeBuild(updates.build),
    status ? `app ${status.nativeVersion}` : null,
    place.staging ? 'staging build, updates off' : host ? `updates from ${host}` : null,
  ]
    .filter(Boolean)
    .join(' · ');
}
