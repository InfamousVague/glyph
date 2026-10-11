import { useEffect, useState } from 'react';
import { Switch } from '@glacier/react';
import { fetchReleases, keptReleases, releaseWhen, type Release } from '../core/changelog.ts';
import { storeOf, type Updates } from '../core/ota.ts';
import { isTauri } from '../core/tauri.ts';
import { PaneSection, RowAction, SettingRow } from './kit/settingsKit.tsx';
import { installable, updatesStatus } from './updateLines.ts';
import { useUpdateAlerts } from './useUpdateAlerts.ts';

/**
 * The two parts of About that are about this build and the ones after it: where its updates stand (`UpdatesSection`)
 * and every release published (`ReleasesSection`). Each was a page of its own until About took them in (Matt:
 * "combine about whats new and updates settings pages"); the page that holds them is AboutPane.tsx, and the words
 * about where the build stands are updateLines.ts.
 */

/** Updates, as a part of the About page: where this build stands, the buttons that move it on, and the alerts switch. */
export function UpdatesSection({ updates }: { updates: Updates }) {
  const { ready, apk, checking } = updates;
  const alerts = useUpdateAlerts();

  if (!isTauri()) {
    return (
      <PaneSection title="Updates">
        <SettingRow label="You're on the web version" hint="Reload the page to update." />
      </PaneSection>
    );
  }

  // From the App Store: it updates the app, and there is nothing to check here.
  const store = storeOf(updates.status);
  if (store === 'appstore') {
    return (
      <PaneSection title="Updates">
        <SettingRow label="Ghost.md updates through the App Store." />
      </PaneSection>
    );
  }

  return (
    <>
      <PaneSection title="Updates" footer={store === 'play' ? 'New versions of the app itself come through the Play Store.' : undefined}>
        <SettingRow label={updatesStatus(updates)} />
      </PaneSection>
      <div className="settingsScreen__actions">
        {ready ? <RowAction onPress={updates.reload}>Reload</RowAction> : null}
        {installable(apk) ? <RowAction onPress={updates.installApk}>Install {apk.info.version}</RowAction> : null}
        <RowAction onPress={updates.check} disabled={checking}>
          Check for updates
        </RowAction>
      </div>
      {alerts.available ? (
        <PaneSection title="Alerts">
          <SettingRow
            label="Update alerts"
            hint={
              alerts.state === 'blocked'
                ? "It's on, but Android is blocking Ghost.md's notifications. Allow them in the app's system settings."
                : 'Get a notification when a new version is out, even when Ghost.md is closed.'
            }
            control={<Switch aria-label="Update alerts" checked={alerts.state !== 'off'} onCheckedChange={alerts.set} />}
          />
        </PaneSection>
      ) : null}
    </>
  );
}

/**
 * What's new, as the foot of the About page: every release published, newest first, with the one running marked
 * (core/changelog.ts). Read from the site each time the page opens, and from what was kept when there is no signal
 * (Matt: "show a changelog with all updates including OTA").
 */
export function ReleasesSection({ updates }: { updates: Updates }) {
  const [releases, setReleases] = useState<Release[]>(keptReleases);
  const [reading, setReading] = useState(true);
  const running = window.__glyphBoot?.build ?? updates.build;
  // A store's copy: the list is of builds from attack.fm, where an "app number" is an APK the store build never installs.
  const store = storeOf(updates.status);

  useEffect(() => {
    const stop = new AbortController();
    void fetchReleases(updates.status?.sources, stop.signal).then((found) => {
      setReleases(found);
      setReading(false);
    });
    return () => stop.abort();
  }, [updates.status?.sources]);

  if (!releases.length) {
    return (
      <PaneSection title="What's new">
        <SettingRow
          label={reading ? 'Reading the updates…' : 'No updates to show yet.'}
          hint={reading ? undefined : 'They are read from where Ghost.md takes its updates.'}
        />
      </PaneSection>
    );
  }

  // One group, a row a release: on the About page the list is the foot of it, not a page of cards of its own.
  return (
    <PaneSection title="What's new" description={store ? 'Every update, newest first.' : 'Every update, newest first. A version with an app number needs installing.'}>
      {releases.map((release) => (
        <SettingRow
          key={release.build}
          label={release.build === running ? `${release.version} · you're on this one` : release.version}
          value={releaseWhen(release)}
          hint={[release.notes, release.apk && !store ? `Installed as Ghost.md ${release.apk}.` : null].filter(Boolean).join(' ')}
        />
      ))}
    </PaneSection>
  );
}
