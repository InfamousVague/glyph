import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { buttonSaying, press, show, waitUntil } from '../../../test/render.tsx';

/**
 * Settings › Plugins › Library folder (docs/DESIGN.md §187): where the notes are, a folder chosen in the system's own
 * panel or picker and said before anything moves, the move, the way home, and the page on a binary or a device that
 * cannot. The app's commands and the activity are stood in for, each answering as library_commands.rs and
 * files/LibraryTree.kt do; the shell's own words are read out of its Kotlin, since the bridge is typed twice.
 */

const device = vi.hoisted(() => ({
  tauri: true,
  android: false,
  ios: false,
  generation: 25,
  calls: [] as { command: string; args: unknown }[],
  answers: {} as Record<string, unknown>,
  changed: 0,
}));
vi.mock('../../core/tauri.ts', () => ({
  isTauri: () => device.tauri,
  invoke: async (command: string, args: unknown) => {
    device.calls.push({ command, args });
    const answer = device.answers[command];
    if (answer instanceof Error) throw answer.message;
    return typeof answer === 'function' ? (answer as (a: unknown) => unknown)(args) : answer;
  },
}));
vi.mock('../../core/nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => device.generation >= wanted }));
vi.mock('../../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../core/platform.ts')>()),
  get isAndroid() {
    return device.android;
  },
  get isIOS() {
    return device.ios;
  },
}));
vi.mock('../../core/store.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../core/store.ts')>()),
  announceNotesChanged: () => {
    device.changed += 1;
  },
}));

const { FolderPane } = await import('./FolderPane.tsx');
const { candidateSaid, readFolderAnswer } = await import('./folder.ts');
const { manifest } = await import('./manifest.ts');

const home = { kind: 'app', path: null, name: null, reachable: true, notes: 2, own: '/Users/matt/Library/Application Support/com.mattssoftware.glyph/Library' };
const vault = { kind: 'folder', path: '/Users/matt/Obsidian/Vault', name: 'Vault', reachable: true, notes: 5, own: home.own };

beforeEach(() => {
  Object.assign(device, { tauri: true, android: false, ios: false, generation: 25, calls: [], changed: 0 });
  device.answers = { library_root: home };
  delete window.GlyphHost;
});

const commands = () => device.calls.map((call) => call.command);

describe('Settings › Library folder, on the Mac', () => {
  it('says where the notes are, and what a folder holds before anything moves into it', async () => {
    device.answers.library_choose_folder = { kind: 'folder', path: '/Users/matt/Obsidian/Vault', name: 'Vault', markdown: 3, obsidian: true, notes: 2 };
    device.answers.library_move = { notes: 2, adopted: 3, renamed: 1, same: 0, removed: 2, status: vault };
    const pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('Ghost.md’s own folder'));
    expect(pane.textContent).toContain('2 notes. /Users/matt/Library/Application Support');
    expect(buttonSaying(pane, 'Use Ghost.md’s own folder')).toBeUndefined();

    press(buttonSaying(pane, 'Choose a folder…'));
    await waitUntil(() => expect(pane.textContent).toContain('Use Vault?'));
    expect(pane.textContent).toContain('Vault has 3 Markdown files, and Obsidian keeps it. Each becomes a note and stays where it is, as it is.');
    expect(pane.textContent).toContain('Your 2 notes move in beside them');
    expect(pane.textContent).toContain('Once they are in, they leave Ghost.md’s own folder.');
    expect(commands()).not.toContain('library_move');

    press(buttonSaying(pane, 'Use it'));
    await waitUntil(() => expect(pane.textContent).toContain('Your notes are in Vault now. 2 notes moved in, 3 notes that were there already, 1 renamed with a number.'));
    expect(commands()).toEqual(['library_root', 'library_choose_folder', 'library_move']);
    expect(device.changed).toBe(1);
    expect(pane.textContent).toContain('5 notes. /Users/matt/Obsidian/Vault');
    expect(buttonSaying(pane, 'Use Ghost.md’s own folder')).toBeTruthy();
  });

  it('does nothing when the panel is closed, and says what the app said when a folder cannot be the library', async () => {
    device.answers.library_choose_folder = null;
    const pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('Ghost.md’s own folder'));
    press(buttonSaying(pane, 'Choose a folder…'));
    await waitUntil(() => expect(commands()).toContain('library_choose_folder'));
    expect(pane.textContent).not.toContain('Use it');
    device.answers.library_choose_folder = new Error('That folder is in Ghost.md’s own storage. Choose one of yours.');
    press(buttonSaying(pane, 'Choose a folder…'));
    await waitUntil(() => expect(pane.textContent).toContain('That folder is in Ghost.md’s own storage.'));
  });

  it('goes home with a copy or with none, and says the folder keeps every file', async () => {
    device.answers.library_root = vault;
    device.answers.library_use_app_folder = (args: unknown) => ({ notes: (args as { copy: boolean }).copy ? 5 : 0, adopted: 0, renamed: 0, same: 0, removed: 0, status: { ...home, notes: 5 } });
    const pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('Vault'));
    press(buttonSaying(pane, 'Use Ghost.md’s own folder'));
    expect(pane.textContent).toContain('Vault keeps every file either way: Ghost.md never deletes anything in a folder of yours.');
    press(buttonSaying(pane, 'Copy'));
    await waitUntil(() => expect(pane.textContent).toContain('Back in Ghost.md’s own folder. 5 notes moved in.'));
    expect(device.calls.at(-1)).toEqual({ command: 'library_use_app_folder', args: { copy: true } });
  });

  it('says so when the chosen folder cannot be reached, and that its notes are untouched', async () => {
    device.answers.library_root = { ...vault, name: 'Backup', reachable: false };
    const pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('Backup can’t be reached'));
    expect(pane.textContent).toContain('the notes in yours are untouched');
  });
});

describe('Settings › Library folder, on Android', () => {
  it('chooses in the phone’s picker, and looks into the folder it granted', async () => {
    device.android = true;
    const picked: string[] = [];
    window.GlyphHost = {
      chooseLibraryFolder: () => {
        picked.push('picker');
        setTimeout(() => window.__glyph?.libraryFolder?.(JSON.stringify({ uri: 'content://com.android.externalstorage.documents/tree/primary%3ANotes', name: 'Notes' })));
        return 'started';
      },
    } as unknown as Window['GlyphHost'];
    device.answers.library_inspect = { kind: 'tree', path: null, name: 'Notes', markdown: 0, obsidian: false, notes: 2 };
    const pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('In the phone’s folder picker.'));
    expect(pane.textContent).toContain('A folder on the phone is the reliable one');
    expect(pane.textContent).toContain('iCloud Drive');
    press(buttonSaying(pane, 'Choose a folder…'));
    await waitUntil(() => expect(pane.textContent).toContain('Use Notes?'));
    expect(picked).toEqual(['picker']);
    expect(device.calls.find((call) => call.command === 'library_inspect')?.args).toEqual({ uri: 'content://com.android.externalstorage.documents/tree/primary%3ANotes' });
    expect(pane.textContent).toContain('Notes is empty of notes. Your 2 notes move in, in the same folders');
  });

  it('asks for the app’s update on a shell without the picker', async () => {
    device.android = true;
    window.GlyphHost = {} as unknown as Window['GlyphHost'];
    const pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('Needs the app’s next update'));
    expect(commands()).toEqual([]);
  });

  it('uses the activity’s own words for the bridge and the event', () => {
    const kotlin = (path: string) => readFileSync(join(process.cwd(), 'src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph', path), 'utf8');
    const activity = kotlin('MainActivity.kt');
    expect(activity).toContain('fun chooseLibraryFolder(): String');
    expect(activity).toContain('window.__glyph.libraryFolder(');
    const tree = kotlin('files/LibraryTree.kt');
    expect(tree).toContain('put("uri", uri.toString())');
    expect(tree).toContain('put("cancelled", true)');
  });
});

describe('Settings › Library folder, where it cannot', () => {
  it('is only in the app, needs generation 25, and is not on an iPhone yet', async () => {
    device.tauri = false;
    let pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('Only in the app'));
    device.tauri = true;
    device.generation = 24;
    pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('Needs the app’s next update'));
    device.generation = 25;
    device.ios = true;
    pane = show(<FolderPane />);
    await waitUntil(() => expect(pane.textContent).toContain('Not on iPhone yet'));
    expect(commands()).toEqual([]);
  });

  it('asks for every command it calls in its manifest, and touches no storage of its own', () => {
    expect(manifest.native).toEqual({ generation: 25, commands: ['library_root', 'library_choose_folder', 'library_inspect', 'library_move', 'library_use_app_folder'] });
    expect(manifest.permissions.map((p) => p.kind)).toEqual(['notes', 'native']);
    expect(manifest.standard).toBe(false);
    expect(manifest.storage).toEqual([]);
  });

  it('reads the picker’s answer, and says what an empty folder and a copy from another folder will do', () => {
    expect(readFolderAnswer('{"uri":"content://x/tree/y","name":"y"}')).toEqual({ uri: 'content://x/tree/y', name: 'y' });
    expect(readFolderAnswer('{"cancelled":true}')).toEqual({ cancelled: true });
    for (const odd of ['{"uri":"file:///sdcard"}', 'nonsense', '[]']) expect('error' in readFolderAnswer(odd)).toBe(true);
    const candidate = { kind: 'folder' as const, path: '/x', name: 'Drive', markdown: 1, obsidian: false, notes: 4 };
    expect(candidateSaid(candidate, false)).toBe('Drive has 1 Markdown file. Each becomes a note and stays where it is, as it is. Your 4 notes are copied in beside them, in the same folders, and a note whose name is taken there gets “2” after it. The folder they are in now keeps its copy.');
  });
});
