//! What the model said, reduced to what the phone may safely apply.
//!
//! `model.rs` owns the conversation with Ollama and `format.rs` owns the wire.
//! This module owns the one promise the endpoint makes that a prompt cannot:
//! every string handed back to the phone is a piece of the transcript it sent,
//! character for character. The system prompt ASKS for that. This is where it
//! is ENFORCED, because a model told "copy exactly" will still, some fraction
//! of the time, fix a spelling, drop a filler word, or tidy "gonna" into
//! "going to" - and a phone that searched for that string would either fail to
//! find it or, worse, find a different occurrence and bold the wrong words.
//!
//! So nothing here trusts the model. A string that does not occur verbatim is
//! dropped and counted, a list that falls below two items is no longer a list,
//! and the two free-text fields (title and heading) are clamped to the lengths
//! the contract names. Pure functions only - no I/O, no clock - so the rules
//! are tested here rather than discovered on the phone.

use serde::{Deserialize, Serialize};

/// The contract's ceiling on a title, in words.
const TITLE_WORDS: usize = 8;
/// The contract's ceiling on a section heading, in words.
const HEADING_WORDS: usize = 5;

/// Generous caps on how many of each thing one response may carry.
///
/// Not the quality rule - that is the grammar's `maxItems` in `prompt.rs`,
/// which holds each chunk far below these. These bound the WHOLE note after
/// `merge` has folded several chunks together, and they hold on their own if
/// a schema change ever loosens the grammar: a model looping inside an array
/// repeats real phrases, and every repetition PASSES the verbatim filter.
const MAX_EMPHASIS: usize = 40;
const MAX_TASKS: usize = 20;
const MAX_LISTS: usize = 12;
const MAX_ITEMS: usize = 30;
const MAX_SECTIONS: usize = 12;

/// The model's answer as it arrives, tolerant of anything the schema allows.
///
/// Every field defaults, so a model that returns `{}` for a note with nothing
/// in it parses as "nothing to annotate" rather than as a failure. `title` is
/// an Option because some models answer `null` where the schema says string.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Raw {
    pub title: Option<String>,
    pub emphasis: Vec<String>,
    pub tasks: Vec<String>,
    pub lists: Vec<RawList>,
    pub sections: Vec<RawSection>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct RawList {
    pub intro: Option<String>,
    pub items: Vec<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct RawSection {
    pub before: String,
    pub heading: String,
}

/// The annotations the phone receives. Field names ARE the wire contract.
#[derive(Debug, Default, PartialEq, Serialize)]
pub struct Annotations {
    pub title: Option<String>,
    pub emphasis: Vec<String>,
    pub tasks: Vec<String>,
    pub lists: Vec<List>,
    pub sections: Vec<Section>,
}

#[derive(Debug, PartialEq, Serialize)]
pub struct List {
    pub intro: Option<String>,
    pub items: Vec<String>,
}

#[derive(Debug, PartialEq, Serialize)]
pub struct Section {
    pub before: String,
    pub heading: String,
}

/// What the filter did, for the log line and the benchmark.
///
/// `proposed` counts every non-empty pointer the model offered (emphasis,
/// tasks, list intros and items, section starts); `dropped` is how many of
/// those were not in the transcript. `kept / proposed` is the validity rate
/// the benchmark reports. Duplicates are neither: repeating a true string is
/// a loop, not a lie.
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct Tally {
    pub proposed: usize,
    pub dropped: usize,
    pub lists_dropped: usize,
}

impl Tally {
    pub fn add(&mut self, other: Tally) {
        self.proposed += other.proposed;
        self.dropped += other.dropped;
        self.lists_dropped += other.lists_dropped;
    }
}

/// The pointer, if it is one.
///
/// Edges are trimmed first - whitespace, and the commas, semicolons and colons
/// a model tends to carry along from "eggs, milk," - because a trimmed piece
/// of a verbatim string is still verbatim, and `**Thursday,**` is worse
/// bolding than `**Thursday**`. Full stops are left alone on purpose: "5 p.m."
/// trimmed to "5 p.m" is a broken abbreviation, not a tidier one.
///
/// Then the only question that matters: does the transcript contain it, with
/// the same case and the same punctuation. Nothing fuzzy - a near match is
/// exactly the rewrite this module exists to refuse.
fn verbatim<'a>(text: &str, candidate: &'a str) -> Result<&'a str, Miss> {
    let trimmed = candidate
        .trim()
        .trim_matches(|c: char| matches!(c, ',' | ';' | ':') || c.is_whitespace());
    if trimmed.is_empty() {
        return Err(Miss::Empty);
    }
    if text.contains(trimmed) {
        Ok(trimmed)
    } else {
        Err(Miss::NotInText)
    }
}

#[derive(Debug, PartialEq)]
enum Miss {
    /// Blank after trimming - not an offer, so not counted against the model.
    Empty,
    /// Offered and not in the transcript: a rewrite, counted and dropped.
    NotInText,
}

/// Free text (a title or a heading), cleaned and cut to `max` words.
///
/// Markdown the model reached for (`#`, `*`) and wrapping quotes go, trailing
/// sentence punctuation goes (the contract says none - but a closing bracket or
/// a percent sign is part of the words, not punctuation after them), and
/// anything left empty is no title at all rather than an empty one.
fn clamp_words(text: &str, max: usize) -> Option<String> {
    let words: Vec<&str> = text.split_whitespace().take(max).collect();
    let joined = words.join(" ");
    let cleaned = joined
        .trim_matches(|c: char| matches!(c, '#' | '*' | '"' | '\'' | '`' | '\u{201c}' | '\u{201d}'))
        .trim_end_matches(['.', ',', ';', ':', '!', '?', '-', '\u{2026}', '\u{2013}', '\u{2014}'])
        .trim();
    (!cleaned.is_empty()).then(|| cleaned.to_string())
}

/// Keep `candidate` in `out` if it is verbatim and new; tally either way.
fn keep(text: &str, candidate: &str, out: &mut Vec<String>, tally: &mut Tally, cap: usize) {
    match verbatim(text, candidate) {
        Ok(piece) => {
            tally.proposed += 1;
            if out.len() < cap && !out.iter().any(|seen| seen == piece) {
                out.push(piece.to_string());
            }
        }
        Err(Miss::NotInText) => {
            tally.proposed += 1;
            tally.dropped += 1;
        }
        Err(Miss::Empty) => {}
    }
}

/// The model's answer, filtered against the transcript it was given.
pub fn shape(text: &str, raw: Raw) -> (Annotations, Tally) {
    let mut tally = Tally::default();
    let mut out = Annotations {
        title: raw.title.as_deref().and_then(|t| clamp_words(t, TITLE_WORDS)),
        ..Annotations::default()
    };

    for candidate in &raw.emphasis {
        keep(text, candidate, &mut out.emphasis, &mut tally, MAX_EMPHASIS);
    }
    for candidate in &raw.tasks {
        keep(text, candidate, &mut out.tasks, &mut tally, MAX_TASKS);
    }

    for list in raw.lists {
        // An intro that is not in the text is dropped like any other pointer,
        // but the list survives it: "eggs, milk and bread" is still a list
        // when the model misquoted the words before it.
        let intro = match list.intro.as_deref().map(|i| verbatim(text, i)) {
            Some(Ok(piece)) => {
                tally.proposed += 1;
                Some(piece.to_string())
            }
            Some(Err(Miss::NotInText)) => {
                tally.proposed += 1;
                tally.dropped += 1;
                None
            }
            Some(Err(Miss::Empty)) | None => None,
        };
        let mut items = Vec::new();
        for candidate in &list.items {
            keep(text, candidate, &mut items, &mut tally, MAX_ITEMS);
        }
        // One item is a sentence with a comma in it, not an enumeration.
        if items.len() < 2 {
            tally.lists_dropped += 1;
            continue;
        }
        if out.lists.len() < MAX_LISTS {
            out.lists.push(List { intro, items });
        }
    }

    for section in raw.sections {
        let before = match verbatim(text, &section.before) {
            Ok(piece) => {
                tally.proposed += 1;
                piece.to_string()
            }
            Err(Miss::NotInText) => {
                tally.proposed += 1;
                tally.dropped += 1;
                continue;
            }
            Err(Miss::Empty) => continue,
        };
        // A section break with nothing to call it is not something the phone
        // can draw, and it is not the model's fault the heading was blank.
        let Some(heading) = clamp_words(&section.heading, HEADING_WORDS) else {
            continue;
        };
        if out.sections.len() < MAX_SECTIONS && !out.sections.iter().any(|s| s.before == before) {
            out.sections.push(Section { before, heading });
        }
    }

    (out, tally)
}

/// Fold one chunk's annotations into the whole note's.
///
/// The title is the FIRST chunk's: a note is named by how it opens, and a
/// title from the fourth page would name a digression. Everything else is
/// appended in order, deduplicated, and held to the same caps as one chunk.
pub fn merge(into: &mut Annotations, part: Annotations) {
    if into.title.is_none() {
        into.title = part.title;
    }
    for piece in part.emphasis {
        if into.emphasis.len() < MAX_EMPHASIS && !into.emphasis.contains(&piece) {
            into.emphasis.push(piece);
        }
    }
    for piece in part.tasks {
        if into.tasks.len() < MAX_TASKS && !into.tasks.contains(&piece) {
            into.tasks.push(piece);
        }
    }
    for list in part.lists {
        if into.lists.len() < MAX_LISTS && !into.lists.contains(&list) {
            into.lists.push(list);
        }
    }
    for section in part.sections {
        if into.sections.len() < MAX_SECTIONS && !into.sections.iter().any(|s| s.before == section.before) {
            into.sections.push(section);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOTE: &str = "Okay so the kitchen plan for the weekend. I need eggs, milk, bread and coffee.\n\n\
                        I have to call the plumber before Friday at 9:30.\n\n\
                        Different thing, the book club moved to Tuesday.";

    fn raw(json: &str) -> Raw {
        serde_json::from_str(json).expect("test fixture parses")
    }

    #[test]
    fn keeps_what_is_verbatim_and_drops_what_was_rewritten() {
        let (out, tally) = shape(
            NOTE,
            raw(r#"{"emphasis":["Friday at 9:30","Friday at nine thirty"],
                    "tasks":["call the plumber","phone the plumber"]}"#),
        );
        assert_eq!(out.emphasis, vec!["Friday at 9:30"]);
        assert_eq!(out.tasks, vec!["call the plumber"], "a synonym is a rewrite, and is dropped");
        assert_eq!(tally, Tally { proposed: 4, dropped: 2, lists_dropped: 0 });
    }

    #[test]
    fn is_case_and_punctuation_exact() {
        let (out, tally) = shape(NOTE, raw(r#"{"emphasis":["tuesday","Book club","book club moved to Tuesday!"]}"#));
        assert!(out.emphasis.is_empty(), "a near match is exactly the rewrite this refuses: {:?}", out.emphasis);
        assert_eq!(tally.dropped, 3);
    }

    #[test]
    fn trims_carried_commas_but_keeps_full_stops() {
        let text = "Meet at 5 p.m. on Thursday, then eggs, milk.";
        let (out, _) = shape(text, raw(r#"{"emphasis":["  Thursday, ","5 p.m."]}"#));
        assert_eq!(out.emphasis, vec!["Thursday", "5 p.m."]);
    }

    #[test]
    fn a_list_needs_two_surviving_items() {
        let (out, tally) = shape(
            NOTE,
            raw(r#"{"lists":[
                {"intro":"I need","items":["eggs","milk","bread","coffee"]},
                {"intro":"I need","items":["eggs","butter","cheese"]},
                {"intro":null,"items":["coffee"]}
            ]}"#),
        );
        assert_eq!(out.lists.len(), 1, "one survivor is a sentence with a comma in it");
        assert_eq!(out.lists[0].items, vec!["eggs", "milk", "bread", "coffee"]);
        assert_eq!(tally.lists_dropped, 2);
        assert_eq!(tally.dropped, 2, "butter and cheese were never said");
    }

    #[test]
    fn a_misquoted_intro_goes_and_the_list_stays() {
        let (out, tally) = shape(NOTE, raw(r#"{"lists":[{"intro":"I must buy","items":["eggs","milk"]}]}"#));
        assert_eq!(out.lists, vec![List { intro: None, items: vec!["eggs".into(), "milk".into()] }]);
        assert_eq!(tally.dropped, 1);

        let (out, tally) = shape(NOTE, raw(r#"{"lists":[{"intro":"","items":["eggs","milk"]}]}"#));
        assert_eq!(out.lists[0].intro, None, "an empty intro is no intro");
        assert_eq!(tally.proposed, 2, "and is not counted as an offer");
    }

    #[test]
    fn clamps_the_title_to_eight_words_and_strips_trailing_punctuation() {
        let (out, _) = shape(NOTE, raw(r#"{"title":"The kitchen plan for the weekend and the book club too!"}"#));
        assert_eq!(out.title.as_deref(), Some("The kitchen plan for the weekend and the"));

        let (out, _) = shape(NOTE, raw(r#"{"title":"\"Kitchen plan.\""}"#));
        assert_eq!(out.title.as_deref(), Some("Kitchen plan"));

        let (out, _) = shape(NOTE, raw(r#"{"title":"  ...  "}"#));
        assert_eq!(out.title, None, "a title of punctuation is no title");
        let (out, _) = shape(NOTE, raw(r#"{"title":null}"#));
        assert_eq!(out.title, None);
    }

    #[test]
    fn clamps_headings_to_five_words_and_checks_where_sections_begin() {
        let (out, tally) = shape(
            NOTE,
            raw(r#"{"sections":[
                {"before":"Different thing, the book club","heading":"Book club moved to a new day"},
                {"before":"On another note","heading":"Nothing"},
                {"before":"Different thing, the book club","heading":"Duplicate"},
                {"before":"I have to call","heading":"   "}
            ]}"#),
        );
        assert_eq!(
            out.sections,
            vec![Section { before: "Different thing, the book club".into(), heading: "Book club moved to a".into() }]
        );
        assert_eq!(tally.dropped, 1, "only the invented start counts as a rewrite");
    }

    #[test]
    fn repeats_are_collapsed_not_counted_as_lies() {
        let (out, tally) = shape(NOTE, raw(r#"{"emphasis":["Tuesday","Tuesday","Tuesday"]}"#));
        assert_eq!(out.emphasis, vec!["Tuesday"]);
        assert_eq!(tally, Tally { proposed: 3, dropped: 0, lists_dropped: 0 });
    }

    #[test]
    fn a_looping_model_is_capped() {
        let text = (0..100).map(|i| format!("word{i}")).collect::<Vec<_>>().join(" ");
        let many: Vec<String> = (0..100).map(|i| format!("\"word{i}\"")).collect();
        let (out, _) = shape(&text, raw(&format!(r#"{{"emphasis":[{}]}}"#, many.join(","))));
        assert_eq!(out.emphasis.len(), MAX_EMPHASIS);
    }

    #[test]
    fn an_empty_answer_is_nothing_to_annotate() {
        let (out, tally) = shape(NOTE, raw("{}"));
        assert_eq!(out, Annotations::default());
        assert_eq!(tally, Tally::default());
    }

    #[test]
    fn serialises_to_the_wire_contract() {
        let (out, _) = shape(
            NOTE,
            raw(r#"{"title":"","emphasis":["Tuesday"],"tasks":[],"lists":[{"intro":"I need","items":["eggs","milk"]}],
                    "sections":[{"before":"Different thing","heading":"Book club"}]}"#),
        );
        let wire = serde_json::to_value(&out).unwrap();
        assert_eq!(
            wire,
            serde_json::json!({
                "title": null,
                "emphasis": ["Tuesday"],
                "tasks": [],
                "lists": [{ "intro": "I need", "items": ["eggs", "milk"] }],
                "sections": [{ "before": "Different thing", "heading": "Book club" }]
            })
        );
    }

    #[test]
    fn merge_takes_the_first_title_and_dedupes_the_rest() {
        let (mut whole, _) = shape(NOTE, raw(r#"{"title":"Kitchen plan","emphasis":["Friday"],"sections":[{"before":"Different thing","heading":"Books"}]}"#));
        let (part, _) = shape(NOTE, raw(r#"{"title":"Book club","emphasis":["Friday","Tuesday"],"sections":[{"before":"Different thing","heading":"Again"}]}"#));
        merge(&mut whole, part);
        assert_eq!(whole.title.as_deref(), Some("Kitchen plan"), "a note is named by how it opens");
        assert_eq!(whole.emphasis, vec!["Friday", "Tuesday"]);
        assert_eq!(whole.sections.len(), 1);
    }
}
