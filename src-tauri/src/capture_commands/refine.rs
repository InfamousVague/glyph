//! Refine: a saved recording transcribed again after Done, with the bigger
//! model (`model::REFINE`) and whisper.cpp's own seeking, where it does not
//! have to keep up with speech (DESIGN section 22). The page decides what the
//! better words replace; this answers with them, on the recording's own
//! timeline.
//!
//! A pass never competes with a capture. One is refused while a capture runs,
//! a second is refused while one runs, and `capture_start` stops one within a
//! graph computation (`CaptureState::refine_abort`).

use tauri::{AppHandle, State};

use super::CaptureState;

#[cfg(not(target_os = "ios"))]
use std::sync::{atomic::AtomicBool, Arc};

#[cfg(not(target_os = "ios"))]
use serde::Serialize;
#[cfg(not(target_os = "ios"))]
use tauri::Emitter;

#[cfg(not(target_os = "ios"))]
use crate::lock::lock;
#[cfg(not(target_os = "ios"))]
use crate::paths;
#[cfg(target_os = "ios")]
use crate::unsupported::{on_ios, TRANSCRIPTION};
#[cfg(not(target_os = "ios"))]
use crate::whisper::{
    engine::{Engine, Session},
    model,
};

/// `capture://refine-progress`, as the page reads it.
#[cfg(not(target_os = "ios"))]
#[derive(Debug, Clone, Serialize)]
struct RefineProgress {
    id: String,
    percent: i32,
}

/// Transcribes a saved recording again with the refine model, from `fromMs` to
/// its end, and answers with its phrases: `[{ text, startMs, endMs }]`, times on
/// the recording's own timeline. The page decides what to do with them.
///
/// `promptTail` is the note's committed text before this take (empty for a
/// first take); it rides after the cue vocabulary so a take that continues a
/// sentence continues its casing. Progress arrives as
/// `capture://refine-progress { id, percent }`.
///
/// Refused with "busy" while a capture runs or another refine does, with "model
/// missing" before the refine model is downloaded, and ends with "cancelled"
/// when `capture_start` runs mid-pass. The refine engine is loaded for the pass
/// and dropped after it: 190 MB is not kept resident for something that runs
/// once a recording.
#[tauri::command]
pub async fn capture_refine(
    app: AppHandle,
    state: State<'_, CaptureState>,
    id: String,
    from_ms: u64,
    prompt_tail: String,
) -> Result<Vec<crate::note::RecordedSegment>, String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (app, state, id, from_ms, prompt_tail));
    #[cfg(not(target_os = "ios"))]
    {
        use std::sync::atomic::{AtomicI32, Ordering};

        if lock(&state.capture).is_some() {
            return Err("busy".into());
        }
        let dir = paths::models_dir(&app)?;
        let status = crate::model_files::status(&dir, &model::REFINE);
        if !status.present {
            return Err("model missing".into());
        }
        let recording = paths::recordings_dir(&app)
            .ok()
            .and_then(|recordings| crate::recordings::recording_file(&recordings, &id))
            .ok_or_else(|| "no such recording".to_string())?;
        if state.refining.swap(true, Ordering::SeqCst) {
            return Err("busy".into());
        }
        struct Done<'a>(&'a AtomicBool);
        impl Drop for Done<'_> {
            fn drop(&mut self) {
                self.0.store(false, Ordering::SeqCst);
            }
        }
        let _done = Done(&state.refining);

        let abort = Arc::clone(&state.refine_abort);
        abort.store(false, Ordering::Relaxed);
        let worker_abort = Arc::clone(&abort);
        let model_path = std::path::PathBuf::from(&status.path);
        let prompt = crate::whisper::text::prompt(&prompt_tail, 200);
        let emitter = app.clone();
        let job = id.clone();
        let result = tauri::async_runtime::spawn_blocking(
            move || -> Result<Vec<crate::note::RecordedSegment>, String> {
                let audio = crate::whisper::wav::read(&recording)?;
                let from = crate::whisper::ms_to_samples(from_ms).min(audio.len());
                if audio.len() - from < crate::whisper::ms_to_samples(100) {
                    return Ok(Vec::new());
                }
                let engine = Arc::new(Engine::load(&model_path)?);
                let mut session = Session::new(engine, worker_abort)?;
                let progress = AtomicI32::new(0);
                let finished = AtomicBool::new(false);
                // A watcher beside the pass turns whisper.cpp's percentage into
                // events a few times a second; the pass itself never waits on IPC.
                std::thread::scope(|scope| {
                    scope.spawn(|| {
                        let mut last = -1;
                        while !finished.load(Ordering::Relaxed) {
                            let percent = progress.load(Ordering::Relaxed);
                            if percent != last {
                                last = percent;
                                let _ = emitter.emit(
                                    "capture://refine-progress",
                                    RefineProgress {
                                        id: job.clone(),
                                        percent,
                                    },
                                );
                            }
                            std::thread::sleep(std::time::Duration::from_millis(250));
                        }
                    });
                    let timed = session.transcribe_timed(&audio[from..], &prompt, &progress);
                    finished.store(true, Ordering::Relaxed);
                    timed
                })
                .map(|timed| offset_segments(timed, from_ms))
            },
        )
        .await
        .map_err(|e| format!("the refine pass stopped: {e}"))?;

        match result {
            Err(_) if abort.load(Ordering::Relaxed) => Err("cancelled".into()),
            Ok(segments) => {
                let _ = app.emit(
                    "capture://refine-progress",
                    RefineProgress { id, percent: 100 },
                );
                Ok(segments)
            }
            Err(e) => Err(e),
        }
    }
}

/// Timed phrases from a pass over `[from_ms, end)`, moved onto the whole
/// recording's timeline.
#[cfg(not(target_os = "ios"))]
fn offset_segments(
    timed: Vec<crate::whisper::engine::TimedText>,
    from_ms: u64,
) -> Vec<crate::note::RecordedSegment> {
    timed
        .into_iter()
        .map(|t| crate::note::RecordedSegment {
            text: t.text,
            start_ms: t.start_ms + from_ms,
            end_ms: t.end_ms + from_ms,
        })
        .collect()
}

#[cfg(all(test, not(target_os = "ios")))]
mod tests {
    use super::offset_segments;
    use crate::whisper::engine::TimedText;

    #[test]
    fn a_refined_take_lands_on_the_whole_recordings_timeline() {
        let timed = vec![
            TimedText {
                text: "Fresh bread.".into(),
                start_ms: 0,
                end_ms: 1200,
            },
            TimedText {
                text: "On the way home.".into(),
                start_ms: 1200,
                end_ms: 2600,
            },
        ];
        let segments = offset_segments(timed, 45_000);
        assert_eq!((segments[0].start_ms, segments[0].end_ms), (45_000, 46_200));
        assert_eq!((segments[1].start_ms, segments[1].end_ms), (46_200, 47_600));
        assert_eq!(segments[1].text, "On the way home.");
    }
}
