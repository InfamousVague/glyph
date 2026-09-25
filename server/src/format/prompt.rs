//! What the model is asked, and what holds it to its answer: the system prompt, the JSON schema generation is
//! constrained to with its item ceilings, and the sampling options a chat carries.
//!
//! Apart from the conversation in `model.rs` because these are the words and numbers a change to the pass is made
//! in, and the tests below hold them to each other: the prompt's worked example must obey the verbatim rule itself and
//! fit inside the ceilings, or the model is taught by example to do what it is told not to.
//!
//! What a chat deliberately never carries: `num_ctx`, `num_thread`,
//! `num_batch` or any other option that changes how a runner is LOADED. The
//! model here is a runner AttackFM already has in memory, and Ollama answers a
//! request whose load options differ from the loaded runner's by unloading it
//! and loading a new one - an eviction of the production server's model,
//! caused by a note-taking app. Sampling options (temperature, `num_predict`)
//! are per request and safe. `keep_alive` is left unset for the same reason:
//! the server's 15-minute default is AttackFM's too, and a different value
//! here would shorten or stretch the life of a runner this service does not
//! own.

use serde_json::{json, Value};

/// Close to deterministic. There is no creative latitude in "which of these
/// words are a date", and every point of temperature is a chance to paraphrase.
const TEMPERATURE: f64 = 0.1;

/// The most tokens one chunk may generate before Ollama stops it.
///
/// The schema's item ceilings already bound an honest answer well below this;
/// it is here for the dishonest one. A model looping inside a string does not
/// stop on its own, and MEASURED on the box, qwen3.5:9b generated at 4.1
/// tokens a second - so every runaway token is a quarter of a second of the
/// slot AttackFM is waiting for.
pub const NUM_PREDICT: u32 = 400;

/// The instruction. Fixed and first, on purpose: Ollama reuses the KV cache
/// for a prompt prefix it has already evaluated, so after the first call the
/// only tokens paid for on the way in are the transcript's own.
const SYSTEM_PROMPT: &str = r#"You annotate a voice note. You never rewrite it.

The user message is a transcript of someone talking. Reply with JSON that POINTS AT parts of it. Every string in emphasis, tasks, lists and sections.before must be copied from the transcript exactly: the same words, spelling, capitals and punctuation. Never fix, reword, shorten or summarise. If you cannot copy a phrase exactly, leave it out.

- title: up to 8 words on what the note is about, in its own words, no punctuation at the end. "" if nothing fits.
- emphasis: only names, dates, times, numbers and decisions. Few: most sentences have none. Never words already in a task or a list.
- tasks: things the speaker must do, as the shortest exact phrase, like "call the plumber".
- lists: things listed in one sentence. intro: the exact words that introduce the list, or "". items: each thing, exact, in order. Two or more.
- sections: only where the topic clearly changes. before: the first exact words of the new topic. heading: up to 5 words. None for a note on one topic.

Example transcript:
Right, notes on the garden. We need compost, twine and seed potatoes. I have to call Tom about the fence on Monday at 10.

Anyway, the car is due its service in March.

Example reply:
{"title":"Notes on the garden","emphasis":["Monday at 10","March"],"tasks":["call Tom about the fence"],"lists":[{"intro":"We need","items":["compost","twine","seed potatoes"]}],"sections":[{"before":"Anyway, the car is due","heading":"The car"}]}"#;

/// The shape Ollama constrains generation to, so the model cannot answer in
/// prose, markdown fences, or a friendly preamble.
///
/// `title` and `intro` are plain strings with "" for none rather than
/// `["string", "null"]`: a union compiles to a larger grammar and buys nothing,
/// because `shape.rs` maps "" to null on the way out either way.
///
/// THE CEILINGS ARE THE LATENCY. Generation is the slow half of a call, and the
/// first measured run on the box bolded 24 phrases in a 198-word note - eggs,
/// milk, "floor" - for 350 output tokens and 85 seconds of generation. A prompt
/// that says "few" is advice; `maxItems` is compiled into the grammar, so the
/// model is made to close the array. They are per chunk, and deliberately
/// tight for a model generating four tokens a second: a faster model later
/// can be given more room here and nowhere else.
const MAX_EMPHASIS: u64 = 8;
const MAX_TASKS: u64 = 8;
const MAX_LISTS: u64 = 4;
const MAX_LIST_ITEMS: u64 = 12;
const MAX_SECTIONS: u64 = 4;

fn schema() -> Value {
    let strings = |max: u64| json!({ "type": "array", "items": { "type": "string" }, "maxItems": max });
    json!({
        "type": "object",
        "properties": {
            "title": { "type": "string" },
            "emphasis": strings(MAX_EMPHASIS),
            "tasks": strings(MAX_TASKS),
            "lists": {
                "type": "array",
                "maxItems": MAX_LISTS,
                "items": {
                    "type": "object",
                    "properties": { "intro": { "type": "string" }, "items": strings(MAX_LIST_ITEMS) },
                    "required": ["intro", "items"]
                }
            },
            "sections": {
                "type": "array",
                "maxItems": MAX_SECTIONS,
                "items": {
                    "type": "object",
                    "properties": { "before": { "type": "string" }, "heading": { "type": "string" } },
                    "required": ["before", "heading"]
                }
            }
        },
        "required": ["title", "emphasis", "tasks", "lists", "sections"]
    })
}

/// The body of one `/api/chat` for `chunk`: streamed, in the schema's shape, the system prompt first and the
/// transcript after it, with sampling options and nothing that would reload the runner. `model.rs` adds `think`
/// when the model has it.
pub fn chat(model: &str, chunk: &str) -> Value {
    json!({
        "model": model,
        "stream": true,
        "format": schema(),
        "messages": [
            { "role": "system", "content": SYSTEM_PROMPT },
            { "role": "user", "content": chunk }
        ],
        "options": { "temperature": TEMPERATURE, "num_predict": NUM_PREDICT }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format::shape::{self, Raw};

    /// The worked example's transcript, as the prompt carries it.
    fn example_transcript() -> &'static str {
        SYSTEM_PROMPT
            .split("Example transcript:\n")
            .nth(1)
            .and_then(|rest| rest.split("\n\nExample reply:").next())
            .expect("the prompt carries an example transcript")
    }

    /// The worked example's reply, as the prompt carries it: the text after its last "Example reply:".
    fn example_reply_text() -> &'static str {
        SYSTEM_PROMPT.rsplit("Example reply:\n").next().unwrap()
    }

    fn example_reply() -> Value {
        serde_json::from_str(example_reply_text()).expect("the example reply is valid JSON")
    }

    #[test]
    fn the_worked_example_obeys_its_own_rules() {
        // If the example in the prompt were not itself verbatim, the model
        // would be taught by demonstration to do the thing the words forbid.
        let transcript = example_transcript();
        let raw: Raw = serde_json::from_str(example_reply_text()).expect("the example reply is valid JSON");
        let (shaped, tally) = shape::shape(transcript, raw);
        assert_eq!(tally.dropped, 0, "every pointer in the example is verbatim");
        assert_eq!(tally.lists_dropped, 0);
        assert_eq!(shaped.sections.len(), 1);
        assert_eq!(shaped.lists[0].items.len(), 3);
    }

    #[test]
    fn the_example_reply_matches_the_schema_it_is_constrained_to() {
        let reply = example_reply();
        let schema = schema();
        for key in schema["required"].as_array().unwrap() {
            assert!(reply.get(key.as_str().unwrap()).is_some(), "example is missing {key}");
        }
        assert_eq!(reply.as_object().unwrap().len(), schema["properties"].as_object().unwrap().len());
    }

    #[test]
    fn the_example_reply_fits_inside_the_ceilings() {
        // A worked example the grammar could not have produced would teach the
        // model an answer it is then forbidden to finish.
        let reply = example_reply();
        let schema = schema();
        for key in ["emphasis", "tasks", "lists", "sections"] {
            let max = schema["properties"][key]["maxItems"].as_u64().unwrap();
            assert!(reply[key].as_array().unwrap().len() as u64 <= max, "{key}");
        }
        assert_eq!(schema["properties"]["lists"]["items"]["properties"]["items"]["maxItems"], MAX_LIST_ITEMS);
    }

    #[test]
    fn a_chat_streams_the_schema_with_the_prompt_first_and_no_load_options() {
        let body = chat("qwen3.5:9b", "call the plumber");
        assert_eq!(body["model"], "qwen3.5:9b");
        assert_eq!(body["stream"], true);
        assert_eq!(body["format"], schema());
        assert_eq!(body["messages"][0], json!({ "role": "system", "content": SYSTEM_PROMPT }), "fixed and first, for the KV cache");
        assert_eq!(body["messages"][1], json!({ "role": "user", "content": "call the plumber" }));
        assert_eq!(body["options"], json!({ "temperature": TEMPERATURE, "num_predict": NUM_PREDICT }), "sampling only");
        assert!(body.get("keep_alive").is_none() && body.get("think").is_none());
    }
}
