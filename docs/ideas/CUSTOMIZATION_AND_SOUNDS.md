# Customization ideas, and sounds

Matt, 2026-10-27: "theorize new customization features we can add as well as notification sounds on mobile and
desktop I can generate with elevenlabs". Ideas only: nothing here is built. What exists today is the starting line:
theme, accent, density, rounding, text size, the interface and note faces, icon packs and styles, five top bars,
home layouts, the sidebar's style, UI scale, code themes, motion speed, ghostly typing, the edges' blur and
ripples. There are no interface sounds at all.

Every idea below is a Market item or a row in Settings › Appearance, so it follows the pattern the themes, fonts and
icon packs set: a card to try, a switch to keep, synced with the account.

## Customization

### Look of the page
1. **Paper.** The page's ground as a material: plain, ruled, dotted, grid, or a faint paper grain (light) and slate
   (dark). Per notebook too, so a journal can be ruled and a project grid. Cheap: a painter under the editor.
2. **Margins and measure.** The note's column width (narrow, book, wide) and its margins, separate from text size.
   Readers who like a book's measure get one on the Fold opened out.
3. **Heading style.** How `#` headings look: the face's bold, a serif display face, small caps, or underlined with
   the accent. A Market "type set": a body face, a heading face and a code face chosen together.
4. **Checkbox and bullet sets.** Round or square boxes, a tick or a cross when done, bullets as dots, dashes or the
   ghost's dot. Small, and the thing people notice most in a to-do app.
5. **Highlight inks.** The highlighter's colours as a set (pastel, neon, pencil), and which one `==` gives.

### The ghost and the app's character
6. **Ghost moods.** The mascot's scenes (empty pages, the recorder, the update card) in alternate sets: the dotwork
   ghost, a line-drawn one, a pixel one, or none. A Market shelf of its own.
7. **App icon.** Alternate launcher and Dock icons (Android's activity-alias, macOS's dock tile): the ghost, the
   outline, a seasonal one. People pay for this in other apps.
8. **Seasonal touches.** Off by default: a little snow on the header in December, leaves in autumn. Driven by the
   date and Reduce motion.

### Layout and navigation
9. **Dock editor.** Choose and order the floating dock's buttons (Claude, search, +, mic, Market, Settings), and
   which sit on the phone versus the Fold. The dock is now fixed; this is the most-asked kind of setting in apps with
   one.
10. **Home sections.** Show, hide and order the home page's sections (pinned, to do, meetings shelf, recent,
    journal), not only pick a layout.
11. **Swipe actions.** What a swipe left or right on a note card does: archive, pin, Trash, move to a workspace.
12. **Per-workspace looks.** A workspace or organization can carry its own accent and paper, so HelloTrade looks
    like work and Family like home without changing the theme by hand.

### Writing
13. **Typing feel.** The caret's shape (bar, block, underline), its blink, and a smooth caret that glides between
    letters. Pairs with ghostly typing.
14. **Focus mode.** Dim every paragraph but the one being written, with a typewriter scroll that keeps the line in
    the middle.
15. **Snippets.** Personal text expansions (`;sig`, `;addr`, today's date in a format) in Settings, offered on the +.

### Everything above as a bundle
16. **Profiles.** A saved set of the above (theme, faces, icon pack, paper, dock, sounds) under a name, "Work" and
    "Night", switched from the command palette or automatically by time of day or focus mode on the phone.

## Sounds

A new **Settings › Sounds** section and a **Sound packs** shelf in the Market, like icon packs. One pack is three
things: interface sounds (inside the app), notification sounds (what the phone or the Mac plays for Ghost.md's
notifications), and the recorder's start and stop.

### What makes a sound
| Event | Where | Length | Notes |
| --- | --- | --- | --- |
| Note saved after a long session, or synced | in-app | under 0.3 s | very quiet; off by default |
| To-do ticked | in-app | under 0.25 s | the one people keep on |
| All to-dos ticked (the ghost's moment) | in-app | about 1 s | small flourish |
| Recording starts | in-app and lock screen | under 0.4 s | must be heard before speech begins |
| Recording stops | in-app | under 0.4 s | the start's answer, falling |
| A summary or write-up is ready | notification | about 1 s | the main notification sound |
| A reminder is due | notification | 1 to 1.5 s | more insistent than the summary's |
| A meeting is starting, Ghost is joining | notification | about 1 s | |
| A comment or mention from the team | notification | under 1 s | |
| Lovart's picture is ready | notification and in-app | under 1 s | |
| Something failed | in-app | under 0.4 s | low, soft, never alarming |

### Packs to generate (ElevenLabs Sound Effects)
Each pack is the same eleven sounds in one voice. Prompts to start from: generate several takes, keep the cleanest,
then trim and normalise (below).

- **Ghostly** (the default, the app's character): "soft breathy airy whoosh, like a gentle exhale through a paper
  tube, warm, no reverb tail, 0.3 seconds". The tick: "a single soft paper tap with a faint airy shimmer". The
  write-up ready: "two soft rising glassy tones with a breathy airy swell, calm and friendly, 1 second". The
  reminder: "three gentle wooden marimba notes rising, warm and clear, 1.2 seconds".
- **Paper**: pencil and paper sounds. "a single short pencil tick on paper", "a page turning softly", "a paper fold
  and crease, crisp, 0.4 seconds".
- **Glass**: clean glassy taps and chimes, for the light themes. "a tiny clear glass tap, high, short", "two crystal
  chimes rising, airy".
- **Analog**: the cassette shelf's world. "a cassette deck play button clunk, mechanical, 0.3 seconds" for record
  start, "a cassette stop button click and tape hiss fade" for stop.
- **Quiet**: the same events, half as loud and half as long, for an office.

Prompt habits that help: say "single", "short" and the length in seconds; say "no reverb tail" or "dry"; name the
material (paper, glass, wood); and generate interface sounds and notification sounds as separate takes, since a
notification must be louder and longer than a tap.

### Delivering them
- **Files.** Mono, 44.1 kHz, peaks at about -3 dBFS for notifications and -12 dBFS for interface sounds, silence
  trimmed to 5 ms at each end. A pack of eleven is about 300 KB as Ogg Opus.
- **Android.** A notification's sound belongs to its channel and cannot be changed once the channel exists, so a
  pack is a set of channels (`summaries-ghostly`, `summaries-paper`): switching pack moves the app's posts to the
  new pack's channels. Files in `res/raw` as `.ogg`. Interface sounds through `SoundPool` for no lag.
- **iPhone and Mac.** Notification sounds are bundled `.caf` or `.aiff`, 30 seconds at most, named in each
  notification's content. Interface sounds through `AVAudioPlayer`, primed when the app opens.
- **Respect the phone.** Interface sounds follow the ringer switch and Do Not Disturb, never play under a recording
  or a call, and the recorder's start and stop are the only ones on by default. A volume slider for the in-app
  sounds alone.
- **Market.** Each pack's card plays its sounds when tapped, as a font card shows its letters.

### Order to build in
1. Settings › Sounds with the to-do tick and the recorder's start and stop, Ghostly only.
2. Notification sounds for write-ups and reminders on Android and the Mac, Ghostly only.
3. The other packs in the Market.
4. Profiles, so a pack goes with a theme.
