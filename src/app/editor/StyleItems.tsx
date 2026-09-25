import { Bold, ChevronLeft, Code, Heading, Italic, Link, List, ListOrdered, ListTodo, Minus, Strikethrough, Table, TextQuote, Type } from '@glacier/icons';
import type { CSSProperties } from 'react';
import type { EditorView } from '@codemirror/view';
import { fireNativeHaptic } from '../core/haptics.ts';
import { useRedraw } from '../core/useRedraw.ts';
import { plugins } from '../plugins/registry.ts';
import { activeBlock, activeMarks, activeWraps, insertLink, insertRule, insertTable, toggleBlock, toggleMark, toggleWrap, type Block, type Mark } from './format.ts';
import { MenuItem, MenuWord, type MenuIcon } from './MenuBand.tsx';
import styles from './ContextMenu.module.css';

/**
 * The press-and-hold menu's Style page (editor/ContextMenu.tsx), not a bar of its own (Matt, of the bar of symbols
 * under the top bar: "redo the UI/UX for selecting text styles, it doesn't look good as is, maybe it needs to be
 * something we do by pressing and holding on text"). Style turns the menu over to the formatting, in the same hand:
 * the marks that wrap the selection (bold, italic, struck, code, and any a switched-on plugin adds, like Spoiler), the
 * forms a line takes (heading, quote, list, numbered, to-do), and the things put in (link, table, rule), all in one
 * band that scrolls sideways, a little space between the three kinds (three bands stacked "looks a bit strange",
 * Matt; a heavier rule between the kinds read as "two pixels thick").
 *
 * A pressed style stays on the page, lit while it applies, so a word can be made bold and struck in one go: what is
 * lit is read from the editor's state on every draw, and a press asks for the next one. An insert closes the menu,
 * since it puts something in and there is nothing to keep lit. The arrow goes back. The commands are editor/format.ts.
 */

const MARKS: { mark: Mark; icon: MenuIcon; label: string }[] = [
  { mark: 'bold', icon: Bold, label: 'Bold' },
  { mark: 'italic', icon: Italic, label: 'Italic' },
  { mark: 'strike', icon: Strikethrough, label: 'Struck' },
  { mark: 'code', icon: Code, label: 'Code' },
];

const INSERTS: { key: string; icon: MenuIcon; label: string; run: (view: EditorView) => void }[] = [
  { key: 'link', icon: Link, label: 'Link', run: insertLink },
  { key: 'table', icon: Table, label: 'Table', run: insertTable },
  { key: 'rule', icon: Minus, label: 'Rule', run: insertRule },
];

const BLOCKS: { block: Block; icon: MenuIcon; label: string }[] = [
  { block: 'heading', icon: Heading, label: 'Heading' },
  { block: 'quote', icon: TextQuote, label: 'Quote' },
  { block: 'bullet', icon: List, label: 'List' },
  { block: 'number', icon: ListOrdered, label: 'Numbered' },
  { block: 'task', icon: ListTodo, label: 'To-do' },
];

/** The Style page's words, for the menu's band: Back, then the marks, the plugins' formats, the line forms, the inserts. */
export function StyleItems({ view, onBack, onClose }: { view: EditorView; onBack: () => void; onClose: () => void }) {
  // A style pressed changes what is lit: the page reads the editor again.
  const restyled = useRedraw();
  const style = (run: (target: EditorView) => void) => () => {
    fireNativeHaptic('selection');
    run(view);
    restyled();
  };
  const put = (run: (target: EditorView) => void) => () => {
    fireNativeHaptic('selection');
    onClose();
    run(view);
    view.focus();
  };
  const state = view.state;
  // Each switched-on plugin's formattings, under that plugin's own icon.
  // A mark's own icon where it has one (plugins/types.ts `InlineFormat`), else the plugin's, else the letter.
  const formats = plugins
    .enabled()
    .flatMap((plugin) => (plugin.formats ?? []).map((format) => ({ format, icon: ((format.icon ?? plugin.icon) as MenuIcon | undefined) ?? Type })));
  return (
    <>
      <MenuItem icon={ChevronLeft} label="Back" onPress={onBack} name="Back to the note's actions" />
      {MARKS.map(({ mark, icon, label }, i) => (
        <StyleItem key={mark} icon={icon} label={label} i={i} lit={activeMarks(state).includes(mark)} onClick={style((target) => toggleMark(target, mark))} />
      ))}
      {formats.map(({ format, icon }, i) => (
        <StyleItem
          key={format.name}
          icon={icon}
          label={format.name}
          i={MARKS.length + i}
          lit={activeWraps(state, [format.delimiter]).length > 0}
          onClick={style((target) => toggleWrap(target, format.delimiter))}
        />
      ))}
      {BLOCKS.map(({ block, icon, label }, i) => (
        <StyleItem
          key={block}
          icon={icon}
          label={label}
          i={MARKS.length + formats.length + i}
          group={i === 0}
          lit={activeBlock(state) === block}
          onClick={style((target) => toggleBlock(target, block))}
        />
      ))}
      {INSERTS.map(({ key, icon, label, run }, i) => (
        <StyleItem key={key} icon={icon} label={label} i={MARKS.length + formats.length + BLOCKS.length + i} group={i === 0} onClick={put(run)} />
      ))}
    </>
  );
}

/** A style: its icon over its word, lit (printed in reverse) while it applies, coming in out of smoke after the ones before it. */
function StyleItem({
  icon,
  label,
  i,
  lit = false,
  group = false,
  onClick,
}: {
  icon: MenuIcon;
  label: string;
  i: number;
  lit?: boolean;
  group?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      role="menuitemcheckbox"
      aria-checked={lit}
      className={`${styles.item} ${styles.style}`}
      data-lit={lit || undefined}
      data-group={group || undefined}
      style={{ '--i': i } as CSSProperties}
      onClick={onClick}
    >
      <MenuWord icon={icon} label={label} />
    </button>
  );
}
