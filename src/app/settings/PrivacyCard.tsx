import { ShieldCheck } from '@glacier/icons';
import { Switch } from '@glacier/react';
import { openLink } from '../core/linkPreview.ts';
import { setPreferences, usePreferences } from '../core/preferences.ts';
import { isTauri } from '../core/tauri.ts';
import { PaneSection, SettingRow } from './kit/settingsKit.tsx';

/**
 * Privacy, a card on Account (docs/DESIGN.md §138): the switches that decide what leaves the device, and the policy
 * with what it comes to in two lines. Account is where sync and shared links already were, the other things that
 * send, so the card is there; signed out it is the first thing on the page, above the ways in.
 *
 * Each was somewhere else before. Local only, the whole network switch, was on Formatting with two pages pointing at
 * it "in Formatting"; Link previews was on Type, though it reads a title from another site; the policy and its two
 * lines were About's foot, reachable from inside the app as the App Store asks (guideline 5.1.1). The page is
 * landing/privacy.html and the footer its short version, so the two say the same.
 *
 * Local only stays on the device (core/sync/prefs.ts), and its hint is one sentence whatever the state, since the
 * switch says the state.
 */

/** The privacy policy (landing/privacy.html), on the download site. */
const PRIVACY_URL = 'https://ghostmarkdown.com/privacy.html';

export function PrivacyCard() {
  const prefs = usePreferences();
  const app = isTauri();
  return (
    <PaneSection
      title="Privacy"
      footer={`${
        app
          ? 'Your notes, recordings and pictures stay on this device, and your voice is turned into text here.'
          : "Your notes stay in this browser. Speech is turned into text by the browser's own recognition, which in Chrome sends it to Google."
      } Signed in, they sync encrypted on the device first, so only your own devices can read them. No ads, no analytics, no tracking.`}
    >
      <SettingRow
        label="Local only"
        hint={
          // What it holds off, by what core/ reads it (sync/engine.ts, ota.ts, ai.ts, linkPreview.ts, location.ts, plugins/registry.ts).
          app
            ? 'No sync, updates, downloads, link previews, maps or place names, and no location for new notes. Plugins that use the internet are held off. Ghost.md runs from what is on this device.'
            : 'No sync, maps or place names, and no location for new notes. Plugins that use the internet are held off.'
        }
        control={<Switch aria-label="Local only" checked={prefs.localOnly} onCheckedChange={(localOnly) => setPreferences({ localOnly })} />}
      />
      <SettingRow
        label="Link previews"
        hint="A card under a line that is only a link. In the app, the page's title is read from that site."
        control={<Switch aria-label="Link previews" checked={prefs.linkPreviews} onCheckedChange={(linkPreviews) => setPreferences({ linkPreviews })} />}
      />
      <SettingRow icon={<ShieldCheck size={20} />} label="Privacy policy" hint="What stays on this device, and what an account, a shared link or a plugin sends." onPress={() => void openLink(PRIVACY_URL)} />
    </PaneSection>
  );
}
