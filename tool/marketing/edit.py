#!/usr/bin/env python3
"""Cuts the marketing video (Matt, 2026-11-02): each scene's pieces of the window recordings (build/marketing/clips),
put on the drifting background by compose.py, crossfaded one into the next, the scene's voice line
(build/marketing/voice) laid in a breath after its first frame. Writes build/marketing/ghost-md.mp4.

    python3 tool/marketing/edit.py            # every piece that is not made yet, then the cut
    python3 tool/marketing/edit.py --again    # every piece made again
"""
import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
M = ROOT / "build" / "marketing"
CLIPS, VOICE, PIECES = M / "clips", M / "voice", M / "pieces"
FADE = 0.5      # each crossfade, in seconds
LEAD = 0.45     # how long after a scene's first frame its line starts
TAIL = 0.9      # the least a scene runs on after its line ends
CHIPS = "30:356:2030:96"   # the workspaces' chips over All notes by folder, in the window's own pixels

# (scene, clip, start, seconds of the clip, speed, blurs)
SEGMENTS = [
    ("01-home", "01-home-raw.mov", 2.2, 9.0, 1.0, []),
    ("02-writing", "02-writing-raw.mov", 2.2, 9.6, 1.0, []),
    ("03-meetings", "03-meetings-raw.mov", 2.0, 8.0, 1.0, []),
    ("04-folders", "04-folders-raw.mov", 2.0, 7.2, 1.0, [CHIPS]),
    ("05-teams", "05-teams-raw.mov", 2.2, 3.6, 1.0, []),
    ("05-teams", "05-teams-raw.mov", 8.6, 5.4, 1.0, []),
    ("06-lovart-header", "06-lovart-header-raw.mov", 2.0, 7.5, 1.0, []),
    ("06-lovart-header", "06-lovart-land-raw.mov", 0.3, 5.5, 1.0, []),
    ("07-lovart-cue", "07-lovart-cue-raw.mov", 6.5, 9.0, 1.6, []),
    ("07-lovart-cue", "07-lovart-cue-raw.mov", 47.0, 4.5, 1.0, []),
    ("08-lovart-moodboard", "08-lovart-moodboard-raw.mov", 2.0, 7.0, 1.4, []),
    ("08-lovart-moodboard", "08-lovart-moodboard-raw.mov", 130.0, 12.0, 1.6, []),
    ("09-market", "09-market-raw.mov", 2.2, 10.5, 1.4, []),
    ("09-market", "09b-plugins-raw.mov", 2.2, 13.5, 1.8, []),
    ("09-market", "09c-add-gantt-raw.mov", 2.5, 6.0, 1.0, []),
    ("10-gantt", "10-gantt-raw.mov", 2.2, 5.0, 1.0, []),
    ("10-gantt", "10-gantt-raw.mov", 10.5, 4.5, 1.0, []),
    ("10-gantt", "10b-board-raw.mov", 1.5, 3.5, 1.0, []),
    ("11-academy", "11-academy-raw.mov", 2.2, 9.5, 1.5, []),
    ("12-close", "12-close-raw.mov", 2.45, 8.0, 1.0, [], "0xfbfbfb"),
]


def seconds(path: pathlib.Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)], capture_output=True, text=True).stdout.strip()
    return float(out)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--again", action="store_true")
    a = p.parse_args()
    PIECES.mkdir(parents=True, exist_ok=True)
    segs = [s for s in SEGMENTS if (CLIPS / s[1]).exists()]
    for s in SEGMENTS:
        if s not in segs:
            print(f"  not recorded yet, left out: {s[1]}")
    # Where each piece starts in the cut, so the background drifts on across it.
    starts, at = [], 0.0
    for i, (_, _, _, dur, speed, *_rest) in enumerate(segs):
        starts.append(at)
        at += dur / speed - FADE
    total = at + FADE
    pieces = []
    for i, ((scene, clip, start, dur, speed, blurs, *bar), phase) in enumerate(zip(segs, starts)):
        out = PIECES / f"{i:02d}-{scene}.mp4"
        pieces.append(out)
        if out.exists() and not a.again:
            continue
        print(f"  piece {i:02d} {scene} ({dur / speed:.1f}s)", flush=True)
        cmd = [sys.executable, str(ROOT / "tool/marketing/compose.py"), str(CLIPS / clip), str(out), "--start", str(start), "--seconds", str(dur), "--speed", str(speed), "--phase", f"{phase:.3f}"]
        for b in blurs:
            cmd += ["--blur", b]
        if bar:
            cmd += ["--bar", bar[0]]
        subprocess.run(cmd, check=True)
    # The scenes' first frames, and how long each runs, to lay the voice in and to say where a line runs long.
    scene_start, scene_len = {}, {}
    for (scene, _, _, dur, speed, *_rest), st in zip(segs, starts):
        scene_start.setdefault(scene, st)
        scene_len[scene] = st + dur / speed - scene_start[scene]
    manifest = json.loads((VOICE / "manifest.json").read_text())["files"]
    for scene, st in scene_start.items():
        line = manifest.get(scene, {}).get("seconds", 0)
        if line + LEAD + TAIL > scene_len[scene]:
            print(f"  ! {scene}: its line ({line:.1f}s) runs past its pictures ({scene_len[scene]:.1f}s)")
    # The pictures: every piece crossfaded into the next.
    inputs, graph, last = [], [], "[0:v]"
    for i, piece in enumerate(pieces):
        inputs += ["-i", str(piece)]
    for i in range(1, len(pieces)):
        offset = starts[i]
        graph.append(f"{last}[{i}:v]xfade=transition=fade:duration={FADE}:offset={offset:.3f}[x{i}]")
        last = f"[x{i}]"
    graph.append(f"{last}fade=t=in:st=0:d=0.6,fade=t=out:st={total - 0.8:.3f}:d=0.8,format=yuv420p[v]")
    # The voice: each line at its scene's start, together, a little under full scale.
    n = len(pieces)
    voices = []
    for scene, st in scene_start.items():
        f = VOICE / f"{scene}.mp3"
        if f.exists():
            inputs += ["-i", str(f)]
            k = n + len(voices)
            ms = int((st + LEAD) * 1000)
            graph.append(f"[{k}:a]aresample=48000,adelay={ms}|{ms},apad[a{len(voices)}]")
            voices.append(f"[a{len(voices)}]")
    graph.append(f"{''.join(voices)}amix=inputs={len(voices)}:normalize=0,atrim=duration={total:.3f},loudnorm=I=-16:TP=-1.5:LRA=11[a]")
    out = M / "ghost-md.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(graph), "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(out)], check=True)
    print(f"{out}: {total:.1f}s")


if __name__ == "__main__":
    main()
