#!/usr/bin/env python3
"""Puts a window recording on the marketing video's background (Matt, 2026-11-02: "instead of making the app 16:9 make
it a more square aspect ratio and use a nice gradient background ... i want it to have subtle animations"): a 1920x1080
frame of a slowly drifting gradient, the 4:3 window centred on it with rounded corners and a soft shadow.

    python3 tool/marketing/compose.py <clip.mov> <out.mp4> [--seconds N] [--start S] [--phase P]

--phase offsets the gradient's drift, so consecutive scenes continue the motion instead of starting it again.
"""
import argparse
import subprocess

W, H = 1920, 1080
WIN_H = 900
WIN_W = WIN_H * 4 // 3          # 1200
X, Y = (W - WIN_W) // 2, (H - WIN_H) // 2 + 6
R = 26                          # the corner's radius
# Ghost's evening: deep ink-violet to violet, rose and a warm ember, drifting slowly.
COLOURS = ["0x140f2e", "0x3a2580", "0x9a3f8f", "0xe0785a"]


def mask_expr(r: int) -> str:
    return (f"if(lte(pow(max(max({r}-X\\,X-(W-1-{r}))\\,0)\\,2)+pow(max(max({r}-Y\\,Y-(H-1-{r}))\\,0)\\,2)\\,{r*r})\\,255\\,0)")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("clip")
    p.add_argument("out")
    p.add_argument("--seconds", type=float)
    p.add_argument("--start", type=float, default=0)
    p.add_argument("--phase", type=float, default=0, help="seconds into the background's drift")
    p.add_argument("--speed", type=float, default=1.0, help="play the clip this much faster")
    p.add_argument("--blur", action="append", default=[], help="x:y:w:h in the clip's own pixels, blurred (a name that should not be shown)")
    p.add_argument("--bar", default="0x020202", help="the header's colour, painted over the capture badge macOS puts where the window's buttons are")
    a = p.parse_args()
    dur = a.seconds or float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", a.clip], capture_output=True, text=True).stdout.strip()) - a.start
    out_dur = dur / a.speed
    cols = ":".join(f"c{i}={c}" for i, c in enumerate(COLOURS))
    bg = f"gradients=s={W}x{H}:r=60:{cols}:nb_colors={len(COLOURS)}:speed=0.0035:type=spiral:seed=7:d={out_dur + a.phase + 1}"
    shadow_pad = 120
    blurs = []
    for i, box in enumerate(a.blur):
        x, y, w, h = box.split(":")
        blurs.append(f"[c{i}]split[c{i}a][c{i}b];[c{i}b]crop={w}:{h}:{x}:{y},boxblur=22:3[c{i}z];[c{i}a][c{i}z]overlay={x}:{y}[c{i+1}]")
    graph = ";".join([
        # The background, its drift begun at the phase, with a little grain so the gradient never bands.
        f"[1:v]trim=start={a.phase},setpts=PTS-STARTPTS,noise=alls=3:allf=t,format=yuv420p,format=rgba[bg]",
        # The rounded corners' mask, and from it the shadow: black, blurred, see-through.
        f"color=black:s={WIN_W}x{WIN_H}:r=60:d={out_dur},format=gray,geq=lum='{mask_expr(R)}'[m0]",
        "[m0]split[m1][m2]",
        f"[m2]pad={WIN_W + 2 * shadow_pad}:{WIN_H + 2 * shadow_pad}:{shadow_pad}:{shadow_pad}:black,boxblur=48:2,lutyuv=y='val*0.55'[sa]",
        f"color=black:s={WIN_W + 2 * shadow_pad}x{WIN_H + 2 * shadow_pad}:r=60:d={out_dur},format=rgba[sb]",
        "[sb][sa]alphamerge[shadow]",
        # The window, scaled down sharply, its corners rounded.
        f"[0:v]trim=start={a.start}:duration={dur},setpts=(PTS-STARTPTS)/{a.speed},fps=60,drawbox=x=6:y=6:w=150:h=52:color={a.bar}:t=fill[c0]",
        *blurs,
        f"[c{len(a.blur)}]scale={WIN_W}:{WIN_H}:flags=lanczos,format=rgba[w0]",
        "[w0][m1]alphamerge[win]",
        f"[bg][shadow]overlay={X - shadow_pad}:{Y - shadow_pad + 22}:shortest=1[b1]",
        f"[b1][win]overlay={X}:{Y}:shortest=1,format=yuv420p[v]",
    ])
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", a.clip, "-f", "lavfi", "-i", bg, "-filter_complex", graph, "-map", "[v]",
           "-t", f"{out_dur}", "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+faststart", a.out]
    subprocess.run(cmd, check=True)


if __name__ == "__main__":
    main()
