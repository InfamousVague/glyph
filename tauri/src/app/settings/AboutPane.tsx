import { BookOpen, BookOpenText, FileCode, GraduationCap, ListChecks, Shapes } from '@glacier/icons';
import { useToast } from '@glacier/react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { storeOf, type Updates } from '../core/ota.ts';
import { GUIDE_CHAPTERS, GUIDE_TITLE } from '../guidebook/guidebook.ts';
import { ReleasesSection, UpdatesSection } from './AboutUpdates.tsx';
import { countKnock, KNOCKS_WANTED, setDeveloperMode } from './developerMode.ts';
import { PaneHero, PaneSection, SettingRow } from './kit/settingsKit.tsx';
import type { SettingsTarget } from './SettingsScreen.tsx';
import { buildLine } from './updateLines.ts';

/**
 * About, updates and what's new, as one page (Matt: "combine about whats new and updates settings pages"): the
 * version, big, then where this build stands and how to move it on, then help, then every release published.
 *
 * Help is five rows since docs/DESIGN.md §138 (Matt: "also see if you can clean up / streamline settings a bit"),
 * where it was eight, five of them "Add …": the cheat sheet and the four examples are pages of their own behind two
 * of them (Settings' sub-pages, back to About), and "How to talk to Ghost.md", which promised voice cues and opened the
 * set-up walkthrough, is named for what it opens. The privacy policy and its two lines went to Account's Privacy
 * card, where sync and shared links already were. The specification joined them as a sixth (GLY-4, §164), a page
 * behind its row as the cheat sheet is.
 *
 * The version is also the door to the developer tools - seven presses on it, the way Android's own are unlocked, with
 * a countdown from the third press so somebody who knows the gesture knows it is working.
 *
 * What the search finds here is AboutPane.findable.ts, in this page's order.
 */

interface AboutPaneProps {
  updates: Updates;
  /** Opens the welcome walkthrough on its first page. */
  onGuide: () => void;
  /** Adds Ghost.md: The Guide, the book (guidebook/guidebook.ts), and opens its index. */
  onGuideBook: () => void;
  onAcademy: () => void;
  /** Lands on another page of Settings: the cheat sheet, the examples, and Developer at the seventh press. */
  onOpen: (target: SettingsTarget) => void;
}

export function AboutPane({ updates, onGuide, onGuideBook, onAcademy, onOpen }: AboutPaneProps) {
  const { toast } = useToast();
  const knock = () => {
    const left = countKnock();
    if (left === 0) {
      setDeveloperMode(true);
      fireNativeHaptic('success');
      toast({ message: 'Developer settings are on.', duration: 1800 });
      onOpen({ id: 'developer' });
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
          hint="Markdown taught a mark at a time. It shows you one, you type your own, and you watch it format."
          onPress={() => onAcademy()}
        />
        {/* What guide/pages.ts shows: four pages, the last of which offers the Academy. */}
        <SettingRow
          icon={<BookOpen size={20} />}
          label="The welcome walkthrough"
          hint="The pages from the first launch: the theme, the model, and where the rest is taught."
          onPress={() => onGuide()}
        />
        <SettingRow icon={<ListChecks size={20} />} label="Cheat sheet" hint="Every mark you can type, and what it looks like, on one page." onPress={() => onOpen({ id: 'cheatsheet' })} />
        <SettingRow
          icon={<FileCode size={20} />}
          label="Specification"
          hint="Exactly how every extension and AI fill is written, and the standard Markdown under them."
          onPress={() => onOpen({ id: 'spec' })}
        />
        <SettingRow
          icon={<BookOpenText size={20} />}
          label={GUIDE_TITLE}
          hint={`The whole app in ${GUIDE_CHAPTERS} short chapters. Added to your notes the first time, and opened after that.`}
          onPress={onGuideBook}
        />
        <SettingRow icon={<Shapes size={20} />} label="Examples" hint="A sample note, a board and two canvases, to add to your notes." onPress={() => onOpen({ id: 'examples' })} />
      </PaneSection>
      {/* The releases are attack.fm's over-the-air builds, which an iPhone never runs: the App Store says what's new there. */}
      {storeOf(updates.status) === 'appstore' ? null : <ReleasesSection updates={updates} />}
    </>
  );
}
