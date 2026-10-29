#!/usr/bin/env python3
"""The placeholder Ghostly pack (assets/sounds/ghostly): twelve short tones made here, so Settings › Sounds works
before Matt's own sounds from ElevenLabs drop in (Matt, 2026-10-27: "build ... the sounds settings";
docs/ideas/CUSTOMIZATION_AND_SOUNDS.md, Sounds). Each is a few soft sine partials under a quick attack and an
exponential fall, mono at 44.1 kHz, with its peak where the doc puts it: -12 dBFS for a sound inside the app and
-3 dBFS for a notification's. Written as Ogg Vorbis for Android and as CAF for the Mac and the iPhone, and the two
notification sounds Android's channels play are copied into android/app/src/main/res/raw as well.

Run again only to remake the placeholders: `python3 tool/placeholder_sounds.py` from the repository root. Needs
numpy and ffmpeg (Homebrew's, /opt/homebrew/bin/ffmpeg). Matt's real files replace what this writes, by the same
names (assets/sounds/README.md).
"""

import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, 'assets', 'sounds', 'ghostly')
RAW = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'raw')
FFMPEG = shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'

# Interface sounds peak at -12 dBFS, notifications at -3 (the doc's "Delivering them").
INTERFACE = -12.0
NOTIFICATION = -3.0


def note(freq, start, length, total, decay=8.0, partials=((1, 1.0), (2, 0.25), (3, 0.08)), glide=None):
    """One soft struck note: a 6 ms rise, then an exponential fall over [length] seconds, placed at [start]."""
    out = np.zeros(int(total * RATE))
    n = int(length * RATE)
    t = np.arange(n) / RATE
    # A glide from freq to glide over the note, for the recorder's rising start and falling stop.
    f = freq if glide is None else freq + (glide - freq) * (t / length)
    phase = 2 * np.pi * np.cumsum(np.broadcast_to(f, t.shape)) / RATE
    tone = sum(weight * np.sin(phase * mult) for mult, weight in partials)
    envelope = np.minimum(1.0, t / 0.006) * np.exp(-decay * t / length)
    begin = int(start * RATE)
    end = min(len(out), begin + n)
    out[begin:end] += (tone * envelope)[: end - begin]
    return out


def breath(total, level=0.04, seed=7):
    """A little filtered noise under a note: the 'airy' of the Ghostly prompts, quiet enough to stay a texture."""
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(int(total * RATE))
    # A gentle low-pass by a moving average, then a swell that rises and falls over the sound.
    noise = np.convolve(noise, np.ones(24) / 24, mode='same')
    t = np.arange(len(noise)) / len(noise)
    return level * noise * np.sin(np.pi * t) ** 2


GLASS = ((1, 1.0), (2.76, 0.18), (5.4, 0.05))
WOOD = ((1, 1.0), (4.0, 0.2), (9.2, 0.04))


def sounds():
    """Each event's samples and its peak, by the event's file name."""
    s = {}
    s['todo-ticked'] = (note(1760, 0, 0.12, 0.14, decay=9, partials=((1, 1.0), (2.5, 0.2))) + breath(0.14, 0.02), INTERFACE)
    s['all-ticked'] = (
        note(1047, 0.0, 0.45, 1.0, partials=GLASS) + note(1319, 0.16, 0.45, 1.0, partials=GLASS) + note(1568, 0.32, 0.65, 1.0, partials=GLASS) + breath(1.0, 0.03),
        INTERFACE,
    )
    s['record-start'] = (note(660, 0, 0.3, 0.32, decay=5, glide=990) + breath(0.32, 0.03), INTERFACE)
    s['record-stop'] = (note(990, 0, 0.3, 0.32, decay=5, glide=620) + breath(0.32, 0.03), INTERFACE)
    s['writeup-ready'] = (note(880, 0.0, 0.6, 1.0, partials=GLASS) + note(1320, 0.22, 0.75, 1.0, partials=GLASS) + breath(1.0, 0.05), NOTIFICATION)
    s['reminder-due'] = (
        note(523, 0.0, 0.4, 1.2, decay=7, partials=WOOD) + note(659, 0.28, 0.4, 1.2, decay=7, partials=WOOD) + note(784, 0.56, 0.62, 1.2, decay=6, partials=WOOD),
        NOTIFICATION,
    )
    s['meeting-joining'] = (note(784, 0.0, 0.5, 1.0, partials=GLASS) + note(1047, 0.25, 0.7, 1.0, partials=GLASS) + breath(1.0, 0.04), NOTIFICATION)
    s['team-comment'] = (note(1175, 0.0, 0.25, 0.6, partials=GLASS) + note(1175, 0.16, 0.42, 0.6, partials=GLASS), NOTIFICATION)
    s['lovart-ready'] = (
        note(1319, 0.0, 0.3, 0.8, partials=GLASS) + note(1568, 0.1, 0.3, 0.8, partials=GLASS) + note(2093, 0.2, 0.55, 0.8, partials=GLASS) + breath(0.8, 0.03),
        NOTIFICATION,
    )
    s['failed'] = (note(330, 0, 0.35, 0.37, decay=6, glide=262, partials=((1, 1.0), (2, 0.15))), INTERFACE)
    # A long job you started is done (lib/activity/activity_chime.dart; docs/ACTIVITY.md, Sound): two soft glass notes
    # rising a fifth, gentler than the write-up's, since it plays inside the app.
    s['job-done'] = (note(988, 0.0, 0.42, 0.75, partials=GLASS) + note(1480, 0.14, 0.55, 0.75, partials=GLASS) + breath(0.75, 0.03), INTERFACE)
    # Saved is the quietest of all, a breath with a tap in it: it is off by default and should stay unnoticed.
    s['saved'] = (note(1200, 0, 0.14, 0.16, decay=10, partials=((1, 0.6),)) + breath(0.16, 0.05), INTERFACE - 6)
    return s


def write_wav(path, samples, peak_db):
    samples = samples / max(1e-9, np.max(np.abs(samples))) * 10 ** (peak_db / 20)
    # 5 ms fades at each end, the doc's trim: no click where the file starts or stops.
    edge = int(0.005 * RATE)
    samples[:edge] *= np.linspace(0, 1, edge)
    samples[-edge:] *= np.linspace(1, 0, edge)
    with wave.open(path, 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes((samples * 32767).astype('<i2').tobytes())


def ffmpeg(*args):
    subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', *args], check=True)


def main():
    os.makedirs(PACK, exist_ok=True)
    os.makedirs(RAW, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        for name, (samples, peak) in sounds().items():
            wav = os.path.join(scratch, name + '.wav')
            write_wav(wav, samples, peak)
            # Vorbis: every Android plays it. ffmpeg's own encoder is marked experimental and writes stereo only, which
            # is fine for these: the one channel copied to both at full level, so the peak stays where it was put.
            ffmpeg('-i', wav, '-af', 'pan=stereo|c0=c0|c1=c0', '-c:a', 'vorbis', '-strict', '-2', '-q:a', '3', os.path.join(PACK, name + '.ogg'))
            # IMA4 in CAF: what AVAudioPlayer and a notification's sound read, a quarter the size of PCM.
            ffmpeg('-i', wav, '-c:a', 'adpcm_ima_qt', os.path.join(PACK, name + '.caf'))
        # Android's notification channels name their sound by a raw resource: only the two wired so far.
        for name in ('writeup-ready', 'reminder-due'):
            shutil.copyfile(os.path.join(PACK, name + '.ogg'), os.path.join(RAW, 'sound_ghostly_' + name.replace('-', '_') + '.ogg'))
    print('wrote', PACK)


if __name__ == '__main__':
    sys.exit(main())
