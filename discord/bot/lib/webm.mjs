/**
 * Opus in WebM, written as the call goes (docs/DISCORD_CALLS.md, "The recording"): the container the Meet bot's
 * Chrome writes, and the one the device reads (lib/meet/webm.dart `readWebmOpus`), so a Discord take is filed by the
 * very same pass as a Meet's.
 *
 * WebM is Matroska, which is EBML: each element an ID, its size as a variable-length integer, then its bytes. What
 * is written, as a live recording is: the EBML header (DocType `webm`); a Segment of unknown size, since its end is
 * not known while the call goes on; its Info (a millisecond timecode scale); its Tracks (one, Opus, mono, 48 kHz,
 * the `OpusHead` as CodecPrivate, the codec delay and seek pre-roll); then a Cluster every `clusterMs`, each a
 * timecode and a SimpleBlock a packet (track 1, its time from the cluster's, a keyframe). A Cluster is written whole,
 * with its size, once it is full, so a call cut short (a crash) loses at most the one being filled, as the Meet bot's
 * five-second slices do. No Cues and no Duration: the device reads neither.
 *
 * Pure: `write` is handed each piece of bytes in order (recorder.mjs appends them to the take's file).
 */

const ID = {
  ebml: [0x1a, 0x45, 0xdf, 0xa3],
  ebmlVersion: [0x42, 0x86],
  ebmlReadVersion: [0x42, 0xf7],
  ebmlMaxIdLength: [0x42, 0xf2],
  ebmlMaxSizeLength: [0x42, 0xf3],
  docType: [0x42, 0x82],
  docTypeVersion: [0x42, 0x87],
  docTypeReadVersion: [0x42, 0x85],
  segment: [0x18, 0x53, 0x80, 0x67],
  info: [0x15, 0x49, 0xa9, 0x66],
  timecodeScale: [0x2a, 0xd7, 0xb1],
  muxingApp: [0x4d, 0x80],
  writingApp: [0x57, 0x41],
  tracks: [0x16, 0x54, 0xae, 0x6b],
  trackEntry: [0xae],
  trackNumber: [0xd7],
  trackUid: [0x73, 0xc5],
  trackType: [0x83],
  codecId: [0x86],
  codecPrivate: [0x63, 0xa2],
  codecDelay: [0x56, 0xaa],
  seekPreRoll: [0x56, 0xbb],
  audio: [0xe1],
  samplingFrequency: [0xb5],
  channels: [0x9f],
  cluster: [0x1f, 0x43, 0xb6, 0x75],
  timecode: [0xe7],
  simpleBlock: [0xa3],
};

/** A size as EBML writes one: the fewest bytes, the length marker in the first. */
export function vsize(n) {
  for (let length = 1; length <= 8; length += 1) {
    // All ones in a length is "unknown", so the largest of each length is not used for a size.
    if (n < 2 ** (7 * length) - 1) {
      const bytes = new Array(length);
      let rest = n;
      for (let i = length - 1; i >= 0; i -= 1) {
        bytes[i] = rest % 256;
        rest = Math.floor(rest / 256);
      }
      bytes[0] |= 0x80 >> (length - 1);
      return bytes;
    }
  }
  throw new RangeError(`${n} is too large for an EBML size`);
}

/** The size that says "unknown", eight bytes long. */
const UNKNOWN = [0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff];

const el = (id, body) => Buffer.concat([Buffer.from(id), Buffer.from(vsize(body.length)), Buffer.from(body)]);

/** An unsigned integer element, in the fewest bytes. */
function uint(id, value) {
  const bytes = [];
  let rest = value;
  do {
    bytes.unshift(rest % 256);
    rest = Math.floor(rest / 256);
  } while (rest > 0);
  return el(id, bytes);
}

const text = (id, value) => el(id, Buffer.from(value, 'ascii'));

function float32(id, value) {
  const bytes = Buffer.alloc(4);
  bytes.writeFloatBE(value);
  return el(id, bytes);
}

/** An `OpusHead`: version 1, `channels`, `preSkip`, 48 kHz input, no gain, channel mapping family 0. */
export function opusHead(channels, preSkip) {
  const head = Buffer.alloc(19);
  head.write('OpusHead', 0, 'ascii');
  head[8] = 1;
  head[9] = channels;
  head.writeUInt16LE(preSkip, 10);
  head.writeUInt32LE(48_000, 12);
  head.writeInt16LE(0, 16);
  head[18] = 0;
  return head;
}

/** libopus's look-ahead at 48 kHz (`OPUS_GET_LOOKAHEAD`): the samples the decoder drops from the start. */
export const PRE_SKIP = 312;

export class WebmOpusWriter {
  /** `write(bytes)` is handed each piece in order. `frameMs`: each packet's length (20 ms, what recorder.mjs encodes). */
  constructor({ write, channels = 1, preSkip = PRE_SKIP, clusterMs = 5000, frameMs = 20, app = 'Ghost.md Discord bot' }) {
    this.write = write;
    this.channels = channels;
    this.preSkip = preSkip;
    this.clusterMs = clusterMs;
    this.frameMs = frameMs;
    this.app = app;
    this.at = 0;
    this.cluster = null;
    this.blocks = [];
    this.packets = 0;
    this.started = false;
  }

  /** The header, the Segment's start, Info and Tracks. */
  start() {
    if (this.started) return;
    this.started = true;
    const header = el(ID.ebml, Buffer.concat([
      uint(ID.ebmlVersion, 1),
      uint(ID.ebmlReadVersion, 1),
      uint(ID.ebmlMaxIdLength, 4),
      uint(ID.ebmlMaxSizeLength, 8),
      text(ID.docType, 'webm'),
      uint(ID.docTypeVersion, 4),
      uint(ID.docTypeReadVersion, 2),
    ]));
    const info = el(ID.info, Buffer.concat([uint(ID.timecodeScale, 1_000_000), text(ID.muxingApp, this.app), text(ID.writingApp, this.app)]));
    const track = el(ID.trackEntry, Buffer.concat([
      uint(ID.trackNumber, 1),
      uint(ID.trackUid, 1),
      uint(ID.trackType, 2),
      text(ID.codecId, 'A_OPUS'),
      el(ID.codecPrivate, opusHead(this.channels, this.preSkip)),
      uint(ID.codecDelay, Math.round((this.preSkip * 1e9) / 48_000)),
      uint(ID.seekPreRoll, 80_000_000),
      el(ID.audio, Buffer.concat([float32(ID.samplingFrequency, 48_000), uint(ID.channels, this.channels)])),
    ]));
    this.write(Buffer.concat([header, Buffer.from(ID.segment), Buffer.from(UNKNOWN), info, el(ID.tracks, track)]));
  }

  /** The next packet, `frameMs` after the one before. */
  packet(bytes) {
    if (!this.started) this.start();
    if (this.cluster == null) this.cluster = this.at;
    const relative = this.at - this.cluster;
    const head = Buffer.alloc(4);
    head[0] = 0x81; // track 1, as a one-byte variable-length integer
    head.writeInt16BE(relative, 1);
    head[3] = 0x80; // a keyframe: every Opus packet stands alone
    this.blocks.push(el(ID.simpleBlock, Buffer.concat([head, bytes])));
    this.packets += 1;
    this.at += this.frameMs;
    if (this.at - this.cluster >= this.clusterMs) this.flush();
  }

  /** The Cluster being filled, written whole. */
  flush() {
    if (this.cluster == null || this.blocks.length === 0) return;
    this.write(el(ID.cluster, Buffer.concat([uint(ID.timecode, this.cluster), ...this.blocks])));
    this.cluster = null;
    this.blocks = [];
  }

  /** The end: the last Cluster written. */
  end() {
    if (!this.started) this.start();
    this.flush();
  }

  /** How long the packets written are, in ms. */
  get durationMs() {
    return this.at;
  }
}
