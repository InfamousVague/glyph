#!/usr/bin/env python3
"""Speaks the plugins' setup steps with ElevenLabs, once, at build time, when there is to be a voice for them (Matt,
2026-10-28: "For each of the plugins add a small onboarding flow"). Not run yet: the steps are read, not heard, and
nothing in the app plays these files until the folder is added to pubspec.yaml's assets.

The walkthrough's tool (tool/onboarding_voice.py) does the work, with its model (Eleven v4, as GET /v1/models names
it), its voice (Jessica) and its file (mono, 64 kbps, the silence trimmed), as tool/academy_voice.py has it: this only
says where the words are, lib/plugins/onboarding/setup_voice.dart's `setupVoice`, one `'<plugin>-<step>': '<words>',`
a line (and `-simple` for Simple's shorter words), and where its files go, assets/plugin-setup/<name>.mp3 with
assets/plugin-setup/narration.json.

The key is read from ~/.elevenlabs-key as the walkthrough's tool reads it: never an argument, never printed.

    python3 tool/plugin_setup_voice.py --list           # the clips and their words, no key needed
    python3 tool/plugin_setup_voice.py                  # every clip whose words or voice changed
    python3 tool/plugin_setup_voice.py --clip lovart-intro --again
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import onboarding_voice as voice  # noqa: E402

WORDS = voice.ROOT / "lib" / "plugins" / "onboarding" / "setup_voice.dart"
OUT = voice.ROOT / "assets" / "plugin-setup"
MANIFEST = OUT / "narration.json"

# `  'lovart-intro': 'Lovart is a design agent …',` inside `setupVoice`.
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
            print(f"{name:<22} {len(words):>4}  {words}")
        print(f"{len(found)} clips, {sum(len(w) for w in found.values())} characters")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    voice.make(voice.key(), found, OUT, MANIFEST, made="tool/plugin_setup_voice.py", only=args.clip, again=args.again)


if __name__ == "__main__":
    main()
