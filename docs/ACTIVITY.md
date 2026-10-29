# Activity: what the app is doing, shown

Matt, 2026-10-29: "Let's theorize how we can improve the flow of things in the app, better show users what background
processes are happening with vivid colors and iconography and more", then "Do them all", with his answers to each
choice below. Built straight (no mockup, no developer switch) and shipped all at once.

## The decisions

| Item | Choice |
|---|---|
| Colour | Vivid by default while work runs; the app is monochrome at rest. A **Calm** setting (Settings › Appearance) turns the colours to ink and keeps the motion. |
| Palette | Drawn from the Market's plugin tile gradients, so a plugin's work wears its tile's colour (Lovart amber-pink, Meet orange). Light and dark tuned for contrast. |
| Kinds | Sync blue, AI writing violet, images amber-pink, audio teal, meetings orange, downloads/updates green, needs-you red (still), waiting grey (dimmed, still). |
| Motion | Gentle and purposeful: reels turn (audio), the brush draws (images), arrows circle (sync), the sparkle shimmers (AI), a people glyph pulses (meetings), a ring fills (downloads). Reduced motion stops it. |
| The record | One record of running work: `lib/core/background_jobs.dart` grows from the device hint into the app's registry. Every job: kind, title, state (queued, running, waiting, done, failed), progress (fraction or indeterminate), what it waits on (Wi-Fi, charger, credits, your Mac, sign-in), Stop, Open result, device it runs on. |
| Jobs on it | All of them: banners, summaries and write-ups, own and team sync, recording, transcription and Better words, share uploads, model and update downloads, Slack posts, ElevenLabs read-alouds, Notion/GitHub/Calendar fetches, the Meet/Zoom bot. |
| Ring | In the header, beside You, in every header version: one arc per running job in its colour. Gone when idle; one bloom when all finish. A still red dot when something needs you. |
| Tray | A card hanging under the ring (as History's does); a sheet on a phone. Live rows (icon, title, live line, progress, Stop/Open), then **Today** ("3 summaries, 12 banners, 40 notes synced, 1 failed"), then **Past 7 days** behind More. |
| In place | Banner shimmer where the banner will land; "Writing the summary…" streaming into the meeting note; per-note sync marks (blue arrow → tick) in lists and the note's header; upload progress on share rows, pictures and recordings. |
| Results | A result chip slides in from the edge ("Banner ready · View"), replacing most toasts; a batch gives one chip. |
| Other devices | In the tray, labelled with the device ("Writing on your Mac", its icon); in the ring, slightly dimmed. |
| Cost | Jobs over about 20 credits or 2 minutes ask first ("12 banners · ~72 Lovart credits · ~4 min", Start / Cancel); smaller ones just run, with the estimate in the tray and a live credit count. |
| Failures | Red row with the cause in plain words and one fix (Top up, Sign in again, Retry); network blips retry on their own. |
| Sound | A soft chime and a light tap when a job the person started and that ran over ~30 s finishes; nothing for sync or small jobs; off with the app's sounds setting. |
| OS surfaces | Android progress notifications (and Samsung's Now Bar where offered) for recording, write-ups, banner runs and uploads; the Mac's Dock icon progress ring and badge; a Mac menu bar item with the ring and a mini tray; iPhone Live Activities (Dynamic Island, lock screen) for write-ups and uploads. |
| Simple mode | The ring, tray, chips and in-place marks all show; the tray's Past 7 days and per-device detail sit behind More. |
