import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The export of everything (core/exportAll.ts; docs/DESIGN.md §167): its name, its README and settings, the Android
 * picker's answer and the clean-up after a failure, the Mac's panel, and a browser's own zip. The apps, their
 * generation, their events and the browser's picture store are stood in for; the shell's own words are read out of
 * its Kotlin, since the bridge is typed twice.
 */

const device = vi.hoisted(() => ({
  tauri: true,
  android: true,
  ios: false,
  generation: 22,
  commands: [] as { command: string; args: unknown }[],
  answer: null as unknown,
  progress: null as ((payload: unknown) => void) | null,
  pictures: {} as Record<string, Blob>,
  notes: [] as { id: string; body: string; createdAt: number; updatedAt: number; source: 'editor' }[],
}));
vi.mock('./tauri.ts', () => ({
  isTauri: () => device.tauri,
  invoke: async (command: string, args: unknown) => {
    device.commands.push({ command, args });
    if (device.answer instanceof Error) throw device.answer.message;
    return device.answer;
  },
}));
vi.mock('./events.ts', () => ({
  listenTo: async (_event: string, handler: (payload: unknown) => void) => {
    device.progress = handler;
    return () => {
      device.progress = null;
    };
  },
}));
vi.mock('./nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => device.generation >= wanted }));
vi.mock('./platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./platform.ts')>()),
  get isAndroid() {
    return device.android;
  },
  get isIOS() {
    return device.ios;
  },
}));
vi.mock('./webImages.ts', () => ({
  webNames: async () => Object.keys(device.pictures).sort(),
  webGet: async (name: string) => device.pictures[name] ?? null,
}));
vi.mock('./store.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./store.ts')>()),
  listNotes: async () => device.notes,
}));

const exportAll = await import('./exportAll.ts');
const { exportName, settingsFile, readme, readTargetAnswer, noteFileName, browserFiles, exportEverything, exportWay, sizeSaid, doneSaid, EXPORT_GENERATION } = exportAll;

const AT = new Date(2026, 9, 1, 21, 42, 5);
const DONE = { name: 'ghostmarkdown_2026-10-01_21-42-05.zip', notes: 12, files: 40, bytes: 9_000_000, written: 8_100_000 };

beforeEach(() => {
  Object.assign(device, { tauri: true, android: true, ios: false, generation: 22, commands: [], answer: DONE, progress: null, pictures: {}, notes: [] });
});

afterEach(() => {
  delete window.GlyphHost;
  localStorage.clear();
});

describe('the archive’s name', () => {
  it('is ghostmarkdown_, the day and the time on the device’s clock, with no colon a USB drive would refuse', () => {
    expect(exportName(AT)).toBe('ghostmarkdown_2026-10-01_21-42-05.zip');
    expect(exportName(new Date(2027, 0, 9, 7, 3, 9))).toBe('ghostmarkdown_2027-01-09_07-03-09.zip');
  });
});

describe('what the page writes into it', () => {
  it('carries the settings, and never an account, a key or a token', () => {
    localStorage.setItem('glyph-preferences', JSON.stringify({ theme: 'dark' }));
    localStorage.setItem('glyph-plugins', JSON.stringify({ marks: true }));
    localStorage.setItem('glyph-account-session', JSON.stringify({ token: 'secret' }));
    localStorage.setItem('glyph-github-token', 'ghp_secret');
    const file = settingsFile();
    expect(JSON.parse(file)).toEqual({ 'glyph-preferences': { theme: 'dark' }, 'glyph-plugins': { marks: true } });
    expect(file).not.toMatch(/secret/);
  });

  it('says what every folder is in a README', () => {
    const text = readme(exportName(AT), AT);
    for (const folder of ['Library/', 'images/', 'video/', 'recordings/', 'settings.json', 'manifest.json']) expect(text).toContain(folder);
    expect(text).toContain('ghostmarkdown_2026-10-01_21-42-05/');
  });

  it('names a browser’s notes from their titles, each once, with nothing a drive will not hold', () => {
    const taken = new Set<string>();
    expect(noteFileName('Milk: oat / soy', taken)).toBe('Milk oat soy.md');
    expect(noteFileName('Milk: oat / soy', taken)).toBe('Milk oat soy 2.md');
    expect(noteFileName('', taken)).toBe('Untitled.md');
  });
});

describe('where it can go from here', () => {
  it('is Android’s picker, the Mac’s panel or a browser’s save, and an update on a binary from before', async () => {
    window.GlyphHost = { chooseExport: () => 'started' } as unknown as Window['GlyphHost'];
    expect(await exportWay()).toBe('android');
    device.generation = EXPORT_GENERATION - 1;
    expect(await exportWay()).toBe('update');
    device.generation = EXPORT_GENERATION;
    device.android = false;
    expect(await exportWay()).toBe('mac');
    device.ios = true;
    expect(await exportWay()).toBe('none');
    device.tauri = false;
    expect(await exportWay()).toBe('browser');
  });
});

describe('on Android', () => {
  /** The activity's picker, answering as files/ExportTarget.kt does. */
  const picker = (answer: object, calls: string[] = []) => {
    window.GlyphHost = {
      chooseExport: (name: string) => {
        calls.push(`choose ${name}`);
        setTimeout(() => window.__glyph?.exportTarget?.(JSON.stringify(answer)));
        return 'started';
      },
      exportDone: () => calls.push('done'),
      discardExport: () => calls.push('discard'),
    } as unknown as Window['GlyphHost'];
    return calls;
  };

  it('writes into the file the picker made, by its descriptor, and keeps it', async () => {
    const calls = picker({ fd: 87, name: 'ghostmarkdown_2026-10-01_21-42-05 (1).zip' });
    const heard: unknown[] = [];
    const done = await exportEverything((progress) => heard.push(progress), AT);
    expect(calls).toEqual(['choose ghostmarkdown_2026-10-01_21-42-05.zip', 'done']);
    expect(done).toEqual({ ...DONE, name: 'ghostmarkdown_2026-10-01_21-42-05 (1).zip' });
    const sent = device.commands.find((c) => c.command === 'export_fd')?.args as { fd: number; request: { name: string; offsetMinutes: number; files: { name: string }[] } };
    expect(sent.fd).toBe(87);
    expect(sent.request.name).toBe('ghostmarkdown_2026-10-01_21-42-05.zip');
    expect(sent.request.offsetMinutes).toBe(-AT.getTimezoneOffset());
    expect(sent.request.files.map((f) => f.name)).toEqual(['README.txt', 'settings.json']);
  });

  it('answers nothing when the picker is closed, and asks Rust for nothing', async () => {
    picker({ cancelled: true });
    expect(await exportEverything(() => undefined, AT)).toBeNull();
    expect(device.commands).toEqual([]);
  });

  it('takes the half-written file away when the export fails, and says why', async () => {
    const calls = picker({ fd: 87, name: 'x.zip' });
    device.answer = new Error('The drive is full.');
    await expect(exportEverything(() => undefined, AT)).rejects.toBe('The drive is full.');
    expect(calls).toEqual(['choose ghostmarkdown_2026-10-01_21-42-05.zip', 'discard']);
  });

  it('reads the picker’s answer, and anything else as a place it cannot write', () => {
    expect(readTargetAnswer('{"fd":87,"name":"a.zip"}')).toEqual({ fd: 87, name: 'a.zip' });
    expect(readTargetAnswer('{"cancelled":true}')).toEqual({ cancelled: true });
    expect(readTargetAnswer('{"error":"No."}')).toEqual({ error: 'No.' });
    for (const odd of ['{"fd":1}', '{"fd":"87"}', 'nonsense', '[]']) expect('error' in readTargetAnswer(odd)).toBe(true);
  });

  it('uses the activity’s own words for the bridge and the event', () => {
    const kotlin = (path: string) => readFileSync(join(process.cwd(), 'src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph', path), 'utf8');
    const activity = kotlin('MainActivity.kt');
    for (const method of ['fun chooseExport(name: String)', 'fun discardExport()', 'fun exportDone()']) expect(activity).toContain(method);
    expect(activity).toContain('window.__glyph.exportTarget(');
    const target = kotlin('files/ExportTarget.kt');
    expect(target).toContain('put("fd", fd)');
    expect(target).toContain('put("cancelled", true)');
  });
});

describe('on the Mac', () => {
  it('asks Rust for its save panel, and answers nothing when it was closed', async () => {
    device.android = false;
    expect(await exportEverything(() => undefined, AT)).toEqual(DONE);
    expect(device.commands.map((c) => c.command)).toEqual(['export_save']);
    device.answer = null;
    expect(await exportEverything(() => undefined, AT)).toBeNull();
  });

  it('hears how far it has got', async () => {
    device.android = false;
    const heard: unknown[] = [];
    // The panel is up and the archive being written until Rust answers.
    let finish: (done: typeof DONE) => void = () => undefined;
    device.answer = new Promise((resolve) => (finish = resolve));
    const run = exportEverything((progress) => heard.push(progress), AT);
    await vi.waitFor(() => expect(device.progress).not.toBeNull());
    device.progress?.({ done: 5, total: 10, files: 1, of: 2 });
    finish(DONE);
    expect(await run).toEqual(DONE);
    // Heard no more once it has answered.
    expect(device.progress).toBeNull();
    expect(heard).toEqual([{ done: 5, total: 10, files: 1, of: 2 }]);
  });
});

describe('in a browser', () => {
  it('zips the notes and pictures it keeps, in one folder of the archive’s name', async () => {
    device.tauri = false;
    device.notes = [
      { id: 'a', body: '# Milk\n\n- [ ] Oat', createdAt: 1, updatedAt: 2, source: 'editor' },
      { id: 'b', body: '# Milk\n\nAgain', createdAt: 1, updatedAt: 2, source: 'editor' },
    ];
    device.pictures = { 'p1.jpg': new Blob([new Uint8Array([1, 2, 3])]) };
    const files = await browserFiles(device.notes, exportName(AT), AT);
    const root = 'ghostmarkdown_2026-10-01_21-42-05';
    expect(files.map((f) => f.name)).toEqual([
      `${root}/README.txt`,
      `${root}/settings.json`,
      `${root}/manifest.json`,
      `${root}/Library/Milk.md`,
      `${root}/Library/Milk 2.md`,
      `${root}/images/p1.jpg`,
    ]);
    expect(new TextDecoder().decode(files[3]!.bytes)).toBe('# Milk\n\n- [ ] Oat');
    expect(JSON.parse(new TextDecoder().decode(files[2]!.bytes))).toMatchObject({ app: 'Ghost.md', notes: 2, files: 3 });
  });
});

describe('what it says it wrote', () => {
  it('counts the notes, then the other files, and the archive’s size and name', () => {
    expect(doneSaid(DONE)).toBe('Exported 12 notes and 28 other files, 8.1 MB, as ghostmarkdown_2026-10-01_21-42-05.zip.');
    expect(doneSaid({ ...DONE, notes: 1, files: 1, written: 2_000 })).toBe('Exported one note, 2 KB, as ghostmarkdown_2026-10-01_21-42-05.zip.');
    expect(doneSaid({ ...DONE, notes: 3, files: 4 })).toBe('Exported 3 notes and one other file, 8.1 MB, as ghostmarkdown_2026-10-01_21-42-05.zip.');
  });
});

describe('a size', () => {
  it('is said the way a person reads it', () => {
    expect([sizeSaid(512), sizeSaid(820_000), sizeSaid(1_400_000_000), sizeSaid(12_500_000)]).toEqual(['512 bytes', '820 KB', '1.4 GB', '13 MB']);
  });
});
