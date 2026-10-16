// @vitest-environment node
import { beforeEach, describe, expect, it } from 'vitest';
import { imageNames } from '../tauri/src/app/core/imageRefs.ts';
import type { Note } from '../tauri/src/app/core/store.ts';
import { openBytes } from '../tauri/src/app/core/sync/crypto.ts';
import { forgetTeamDocs } from '../tauri/src/app/core/team/doc.ts';
import { downloadPicture, isPublicAddress, pictureKindOf, placePicture } from './pictures.ts';
import { aNote, anOrganization, connected, teamDevice } from './testKit.ts';

/**
 * `add_picture` (mcp/pictures.ts, mcp/server.ts): a picture from the web kept as a device keeps one, sealed where the
 * note's readers fetch it, and drawn on a line of its own where it was asked for; and what it will not fetch.
 */

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46]);
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0x0d]);
const WEBP = new Uint8Array([...'RIFF'].map((c) => c.charCodeAt(0)).concat([0, 0, 0, 0], [...'WEBPVP8 '].map((c) => c.charCodeAt(0))));

beforeEach(() => {
  forgetTeamDocs();
});

describe('what a picture is, and where it may come from', () => {
  it('knows a JPEG, a PNG and a WebP by their first bytes, and nothing else', () => {
    expect(pictureKindOf(JPEG)).toBe('jpg');
    expect(pictureKindOf(PNG)).toBe('png');
    expect(pictureKindOf(WEBP)).toBe('webp');
    expect(pictureKindOf(new TextEncoder().encode('<html>not a picture</html>'))).toBeNull();
    expect(pictureKindOf(new TextEncoder().encode('GIF89a......'))).toBeNull();
  });

  it('fetches only from public internet addresses', () => {
    for (const open of ['93.184.215.14', '2606:2800:21f:cb07:6820:80da:af6b:8b2c', '8.8.8.8']) expect(isPublicAddress(open)).toBe(true);
    for (const shut of ['127.0.0.1', '10.1.2.3', '172.20.0.1', '192.168.1.10', '169.254.169.254', '100.64.0.1', '0.0.0.0', '::1', '::', 'fe80::1', 'fd00::1', '::ffff:127.0.0.1', '::ffff:10.0.0.1', 'localhost']) {
      expect(isPublicAddress(shut)).toBe(false);
    }
  });

  it('refuses an address that is not https, carries a password, or names a private machine, before asking it anything', async () => {
    await expect(downloadPicture('http://example.com/a.jpg')).rejects.toThrow('https only');
    await expect(downloadPicture('https://me:secret@example.com/a.jpg')).rejects.toThrow('name or password');
    await expect(downloadPicture('https://127.0.0.1/a.jpg')).rejects.toThrow('not a public address');
    await expect(downloadPicture('https://[::1]/a.jpg')).rejects.toThrow('not a public address');
    await expect(downloadPicture('https://localhost/a.jpg')).rejects.toThrow('not a public address');
    await expect(downloadPicture('not an address')).rejects.toThrow('not an address');
  });
});

describe('where a picture goes in the words', () => {
  const line = '![A lemon](image/x.jpg)';

  it('goes straight under a heading, with a blank line before the words under it', () => {
    expect(placePicture('# Month 3\n\n## The baby\n- Grows to 3 inches\n', line, '## The baby')).toBe('# Month 3\n\n## The baby\n![A lemon](image/x.jpg)\n\n- Grows to 3 inches\n');
  });

  it('keeps a blank line from a list, a paragraph or a table above it, so it is never a to-do or a row', () => {
    expect(placePicture('# Note\n\n- [ ] Buy a crib\n', line)).toBe('# Note\n\n- [ ] Buy a crib\n\n![A lemon](image/x.jpg)\n');
    expect(placePicture('| a | b |\n| --- | --- |\n| 1 | 2 |\n\nAfter.', line, '| 1 | 2 |')).toBe('| a | b |\n| --- | --- |\n| 1 | 2 |\n\n![A lemon](image/x.jpg)\n\nAfter.\n');
  });

  it('goes at the end, past trailing blank lines, when no line is named, and says when the named one is not there', () => {
    expect(placePicture('# Note\n\nWords.\n\n\n', line)).toBe('# Note\n\nWords.\n\n![A lemon](image/x.jpg)\n\n\n');
    expect(placePicture('# Note\n', line, '## Nowhere')).toBeNull();
  });
});

describe('add_picture', () => {
  it('keeps the picture in the account’s files, sealed as a device seals one, then names it under the line asked for', async () => {
    const asked: string[] = [];
    const { service, call } = await connected({ download: async (url) => (asked.push(url), { bytes: JPEG, kind: 'jpg' }) });
    await service.deviceWrites(aNote('n1', '# Week 12\n\n## The baby\n- About 2 inches\n'));
    const result = await call('add_picture', { id: 'n1', url: 'https://upload.wikimedia.org/a.jpg', caption: 'At 12 weeks [ultrasound]', after: '## The baby' });
    expect(result.isError).toBe(false);
    const answer = JSON.parse(result.text) as { picture: string; line: string };
    expect(asked).toEqual(['https://upload.wikimedia.org/a.jpg']);
    expect(answer.picture).toMatch(/^[0-9a-f-]{36}\.jpg$/);
    // Brackets in the caption would end the picture's words early.
    expect(answer.line).toBe(`![At 12 weeks ultrasound](image/${answer.picture})`);
    const id = `i-jpg-${answer.picture.replace(/\.jpg$/, '')}`;
    expect(await openBytes(service.accountKey, service.files.get(id)!.bytes, `file:${id}`)).toEqual(JPEG);
    const stored = (await service.stored('n1'))!;
    expect(stored.note.body).toContain(`## The baby\n${answer.line}\n\n- About 2 inches`);
    expect(stored.images).toEqual([answer.picture]);
  });

  it('keeps a team note’s picture in the organization’s files, under its key, where a member’s phone fetches it', async () => {
    const { service, call } = await connected({ download: async () => ({ bytes: PNG, kind: 'png' }) });
    const org = await anOrganization(service, 'Family');
    const phone = teamDevice(service, org);
    phone.put('t1', '# Month 3\n\nWeeks 9 to 13.');
    await phone.sync();
    await call('list_notes');
    const answer = JSON.parse((await call('add_picture', { id: 't1', url: 'https://example.org/lemon.png', caption: 'A lemon' })).text) as { picture: string };
    const id = `i-png-${answer.picture.replace(/\.png$/, '')}`;
    expect(service.files.get(id)).toBeUndefined();
    expect(await openBytes(org.key, service.teamFiles(org.id).get(id)!.bytes, `file:${id}`)).toEqual(PNG);
    await phone.sync();
    const body = phone.notes.get('t1')!.body;
    expect(body).toContain(`Weeks 9 to 13.\n\n![A lemon](image/${answer.picture})`);
    expect(imageNames(body)).toEqual([answer.picture]);
    expect(phone.pictures.get(answer.picture)).toEqual(PNG);
  });

  it('says why when the picture cannot be had or the line is not there, and writes nothing', async () => {
    const { service, call } = await connected({ download: async () => Promise.reject(new Error('That address is not a JPEG, PNG or WebP picture.')) });
    await service.deviceWrites(aNote('n1', '# Week 12\n'));
    const refused = await call('add_picture', { id: 'n1', url: 'https://example.org/page.html' });
    expect(refused).toEqual({ isError: true, text: 'That address is not a JPEG, PNG or WebP picture.' });
    const nowhere = await call('add_picture', { id: 'n1', url: 'https://example.org/a.jpg', after: '## Missing' });
    expect(nowhere).toEqual({ isError: true, text: 'No line of “Week 12” reads “## Missing”.' });
    expect(service.files.size).toBe(0);
    expect(((await service.stored('n1')) as { note: Note }).note.body).toBe('# Week 12\n');
  });
});
