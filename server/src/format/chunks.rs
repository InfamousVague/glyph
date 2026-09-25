//! A long transcript, cut into the pieces the model reads one at a time.
//!
//! Apart from the verbatim rule in `shape.rs` because it answers a different question - not "is this what was said"
//! but "how much can the runner read at once" - and because the pieces it makes are what keep that rule honest: they
//! are contiguous slices of the transcript, so anything verbatim in a piece is verbatim in the whole. Pure functions,
//! as shape.rs's are.

/// The transcript, cut into pieces no longer than `budget` bytes.
///
/// WHY THIS EXISTS AT ALL: the model runs inside the SAME Ollama runner
/// AttackFM keeps loaded, and that runner was started with a 4,096-token
/// context. Asking for a bigger one is not a request option here - a
/// different `num_ctx` makes Ollama reload the model, which is exactly the
/// eviction this service promises not to cause. A 16 KB transcript is about
/// 4,000 tokens on its own, so past a point the note has to be read in parts
/// or Ollama silently truncates it and the model annotates half of it.
///
/// Cuts prefer, in order: a paragraph break, the end of a sentence, any
/// whitespace, and only then a bare character boundary. The pieces are
/// contiguous slices of `text`, which is what keeps the verbatim rule
/// honest - anything verbatim in a piece is verbatim in the whole.
pub fn chunks(text: &str, budget: usize) -> Vec<&str> {
    let budget = budget.max(1);
    let mut out = Vec::new();
    let mut start = 0;
    while text.len() - start > budget {
        let window_end = floor_char_boundary(text, start + budget);
        let window = &text[start..window_end];
        let cut = last_cut(window, |w, i| w[..i].ends_with("\n\n"))
            .or_else(|| last_cut(window, |w, i| ends_sentence(&w[..i])))
            .or_else(|| last_cut(window, |w, i| w[..i].ends_with(char::is_whitespace)))
            .unwrap_or(window.len());
        // A zero-length piece would loop forever; a window with no cut point
        // at all is cut at its end instead.
        let cut = if cut == 0 { window.len().max(1) } else { cut };
        let end = floor_char_boundary(text, start + cut).max(start + 1);
        out.push(&text[start..end]);
        start = end;
    }
    if start < text.len() || out.is_empty() {
        out.push(&text[start..]);
    }
    out
}

/// The last index in `window` (a char boundary, never 0) where `is_cut` holds.
fn last_cut(window: &str, is_cut: impl Fn(&str, usize) -> bool) -> Option<usize> {
    window
        .char_indices()
        .map(|(i, c)| i + c.len_utf8())
        .rev()
        .find(|&i| is_cut(window, i))
}

fn ends_sentence(prefix: &str) -> bool {
    let mut tail = prefix.chars().rev();
    matches!(
        (tail.next(), tail.next()),
        (Some(space), Some('.' | '?' | '!')) if space.is_whitespace()
    )
}

/// `str::floor_char_boundary`, which is not stable on this toolchain.
fn floor_char_boundary(text: &str, index: usize) -> usize {
    if index >= text.len() {
        return text.len();
    }
    let mut i = index;
    while !text.is_char_boundary(i) {
        i -= 1;
    }
    i
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOTE: &str = "Okay so the kitchen plan for the weekend. I need eggs, milk, bread and coffee.\n\n\
                        I have to call the plumber before Friday at 9:30.\n\n\
                        Different thing, the book club moved to Tuesday.";

    #[test]
    fn a_short_note_is_one_chunk() {
        assert_eq!(chunks(NOTE, 6000), vec![NOTE]);
        assert_eq!(chunks("", 6000), vec![""]);
    }

    #[test]
    fn chunks_are_contiguous_bounded_and_cut_at_paragraphs_first() {
        let pieces = chunks(NOTE, 100);
        assert_eq!(pieces.concat(), NOTE, "nothing lost, nothing reordered");
        assert!(pieces.iter().all(|p| p.len() <= 100), "{pieces:?}");
        assert!(pieces[0].ends_with("\n\n"), "the first cut is the paragraph break: {:?}", pieces[0]);
    }

    #[test]
    fn a_paragraph_longer_than_the_budget_is_cut_at_a_sentence() {
        let one_paragraph = "First sentence here. Second sentence here. Third sentence here.";
        let pieces = chunks(one_paragraph, 30);
        assert_eq!(pieces.concat(), one_paragraph);
        assert_eq!(pieces[0], "First sentence here. ");
    }

    #[test]
    fn chunking_never_splits_a_character_or_stalls() {
        let text = "é".repeat(50); // two bytes each, no spaces, no sentences
        let pieces = chunks(&text, 7);
        assert_eq!(pieces.concat(), text);
        assert!(pieces.iter().all(|p| !p.is_empty() && p.len() <= 7));
    }
}
