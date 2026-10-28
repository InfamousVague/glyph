#!/usr/bin/env python3
"""Speaks the walkthrough's words with ElevenLabs, once, at build time (Matt, 2026-10-27: "build an onboarding flow
with vivid colors and iconography as well as a friendly elevenlabs v4 voice explaining each section").

The words live in lib/guide/narration.dart and nowhere else: this reads them from there, has each page's said, and
writes assets/onboarding/<page>.mp3, mono at 64 kbps (a voice needs no more, and the app carries every byte), with
assets/onboarding/narration.json saying which words, model and voice each file was made from. The app ships the
files, so a new person hears the voice with no key and no network; test/guide/narration_test.dart fails when a
page's words have changed and its file has not been made again.

The key is read the way tauri/scripts/voice-tests/make_audio.py reads it, from ~/.elevenlabs-key (one line, chmod
600): never an argument, never printed, never written anywhere.

    python3 tool/onboarding_voice.py --models        # the account's models, to find the newest
    python3 tool/onboarding_voice.py --voices        # the voices on the account
    python3 tool/onboarding_voice.py                 # every page whose words or voice changed
    python3 tool/onboarding_voice.py --page welcome --again
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

API = "https://api.elevenlabs.io/v1"
KEY_FILE = pathlib.Path.home() / ".elevenlabs-key"
ROOT = pathlib.Path(__file__).resolve().parents[1]
WORDS = ROOT / "lib" / "guide" / "narration.dart"
OUT = ROOT / "assets" / "onboarding"
MANIFEST = OUT / "narration.json"

# Eleven v4, ElevenLabs' newest (2026-09-28), as GET /v1/models names it; eleven_multilingual_v2 only where the
# account has no v4. Which one made each file is in the manifest.
PREFERRED = "eleven_v4"
FALLBACK = "eleven_multilingual_v2"

# A warm, friendly premade voice: Jessica ("playful, bright, warm", American), on every account.
VOICE = "cgSgspJ2msm6clMCkdW9"
VOICE_NAME = "Jessica"

# A little steadier than the default for a calm read, a touch of style for warmth.
SETTINGS = {"stability": 0.5, "similarity_boost": 0.75, "style": 0.2, "use_speaker_boost": True}


def key() -> str:
    if not KEY_FILE.exists():
        sys.exit(f"No key at {KEY_FILE}. Put the ElevenLabs key in that file, one line, chmod 600.")
    value = KEY_FILE.read_text().strip()
    if not value:
        sys.exit(f"{KEY_FILE} is empty.")
    return value


def call(path: str, token: str, body: dict | None = None) -> bytes:
    request = urllib.request.Request(
        f"{API}{path}",
        data=json.dumps(body).encode() if body else None,
        headers={"xi-api-key": token, "Content-Type": "application/json", "Accept": "*/*"},
        method="POST" if body else "GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as answer:
            return answer.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:400]
        # The key itself is never in the message: only the status and the API's words.
        sys.exit(f"ElevenLabs said {error.code} for {path}: {detail}")


def scripts(words: pathlib.Path = WORDS, pattern: str = r"GuidePage\.(\w+):\s*'((?:[^'\\]|\\.)*)'") -> dict[str, str]:
    """Each page's words, read from narration.dart's map: `GuidePage.<name>: '<words>',` on one line. Another file
    and pattern for other words: tool/academy_voice.py reads lib/academy/voice.dart's `'<name>': '<words>',`."""
    found = {}
    for name, said in re.findall(pattern, words.read_text()):
        found[name] = said.replace("\\'", "'").replace("\\$", "$")
    if not found:
        sys.exit(f"No words found in {words}.")
    return found


def digest(words: str) -> str:
    """What the manifest keeps of a page's words; the test works the same out of narration.dart."""
    return hashlib.sha256(words.encode("utf-8")).hexdigest()[:16]


def models(token: str) -> list[dict]:
    return json.loads(call("/models", token))


def pick_model(token: str) -> str:
    ids = [m["model_id"] for m in models(token) if m.get("can_do_text_to_speech", True)]
    if PREFERRED in ids:
        return PREFERRED
    # A v4 by another name (a dated or regional id) is still v4.
    v4 = [i for i in ids if re.search(r"(^|_)v4($|_)", i)]
    if v4:
        return v4[0]
    print(f"No Eleven v4 on this account; using {FALLBACK}.")
    return FALLBACK


def run(command: list[str]) -> None:
    done = subprocess.run(command, capture_output=True)
    if done.returncode:
        sys.exit(done.stderr.decode(errors="replace")[-600:])


def seconds(path: pathlib.Path) -> float:
    done = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)], capture_output=True)
    try:
        return round(float(done.stdout.decode().strip()), 2)
    except ValueError:
        return 0.0


def speak(token: str, model: str, words: str, out: pathlib.Path) -> None:
    body = {"text": words, "model_id": model, "voice_settings": SETTINGS}
    with tempfile.TemporaryDirectory() as work:
        raw = pathlib.Path(work) / "raw.mp3"
        raw.write_bytes(call(f"/text-to-speech/{VOICE}?output_format=mp3_44100_128", token, body))
        # Mono, 64 kbps at 44.1 kHz, the silence at either end trimmed to a breath so the voice starts as the page does.
        trim = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.25,areverse"
        run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw), "-af", trim, "-ac", "1", "-ar", "44100", "-codec:a", "libmp3lame", "-b:a", "64k", "-map_metadata", "-1", str(out)])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", action="store_true", help="list the account's text-to-speech models and stop")
    parser.add_argument("--voices", action="store_true", help="list the account's voices and stop")
    parser.add_argument("--page", help="one page by name, else every page")
    parser.add_argument("--again", action="store_true", help="speak pages whose file is already up to date")
    args = parser.parse_args()
    token = key()

    if args.models:
        for model in models(token):
            print(f"{model['model_id']:<32} {model.get('name', '')}  tts={model.get('can_do_text_to_speech')}")
        return
    if args.voices:
        for voice in json.loads(call("/voices", token)).get("voices", []):
            labels = ", ".join(str(v) for v in (voice.get("labels") or {}).values())
            print(f"{voice['voice_id']}  {voice['name']:<22} {voice.get('category', '')}  {labels}")
        return

    make(token, scripts(), OUT, MANIFEST, made="tool/onboarding_voice.py", only=args.page, again=args.again)


def make(token: str, clips: dict[str, str], out_dir: pathlib.Path, manifest_path: pathlib.Path, *, made: str, only: str | None = None, again: bool = False) -> None:
    """Speaks each clip of [clips] whose words, model or voice changed since its file was made ([only] that one, or
    every one [again]), takes away the files of clips that are gone, and writes the manifest. The Academy's voice
    (tool/academy_voice.py) is made with this too, into its own folder."""
    if only and only not in clips:
        sys.exit(f"No clip called {only}. Clips: {', '.join(clips)}")
    model = pick_model(token)
    out_dir.mkdir(parents=True, exist_ok=True)
    kept = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    files = kept.get("files", {})
    for name, words in clips.items():
        if only and name != only:
            continue
        out = out_dir / f"{name}.mp3"
        was = files.get(name, {})
        if not again and out.exists() and was.get("words") == digest(words) and was.get("model") == model and was.get("voice") == VOICE:
            continue
        print(f"  {name}", flush=True)
        speak(token, model, words, out)
        files[name] = {"words": digest(words), "model": model, "voice": VOICE, "bytes": out.stat().st_size, "seconds": seconds(out)}
        # Written after every clip, so a run stopped halfway keeps what it made.
        write_manifest(manifest_path, made, files)
    # Clips that are gone from the words lose their files too.
    for name in list(files):
        if name not in clips:
            (out_dir / f"{name}.mp3").unlink(missing_ok=True)
            del files[name]
    write_manifest(manifest_path, made, files)
    total = sum(f["bytes"] for f in files.values())
    print(f"{len(files)} files, {total / 1024:.0f} KB, model {model}, voice {VOICE_NAME}")


def write_manifest(manifest_path: pathlib.Path, made: str, files: dict) -> None:
    manifest = {"made": made, "voice": {"id": VOICE, "name": VOICE_NAME}, "files": dict(sorted(files.items()))}
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
