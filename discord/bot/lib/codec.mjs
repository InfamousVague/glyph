/**
 * Opus, both ways, for the recorder: each speaker's packets decoded to sound to be mixed (mixer.mjs), and the mix
 * encoded again for the take. opusscript is libopus compiled to WebAssembly: nothing to build on the box, which has
 * no compiler for one and no npm (scripts/setup-discord-box.mjs), and an hour of a call is a few seconds of its work.
 *
 * Mono at 48 kHz both ways. Discord sends stereo; a mono decoder folds it down itself, and what the device makes of
 * the take is mono at 16 kHz anyway (lib/meet/tape.dart). The mix is Opus VOIP at 32 kbit/s, Chrome's rate for the
 * Meet bot's recording: about 15 MB an hour.
 */
import OpusScript from 'opusscript';
import { FRAME_SAMPLES, RATE } from './mixer.mjs';

export const BITRATE = 32_000;

/** A buffer of 16-bit little-endian samples as an Int16Array, copied (opusscript's buffers are views of its heap). */
function samples(buffer) {
  const out = new Int16Array(buffer.length >> 1);
  for (let i = 0; i < out.length; i += 1) out[i] = buffer.readInt16LE(i * 2);
  return out;
}

export function opusCodec({ bitrate = BITRATE } = {}) {
  return {
    /** One speaker's decoder (each keeps its own state, as Opus needs). */
    decoder() {
      const decoder = new OpusScript(RATE, 1);
      return {
        decode: (packet) => samples(decoder.decode(packet)),
        close: () => decoder.delete(),
      };
    },
    /** The mix's encoder: a 20 ms frame of 960 samples at a time. */
    encoder() {
      const encoder = new OpusScript(RATE, 1, OpusScript.Application.VOIP);
      encoder.setBitrate(bitrate);
      return {
        encode: (pcm) => encoder.encode(Buffer.from(pcm.buffer, pcm.byteOffset, pcm.byteLength), FRAME_SAMPLES),
        close: () => encoder.delete(),
      };
    },
  };
}
