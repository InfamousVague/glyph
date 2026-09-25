//! The streamer driven one 250 ms chunk at a time with a transcriber that
//! counts its calls and never loads a model: what is committed, when, and what
//! the model is never asked.

use super::*;
use crate::whisper::SAMPLE_RATE;

/// Answers every window with a word per second of audio it was given, and
/// remembers every call - so a test can say exactly what the model would
/// have been asked, and prove what it was never asked.
#[derive(Default)]
struct Counting {
    calls: Vec<(usize, Pass)>,
    prompts: Vec<String>,
}

impl Transcribe for Counting {
    fn transcribe(&mut self, audio: &[f32], prompt: &str, pass: Pass) -> Result<String, String> {
        self.calls.push((audio.len(), pass));
        self.prompts.push(prompt.to_string());
        let words = (audio.len() / SAMPLE_RATE).max(1);
        Ok(vec!["word"; words].join(" "))
    }
}

/// Syllables: 160 ms of loud noise, 60 ms of a dip, repeated - speech as
/// the VAD sees it, with the gaps between syllables that keep the room
/// honest.
fn speech(ms: usize) -> Vec<f32> {
    let mut state = 0x2545_f491_u32;
    (0..ms_to_samples(ms as u64))
        .map(|i| {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            let noise = (state as f32 / u32::MAX as f32) * 2.0 - 1.0;
            let in_dip = (i % ms_to_samples(220)) >= ms_to_samples(160);
            noise * if in_dip { 0.004 } else { 0.2 }
        })
        .collect()
}

fn silence(ms: usize) -> Vec<f32> {
    vec![0.0; ms_to_samples(ms as u64)]
}

/// Feeds `audio` in 250 ms chunks, ticking after each, the way the worker
/// does - and returns every event, finish included.
fn run(streamer: &mut Streamer<Counting>, audio: &[f32]) -> Vec<Event> {
    let mut events = Vec::new();
    for chunk in audio.chunks(ms_to_samples(250)) {
        streamer.feed(chunk);
        events.extend(streamer.tick().unwrap());
    }
    events.extend(streamer.finish().unwrap());
    events
}

fn segments(events: &[Event]) -> Vec<&Segment> {
    events
        .iter()
        .filter_map(|e| match e {
            Event::Segment(s) => Some(s),
            _ => None,
        })
        .collect()
}

#[test]
fn silence_never_reaches_the_model_and_is_not_hoarded() {
    let mut streamer = Streamer::new(Counting::default());
    let mut events = Vec::new();
    let mut most_held = 0;
    for chunk in silence(30_000).chunks(ms_to_samples(250)) {
        streamer.feed(chunk);
        events.extend(streamer.tick().unwrap());
        most_held = most_held.max(streamer.audio.len());
    }
    events.extend(streamer.finish().unwrap());
    assert!(events.is_empty(), "{events:?}");
    assert!(
        streamer.transcriber.calls.is_empty(),
        "thirty seconds of silence cost {} inferences; it must cost none",
        streamer.transcriber.calls.len()
    );
    // Thirty seconds is 480,000 samples; a person who presses the key and
    // then thinks for a minute must not be paying for it in memory.
    assert!(most_held <= SILENCE_DROP + ms_to_samples(250), "held {most_held} samples");
}

#[test]
fn a_pause_after_a_phrase_commits_it_and_the_cut_is_in_the_pause() {
    let mut streamer = Streamer::new(Counting::default());
    let mut audio = silence(500);
    audio.extend(speech(2_400));
    audio.extend(silence(1_000));
    audio.extend(speech(2_400));
    audio.extend(silence(500));
    let events = run(&mut streamer, &audio);

    let segs = segments(&events);
    assert_eq!(segs.len(), 2, "{events:?}");
    // The first cut sits 300 ms into the 1 s pause that starts at 2.9 s,
    // give or take the 20 ms a frame is and the 160 ms dip that ends a
    // syllable.
    assert_eq!(segs[0].start_ms, 0);
    assert!((3_000..=3_260).contains(&segs[0].end_ms), "{:?}", segs[0]);
    assert_eq!(segs[1].start_ms, segs[0].end_ms, "segments must tile, never overlap");
    assert_eq!(streamer.transcript(), format!("{} {}", segs[0].text, segs[1].text));
}

#[test]
fn every_window_is_prompted_with_the_cue_vocabulary_then_what_was_committed() {
    let mut streamer = Streamer::new(Counting::default());
    let mut audio = silence(500);
    audio.extend(speech(2_400));
    audio.extend(silence(1_000));
    audio.extend(speech(2_400));
    audio.extend(silence(500));
    let events = run(&mut streamer, &audio);
    let first = segments(&events)[0].text.clone();

    let prompts = &streamer.transcriber.prompts;
    assert_eq!(prompts[0], text::prompt("", PROMPT_CHARS), "nothing committed yet");
    let after = text::prompt(&first, PROMPT_CHARS);
    assert!(prompts.contains(&after), "{prompts:#?}");
    assert!(prompts.iter().all(|p| p.starts_with(text::CUE_VOCABULARY)), "{prompts:#?}");
}

#[test]
fn partials_appear_while_talking_and_are_cleared_when_their_audio_commits() {
    let mut streamer = Streamer::new(Counting::default());
    let mut audio = speech(4_000);
    audio.extend(silence(1_500));
    let events = run(&mut streamer, &audio);

    let partials: Vec<&Partial> = events
        .iter()
        .filter_map(|e| match e {
            Event::Partial(p) => Some(p),
            _ => None,
        })
        .collect();
    assert!(partials.len() >= 3, "4 s of speech should show several guesses: {events:?}");
    // The last word on the partial line after a commit is the empty one:
    // otherwise the page shows the committed text twice.
    let last_segment = events.iter().rposition(|e| matches!(e, Event::Segment(_))).unwrap();
    let after: Vec<&Event> = events[last_segment..].iter().collect();
    assert!(
        matches!(after.last(), Some(Event::Partial(p)) if p.text.is_empty()),
        "{after:?}"
    );
}

#[test]
fn a_speaker_who_has_gone_quiet_costs_no_more_partials() {
    let mut streamer = Streamer::new(Counting::default());
    let mut audio = speech(1_000);
    audio.extend(silence(5_000));
    run(&mut streamer, &audio);
    let partials = streamer
        .transcriber
        .calls
        .iter()
        .filter(|(_, pass)| *pass == Pass::Partial)
        .count();
    assert!(partials <= 2, "{partials} partials for one second of speech");
}

#[test]
fn a_short_phrase_left_alone_is_committed_by_the_long_pause() {
    let mut streamer = Streamer::new(Counting::default());
    let mut audio = speech(700);
    audio.extend(silence(2_000));
    let mut events = Vec::new();
    for chunk in audio.chunks(ms_to_samples(250)) {
        streamer.feed(chunk);
        events.extend(streamer.tick().unwrap());
    }
    // Committed WITHOUT finish(): nobody pressed stop, the speaker just
    // said "buy milk" and waited.
    assert_eq!(segments(&events).len(), 1, "{events:?}");
}

#[test]
fn twenty_seconds_without_a_pause_is_cut_anyway_and_never_past_the_window() {
    let mut streamer = Streamer::new(Counting::default());
    let events = run(&mut streamer, &speech(45_000));
    let segs = segments(&events);
    assert!(segs.len() >= 3, "{segs:?}");
    for pair in segs.windows(2) {
        assert_eq!(pair[0].end_ms, pair[1].start_ms);
    }
    for (len, _) in &streamer.transcriber.calls {
        assert!(*len <= WINDOW_CAP);
    }
    for s in &segs[..segs.len() - 1] {
        assert!(s.end_ms - s.start_ms <= 20_000, "{s:?}");
    }
}

#[test]
fn commits_do_not_depend_on_how_often_tick_runs() {
    let mut audio = speech(2_000);
    audio.extend(silence(800));
    audio.extend(speech(2_000));
    audio.extend(silence(800));
    audio.extend(speech(2_000));

    let mut eager = Streamer::new(Counting::default());
    let eager_segments: Vec<Segment> =
        segments(&run(&mut eager, &audio)).into_iter().cloned().collect();

    // A worker stuck behind a slow inference: all the audio arrives before
    // the first tick.
    let mut starved = Streamer::new(Counting::default());
    starved.feed(&audio);
    let mut events = starved.tick().unwrap();
    events.extend(starved.finish().unwrap());
    let starved_segments: Vec<Segment> = segments(&events).into_iter().cloned().collect();

    assert_eq!(eager_segments.len(), 3);
    assert_eq!(eager_segments, starved_segments);
}

fn rewound(events: &[Event]) -> Option<&Rewound> {
    events.iter().find_map(|e| match e {
        Event::Rewound(r) => Some(r),
        _ => None,
    })
}

/// Two phrases with a pause between, ticked in as the worker would, and not
/// finished - the tape is still running.
fn two_phrases(streamer: &mut Streamer<Counting>) -> Vec<Segment> {
    let mut audio = silence(500);
    audio.extend(speech(2_400));
    audio.extend(silence(1_000));
    audio.extend(speech(2_400));
    audio.extend(silence(1_400));
    let mut events = Vec::new();
    for chunk in audio.chunks(ms_to_samples(250)) {
        streamer.feed(chunk);
        events.extend(streamer.tick().unwrap());
    }
    let segs: Vec<Segment> = segments(&events).into_iter().cloned().collect();
    assert_eq!(segs.len(), 2, "{events:?}");
    segs
}

#[test]
fn a_rewind_drops_every_segment_after_the_moment_and_what_follows_tiles_on() {
    let mut streamer = Streamer::new(Counting::default());
    let segs = two_phrases(&mut streamer);

    // Into the middle of the second phrase.
    let moment = segs[1].start_ms + 1_000;
    let events = streamer.rewind(moment);
    let rewound = rewound(&events).expect("a rewind says so");
    assert_eq!(rewound.segments, vec![segs[0].clone()]);
    assert_eq!(rewound.to_ms, moment);
    assert_eq!(streamer.recorded_ms(), moment, "the audio after the moment is gone");
    assert_eq!(streamer.transcript(), segs[0].text);

    // Talking over it: the second phrase is re-heard from where it started,
    // and the new speech follows it on the same timeline.
    let mut audio = speech(2_000);
    audio.extend(silence(1_500));
    let events = run(&mut streamer, &audio);
    let again = segments(&events);
    assert!(!again.is_empty(), "{events:?}");
    assert_eq!(again[0].start_ms, segs[0].end_ms, "re-recorded speech must tile onto what was kept");
    for pair in again.windows(2) {
        assert_eq!(pair[0].end_ms, pair[1].start_ms);
    }
}

#[test]
fn the_next_prompt_follows_the_transcript_as_it_now_stands() {
    let mut streamer = Streamer::new(Counting::default());
    let segs = two_phrases(&mut streamer);
    streamer.rewind(segs[1].start_ms);
    let before = streamer.transcriber.prompts.len();
    let mut audio = speech(2_000);
    audio.extend(silence(1_500));
    run(&mut streamer, &audio);
    let after = &streamer.transcriber.prompts[before..];
    let expected = text::prompt(&segs[0].text, PROMPT_CHARS);
    assert!(after.iter().all(|p| *p == expected), "{after:#?}");
}

#[test]
fn a_rewind_to_the_start_starts_the_note_over() {
    let mut streamer = Streamer::new(Counting::default());
    two_phrases(&mut streamer);
    let events = streamer.rewind(0);
    assert!(rewound(&events).unwrap().segments.is_empty());
    assert_eq!(streamer.transcript(), "");
    let mut audio = speech(2_000);
    audio.extend(silence(1_500));
    let events = run(&mut streamer, &audio);
    assert_eq!(segments(&events)[0].start_ms, 0);
}

#[test]
fn a_rewind_clears_the_guess_on_screen() {
    let mut streamer = Streamer::new(Counting::default());
    let mut events = Vec::new();
    for chunk in speech(3_000).chunks(ms_to_samples(250)) {
        streamer.feed(chunk);
        events.extend(streamer.tick().unwrap());
    }
    assert!(streamer.showing_partial, "{events:?}");
    let events = streamer.rewind(1_000);
    assert!(matches!(events.first(), Some(Event::Partial(p)) if p.text.is_empty()), "{events:?}");
    assert!(matches!(events.last(), Some(Event::Rewound(_))), "{events:?}");
}

#[test]
fn a_rewind_past_the_end_is_the_end_and_loses_nothing() {
    let mut streamer = Streamer::new(Counting::default());
    let segs = two_phrases(&mut streamer);
    let recorded = streamer.recorded_ms();
    let events = streamer.rewind(recorded + 60_000);
    assert_eq!(rewound(&events).unwrap().segments, segs);
    assert_eq!(streamer.recorded_ms(), recorded / 20 * 20);
}

#[test]
fn a_click_in_a_pause_is_not_speech() {
    let mut streamer = Streamer::new(Counting::default());
    let mut audio = silence(1_000);
    // One loud 20 ms frame.
    audio.extend(vec![0.5; FRAME]);
    audio.extend(silence(3_000));
    let events = run(&mut streamer, &audio);
    assert!(events.is_empty(), "{events:?}");
    assert!(streamer.transcriber.calls.is_empty());
}
