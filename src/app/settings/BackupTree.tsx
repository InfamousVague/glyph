import { useState } from 'react';
import { ChevronDown, ChevronRight, File, Folder, FolderOpen } from '@glacier/icons';
import { sizeSaid, type TreeFolder } from '../core/backup.ts';
import styles from './BackupTree.module.css';

/**
 * What a drive's Ghost.md folder holds, as a tree (Matt: "On the backup page, show a logical file tree of all the
 * files on the USB drive inside the ghost folder specifically"; docs/DESIGN.md §213): the folder itself open, its
 * folders - Inbox, Workspaces, Organizations, Attachments - closed until tapped, each saying how many files are under
 * it and their size, and a file its own size. A library is hundreds of files, so only what is opened is drawn.
 */

const filesSaid = (count: number) => (count === 1 ? 'one file' : `${count} files`);

function FolderRows({ folder, open: startsOpen }: { folder: TreeFolder; open: boolean }) {
  const [open, setOpen] = useState(startsOpen);
  return (
    <li>
      <button type="button" className={`${styles.row} ${styles.folder}`} aria-expanded={open} onClick={() => setOpen((was) => !was)}>
        {open ? <ChevronDown className={styles.mark} size={14} aria-hidden="true" /> : <ChevronRight className={styles.mark} size={14} aria-hidden="true" />}
        {open ? <FolderOpen className={styles.mark} size={16} aria-hidden="true" /> : <Folder className={styles.mark} size={16} aria-hidden="true" />}
        <span className={styles.name}>{folder.name}</span>
        <span className={styles.said}>
          {filesSaid(folder.files)} · {sizeSaid(folder.size)}
        </span>
      </button>
      {open ? (
        <ul className={styles.list}>
          {folder.folders.map((each) => (
            <FolderRows key={each.path} folder={each} open={false} />
          ))}
          {folder.leaves.map((leaf) => (
            <li key={leaf.path} className={styles.row}>
              <File className={styles.mark} size={14} aria-hidden="true" />
              <span className={styles.name} title={leaf.name}>
                {leaf.name}
              </span>
              <span className={styles.said}>{sizeSaid(leaf.size)}</span>
            </li>
          ))}
        </ul>
      ) : null}
    </li>
  );
}

export function BackupTree({ tree }: { tree: TreeFolder }) {
  return (
    <div className={styles.tree}>
      <ul className={styles.list} aria-label={`Files in ${tree.name}`}>
        <FolderRows folder={tree} open />
      </ul>
    </div>
  );
}
