import { BookOpen, BookOpenText, Compass, FileText, GraduationCap, LayoutGrid, ListChecks, ShieldCheck, Workflow } from '@glacier/icons';
import { useToast } from '@glacier/react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { openLink } from '../core/linkPreview.ts';
import { storeOf, type Updates } from '../core/ota.ts';
import { isAndroid } from '../core/platform.ts';
import { isTauri } from '../core/tauri.ts';
import { GUIDE_CHAPTERS, GUIDE_TITLE } from '../guidebook/guidebook.ts';
import { ReleasesSection, UpdatesSection } from './AboutUpdates.tsx';
import { countKnock, KNOCKS_WANTED, setDeveloperMode } from './developerMode.ts';
import { PaneHero, PaneSection, SettingRow, SettingsFootnote } from './kit/settingsKit.tsx';
import { buildLine } from './updateLines.ts';

/**
 * About, updates and what's new, as one page (Matt: "combine about whats new and updates settings pages"): the
 * version, big, then where this build stands and how to move it on, then help, then every release published, then
 * the privacy policy.
 *
 * The version is also the door to the developer tools - seven presses on it, the way Android's own are unlocked, with
 * a countdown from the third press so somebody who knows the gesture knows it is working.
 */

/** The privacy policy (landing/privacy.html), on the download site. */
const PRIVACY_URL = 'https://ghostmarkdown.com/privacy.html';

interface AboutPaneProps {
  updates: Updates;
  onGuide: () => void;
  onSample: () => void;
  /** Adds Ghost.md: The Guide, the book (guidebook/guidebook.ts), and opens its index. */
  onGuideBook: () => void;
  onBoard: () => void;
  onCanvas: () => void;
  onHowCanvas: () => void;
  onAcademy: () => void;
  onCheatSheet: () => void;
  /** The seventh press: developer mode is on, and the page to go to is Developer. */
  onDeveloper: () => void;
}

export function AboutPane({ updates, onGuide, onSample, onGuideBook, onBoard, onCanvas, onHowCanvas, onAcademy, onCheatSheet, onDeveloper }: AboutPaneProps) {
  const { toast } = useToast();
  const knock = () => {
    const left = countKnock();
    if (left === 0) {
      setDeveloperMode(true);
      fireNativeHaptic('success');
      toast({ message: 'Developer settings are on.', duration: 1800 });
      onDeveloper();
      return;
    }
    if (left <= KNOCKS_WANTED - 3) {
      toast({ message: `${left} more ${left === 1 ? 'tap' : 'taps'} for developer settings.`, duration: 1000 });
    }
  };
  return (
    <>
      <PaneSection>
        <PaneHero title={updates.version} meta={buildLine(updates)} onPress={knock} />
      </PaneSection>
      <UpdatesSection updates={updates} />
      <PaneSection title="Help">
        <SettingRow
          icon={<GraduationCap size={20} />}
          label="Ghost.md Academy"
          hint="Markdown taught a mark at a time: it shows you one, you type your own, and you watch it format underneath."
          onPress={() => onAcademy()}
        />
        <SettingRow
          icon={<BookOpen size={20} />}
          label="How to talk to Ghost.md"
          hint={isAndroid ? 'The side key, and the cues that make markdown.' : 'The cues that make markdown.'}
          onPress={() => onGuide()}
        />
        <SettingRow
          icon={<ListChecks size={20} />}
          label="Formatting cheat sheet"
          hint="Every mark you can type, with what it looks like, in one page to look things up in."
          onPress={() => onCheatSheet()}
        />
        <SettingRow
          icon={<BookOpenText size={20} />}
          label={`Add ${GUIDE_TITLE}`}
          hint={`The whole app as a book of ${GUIDE_CHAPTERS} short chapters: how to use it, then how it is made. Pressed again, it opens the book you have.`}
          onPress={onGuideBook}
        />
        <SettingRow
          icon={<LayoutGrid size={20} />}
          label="Add the example board"
          hint="A working board written in markdown: columns, cards, and the items they point at."
          onPress={onBoard}
        />
        <SettingRow
          icon={<Workflow size={20} />}
          label="Add the example canvas"
          hint="Cards on a page with lines between them, in the same file Obsidian's canvas uses."
          onPress={onCanvas}
        />
        <SettingRow
          icon={<Compass size={20} />}
          label="Add the “How Ghost.md works” canvas"
          hint="Eight plain cards, in order: say it, it lands as a note, and where a note can go."
          onPress={onHowCanvas}
        />
        <SettingRow
          icon={<FileText size={20} />}
          label="Add the sample note"
          hint="One note with every mark in it: headings, lists, a table, a picture, a secret in smoke."
          onPress={onSample}
        />
      </PaneSection>
      {/* The releases are attack.fm's over-the-air builds, which an iPhone never runs: the App Store says what's new there. */}
      {storeOf(updates.status) === 'appstore' ? null : <ReleasesSection updates={updates} />}
      {/*
        The privacy policy, reachable from inside the app as the App Store asks (guideline 5.1.1), and what it comes to
        in two lines. The page is landing/privacy.html; the footnote is its short version, so the two say the same.
      */}
      <PaneSection title="Privacy">
        <SettingRow icon={<ShieldCheck size={20} />} label="Privacy policy" hint="What stays on this device, and what an account, a shared link or a plugin sends." onPress={() => void openLink(PRIVACY_URL)} />
      </PaneSection>
      <SettingsFootnote>
        {isTauri()
          ? 'Your notes, recordings and pictures stay on this device, and your voice is turned into text here.'
          : "Your notes stay in this browser. Speech is turned into text by the browser's own recognition, which in Chrome sends it to Google."}{' '}
        Signed in to an account, they're synced encrypted on the device first, so only your own devices can read them. No ads, no analytics, no tracking.
      </SettingsFootnote>
    </>
  );
}
