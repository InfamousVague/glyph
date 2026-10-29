import { API_BASE } from '../app/core/account/api.ts';
import { fromBase64Url } from '../app/core/sync/crypto.ts';
import { audioContext, Frames, readWav, wavHeader, type SharedAudio, type Wav } from './meeting.ts';

/**
 * A shared meeting's recording, fetched and opened in the browser (docs/SHARING.md, "A meeting's recording"): the
 * service streams its parts as they were sealed (server/src/shares.rs), each is opened with WebCrypto under the key in
 * the link as soon as its last byte is in, and the sound so far is a WAV the page can play: so playback starts on the
 * first part, half a minute of the meeting, while the rest arrives. Nothing leaves the browser but the one read of
 * ciphertext; the key never does.
 *
 * A recording that is not a WAV (none is yet: the app keeps every recording as one) is played once it is all in.
 */

const opener = new TextEncoder();

/** The words for a read the service refused. */
function refused(status: number): string {
  if (status === 404) return 'The recording isn’t there any more. Its owner may have taken it down.';
  if (status === 429) return 'Too many plays in a minute. Try again shortly.';
  return 'The recording could not be fetched. Try again shortly.';
}

export class SharedRecording {
  private readonly plain: Uint8Array[] = [];
  private bytes = 0;
  private wav: Wav | null = null;
  /** Every part is in, and opened. */
  done = false;

  constructor(
    private readonly id: string,
    private readonly key: string,
    readonly audio: SharedAudio,
    // Called as a plain function: `fetch` called as this object's method is an illegal invocation in a browser.
    private readonly fetcher: typeof fetch = (input, init) => fetch(input, init),
  ) {}

  /** How much of the recording has come, 0 to 1. */
  get progress(): number {
    return this.done ? 1 : Math.min(1, this.bytes / Math.max(1, this.audio.bytes));
  }

  /** How many ms of sound can be played. */
  get loadedMs(): number {
    if (!this.wav) return this.done ? this.audio.ms : 0;
    return (this.dataLength() / Math.max(1, this.wav.byteRate)) * 1000;
  }

  private dataLength(): number {
    const wav = this.wav!;
    let length = Math.max(0, this.bytes - wav.dataOffset);
    // A file that says how long its sound is, and is longer (a chunk after the sound), plays to what it says.
    if (wav.dataSize > 0 && wav.dataSize < length) length = wav.dataSize;
    return length - (length % Math.max(1, wav.blockAlign));
  }

  /** What has come, to play: a WAV of the sound so far, and how long it is. Null before any of it can play. */
  sound(): { blob: Blob; ms: number } | null {
    if (!this.wav) return this.done && this.plain.length ? { blob: new Blob(this.plain as BlobPart[], { type: this.audio.mime }), ms: this.audio.ms } : null;
    const length = this.dataLength();
    if (length <= 0) return null;
    const pieces: BlobPart[] = [wavHeader(this.wav, length) as BlobPart];
    let left = length;
    let skip = this.wav.dataOffset;
    for (const part of this.plain) {
      if (left <= 0) break;
      const from = Math.min(skip, part.length);
      skip -= from;
      const piece = part.subarray(from, from + Math.min(part.length - from, left));
      left -= piece.length;
      if (piece.length) pieces.push(piece as BlobPart);
    }
    return { blob: new Blob(pieces, { type: 'audio/wav' }), ms: this.loadedMs };
  }

  /** Fetches and opens every part in order, telling `onPart` after each. Throws, in words a reader can read, where it cannot. */
  async load(onPart: () => void, signal?: AbortSignal): Promise<void> {
    const key = await crypto.subtle.importKey('raw', fromBase64Url(this.key), { name: 'AES-GCM' }, false, ['decrypt']);
    let response: Response;
    try {
      response = await this.fetcher(`${API_BASE}/v1/shares/${this.id}/audio`, { signal, cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer' });
    } catch {
      throw new Error('The recording could not be reached. Check the connection and try again.');
    }
    if (!response.ok) throw new Error(refused(response.status));
    const frames = new Frames();
    let n = 0;
    const take = async (piece: Uint8Array) => {
      for (const sealed of frames.push(piece)) {
        await this.open(key, sealed, n);
        n += 1;
        onPart();
      }
    };
    const reader = response.body?.getReader();
    if (reader) {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        if (value?.length) await take(value);
      }
    } else {
      // A browser that cannot read a response as it comes: the whole of it, then the parts.
      await take(new Uint8Array(await response.arrayBuffer()));
    }
    if (frames.pending || n !== this.audio.parts) throw new Error('The recording stopped short. Reload the page to try again.');
    this.done = true;
    onPart();
  }

  private async open(key: CryptoKey, sealed: Uint8Array, n: number): Promise<void> {
    if (n >= this.audio.parts) throw new Error('The recording has more parts than its share says.');
    if (sealed[0] !== 1) throw new Error('This recording was shared by a newer Ghost.md.');
    let plain: Uint8Array;
    try {
      const opened = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: sealed.slice(1, 13), additionalData: opener.encode(audioContext(this.audio.upload, n, this.audio.parts)) },
        key,
        sealed.slice(13),
      );
      plain = new Uint8Array(opened);
    } catch {
      throw new Error('The recording does not open with this link. It may have changed: reload the page.');
    }
    this.plain.push(plain);
    this.bytes += plain.length;
    if (n === 0 && this.audio.mime.includes('wav')) this.wav = readWav(plain);
  }
}
