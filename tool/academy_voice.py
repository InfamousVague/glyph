#!/usr/bin/env python3
"""Speaks the Academy's words with ElevenLabs, once, at build time (Matt, 2026-10-28: "Add the voiceover to the
academy sections").

The walkthrough's tool (tool/onboarding_voice.py) does the work, with its model (Eleven v4, as GET /v1/models names
it), its voice (Jessica) and its file (mono, 64 kbps, the silence trimmed): this only says where the Academy's words
are, lib/academy/voice.dart's `academyVoice`, one `'<name>': '<words>',` a line, and where its files go,
assets/academy/<name>.mp3 with assets/academy/narration.json. test/academy/voice_test.dart fails when an entry's words
have changed and its file has not been made again.

The key is read from ~/.elevenlabs-key as the walkthrough's tool reads it: never an argument, never printed.

    python3 tool/academy_voice.py --list           # the clips and their words, no key needed
    python3 tool/academy_voice.py                  # every clip whose words or voice changed
    python3 tool/academy_voice.py --clip bold --again
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import onboarding_voice as voice  # noqa: E402

WORDS = voice.ROOT / "lib" / "academy" / "voice.dart"
OUT = voice.ROOT / "assets" / "academy"
MANIFEST = OUT / "narration.json"

# `  'bold': 'Put two stars …',` inside `academyVoice`; the names of `chapterVoiceNames` have spaces, and are not read.
PATTERN = r"^\s*'([\w-]+)':\s*'((?:[^'\\]|\\.)*)',\s*$"


def clips() -> dict[str, str]:
    found = {}
    for name, said in re.findall(PATTERN, WORDS.read_text(), flags=re.MULTILINE):
        found[name] = said.replace("\\'", "'").replace("\\$", "$")
    if not found:
        sys.exit(f"No words found in {WORDS}.")
    return found


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--clip", help="one clip by name, else every clip")
    parser.add_argument("--again", action="store_true", help="speak clips whose file is already up to date")
    parser.add_argument("--list", action="store_true", help="print the clips found and stop, without a key")
    args = parser.parse_args()
    found = clips()
    if args.list:
        for name, words in found.items():
            print(f"{name:<16} {len(words):>4}  {words}")
        print(f"{len(found)} clips, {sum(len(w) for w in found.values())} characters")
        return
    voice.make(voice.key(), found, OUT, MANIFEST, made="tool/academy_voice.py", only=args.clip, again=args.again)


if __name__ == "__main__":
    main()
