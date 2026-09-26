# From microphone to Markdown

_One recording, from the held side key to a note on disk: what opens first, what decides a phrase, what only shows, and what Done writes._

The recorder is `src/app/capture/CaptureScreen.tsx`. It ties together a microphone, a transcriber, a take and a writer, and each is its own module. This chapter follows one recording through them. What the words mean as commands is the next chapter.

## The microphone opens first

A held side key opens the recorder, and the first words of a voice note are usually its subject. So `useCaptureSession.ts` opens the microphone before anything else is ready, and the model loads while it listens. Samples heard in the meantime are held in an array and replayed into the session the moment it exists.

A start that is called off, by React's development double start or a screen closed at once, stops its own microphone. Left running, it would feed the next session a second copy of every chunk.

`audio.ts` captures in the page with `getUserMedia`, not in Kotlin or Rust. It asks the `AudioContext` for 16 kHz, so Chromium resamples the hardware's 48 kHz properly. If a WebView ignores the request, `createResampler` brings the samples to 16 kHz itself: 48 kHz audio labelled 16 kHz reaches Whisper as slowed speech and comes back as nothing. An `AudioWorklet`, loaded from a Blob URL, hands over chunks of 3,200 samples, which is 200 ms. Noise suppression and gain control are on. Echo cancellation is off, because it can clip the first syllable.

## One interface, three engines

`engine.ts` puts every transcriber behind one `CaptureSession`: `push`, `positionMs`, `stop` and `cancel`. `startCapture` picks the engine.

| Engine | Chosen when | Keeps audio | Final transcript |
|---|---|---|---|
| `whisper` | In the app | Yes, on native generation 6 or later | Yes, from `capture_stop`, on the same generations |
| `browser` | A desktop browser with `webkitSpeechRecognition` | No | No |
| `simulated` | `?simulate` in the URL (`simulated.ts`) | A length only | No |

`simulated.ts` speaks fixed scripts on a clock, partials first and then a committed phrase, which is the rhythm Whisper has. `?simulate=say&say=a|b` speaks any phrases given, so the screen can be tried with no microphone.

## Across the bridge

`src-tauri/src/capture_commands.rs` is the seam, and its header is the contract: `capture_start`, then `capture_push` repeatedly, then `capture_stop` or `capture_cancel`. `capture://partial`, `capture://segment` and `capture://error` come back as events.

Two rules are the page's to keep. Each push waits for the one before it, because on Android two invokes in flight can run in either order, and PCM applied out of order is noise. And no push goes before `capture_start` resolves. Each chunk travels as base64 in `{ pcm }`, because Android's WebView gives Rust no request body and raw bytes never arrived. A module-level `owner` symbol in `engine.ts` stops a replaced session pushing into the live one.

The loaded model stays in `CaptureState` for the life of the process, about 60 MB resident, so no press after the first waits for a load. The contract also lists `capture_rewind` and `transcribe_wav`; nothing on the page calls either.

## Phrases are decided by the audio

`whisper/worker.rs` is a thread that wakes at least every 100 ms, takes whatever audio has arrived, and feeds `whisper/stream.rs`. The streamer is a state machine with no clock and no model of its own. It classifies every 20 ms frame as it is fed, so a commit depends on the audio alone, never on when the timer fired. Only partials depend on timing.

| Rule | Value |
|---|---|
| A pause ends a phrase | 600 ms after at least 1.5 s of speech, or 1.2 s after any |
| Where the cut goes | The middle of the pause: 300 ms of quiet each side |
| The longest phrase | 20 s, then a cut at the quietest 200 ms of the last 4 s |
| Silence | Dropped after 2 s, keeping 300 ms, and never sent to the model |
| A partial | 1 s of uncommitted speech, 700 ms of new audio, some of it speech |
| The prompt | The cue vocabulary, then up to 200 characters of committed text |

`whisper/vad.rs` finds speech by energy against the room, which is the quietest frame of the last three seconds. A frame is voiced at 10 dB over the room, and never under -50 dBFS. The file says plainly that the 10 dB threshold has not yet been measured on the phone's microphone. The streamer then counts speech only after two voiced frames in a row (`ONSET_FRAMES`, 40 ms), so a tap on the glass is not a word.

`whisper/engine.rs` runs whisper.cpp greedy, with no carried context, and hands the prompt over as tokens. A window under a second is padded with silence rather than lost. Partials skip timestamps and the temperature fallback. Commits keep both, because commits are the words that stand.

## A phrase only shows

Every committed phrase goes to `take.listen` in `take.ts`. It joins the take's segments and is drawn. It does not route, write a note or call a model. Partials are only drawn too.

The page is `takeMarkdown`, which runs `renderNote` in `markdown.ts` over every phrase so far, on every event. What the page shows and what Done saves are the same function, so they cannot disagree.

`markdown.ts` is the driver. It groups phrases into paragraphs, splits sentences, and passes each through the rule families in `capture/spoken/`: `inline.ts` for marks said around words, `blocks.ts` for the cues that make a sentence a block, and `lists.ts`, `numbers.ts`, `codeBlocks.ts` and `extras.ts` for the rest. "Bold … end bold" is matched across a whole paragraph, because Whisper turns each pause into a full stop. A cue said alone, like "Heading." before a pause, is held for the next sentence (`STANDALONE_CUE` in `spoken/blocks.ts`). That also guards against Whisper echoing its prompt on silence: an echoed "Bullet point." waits for a sentence that never comes. [[Saying the marks]] lists the cues.

A paragraph breaks at "new paragraph", or at a pause. `PARAGRAPH_GAP_MS` is 1,500 ms, but it is measured between committed phrases, not in the room. The streamer keeps 300 ms of each pause and drops quiet in two-second pieces, so a spoken pause of about 2.3 s or more arrives as a gap of 1.7 s or more, and a shorter one as no gap at all.

## The tape

The note id is chosen as the recorder opens (`takeWriter.ts`): a fresh one for a new recording, or the note's own when you speak into it. The audio is kept under that id.

In the code, Rust holds the recording in memory, as 16-bit PCM inside the streamer, about 1.9 MB a minute. It is written only at stop: `capture_stop` with `recordAs` writes `recordings/<id>.wav` under the app's data directory, on the end of the file when `append` is set. The headers of `CaptureScreen.tsx` and `takeWriter.ts` say the sound is kept from the first second. It is not yet. A process killed mid-recording loses the take, words and sound, because nothing of it is written before Done. The one exception is New note, on a note being spoken into: it writes the words so far into that note and carries on in a fresh one.

A take said into a note that already has a tape goes on the end of that note's file (`appendsTo` in `timeline.ts`). `onTape` shifts the take's phrases, command spans and voice memo marks by the tape's existing length, so words and sound share one timeline. `recordings.rs` confines every id to a plain name and serves the file through the `rec` scheme (`http://rec.localhost/<id>.wav` on Android) with byte ranges, so the player can seek. `tape.ts` is only the tape's geometry and its counter: two reels whose packs grow and shrink as square roots, drawn by `tapes/TapeArt.tsx`.

## Done

`finish` in `CaptureScreen.tsx` runs from Done, the back gesture, the side key held again, the screen going off, or the quiet stop. In order:

1. The microphone stops, and `session.stop` calls `capture_stop`. Rust drains the last audio, commits it, and answers with the whole transcript.
2. `withFinalWords` in `finalWords.ts` adds what that transcript says past the committed phrases as one more phrase, when it carries on from them word for word. Phrase events can still be in flight when the listeners go.
3. `readInstruction` reads the transcript, once. The next chapter is about that.
4. The words are written: `writer.persist` inside `writer.queue`, a `create_note` for a new note or a revision-checked `update_note` for a continued one.

Every write the recorder makes to a note's words joins one chain, `TakeWriter.queue`, which runs them in turn. A continued note's own text is read once into a promise (`baseBody`), so two writes never compose onto each other's words. The exceptions are a confirmed command's write, which calls `applyCommandMutation` directly and relies on its revision check, and the tape's length and phrases, which `setNoteRecording` stores.

A take with nothing in it leaves nothing. `take.hasContent` asks the laid-out note, not the transcript, so a cue said alone makes no note.

The endings that keep no words let the sound go through one rule, `letGo` (DESIGN §123), the one a take that said nothing already followed. A take on a file of its own, a new recording's, has that file removed. A take on the end of a continued note's own tape stays, because that file is the whole of the note's recording; the note is told the tape's new length, with its phrases as they were. Before §123, three endings deleted a note's entire recording and a fourth moved it onto another note.

## The quiet stop, and better words later

"Stop when I go quiet" (Settings, Recording) is `quiet.ts`. It watches the microphone's level against a floor that follows the room, and the words as they come back. Nothing stops before the first word. Four seconds of quiet after it (`QUIET_STOP_MS`, in `CaptureScreen.tsx`) and the take saves itself.

The live model is small and fast. With Better words on (Settings, Recording) and a binary of native generation 7 or later, `refine.ts` queues a job after Done for the larger `small.en` to go over the take's stretch of the tape (`capture_refine` in `capture_commands/refine.rs`). The queue lives in localStorage, runs one job at a time, never while the recorder or a review is on screen, and resumes on the next launch. `capture_start` aborts a pass in progress within one graph computation. The better words replace the note's only if it still reads exactly as Done saved it; the tape's phrases are replaced either way. When the review after a recording runs, it does this pass itself (`listenAgain`).

## What Android adds

The side key reaches the app through the assistant role: `GlyphInteractionService.kt` and `GlyphSessionService.kt` under `src-tauri/gen/android`. Holding the key again during a take bumps a stop count (`shell/useCaptureRoute.ts`), which `finish` answers. On native generation 12, `setCapturing` in `core/host.ts` keeps the screen on while recording, and `MainActivity.kt` listens for `ACTION_SCREEN_OFF`. A quick press of the side key turns the screen off, which is the only sign of that key Android gives an app, and the page saves the take as Done would.

## Read next

- [[Reading a command, writing it safely]]
- [[The engines on the device]]
- [[The library on disk]]
