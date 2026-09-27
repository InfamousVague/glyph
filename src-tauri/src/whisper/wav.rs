//! A WAV file, as 16 kHz mono `f32` samples, or a sentence saying why not.
//!
//! It writes a note's kept recording (`capture_stop`, as 16 kHz mono PCM16,
//! appended to when a take continues the note) and moves one to the note it
//! belongs to (`capture_reassign_recording`). It reads one back for the refine
//! pass (`capture_refine`), for `transcribe_wav`'s whole-file benchmark on the
//! phone, and for the tests, which read a fixture `afconvert` wrote. A
//! meeting's write-up (`write_up.rs`) reads one a stretch at a time
//! (`read_span`), asks its length without reading it (`duration_ms`), and puts
//! right the header the meeting service left behind (`patch_header`). All of
//! those are exactly the formats handled here, and nothing else is.
//!
//! ONE RULE FOR WHERE THE SAMPLES END, `data_end`. The meeting service writes
//! the WAV as it records and patches the header's two lengths every ten
//! seconds, so a kill leaves a file whose header is up to ten seconds short of
//! the audio that landed; an append killed between the samples and the header
//! leaves the same. Those samples are real audio, so when `data` is the last
//! chunk its bytes run to the end of the file, whatever the header says - and a
//! header that claims MORE than the file holds is clamped to the file. Every
//! reader here takes its end from that one function, so a short header reads
//! the same in the whole-file read, the span read, the length and the span
//! finder.
//!
//! Hand-written rather than `hound`, and on the same arithmetic as
//! `store.rs`'s error enum: RIFF is a chunk list with a four-byte tag and a
//! length, the two sample formats that arrive are sixteen-bit integers and
//! 32-bit floats, and a crate for a hundred lines is a dependency whose whole
//! surface is one function. What it does NOT do is resample. A file at 44.1
//! kHz is refused with its rate in the message rather than quietly converted -
//! see `SAMPLE_RATE` for why that is the caller's problem.

use std::io::{Cursor, Read, Seek, SeekFrom};
use std::path::Path;

use super::{ms_to_samples, samples_to_ms, SAMPLE_RATE};

/// PCM integer samples.
const FORMAT_PCM: u16 = 1;
/// IEEE float samples.
const FORMAT_FLOAT: u16 = 3;
/// WAVE_FORMAT_EXTENSIBLE, whose real format tag is the first two bytes of the
/// sub-format GUID. `afconvert` writes this for some layouts.
const FORMAT_EXTENSIBLE: u16 = 0xFFFE;

/// Reads a WAV file from disk. See `parse`.
pub fn read(path: &Path) -> Result<Vec<f32>, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    parse(&bytes).map_err(|e| format!("{}: {e}", path.display()))
}

/// The canonical 44-byte header this module writes: RIFF, a 16-byte `fmt `,
/// then `data`. Fixed so `append` can find the two length fields by offset,
/// and so Kotlin's meeting service can write the same header and patch the
/// same two fields (offsets 4 and 40).
pub const HEADER_LEN: usize = 44;

/// Writes `samples` (16 kHz mono 16-bit) to `path` as a WAV file, or adds them
/// to the end of the one already there when `append` is set and the file was
/// written by this function. Answers with the file's sample count afterwards -
/// the recording's length, on the timeline segment times use.
///
/// Appending is what a side-key capture that continues a note does: the note's
/// tape is one file, the new take after the old, so the words and the audio
/// stay one timeline. A file that is not ours (no such header) is replaced
/// rather than corrupted.
pub fn write_pcm16(path: &Path, samples: &[i16], append: bool) -> Result<usize, String> {
    use std::io::Write;
    let mut data = Vec::with_capacity(samples.len() * 2);
    for s in samples {
        data.extend_from_slice(&s.to_le_bytes());
    }
    let fail = |e: std::io::Error| format!("could not write the recording: {e}");

    let existing = if append { ours(path).map(|(_, actual)| actual) } else { None };
    let (mut file, before) = match existing {
        Some(bytes) => (
            std::fs::OpenOptions::new()
                .write(true)
                .open(path)
                .map_err(fail)?,
            bytes,
        ),
        None => (std::fs::File::create(path).map_err(fail)?, 0),
    };
    file.seek(SeekFrom::Start((HEADER_LEN + before) as u64))
        .map_err(fail)?;
    file.write_all(&data).map_err(fail)?;
    let total = before + data.len();
    file.seek(SeekFrom::Start(0)).map_err(fail)?;
    file.write_all(&header(total)).map_err(fail)?;
    file.flush().map_err(fail)?;
    Ok(total / 2)
}

/** Move a recorder-owned WAV, or append it to another recorder-owned tape. */
pub fn move_or_append(from: &Path, to: &Path, append: bool) -> Result<usize, String> {
    if !from.is_file() {
        return Ok(0);
    }
    if !append || !to.is_file() {
        std::fs::rename(from, to).map_err(|e| format!("could not move the recording: {e}"))?;
        return ours(to)
            .ok_or_else(|| "the moved recording was not a recorder WAV".to_string())
            .map(|(_, actual)| actual / 2);
    }
    let bytes =
        std::fs::read(from).map_err(|e| format!("could not read the temporary recording: {e}"))?;
    let data = bytes
        .get(HEADER_LEN..)
        .ok_or_else(|| "the temporary recording was not a recorder WAV".to_string())?;
    let samples = data
        .chunks_exact(2)
        .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
        .collect::<Vec<_>>();
    let total = write_pcm16(to, &samples, true)?;
    std::fs::remove_file(from)
        .map_err(|e| format!("could not remove the temporary recording: {e}"))?;
    Ok(total)
}

/// Puts a recorder-owned file's header right from the file's length: the two
/// u32 fields are rewritten only when they do not already say what is on
/// disk. Answers with the file's sample count. What the write-up does with a
/// file the meeting service (or a kill) left short.
pub fn patch_header(path: &Path) -> Result<usize, String> {
    use std::io::Write;
    let (declared, actual) = ours(path).ok_or_else(|| "not a recorder WAV".to_string())?;
    if declared != actual {
        let fail = |e: std::io::Error| format!("could not patch the recording's header: {e}");
        let mut file = std::fs::OpenOptions::new().write(true).open(path).map_err(fail)?;
        file.write_all(&header(actual)).map_err(fail)?;
        file.flush().map_err(fail)?;
    }
    Ok(actual / 2)
}

/// A 16 kHz mono PCM16 header for `data_len` bytes of samples.
fn header(data_len: usize) -> [u8; HEADER_LEN] {
    let mut out = [0u8; HEADER_LEN];
    out[0..4].copy_from_slice(b"RIFF");
    out[4..8].copy_from_slice(&((HEADER_LEN - 8 + data_len) as u32).to_le_bytes());
    out[8..12].copy_from_slice(b"WAVE");
    out[12..16].copy_from_slice(b"fmt ");
    out[16..20].copy_from_slice(&16u32.to_le_bytes());
    out[20..22].copy_from_slice(&FORMAT_PCM.to_le_bytes());
    out[22..24].copy_from_slice(&1u16.to_le_bytes());
    out[24..28].copy_from_slice(&(SAMPLE_RATE as u32).to_le_bytes());
    out[28..32].copy_from_slice(&(SAMPLE_RATE as u32 * 2).to_le_bytes());
    out[32..34].copy_from_slice(&2u16.to_le_bytes());
    out[34..36].copy_from_slice(&16u16.to_le_bytes());
    out[36..40].copy_from_slice(b"data");
    out[40..44].copy_from_slice(&(data_len as u32).to_le_bytes());
    out
}

/// Whether the first 44 bytes are the canonical header this module (and the
/// meeting service) writes: `fmt ` at 12, sixteen bytes long, `data` at 36.
fn canonical(head: &[u8]) -> bool {
    head.len() >= HEADER_LEN
        && &head[0..4] == b"RIFF"
        && &head[12..16] == b"fmt "
        && u32::from_le_bytes([head[16], head[17], head[18], head[19]]) == 16
        && &head[36..40] == b"data"
}

/// The declared and the actual data length of a file this module wrote, or
/// None for anything else.
///
/// The actual length is measured from the bytes on disk, not the header: an
/// append writes the samples first and the header second, and a process killed
/// between the two leaves a file longer than its header says. That tail is real
/// audio that was recorded, so it is kept - only whole samples - and the header
/// is put right by the next write. Trusting the header instead would have made
/// the next continuation replace the file and lose every earlier take. Only
/// the header is read; a long tape is not pulled into memory to check 44
/// bytes.
fn ours(path: &Path) -> Option<(usize, usize)> {
    let mut file = std::fs::File::open(path).ok()?;
    let len = file.metadata().ok()?.len() as usize;
    let mut head = [0u8; HEADER_LEN];
    file.read_exact(&mut head).ok()?;
    if !canonical(&head) {
        return None;
    }
    let declared = u32::from_le_bytes([head[40], head[41], head[42], head[43]]) as usize;
    let actual = (len - HEADER_LEN) & !1;
    (declared <= actual).then_some((declared, actual))
}

/// What a WAV's chunk list says about its samples: the format, and where the
/// `data` chunk's bytes start and end.
struct Layout {
    tag: u16,
    channels: usize,
    rate: u32,
    bits: u16,
    /// The first sample byte.
    data_start: usize,
    /// One past the last sample byte, by the module header's rule.
    data_end: usize,
}

impl Layout {
    /// Bytes a frame of every channel takes.
    fn frame_bytes(&self) -> usize {
        (self.channels * (self.bits as usize / 8)).max(1)
    }

    /// Refuses what this module does not decode for transcription.
    fn check_rate_and_channels(&self) -> Result<(), String> {
        if self.rate as usize != SAMPLE_RATE {
            return Err(format!("sample rate is {} Hz; transcription needs {SAMPLE_RATE} Hz mono", self.rate));
        }
        if self.channels == 0 {
            return Err("zero channels".to_string());
        }
        Ok(())
    }
}

fn read_at(source: &mut (impl Read + Seek), at: usize, buffer: &mut [u8]) -> Result<(), String> {
    source.seek(SeekFrom::Start(at as u64)).map_err(|e| format!("cannot read the WAV: {e}"))?;
    source.read_exact(buffer).map_err(|e| format!("cannot read the WAV: {e}"))
}

/// Whether a chunk header that could be one sits at `at`: a tag of letters,
/// digits and spaces, and a length that fits in the file. Asked of the bytes
/// after a `data` chunk's declared length, to tell "more chunks follow" from
/// "the header is short and this is audio". Never asked of a canonical file,
/// where `data` is the last chunk by construction.
fn chunk_follows(source: &mut (impl Read + Seek), at: usize, total: usize) -> bool {
    if at + 8 > total {
        return false;
    }
    let mut head = [0u8; 8];
    if read_at(source, at, &mut head).is_err() {
        return false;
    }
    let tag_like = head[..4].iter().all(|b| b.is_ascii_alphanumeric() || *b == b' ');
    let len = u32::from_le_bytes([head[4], head[5], head[6], head[7]]) as usize;
    tag_like && at + 8 + len <= total
}

/// Walks the chunk list of `source`, which is a whole file or the bytes of one.
fn layout(source: &mut (impl Read + Seek)) -> Result<Layout, String> {
    let total = source.seek(SeekFrom::End(0)).map_err(|e| format!("cannot read the WAV: {e}"))? as usize;
    let mut riff = [0u8; 12];
    if total < 12 || read_at(source, 0, &mut riff).is_err() || &riff[0..4] != b"RIFF" || &riff[8..12] != b"WAVE" {
        return Err("not a RIFF/WAVE file".to_string());
    }
    let mut head = [0u8; HEADER_LEN];
    let is_canonical = total >= HEADER_LEN && read_at(source, 0, &mut head).is_ok() && canonical(&head);
    let mut format: Option<(u16, usize, u32, u16)> = None;
    let mut at = 12;
    while at + 8 <= total {
        let mut chunk = [0u8; 8];
        read_at(source, at, &mut chunk)?;
        let tag = &chunk[0..4];
        let len = u32::from_le_bytes([chunk[4], chunk[5], chunk[6], chunk[7]]) as usize;
        let body_start = at + 8;
        match tag {
            b"fmt " => {
                let have = len.min(40).min(total - body_start);
                let mut body = vec![0u8; have];
                read_at(source, body_start, &mut body)?;
                if body.len() < 16 {
                    return Err("fmt chunk too short".to_string());
                }
                let mut tag = u16::from_le_bytes([body[0], body[1]]);
                let channels = u16::from_le_bytes([body[2], body[3]]) as usize;
                let rate = u32::from_le_bytes([body[4], body[5], body[6], body[7]]);
                let bits = u16::from_le_bytes([body[14], body[15]]);
                if tag == FORMAT_EXTENSIBLE && body.len() >= 26 {
                    tag = u16::from_le_bytes([body[24], body[25]]);
                }
                format = Some((tag, channels, rate, bits));
            }
            b"data" => {
                let (tag, channels, rate, bits) = format.ok_or("data chunk before any fmt chunk")?;
                // A `data` length past the end of the file is what a recorder
                // killed mid-write leaves behind; the samples that DID land are
                // still worth reading, so the length is clamped rather than
                // refused. A length SHORT of the file is the same recorder's
                // header from ten seconds ago: when nothing follows the chunk,
                // the samples run to the end of the file.
                let declared_end = body_start.saturating_add(len).min(total);
                let last_chunk = is_canonical || !chunk_follows(source, body_start.saturating_add(len).saturating_add(len & 1), total);
                let end = if last_chunk { total } else { declared_end };
                let mut layout = Layout { tag, channels, rate, bits, data_start: body_start, data_end: end };
                let frame = layout.frame_bytes();
                layout.data_end = body_start + ((end - body_start) / frame) * frame;
                return Ok(layout);
            }
            _ => {}
        }
        // Chunks are word-aligned: an odd length is followed by a pad byte.
        at = body_start.saturating_add(len).saturating_add(len & 1);
    }
    Err("no data chunk".to_string())
}

/// One past the last sample byte of a WAV, whole frames, by the module
/// header's rule: the file's end when `data` is its last chunk, else the
/// declared length clamped to the file. `source` is a file or the bytes of one.
pub fn data_end(source: &mut (impl Read + Seek)) -> Result<usize, String> {
    layout(source).map(|layout| layout.data_end)
}

/// The length of the audio in the file at `path`, from its header and its
/// size alone: nothing but the chunk list is read. Refuses a rate other than
/// 16 kHz as `parse` does, so the number is on the timeline segments use.
pub fn duration_ms(path: &Path) -> Result<u64, String> {
    let mut file = std::fs::File::open(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    let layout = layout(&mut file).map_err(|e| format!("{}: {e}", path.display()))?;
    layout.check_rate_and_channels().map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(samples_to_ms((layout.data_end - layout.data_start) / layout.frame_bytes()))
}

/// The samples of `path` from `from_ms` to `to_ms`, and nothing else read: the
/// chunk list, a seek, and `(to - from)` frames of 16 kHz mono PCM16, clamped
/// to where the samples end. A stereo or float file is refused: the recorder
/// and the meeting service write neither, and a span is asked of their files.
pub fn read_span(path: &Path, from_ms: u64, to_ms: u64) -> Result<Vec<f32>, String> {
    let fail = |e: String| format!("{}: {e}", path.display());
    let mut file = std::fs::File::open(path).map_err(|e| fail(e.to_string()))?;
    let layout = layout(&mut file).map_err(fail)?;
    layout.check_rate_and_channels().map_err(fail)?;
    if layout.channels != 1 {
        return Err(fail(format!("{} channels; a span is read from a mono recording", layout.channels)));
    }
    if (layout.tag, layout.bits) != (FORMAT_PCM, 16) {
        return Err(fail(format!("sample format (tag {}, {}-bit); a span is read from 16-bit PCM", layout.tag, layout.bits)));
    }
    let from = (layout.data_start + ms_to_samples(from_ms) * 2).min(layout.data_end);
    let to = (layout.data_start + ms_to_samples(to_ms) * 2).min(layout.data_end);
    if to <= from {
        return Ok(Vec::new());
    }
    let mut bytes = vec![0u8; to - from];
    read_at(&mut file, from, &mut bytes).map_err(fail)?;
    decode(&bytes, FORMAT_PCM, 1, 16)
}

/// Decodes a WAV held in memory to 16 kHz mono `f32` in [-1, 1].
///
/// Stereo (or more) is averaged to mono rather than refused: a file recorded
/// on a desktop for a benchmark is usually stereo, and averaging two copies of
/// one microphone costs nothing a transcript can hear.
///
/// Chunks other than `fmt ` and `data` are stepped over, padding byte and all,
/// because `afconvert` puts a `FLLR` chunk between them and a reader that
/// assumed `data` came next would read the filler as audio.
pub fn parse(bytes: &[u8]) -> Result<Vec<f32>, String> {
    let layout = layout(&mut Cursor::new(bytes))?;
    layout.check_rate_and_channels()?;
    decode(&bytes[layout.data_start..layout.data_end], layout.tag, layout.channels, layout.bits)
}

fn decode(body: &[u8], tag: u16, channels: usize, bits: u16) -> Result<Vec<f32>, String> {
    let interleaved: Vec<f32> = match (tag, bits) {
        (FORMAT_PCM, 16) => body
            .chunks_exact(2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32768.0)
            .collect(),
        (FORMAT_FLOAT, 32) => super::f32_samples(body),
        _ => {
            return Err(format!(
                "unsupported sample format (tag {tag}, {bits}-bit); expected 16-bit PCM or 32-bit float"
            ))
        }
    };
    if channels == 1 {
        return Ok(interleaved);
    }
    Ok(interleaved
        .chunks_exact(channels)
        .map(|frame| frame.iter().sum::<f32>() / channels as f32)
        .collect())
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// A 16 kHz PCM16 WAV of `samples`, with a filler chunk between `fmt ` and
    /// `data` the way `afconvert` writes one, and an odd-length chunk to prove
    /// the pad byte is honoured.
    pub(crate) fn encode(samples: &[f32], channels: u16) -> Vec<u8> {
        let mut data = Vec::new();
        for s in samples {
            let v = (s.clamp(-1.0, 1.0) * 32767.0) as i16;
            for _ in 0..channels {
                data.extend_from_slice(&v.to_le_bytes());
            }
        }
        let mut out = Vec::new();
        out.extend_from_slice(b"RIFF\0\0\0\0WAVE");
        out.extend_from_slice(b"fmt ");
        out.extend_from_slice(&16u32.to_le_bytes());
        out.extend_from_slice(&FORMAT_PCM.to_le_bytes());
        out.extend_from_slice(&channels.to_le_bytes());
        out.extend_from_slice(&(SAMPLE_RATE as u32).to_le_bytes());
        out.extend_from_slice(&(SAMPLE_RATE as u32 * 2 * channels as u32).to_le_bytes());
        out.extend_from_slice(&(2 * channels).to_le_bytes());
        out.extend_from_slice(&16u16.to_le_bytes());
        out.extend_from_slice(b"FLLR");
        out.extend_from_slice(&3u32.to_le_bytes());
        out.extend_from_slice(&[0, 0, 0, 0]); // three bytes and the pad byte
        out.extend_from_slice(b"data");
        out.extend_from_slice(&(data.len() as u32).to_le_bytes());
        out.extend_from_slice(&data);
        let riff_len = (out.len() - 8) as u32;
        out[4..8].copy_from_slice(&riff_len.to_le_bytes());
        out
    }

    /// The offset of the `data` chunk's length field in an `encode`d file.
    fn data_len_at(bytes: &[u8]) -> usize {
        bytes.windows(4).position(|w| w == b"data").unwrap() + 4
    }

    #[test]
    fn a_written_recording_reads_back_and_appends_onto_itself() {
        let dir = crate::test_support::TempDir::new("wav");
        let path = dir.join("take.wav");
        let first: Vec<i16> = (0..1600).map(|i| (i % 200) as i16 * 100).collect();
        assert_eq!(write_pcm16(&path, &first, false).unwrap(), 1600);
        let second: Vec<i16> = vec![1234; 800];
        assert_eq!(
            write_pcm16(&path, &second, true).unwrap(),
            2400,
            "appending adds to the count"
        );
        let back = read(&path).unwrap();
        assert_eq!(back.len(), 2400);
        assert!((back[2399] - 1234.0 / 32768.0).abs() < 1e-3);
        // A write cut short between the samples and the header: the next
        // append keeps what was on disk and puts the header right.
        let mut bytes = std::fs::read(&path).unwrap();
        bytes[40..44].copy_from_slice(&(1600u32 * 2).to_le_bytes());
        std::fs::write(&path, &bytes).unwrap();
        assert_eq!(
            write_pcm16(&path, &second, true).unwrap(),
            3200,
            "the orphaned tail counts"
        );
        assert_eq!(read(&path).unwrap().len(), 3200);
        // Not ours: replaced, not corrupted.
        std::fs::write(&path, b"not a wav").unwrap();
        assert_eq!(write_pcm16(&path, &second, true).unwrap(), 800);
        assert_eq!(read(&path).unwrap().len(), 800);
    }

    #[test]
    fn pcm16_comes_back_as_the_samples_that_went_in() {
        let samples: Vec<f32> = (0..1600).map(|i| ((i as f32) * 0.01).sin() * 0.5).collect();
        let decoded = parse(&encode(&samples, 1)).unwrap();
        assert_eq!(decoded.len(), samples.len());
        for (a, b) in decoded.iter().zip(&samples) {
            assert!((a - b).abs() < 1e-4);
        }
    }

    #[test]
    fn float_samples_come_back_exactly() {
        // `encode`'s PCM16 file, made a 32-bit float one: format tag 3, four
        // bytes a sample, and the data chunk holding the floats themselves.
        let samples = [0.5f32, -0.25, 1.0, -1.0, 0.0];
        let mut bytes = encode(&[0.0; 5], 1);
        bytes[20..22].copy_from_slice(&FORMAT_FLOAT.to_le_bytes());
        bytes[28..32].copy_from_slice(&(SAMPLE_RATE as u32 * 4).to_le_bytes());
        bytes[32..34].copy_from_slice(&4u16.to_le_bytes());
        bytes[34..36].copy_from_slice(&32u16.to_le_bytes());
        let data_at = bytes.windows(4).position(|w| w == b"data").unwrap();
        bytes.truncate(data_at + 4);
        bytes.extend_from_slice(&(samples.len() as u32 * 4).to_le_bytes());
        bytes.extend(samples.iter().flat_map(|s| s.to_le_bytes()));
        let riff_len = (bytes.len() - 8) as u32;
        bytes[4..8].copy_from_slice(&riff_len.to_le_bytes());
        assert_eq!(parse(&bytes).unwrap(), samples);
        assert_eq!(crate::whisper::f32_samples(&[0, 0, 0, 0x3f, 0xff]), [0.5], "a partial sample is not one");
    }

    #[test]
    fn stereo_is_averaged_to_mono() {
        let samples = vec![0.25f32; 800];
        let decoded = parse(&encode(&samples, 2)).unwrap();
        assert_eq!(decoded.len(), 800);
        assert!((decoded[0] - 0.25).abs() < 1e-4);
    }

    #[test]
    fn the_wrong_sample_rate_is_refused_with_the_rate_in_the_sentence() {
        let mut bytes = encode(&[0.0; 16], 1);
        bytes[24..28].copy_from_slice(&44_100u32.to_le_bytes());
        let error = parse(&bytes).unwrap_err();
        assert!(error.contains("44100"), "{error}");
        assert!(parse(b"RIFF\0\0\0\0WAVEfmt ").is_err());
        assert_eq!(parse(b"not a wav at all").unwrap_err(), "not a RIFF/WAVE file");
    }

    /// The module header's rule, both ways round, on a file the recorder wrote
    /// and on one `afconvert` did.
    #[test]
    fn a_short_header_reads_every_sample_and_a_long_one_what_landed() {
        let dir = crate::test_support::TempDir::new("wav-end");
        let path = dir.join("meeting.wav");
        let samples: Vec<i16> = (0..32_000).map(|i| (i % 300) as i16 * 50).collect();
        write_pcm16(&path, &samples, false).unwrap();
        // The meeting service's header from ten seconds ago: 16,000 samples short.
        let mut bytes = std::fs::read(&path).unwrap();
        bytes[40..44].copy_from_slice(&(16_000u32 * 2).to_le_bytes());
        std::fs::write(&path, &bytes).unwrap();
        assert_eq!(read(&path).unwrap().len(), 32_000, "the whole-file read");
        assert_eq!(data_end(&mut std::fs::File::open(&path).unwrap()).unwrap(), HEADER_LEN + 64_000);
        assert_eq!(duration_ms(&path).unwrap(), 2000, "the length");
        assert_eq!(read_span(&path, 1500, 2500).unwrap().len(), 8000, "a span clamped to the samples, not the header");
        assert_eq!(patch_header(&path).unwrap(), 32_000);
        assert_eq!(std::fs::read(&path).unwrap()[40..44], (64_000u32).to_le_bytes(), "the header put right");
        assert_eq!(patch_header(&path).unwrap(), 32_000, "and again is nothing");
        // A header that claims more than landed: clamped to the file, whole samples.
        bytes[40..44].copy_from_slice(&(100_000u32 * 2).to_le_bytes());
        bytes.push(0);
        std::fs::write(&path, &bytes).unwrap();
        assert_eq!(read(&path).unwrap().len(), 32_000);
        assert_eq!(duration_ms(&path).unwrap(), 2000);
        // An afconvert file: FLLR before the data, and a short header reads to the end too.
        let floats: Vec<f32> = (0..8000).map(|i| ((i as f32) * 0.02).sin() * 0.4).collect();
        let mut foreign = encode(&floats, 1);
        let at = data_len_at(&foreign);
        foreign[at..at + 4].copy_from_slice(&(4000u32 * 2).to_le_bytes());
        assert_eq!(parse(&foreign).unwrap().len(), 8000);
        assert_eq!(data_end(&mut Cursor::new(&foreign[..])).unwrap(), foreign.len());
        // ...unless another chunk follows the declared length, which is then the end.
        let mut listed = encode(&floats[..4000], 1);
        listed.extend_from_slice(b"LIST");
        listed.extend_from_slice(&(4u32).to_le_bytes());
        listed.extend_from_slice(b"INFO");
        assert_eq!(parse(&listed).unwrap().len(), 4000, "the chunk after the data is not audio");
    }

    #[test]
    fn a_span_is_the_stretch_asked_for_and_nothing_else() {
        let dir = crate::test_support::TempDir::new("wav-span");
        let path = dir.join("take.wav");
        let samples: Vec<f32> = (0..48_000).map(|i| if i < 16_000 { 0.1 } else if i < 32_000 { 0.2 } else { 0.3 }).collect();
        std::fs::write(&path, encode(&samples, 1)).unwrap();
        let middle = read_span(&path, 1000, 2000).unwrap();
        assert_eq!(middle.len(), 16_000);
        assert!(middle.iter().all(|s| (s - 0.2).abs() < 1e-3), "the second second, through the FLLR chunk");
        let tail = read_span(&path, 2500, 9000).unwrap();
        assert_eq!(tail.len(), 8000, "clamped to the end");
        assert!((tail[0] - 0.3).abs() < 1e-3);
        assert!(read_span(&path, 5000, 6000).unwrap().is_empty(), "past the end is nothing");
        assert!(read_span(&path, 2000, 1000).unwrap().is_empty(), "backwards is nothing");
        assert_eq!(duration_ms(&path).unwrap(), 3000);
        std::fs::write(&path, encode(&samples[..800], 2)).unwrap();
        assert!(read_span(&path, 0, 50).unwrap_err().contains("channels"), "stereo is refused for a span");
        assert!(patch_header(&path).is_err(), "not a recorder WAV");
        assert_eq!(duration_ms(&path).unwrap(), 50, "but its length still reads");
    }
}
