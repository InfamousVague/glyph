import { describe, expect, it, vi } from 'vitest';
import { sealBytes, toBase64Url } from '../app/core/sync/crypto.ts';
import { audioContext, readWav, type SharedAudio } from './meeting.ts';
import { SharedRecording } from './shareAudio.ts';

/*
 * A shared recording fetched and opened in the browser (shareAudio.ts), sealed here as the app seals it
 * (lib/share/share_audio.dart: a part a megabyte, `1 ‖ iv ‖ AES-GCM`, in its part's context) and streamed in the
 * service's framing (server/src/shares.rs) in pieces of any size: it plays from the first part, opens whole, and says
 * what went wrong in words.
 */

const CHUNK = 4096;

function aWav(seconds: number): Uint8Array {
  const data = seconds * 32000;
  const out = new Uint8Array(44 + data);
  const view = new DataView(out.buffer);
  const put = (at: number, text: string) => [...text].forEach((c, i) => (out[at + i] = c.charCodeAt(0)));
  put(0, 'RIFF');
  view.setUint32(4, 36 + data, true);
  put(8, 'WAVE');
  put(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, 16000, true);
  view.setUint32(28, 32000, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  put(36, 'data');
  view.setUint32(40, data, true);
  for (let i = 44; i < out.length; i += 1) out[i] = (i * 7) & 255;
  return out;
}

async function sealed(recording: Uint8Array, upload = 'UpLoAd0123456789abcdef') {
  const raw = crypto.getRandomValues(new Uint8Array(32));
  const key = await crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
  const parts = Math.ceil(recording.length / CHUNK);
  const frames: number[] = [];
  const pieces: Uint8Array[] = [];
  for (let n = 0; n < parts; n += 1) {
    const part = await sealBytes(key, recording.slice(n * CHUNK, (n + 1) * CHUNK), audioContext(upload, n, parts));
    pieces.push(part);
    frames.push((part.length >>> 24) & 255, (part.length >>> 16) & 255, (part.length >>> 8) & 255, part.length & 255, ...part);
  }
  const audio: SharedAudio = { upload, parts, bytes: recording.length, mime: 'audio/wav', ms: (recording.length - 44) / 32, chunk: CHUNK };
  return { secret: toBase64Url(raw), audio, framed: Uint8Array.from(frames), pieces };
}

/** The service answering `body` in pieces of `size`, and what it was asked for. */
function service(body: Uint8Array, size = 1000, status = 200) {
  const asked: string[] = [];
  const fetcher = (async (url: string) => {
    asked.push(url);
    if (status !== 200) return new Response(JSON.stringify({ error: 'no' }), { status });
    let at = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (at >= body.length) return controller.close();
        controller.enqueue(body.slice(at, at + size));
        at += size;
      },
    });
    return new Response(stream, { status: 200 });
  }) as unknown as typeof fetch;
  return { asked, fetcher };
}

describe('a shared recording in the browser', () => {
  it('opens part by part as it arrives, plays from the first, and is the recording whole at the end', async () => {
    const recording = aWav(1);
    const { secret, audio, framed } = await sealed(recording);
    const { asked, fetcher } = service(framed, 777);
    const rec = new SharedRecording('ShareId0123456789abcd', secret, audio, fetcher);
    const heard: number[] = [];
    let first: { blob: Blob; ms: number } | null = null;
    await rec.load(() => {
      heard.push(rec.progress);
      first ??= rec.sound();
    });
    expect(asked).toEqual(['https://ghostmarkdown.com/api/v1/shares/ShareId0123456789abcd/audio']);
    expect(heard.at(-1)).toBe(1);
    expect(heard.length).toBe(audio.parts + 1);
    // The first part alone already plays: a WAV whose header says just that much sound.
    const early = new Uint8Array(await first!.blob.arrayBuffer());
    expect(readWav(early)).toMatchObject({ dataOffset: 44, dataSize: CHUNK - 44 });
    expect(first!.ms).toBeCloseTo(((CHUNK - 44) / 32000) * 1000);
    const whole = rec.sound()!;
    expect(new Uint8Array(await whole.blob.arrayBuffer())).toEqual(recording);
    expect(whole.ms).toBe(1000);
    expect(rec.done).toBe(true);
  });

  it('will not open a part moved, a part of another upload, or a stream cut short, and says so', async () => {
    const recording = aWav(1);
    const { secret, audio, framed, pieces } = await sealed(recording);
    // Parts 0 and 1 swapped.
    const swapped: number[] = [];
    for (const part of [pieces[1]!, pieces[0]!, ...pieces.slice(2)]) swapped.push(0, 0, (part.length >>> 8) & 255, part.length & 255, ...part);
    await expect(new SharedRecording('ShareId0123456789abcd', secret, audio, service(Uint8Array.from(swapped)).fetcher).load(() => undefined)).rejects.toThrow('does not open with this link');
    await expect(new SharedRecording('ShareId0123456789abcd', secret, { ...audio, upload: 'another' }, service(framed).fetcher).load(() => undefined)).rejects.toThrow('does not open with this link');
    await expect(new SharedRecording('ShareId0123456789abcd', secret, audio, service(framed.slice(0, framed.length - 10)).fetcher).load(() => undefined)).rejects.toThrow('stopped short');
    await expect(new SharedRecording('ShareId0123456789abcd', secret, { ...audio, parts: audio.parts + 1 }, service(framed).fetcher).load(() => undefined)).rejects.toThrow();
  });

  it('asks with the browser’s own fetch, called as a browser lets it be called', async () => {
    const recording = aWav(1);
    const { secret, audio, framed } = await sealed(recording);
    const { fetcher } = service(framed);
    // A browser's fetch refuses to be called as another object's method ("Illegal invocation").
    vi.stubGlobal('fetch', function (this: unknown, ...args: Parameters<typeof fetch>) {
      if (this !== undefined && this !== globalThis) throw new TypeError('Illegal invocation');
      return fetcher(...args);
    });
    try {
      const rec = new SharedRecording('ShareId0123456789abcd', secret, audio);
      await rec.load(() => undefined);
      expect(rec.done).toBe(true);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it('says why when the service will not give it', async () => {
    const { secret, audio } = await sealed(aWav(1));
    await expect(new SharedRecording('ShareId0123456789abcd', secret, audio, service(new Uint8Array(0), 1, 404).fetcher).load(() => undefined)).rejects.toThrow('isn’t there any more');
    await expect(new SharedRecording('ShareId0123456789abcd', secret, audio, service(new Uint8Array(0), 1, 429).fetcher).load(() => undefined)).rejects.toThrow('Too many plays');
  });
});
