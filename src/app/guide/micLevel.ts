/**
 * The phone's microphone as a level, 0 (silence) to 1 (talking up close), for
 * the first page's rings (SideKeyWaves.tsx). Its own small listener rather
 * than the recorder's (capture/audio.ts), which is built for speech: this
 * one wants nothing but loudness, and closes the moment the page goes.
 *
 * The guide never asks for the microphone itself: the first screen of the
 * app should not open with a permission dialog, and the recorder asks when
 * there is a reason to. So the rings listen only where the microphone is
 * already allowed (the Permissions API says granted), and keep their resting
 * beat everywhere else: a fresh install until its first recording, a refused
 * permission, a page served over plain http (the hot-reloading dev build),
 * which has no `mediaDevices` at all.
 */

/** Whether the microphone is already allowed, without asking. Unknown counts as no. */
async function allowed(): Promise<boolean> {
  try {
    const status = await navigator.permissions.query({ name: 'microphone' as PermissionName });
    return status.state === 'granted';
  } catch {
    return false;
  }
}

export function listenToMicrophone(onLevel: (level: number) => void): () => void {
  const media = typeof navigator === 'undefined' ? undefined : navigator.mediaDevices;
  if (!media?.getUserMedia || typeof AudioContext === 'undefined') return () => undefined;

  let stopped = false;
  let stream: MediaStream | null = null;
  let context: AudioContext | null = null;
  let raf = 0;

  const wake = () => void context?.resume().catch(() => undefined);

  allowed()
    .then((yes) => (yes && !stopped ? media.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } }) : null))
    .then(
      (got) => {
        if (!got) return;
        if (stopped) {
          got.getTracks().forEach((track) => track.stop());
          return;
        }
        stream = got;
        context = new AudioContext();
        const analyser = context.createAnalyser();
        analyser.fftSize = 1024;
        context.createMediaStreamSource(got).connect(analyser);
        // Android may hold a fresh context suspended until a touch; ask now and again at the next one.
        wake();
        document.addEventListener('pointerdown', wake, { once: true });
        const samples = new Float32Array(analyser.fftSize);
        const tick = () => {
          if (stopped) return;
          analyser.getFloatTimeDomainData(samples);
          let sum = 0;
          for (const sample of samples) sum += sample * sample;
          onLevel(Math.min(1, Math.sqrt(sum / samples.length) * 5));
          raf = requestAnimationFrame(tick);
        };
        tick();
      },
      () => {
        // No microphone after all: the rings keep their own beat.
      },
    );

  return () => {
    stopped = true;
    cancelAnimationFrame(raf);
    document.removeEventListener('pointerdown', wake);
    stream?.getTracks().forEach((track) => track.stop());
    void context?.close().catch(() => undefined);
  };
}
