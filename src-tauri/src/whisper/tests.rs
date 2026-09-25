//! The engine against the real model and real (synthesised) speech.
//!
//! `stream.rs` proves the DECISIONS with a transcriber that counts words; this
//! file proves the whole thing hears what was said. It needs two things the
//! repository does not carry, and says plainly when either is missing rather
//! than passing by doing nothing:
//!
//! - the model, from `npm run fetch:model` (base.en-q5_1; the benchmark also
//!   wants `npm run fetch:model small`), in the repository's `models/`;
//! - a fixture, which is generated here on first use with macOS's `say` and
//!   `afconvert` - so no recorded audio is ever committed, and the words in it
//!   are the words in `SCRIPT`, exactly.
//!
//! The fixture has two deliberate 1.5 s pauses (`[[slnc 1500]]`), which is
//! what the streaming test checks the commits land in.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Instant;

use super::engine::{Engine, Session};
use super::fixtures::{models_dir, to_16k_mono_wav};
use super::model;
use super::stream::{Event, Streamer};
use super::vad::rms;
use super::{ms_to_samples, samples_to_ms, wav, SAMPLE_RATE};
use crate::model_files::{self, ModelSpec};

const SCRIPT: &str = "Remember to buy oat milk and fresh bread on the way home. \
    [[slnc 1500]] Then call the plumber about the leaking kitchen tap before Thursday. \
    [[slnc 1500]] The quarterly report for Northwind is due next Monday morning.";

/// Words from each of the three sentences that a transcript which heard them
/// cannot avoid containing. Not "Northwind": a proper noun the model has never
/// seen is exactly what base.en misspells, and a test that fails on a
/// defensible spelling is a test somebody deletes.
const KEY_WORDS: [&str; 7] = ["milk", "bread", "plumber", "kitchen", "thursday", "report", "monday"];

/// The loaded model, shared by every test in the run - loading it once per
/// test would be most of the suite's time - or `None` with a message saying
/// how to get it.
fn engine() -> Option<Arc<Engine>> {
    static ENGINE: OnceLock<Option<Arc<Engine>>> = OnceLock::new();
    ENGINE
        .get_or_init(|| load(&model::BASE_EN_Q5_1).map(Arc::new))
        .clone()
}

fn load(spec: &ModelSpec) -> Option<Engine> {
    let status = model_files::status(&models_dir(), spec);
    if !status.present {
        eprintln!(
            "SKIPPED: {} is not in models/ - run `npm run fetch:model` to test against the real model",
            spec.file
        );
        return None;
    }
    Some(Engine::load(Path::new(&status.path)).expect("a verified model loads"))
}

/// `models/fixture.wav`, generated on first use. Serialised by a lock so that
/// two tests starting together do not both run `say` into the same file.
fn fixture() -> Option<Vec<f32>> {
    static MAKING: Mutex<()> = Mutex::new(());
    let _one_at_a_time = crate::lock::lock(&MAKING);
    let wav_path = models_dir().join("fixture.wav");
    if !wav_path.exists() {
        std::fs::create_dir_all(models_dir()).ok()?;
        let aiff = std::env::temp_dir().join(format!("glyph-fixture-{}.aiff", uuid::Uuid::new_v4()));
        let spoke = Command::new("say").arg("-o").arg(&aiff).arg(SCRIPT).status();
        if !matches!(spoke, Ok(s) if s.success()) {
            eprintln!("SKIPPED: no `say` to synthesise the fixture with (this test generates it on macOS)");
            return None;
        }
        let part = wav_path.with_extension("wav.part");
        let converted = to_16k_mono_wav(&aiff, &part);
        let _ = std::fs::remove_file(&aiff);
        if converted.is_err() {
            eprintln!("SKIPPED: `afconvert` could not make the 16 kHz fixture");
            return None;
        }
        std::fs::rename(&part, &wav_path).ok()?;
    }
    Some(wav::read(&wav_path).expect("the fixture afconvert wrote is a 16 kHz mono WAV"))
}

fn missing_key_words(transcript: &str) -> Vec<&'static str> {
    let lower = transcript.to_lowercase();
    KEY_WORDS.into_iter().filter(|w| !lower.contains(w)).collect()
}

fn session(engine: &Arc<Engine>) -> Session {
    Session::new(Arc::clone(engine), Arc::new(AtomicBool::new(false))).unwrap()
}

#[test]
fn whole_file_transcription_hears_every_key_word() {
    let (Some(engine), Some(audio)) = (engine(), fixture()) else { return };
    let transcript = session(&engine).transcribe_all(&audio).unwrap();
    assert!(
        missing_key_words(&transcript).is_empty(),
        "missing {:?} from {transcript:?}",
        missing_key_words(&transcript)
    );
}

#[test]
fn streaming_in_250ms_chunks_shows_partials_commits_in_the_pauses_and_never_revises() {
    let (Some(engine), Some(audio)) = (engine(), fixture()) else { return };
    let mut streamer = Streamer::new(session(&engine));
    let mut events = Vec::new();
    for chunk in audio.chunks(ms_to_samples(250)) {
        streamer.feed(chunk);
        events.extend(streamer.tick().unwrap());
    }
    events.extend(streamer.finish().unwrap());

    let mut committed = Vec::new();
    let mut partials_before_first_commit = 0;
    for event in &events {
        match event {
            Event::Partial(p) if committed.is_empty() && !p.text.is_empty() => {
                partials_before_first_commit += 1
            }
            Event::Segment(s) => committed.push(s.clone()),
            Event::Error(e) => panic!("{}", e.message),
            _ => {}
        }
    }
    eprintln!("streamed segments: {committed:#?}");

    assert!(partials_before_first_commit >= 1, "no partial text before the first commit: {events:?}");
    assert!(committed.len() >= 3, "three sentences with two long pauses: {committed:?}");

    // Every cut between two segments is in quiet audio: 100 ms either side of
    // it is below the VAD's absolute floor.
    for pair in committed.windows(2) {
        assert_eq!(pair[0].end_ms, pair[1].start_ms, "segments tile the timeline");
        let cut = ms_to_samples(pair[0].end_ms);
        let around = &audio[cut.saturating_sub(ms_to_samples(100))..(cut + ms_to_samples(100)).min(audio.len())];
        assert!(rms(around) < 0.003, "a cut at {} ms is inside speech", pair[0].end_ms);
    }
    assert_eq!(committed.first().unwrap().start_ms, 0);
    assert!(committed.last().unwrap().end_ms <= samples_to_ms(audio.len()));

    // Append-only: what the page was told, in order, IS the transcript. A
    // revision would have to be a second event for the same audio, and the
    // tiling above rules that out.
    let told: Vec<&str> = committed.iter().map(|s| s.text.as_str()).collect();
    assert_eq!(streamer.transcript(), told.join(" "));
    assert!(
        missing_key_words(&streamer.transcript()).is_empty(),
        "missing {:?} from {:?}",
        missing_key_words(&streamer.transcript()),
        streamer.transcript()
    );
}

#[test]
fn silence_produces_no_segments_no_partials_and_no_hallucinated_text() {
    let Some(engine) = engine() else { return };
    let mut streamer = Streamer::new(session(&engine));
    let mut audio = vec![0.0f32; ms_to_samples(10_000)];
    // And ten seconds of the faintest hiss, which digital zeros are not.
    let mut state = 0x9e37_79b9_u32;
    audio.extend((0..ms_to_samples(10_000)).map(|_| {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        ((state as f32 / u32::MAX as f32) * 2.0 - 1.0) * 0.002
    }));
    let mut events = Vec::new();
    for chunk in audio.chunks(ms_to_samples(250)) {
        streamer.feed(chunk);
        events.extend(streamer.tick().unwrap());
    }
    events.extend(streamer.finish().unwrap());
    assert!(events.is_empty(), "{events:?}");
    assert_eq!(streamer.transcript(), "");
}

/// Real-time factor and load time, base.en against small.en, on this machine.
///
/// Ignored because it is a measurement, not a test, and takes the better part
/// of a minute. Run it with:
///
/// `cargo test --release whisper::tests::benchmark -- --ignored --nocapture`
#[test]
#[ignore]
fn benchmark() {
    let Some(audio) = fixture() else { return };
    let audio_s = audio.len() as f64 / SAMPLE_RATE as f64;
    println!("fixture: {audio_s:.2} s of audio; {} threads", std::thread::available_parallelism().map(|n| n.get().min(4)).unwrap_or(4));

    for spec in [model::BASE_EN_Q5_1, model::SMALL_EN_Q5_1] {
        let Some(engine) = load(&spec).map(Arc::new) else { continue };
        println!("\n{}", spec.file);
        println!("  load:                 {:>7.0} ms", engine.loaded_in().as_secs_f64() * 1e3);

        let started = Instant::now();
        let mut s = session(&engine);
        println!("  state:                {:>7.0} ms", started.elapsed().as_secs_f64() * 1e3);

        // The first inference pays for buffer allocation; measure the second.
        s.transcribe_all(&audio).unwrap();
        let started = Instant::now();
        let text = s.transcribe_all(&audio).unwrap();
        let whole = started.elapsed().as_secs_f64();
        println!("  whole file:           {:>7.0} ms  RTF {:.1}x  {text:?}", whole * 1e3, audio_s / whole);

        // A streaming run: what the phone will actually do, per inference.
        let mut streamer = Streamer::new(session(&engine));
        let started = Instant::now();
        let mut partials = 0;
        let mut segments = 0;
        for chunk in audio.chunks(ms_to_samples(250)) {
            streamer.feed(chunk);
            for event in streamer.tick().unwrap() {
                match event {
                    Event::Partial(p) if !p.text.is_empty() => partials += 1,
                    Event::Segment(_) => segments += 1,
                    _ => {}
                }
            }
        }
        segments += streamer.finish().unwrap().iter().filter(|e| matches!(e, Event::Segment(_))).count();
        let streamed = started.elapsed().as_secs_f64();
        println!(
            "  streamed (250 ms):    {:>7.0} ms  RTF {:.1}x  {partials} partials, {segments} segments, {:?}",
            streamed * 1e3,
            audio_s / streamed,
            streamer.transcript()
        );

        // What the model says when it IS asked about silence - the reason the
        // streamer never asks.
        let silent = vec![0.0f32; ms_to_samples(5_000)];
        let raw = {
            use super::stream::{Pass, Transcribe};
            s.transcribe(&silent, "", Pass::Partial).unwrap()
        };
        println!("  5 s of silence, raw:  {raw:?}");
    }
}

/// How whisper spells the spoken cues with no prompt and with
/// `text::CUE_VOCABULARY`, for three voices, and what each prompt gets back
/// from noise. This is the evidence behind the vocabulary, and the way to check
/// a change to it or to the model.
///
/// Ignored because it is a measurement, not a test. Run it with:
///
/// `cargo test --release whisper::tests::cue_vocabulary -- --ignored --nocapture`
#[test]
#[ignore]
fn cue_vocabulary() {
    use super::stream::{Pass, Transcribe};
    use super::text::CUE_VOCABULARY;

    const LINES: [&str; 16] = [
        "Title. Weekend plans.",
        "Bullet point. Oat milk.",
        "Checkbox, call the bank about the card.",
        "Check box. Renew the passport.",
        "Number one, book the flights.",
        "Number two. Pack the charger.",
        "Bold, this really matters, end bold.",
        "Italics, maybe, end italics.",
        "To do. Email Sarah the invoice.",
        "New paragraph. The garden is fine as it is.",
        "Quote. Less is more.",
        "Heading. Budget.",
        "Important. The deadline moved to Friday.",
        "Horizontal line.",
        "Divider.",
        "Remember to buy oat milk and fresh bread on the way home.",
    ];
    let Some(engine) = engine() else { return };
    let mut s = session(&engine);

    for voice in ["Samantha", "Daniel", "Fred"] {
        println!("\n{voice}");
        for line in LINES {
            let Some(audio) = synthesise(line, voice) else { return };
            let bare = s.transcribe(&audio, "", Pass::Commit).unwrap();
            let cued = s.transcribe(&audio, CUE_VOCABULARY, Pass::Commit).unwrap();
            println!("  {line:<58} none {:<48} cued {:?}", format!("{:?}", bare.trim()), cued.trim());
        }
    }

    // Speech-shaped noise (the stream tests' syllables) at three levels. The
    // streamer never sends these to the model; this is what it would say if
    // it did, which is where a recited prompt would show.
    let mut state = 0x2545_f491_u32;
    for (label, amplitude) in [("hiss", 0.01f32), ("syllables", 0.2), ("loud", 0.5)] {
        let audio: Vec<f32> = (0..ms_to_samples(3_000))
            .map(|i| {
                state ^= state << 13;
                state ^= state >> 17;
                state ^= state << 5;
                let noise = (state as f32 / u32::MAX as f32) * 2.0 - 1.0;
                let in_dip = (i % ms_to_samples(220)) >= ms_to_samples(160);
                noise * if in_dip { amplitude * 0.02 } else { amplitude }
            })
            .collect();
        for pass in [Pass::Partial, Pass::Commit] {
            let bare = s.transcribe(&audio, "", pass).unwrap();
            let cued = s.transcribe(&audio, CUE_VOCABULARY, pass).unwrap();
            println!("{label:>9} {pass:?}: none {:?}, cued {:?}", bare.trim(), cued.trim());
        }
    }
}

/// `text` spoken by a macOS voice as 16 kHz mono, or `None` where there is no `say`.
fn synthesise(text: &str, voice: &str) -> Option<Vec<f32>> {
    let stem = std::env::temp_dir().join(format!("glyph-cue-{}", uuid::Uuid::new_v4()));
    let (aiff, wav_path) = (stem.with_extension("aiff"), stem.with_extension("wav"));
    let spoke = Command::new("say").args(["-v", voice, "-o"]).arg(&aiff).arg(text).status();
    let converted = matches!(spoke, Ok(s) if s.success()) && to_16k_mono_wav(&aiff, &wav_path).is_ok();
    let audio = converted.then(|| wav::read(&wav_path).ok()).flatten();
    let _ = std::fs::remove_file(&aiff);
    let _ = std::fs::remove_file(&wav_path);
    if audio.is_none() {
        eprintln!("SKIPPED: no `say`/`afconvert` to synthesise {voice:?} with (macOS only)");
    }
    audio
}

/// Word error rate and time per inference, for every model named, on a
/// directory of real speech: `<id>.wav` (16 kHz mono) beside `<id>.txt` (the
/// reference). Each clip goes through the same call a commit makes - the cue
/// vocabulary as the prompt, `Pass::Commit`, then `text::clean` and the echo
/// guard - so the number is what the phone's committed text would score.
/// Then the fixture is streamed in real time, per model, for the real-time
/// factor the phone has to keep above 1.
///
/// Ignored because it downloads nothing and measures everything: run it with
/// `GLYPH_EVAL=dir1,dir2 GLYPH_EVAL_MODELS=ggml-base.en-q5_1.bin,... \
///  cargo test --release whisper::tests::accuracy -- --ignored --nocapture`
/// (`GLYPH_EVAL_LIMIT` caps the clips per directory). Models are read from
/// the repository's `models/`.
#[test]
#[ignore]
fn accuracy() {
    use super::stream::{Pass, Transcribe};
    use super::text;

    let dirs: Vec<PathBuf> = std::env::var("GLYPH_EVAL").unwrap_or_default().split(',').filter(|d| !d.is_empty()).map(PathBuf::from).collect();
    let files: Vec<String> = std::env::var("GLYPH_EVAL_MODELS").unwrap_or_default().split(',').filter(|m| !m.is_empty()).map(String::from).collect();
    let limit: usize = std::env::var("GLYPH_EVAL_LIMIT").ok().and_then(|l| l.parse().ok()).unwrap_or(usize::MAX);
    if dirs.is_empty() || files.is_empty() {
        eprintln!("SKIPPED: set GLYPH_EVAL and GLYPH_EVAL_MODELS");
        return;
    }
    /// A directory, and its clips as (id, audio, reference transcript).
    type Clips = Vec<(PathBuf, Vec<(String, Vec<f32>, String)>)>;
    let clips: Clips = dirs
        .iter()
        .map(|dir| {
            let mut ids: Vec<String> = std::fs::read_dir(dir)
                .unwrap()
                .filter_map(|e| e.ok()?.file_name().to_str()?.strip_suffix(".wav").map(String::from))
                .collect();
            ids.sort();
            let loaded = ids
                .into_iter()
                .take(limit)
                .map(|id| {
                    let audio = wav::read(&dir.join(format!("{id}.wav"))).unwrap();
                    let reference = std::fs::read_to_string(dir.join(format!("{id}.txt"))).unwrap();
                    (id, audio, reference)
                })
                .collect();
            (dir.clone(), loaded)
        })
        .collect();
    let prompt = text::prompt("", 200);
    let threads = std::thread::available_parallelism().map(|n| n.get().min(4)).unwrap_or(4);
    println!("{threads} threads; {} directories", dirs.len());

    for file in &files {
        let path = models_dir().join(file);
        let Ok(engine) = Engine::load(&path).map(Arc::new) else {
            println!("\n{file}: could not load");
            continue;
        };
        let bytes = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
        println!("\n{file}  ({} MB, load {:.0} ms)", bytes / 1_000_000, engine.loaded_in().as_secs_f64() * 1e3);
        let mut s = session(&engine);
        // The first inference allocates; keep it out of the timings.
        if let Some((_, audio, _)) = clips.first().and_then(|(_, c)| c.first()) {
            s.transcribe(audio, &prompt, Pass::Commit).unwrap();
        }
        for (dir, set) in &clips {
            let (mut errors, mut words) = (0usize, 0usize);
            let mut times = Vec::new();
            for (_, audio, reference) in set {
                let started = Instant::now();
                let raw = s.transcribe(audio, &prompt, Pass::Commit).unwrap();
                times.push(started.elapsed().as_secs_f64() * 1e3);
                let hypothesis = text::without_prompt_echo(&text::clean(&raw));
                let (want, got) = (eval_words(reference), eval_words(&hypothesis));
                errors += edit_distance(&want, &got);
                words += want.len();
            }
            times.sort_by(f64::total_cmp);
            let mean = times.iter().sum::<f64>() / times.len().max(1) as f64;
            let p90 = times.get(times.len() * 9 / 10).copied().unwrap_or(0.0);
            println!(
                "  {:<8} WER {:>5.2}%  ({errors}/{words})  commit {:>6.0} ms mean, {:>6.0} ms p90",
                dir.file_name().and_then(|n| n.to_str()).unwrap_or("?"),
                100.0 * errors as f64 / words.max(1) as f64,
                mean,
                p90
            );
        }
        if let Some(audio) = fixture() {
            let mut partial_ms = Vec::new();
            let mut streamer = Streamer::new(session(&engine));
            let started = Instant::now();
            for chunk in audio.chunks(ms_to_samples(250)) {
                streamer.feed(chunk);
                let tick = Instant::now();
                let events = streamer.tick().unwrap();
                if events.iter().any(|e| matches!(e, Event::Partial(_))) {
                    partial_ms.push(tick.elapsed().as_secs_f64() * 1e3);
                }
            }
            streamer.finish().unwrap();
            let streamed = started.elapsed().as_secs_f64();
            let audio_s = audio.len() as f64 / SAMPLE_RATE as f64;
            let partial_mean = partial_ms.iter().sum::<f64>() / partial_ms.len().max(1) as f64;
            println!(
                "  fixture  streamed RTF {:.2}x  ({:.1} s for {:.1} s), partial tick {:.0} ms mean",
                audio_s / streamed,
                streamed,
                audio_s,
                partial_mean
            );
        }
    }
}

/// Words for scoring: lowercase, apostrophes kept, everything else a break,
/// and the few spellings LibriSpeech writes out that Whisper abbreviates.
fn eval_words(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split(|c: char| !(c.is_alphanumeric() || c == '\''))
        .filter(|w| !w.is_empty())
        .map(|w| match w {
            "mr" => "mister".to_string(),
            "mrs" => "missus".to_string(),
            "dr" => "doctor".to_string(),
            other => other.trim_matches('\'').to_string(),
        })
        .filter(|w| !w.is_empty())
        .collect()
}

/// Levenshtein distance over words: substitutions, insertions and deletions.
fn edit_distance(want: &[String], got: &[String]) -> usize {
    let mut row: Vec<usize> = (0..=got.len()).collect();
    for (i, w) in want.iter().enumerate() {
        let mut diagonal = row[0];
        row[0] = i + 1;
        for (j, g) in got.iter().enumerate() {
            let above = row[j + 1];
            row[j + 1] = if w == g { diagonal } else { 1 + diagonal.min(above).min(row[j]) };
            diagonal = above;
        }
    }
    row[got.len()]
}

#[test]
fn a_timed_pass_over_part_of_a_recording_keeps_its_phrases_in_order_and_in_range() {
    use std::sync::atomic::AtomicI32;
    let (Some(engine), Some(audio)) = (engine(), fixture()) else { return };
    // From three seconds in, as a memo take that starts mid-recording would.
    let from = ms_to_samples(3_000);
    let slice = &audio[from..];
    let slice_ms = samples_to_ms(slice.len());
    let progress = AtomicI32::new(0);
    let timed = session(&engine).transcribe_timed(slice, &super::text::prompt("", 200), &progress).unwrap();

    assert!(!timed.is_empty());
    let mut previous_start = 0;
    for phrase in &timed {
        assert!(phrase.start_ms <= phrase.end_ms, "{phrase:?}");
        assert!(phrase.start_ms >= previous_start, "phrases out of order: {timed:?}");
        assert!(phrase.end_ms <= slice_ms, "{phrase:?} ends past the {slice_ms} ms it was given");
        assert!(!phrase.text.trim().is_empty());
        previous_start = phrase.start_ms;
    }
    let words = timed.iter().map(|t| t.text.as_str()).collect::<Vec<_>>().join(" ").to_lowercase();
    for word in ["plumber", "report", "monday"] {
        assert!(words.contains(word), "missing {word} from {words:?}");
    }
    assert_eq!(progress.load(std::sync::atomic::Ordering::Relaxed), 100, "whisper reported its progress to the end");
}

#[test]
fn a_prompt_tail_carries_a_sentence_across_the_cut() {
    use std::sync::atomic::AtomicI32;
    let Some(engine) = engine() else { return };
    let Some(audio) = synthesise("fresh bread on the way home.", "Samantha") else { return };
    let progress = AtomicI32::new(0);
    let first = |tail: &str| {
        let timed = session(&engine).transcribe_timed(&audio, &super::text::prompt(tail, 200), &progress).unwrap();
        timed.first().map(|t| t.text.clone()).unwrap_or_default()
    };
    let cold = first("");
    let continued = first("Remember to buy oat milk and");
    eprintln!("cold {cold:?}, continued {continued:?}");
    assert!(cold.starts_with('F'), "on its own the take starts a sentence: {cold:?}");
    assert!(continued.starts_with('f'), "after an unfinished sentence it carries on in lower case: {continued:?}");
}
