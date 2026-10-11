import { Compass, FileText, LayoutGrid, Workflow } from '@glacier/icons';
import { PaneSection, SettingRow } from './kit/settingsKit.tsx';

/**
 * Examples, a page behind About's Help (docs/DESIGN.md §138): the notes Ghost.md can add to show what a note can be.
 * They were four "Add …" rows in About's Help card, which was eight rows long; they are one row there now, and this
 * page. Each is made and opened by App.tsx (core/seed.ts, core/boardNote.ts, canvas/sampleCanvas.ts,
 * canvas/howCanvas.ts), and each says what is in it.
 *
 * What the search finds here is ExamplesPane.findable.ts.
 */

interface ExamplesPaneProps {
  /** Makes the sample note, the one with every mark in it, and opens it. */
  onSample: () => void;
  onBoard: () => void;
  onCanvas: () => void;
  onHowCanvas: () => void;
}

export function ExamplesPane({ onSample, onBoard, onCanvas, onHowCanvas }: ExamplesPaneProps) {
  return (
    <PaneSection>
      <SettingRow icon={<FileText size={20} />} label="Add the sample note" hint="Every mark in one note: headings, lists, a table, a picture, a secret in smoke." onPress={onSample} />
      <SettingRow icon={<LayoutGrid size={20} />} label="Add the example board" hint="Columns, cards and the items they point at, written in markdown." onPress={onBoard} />
      <SettingRow icon={<Workflow size={20} />} label="Add the example canvas" hint="Cards on a page with lines between them, in Obsidian's canvas file." onPress={onCanvas} />
      <SettingRow icon={<Compass size={20} />} label="Add the “How Ghost.md works” canvas" hint="Eight plain cards, in order: say it, it lands as a note, and where a note can go." onPress={onHowCanvas} />
    </PaneSection>
  );
}
