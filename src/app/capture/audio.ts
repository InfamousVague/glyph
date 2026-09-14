/**
 * The microphone, as 16 kHz mono float samples.
 *
 * Captured in the page rather than in Kotlin or Rust, because this path is
 * already proven on this exact phone: AttackFM's Booth records through
 * getUserMedia in the same Tauri WebView, and the generated RustWebChromeClient
 * already turns the page's microphone request into Android's RECORD_AUDIO
 * prompt. A native capture path would have meant a second permission flow and,
 * for Rust, a C++ audio backend on top of whisper.cpp's own build.
 *
 * 16 kHz because that is what Whisper consumes, and asking the AudioContext for
 * it makes Chromium resample the hardware's native 48 kHz before any sample
 * reaches us - a correct polyphase resampler for free, rather than a
 * hand-written decimator that aliases.
 *
 * Samples are handed over in chunks of about 200 ms. Smaller chunks cost an IPC
 * round trip each for no gain in latency, since the engine only looks at the
 * buffer every 600-800 ms; larger ones delay the first partial.
 */

export const SAMPLE_RATE = 16_000;
const CHUNK = 3_200; // 200 ms

/*
 * The worklet, as source text turned into a Blob URL. A separate file would
 * need its own entry in the Vite build and a path that resolves under Tauri's
 * custom protocol; a Blob URL resolves everywhere the page does. It runs on the
 * audio rendering thread, so it only copies samples and posts them - no
 * allocation per render quantum beyond the chunk it hands off.
 */
const WORKLET = `
class GlyphTap extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunk = new Float32Array(${CHUNK});
    this.filled = 0;
  }
  process(inputs) {
    const channel = inputs[0] && inputs[0][0];
    if (!channel) return true;
    for (let i = 0; i < channel.length; i += 1) {
      this.chunk[this.filled] = channel[i];
      this.filled += 1;
      if (this.filled === this.chunk.length) {
        this.port.postMessage(this.chunk, [this.chunk.buffer]);
        this.chunk = new Float32Array(${CHUNK});
        this.filled = 0;
      }
    }
    return true;
  }
}
registerProcessor('glyph-tap', GlyphTap);
`;

export interface Microphone {
  stop: () => void;
  /** The rate the AudioContext actually runs at, before any resampling to 16 kHz. */
  deviceRate: number;
  /** The AudioContext's state now: a context that stays 'suspended' delivers nothing. */
  state: () => AudioContextState;
}

/**
 * A streaming resampler to 16 kHz, for a platform that ignores the rate the
 * AudioContext asked for.
 *
 * Asking for `sampleRate: 16000` normally makes Chromium resample for us, but
 * nothing obliges a WebView to honour it, and when one does not the failure is
 * silent and total: 48 kHz samples labelled 16 kHz reach Whisper as speech
 * slowed to a third of its speed, which it hears as noise and transcribes as
 * nothing. So the actual rate is checked, and anything else is brought to 16 kHz
 * here.
 *
 * Each output sample is the mean of the input samples its window covers. A box
 * average is a crude low-pass, but it is the low-pass decimation needs to stop
 * high frequencies folding back into the speech band, and Whisper was trained on
 * far rougher audio than this. State carries across calls, so a chunk boundary
 * never produces a click or a dropped sample.
 */
export function createResampler(fromRate: number, toRate: number): (input: Float32Array) => Float32Array {
  if (fromRate === toRate) return (input) => input;
  const step = fromRate / toRate;
  let carry = new Float32Array(0);
  let position = 0;
  return (input) => {
    const buffer = new Float32Array(carry.length + input.length);
    buffer.set(carry);
    buffer.set(input, carry.length);
    const out: number[] = [];
    while (position + step <= buffer.length) {
      const start = Math.floor(position);
      const end = Math.floor(position + step);
      if (end <= start) {
        out.push(buffer[start] ?? 0);
      } else {
        let sum = 0;
        for (let i = start; i < end; i += 1) sum += buffer[i] ?? 0;
        out.push(sum / (end - start));
      }
      position += step;
    }
    const consumed = Math.floor(position);
    carry = buffer.slice(consumed);
    position -= consumed;
    return Float32Array.from(out);
  };
}

export interface MicrophoneHandlers {
  onChunk: (samples: Float32Array) => void;
  /** Root-mean-square level of the latest chunk, 0-1, for the meter. */
  onLevel: (rms: number) => void;
}

/**
 * Start capturing. Rejects when the person declines the microphone or the
 * platform has none; the caller shows why.
 */
export async function openMicrophone({ onChunk, onLevel }: MicrophoneHandlers): Promise<Microphone> {
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      channelCount: 1,
      // Noise suppression and gain control help recognition in a pocket or a
      // street; echo cancellation does nothing useful when nothing is playing
      // and can clip the first syllable while it converges.
      noiseSuppression: true,
      autoGainControl: true,
      echoCancellation: false,
    },
  });

  const context = new AudioContext({ sampleRate: SAMPLE_RATE });
  const url = URL.createObjectURL(new Blob([WORKLET], { type: 'application/javascript' }));
  try {
    await context.audioWorklet.addModule(url);
  } finally {
    URL.revokeObjectURL(url);
  }

  const source = context.createMediaStreamSource(stream);
  const tap = new AudioWorkletNode(context, 'glyph-tap');
  // A worklet with nothing downstream is not pulled on every platform, so it
  // feeds a silent gain into the destination. Silent because Matt should not
  // hear himself.
  const sink = context.createGain();
  sink.gain.value = 0;
  source.connect(tap).connect(sink).connect(context.destination);

  const resample = createResampler(context.sampleRate, SAMPLE_RATE);
  tap.port.onmessage = (event: MessageEvent<Float32Array>) => {
    const samples = resample(event.data);
    if (!samples.length) return;
    let sum = 0;
    for (let i = 0; i < samples.length; i += 1) sum += (samples[i] ?? 0) ** 2;
    onLevel(Math.sqrt(sum / samples.length));
    onChunk(samples);
  };

  // A suspended context delivers no audio at all. Resuming is bounded, because
  // a resume the platform declines never settles, and an unbounded await here
  // would leave the capture screen reading "Starting" forever with no error.
  if (context.state === 'suspended') {
    await Promise.race([context.resume(), new Promise((resolve) => window.setTimeout(resolve, 1500))]);
  }

  return {
    deviceRate: context.sampleRate,
    state: () => context.state,
    stop: () => {
      tap.port.onmessage = null;
      source.disconnect();
      tap.disconnect();
      sink.disconnect();
      for (const track of stream.getTracks()) track.stop();
      void context.close();
    },
  };
}
