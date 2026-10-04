import { browseFiles, canBrowseFiles } from '../libraryFiles.ts';
import { isMacApp } from '../platform.ts';
import { isTauri } from '../tauri.ts';
import { readVersionsFile } from './store.ts';

/**
 * A note's versions file handed to the person (Matt: "a way that can be shared via a file"): the phone's share sheet
 * where it takes a file, a download in a browser, the library's folder opened on the Mac - where the file is beside
 * its note, `<Title>.versions` - and, where none of those is there, the file's text copied. Answers what was done, in
 * the words a toast says it.
 */
export async function shareVersionsFile(noteId: string, title: string): Promise<string> {
  const text = await readVersionsFile(noteId);
  if (!text) return 'This note has no versions yet.';
  const name = `${(title.trim() || 'Untitled').replace(/[\\/:*?"<>|]+/g, ' ').trim()}.versions`;
  const file = new File([text], name, { type: 'text/plain' });
  if (typeof navigator.canShare === 'function' && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: name });
      return `Shared ${name}.`;
    } catch (failure) {
      if (failure instanceof DOMException && failure.name === 'AbortError') return '';
      // A share that would not go: the ways below.
    }
  }
  if (!isTauri()) {
    const url = URL.createObjectURL(file);
    const link = document.createElement('a');
    link.href = url;
    link.download = name;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10_000);
    return `Saved ${name}.`;
  }
  if (isMacApp && (await canBrowseFiles())) {
    await browseFiles();
    return `${name} is beside the note in the folder that opened.`;
  }
  await navigator.clipboard.writeText(text);
  return `This device can’t send a file, so the versions file is copied as text.`;
}
