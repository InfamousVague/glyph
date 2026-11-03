#!/usr/bin/env python3
"""The marketing video's voiceover (Matt, 2026-11-02: "make a marketing video scrolling through the app smoothly with
transitions and crossfades and elevenlabs voiceovers"): one clip per scene, spoken by the walkthrough's voice
(Jessica, Eleven v4) with tool/onboarding_voice.py's own code, so the key is read the same way, from
~/.elevenlabs-key, and never printed. Writes build/marketing/voice/<scene>.mp3 and its manifest.

    python3 tool/marketing/voice.py            # every scene whose words changed
    python3 tool/marketing/voice.py --again    # all of them
"""
from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))
import onboarding_voice as ov  # noqa: E402

OUT = ROOT / "build" / "marketing" / "voice"

SCENES = {
    "01-home": "This is Ghost Markdown. Your notes, your meetings and your ideas, in one calm place.",
    "02-writing": "Write in plain markdown and watch it come alive as you type. Headings, to-dos, tables. Just text, and it's yours.",
    "03-meetings": "Invite Ghost to your Google Meet or Zoom calls. It takes the notes, so you can stay in the conversation.",
    "04-folders": "Everything stays organised, and it's all plain files you can back up anywhere.",
    "05-teams": "Bring your team in. Shared docs, a page tree, and everyone's edits, live.",
    "06-lovart-header": "Ghost works with the tools you love. Lovart draws a header for every note, in a style that's yours.",
    "07-lovart-cue": "Type an image cue, and Lovart paints it right where you wrote it.",
    "08-lovart-moodboard": "Need a spark? Ask for a moodboard, and four fresh directions appear.",
    "09-market": "The Market has a plugin for everything, from Claude and Figma to Notion and GitHub. Each one is a single switch.",
    "10-gantt": "Turn on Gantt, and your project plan becomes a timeline you can drag.",
    "11-academy": "And Ghost Academy teaches you every trick, one lesson at a time.",
    "12-close": "Ghost Markdown. Notes that listen. Get it at ghost markdown dot com.",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--again", action="store_true")
    parser.add_argument("--scene")
    args = parser.parse_args()
    ov.make(ov.key(), SCENES, OUT, OUT / "manifest.json", made="tool/marketing/voice.py", only=args.scene, again=args.again)


if __name__ == "__main__":
    main()
