//! A request, framed in the model's chat template - with no model loaded.
//!
//! The engine needs the prompt in two pieces: the PREFIX (the template's
//! opening, the system prompt, any context and the template's user header),
//! which is the same from one note to the next and is snapshotted, and the
//! REST (the note and the template's closing), which is not. llama.cpp can
//! only render a whole conversation, so the conversation is rendered once with
//! a sentinel where the note goes, and cut at the sentinel.

/// Stands where the note will go. Private-use code points, which no template
/// writes and no tokenizer merges with a neighbour.
pub const SENTINEL: &str = "\u{E000}glyph-note\u{E001}";

/// Appended after the assistant header for a model whose template knows about
/// thinking: an empty thought, which is how Qwen's own templates switch
/// reasoning off. A model that reasons first spends hundreds of tokens before
/// the first word of the note, and a person watching the note take shape sees
/// nothing happen for a minute.
pub const EMPTY_THOUGHT: &str = "<think>\n\n</think>\n\n";

/// Closes a thought that has run past its budget, so the answer comes. Qwen's
/// own advice for budget forcing is to end the thinking in the model's voice
/// and close the tag: the model then answers from what it has thought so far.
pub const THOUGHT_CUTOFF: &str = "\n\nI have thought about this enough; time to give the answer from what I have so far.\n</think>\n\n";

/// The system message: the page's system prompt, then any context.
///
/// Context goes in the system message rather than beside the note so that it
/// is part of the snapshotted prefix: a project's context pack, when that
/// feature lands, is the longest thing in a prompt and the same for every note
/// on the project.
pub fn system_text(system: &str, context: Option<&str>) -> String {
    match context.map(str::trim).filter(|c| !c.is_empty()) {
        Some(context) => format!("{}\n\n{context}", system.trim_end()),
        None => system.trim_end().to_string(),
    }
}

/// The rendered conversation, cut at the sentinel.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Framed {
    pub prefix: String,
    pub suffix: String,
}

/// Cuts `rendered` - a conversation whose user message was [`SENTINEL`] - into
/// the part before the note and the part after it, adding [`EMPTY_THOUGHT`]
/// when the template `thinks`.
///
/// Refuses a rendering with no sentinel or more than one, which would mean the
/// template rewrote the message (trimmed it, escaped it) and the cut would put
/// the note somewhere the model was not told it would be.
pub fn frame(rendered: &str, thinks: bool) -> Result<Framed, String> {
    let mut parts = rendered.split(SENTINEL);
    let (Some(prefix), Some(suffix), None) = (parts.next(), parts.next(), parts.next()) else {
        return Err("the model's chat template did not keep the note in one place".to_string());
    };
    let mut suffix = suffix.to_string();
    if thinks && !suffix.contains("<think>") {
        suffix.push_str(EMPTY_THOUGHT);
    }
    Ok(Framed {
        prefix: prefix.to_string(),
        suffix,
    })
}

/// The model's own chat template, rendered: for a model whose template
/// llama.cpp does not know by its marks (GLY-2, GLY-5; docs/DESIGN.md §163).
///
/// llama.cpp renders a conversation from a list of templates it recognises
/// by a few characters each - `<|im_start|>` for Qwen's ChatML,
/// `<start_of_turn>` for Gemma 2 and 3 - and answers -1 for any other, which
/// llama-cpp-2 reports as "ffi error -1". Gemma 4's template is none of
/// them, so every request on it failed: every summary ("The summary didn't
/// come"), every fill, every rewrite. The template itself is in the model's
/// file, `tokenizer.chat_template`, as the Jinja the model was trained with,
/// so a template llama.cpp does not know is rendered from that instead, with
/// the variables Hugging Face's renderer gives it: the messages, the
/// generation prompt, the BOS and EOS tokens as text (the tokenizer parses
/// them back into tokens), and `enable_thinking` for the templates that
/// switch reasoning on and off with it.
///
/// Chat templates are written for Python's Jinja, so Python's string and
/// dictionary methods are there (`.strip()`, `.startswith()`, `.items()`),
/// as are `{% break %}`, `tojson`, `raise_exception` and `strftime_now`. A
/// template that refuses a system turn (Gemma 2's raises) is rendered again
/// with the system prompt at the head of the user's turn, which is where
/// those models are trained to read it.
pub fn render_template(source: &str, system: &str, user: &str, bos: &str, eos: &str, think: bool) -> Result<String, String> {
    let mut env = minijinja::Environment::new();
    env.set_unknown_method_callback(minijinja_contrib::pycompat::unknown_method_callback);
    env.add_function("raise_exception", |message: String| -> Result<String, minijinja::Error> {
        Err(minijinja::Error::new(minijinja::ErrorKind::InvalidOperation, message))
    });
    env.add_function("strftime_now", |format: String| strftime_now(&format));
    env.add_template("chat", source).map_err(|e| format!("the model's chat template cannot be read: {e}"))?;
    let template = env.get_template("chat").map_err(|e| e.to_string())?;
    let render = |messages: minijinja::Value| {
        template.render(minijinja::context! {
            messages => messages,
            add_generation_prompt => true,
            bos_token => bos,
            eos_token => eos,
            enable_thinking => think,
        })
    };
    let turn = |role: &str, content: &str| minijinja::context! { role => role, content => content };
    let turns = minijinja::Value::from(vec![turn("system", system), turn("user", user)]);
    match render(turns) {
        Ok(text) if text.matches(SENTINEL).count() == 1 => Ok(text),
        first => {
            let merged = format!("{}\n\n{user}", system.trim_end());
            let alone = minijinja::Value::from(vec![turn("user", &merged)]);
            match render(alone) {
                Ok(text) => Ok(text),
                Err(e) => Err(match first {
                    Err(original) => format!("the model's chat template cannot be rendered: {original}"),
                    Ok(_) => format!("the model's chat template cannot be rendered: {e}"),
                }),
            }
        }
    }
}

/// Today's date in `format`, for a template that dates its system prompt
/// (`strftime_now("%d %b %Y")`): the common directives, in UTC.
fn strftime_now(format: &str) -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let (year, month, day) = civil_from_days((secs / 86_400) as i64);
    const MONTHS: [&str; 12] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
    let name = MONTHS[(month - 1) as usize];
    let mut out = String::new();
    let mut chars = format.chars();
    while let Some(c) = chars.next() {
        if c != '%' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('Y') => out.push_str(&year.to_string()),
            Some('y') => out.push_str(&format!("{:02}", year % 100)),
            Some('m') => out.push_str(&format!("{month:02}")),
            Some('d') => out.push_str(&format!("{day:02}")),
            Some('e') => out.push_str(&day.to_string()),
            Some('B') => out.push_str(name),
            Some('b') => out.push_str(&name[..3]),
            Some('%') => out.push('%'),
            Some(other) => {
                out.push('%');
                out.push(other);
            }
            None => out.push('%'),
        }
    }
    out
}

/// A day count from 1970-01-01 as a year, a month and a day (Howard Hinnant's
/// `civil_from_days`).
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + i64::from(month <= 2), month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    const CHATML: &str = "<|im_start|>system\nYou format notes.<|im_end|>\n<|im_start|>user\n\u{E000}glyph-note\u{E001}<|im_end|>\n<|im_start|>assistant\n";

    #[test]
    fn the_prefix_is_everything_before_the_note() {
        let framed = frame(CHATML, false).unwrap();
        assert_eq!(framed.prefix, "<|im_start|>system\nYou format notes.<|im_end|>\n<|im_start|>user\n");
        assert_eq!(framed.suffix, "<|im_end|>\n<|im_start|>assistant\n");
    }

    #[test]
    fn the_snapshotted_prefix_excludes_every_user_utterance() {
        let framed = frame(CHATML, false).unwrap();
        let old = format!("{}{}{}", framed.prefix, "make Brofries", framed.suffix);
        let current = format!("{}{}{}", framed.prefix, "add eggs to groceries", framed.suffix);
        assert_eq!(&old[..framed.prefix.len()], framed.prefix);
        assert_eq!(&current[..framed.prefix.len()], framed.prefix);
        assert!(!framed.prefix.contains("Brofries"));
        assert!(!framed.prefix.contains("groceries"));
        assert_ne!(old, current, "only the uncached user remainder changes");
    }

    #[test]
    fn a_thinking_template_gets_an_empty_thought_once() {
        assert_eq!(frame(CHATML, true).unwrap().suffix, "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n");
        let already = CHATML.replace("assistant\n", "assistant\n<think>\n\n</think>\n\n");
        assert_eq!(frame(&already, true).unwrap().suffix.matches("<think>").count(), 1);
    }

    #[test]
    fn a_template_that_lost_or_repeated_the_note_is_refused() {
        assert!(frame("<|im_start|>user\n<|im_end|>", false).is_err());
        assert!(frame(&format!("{SENTINEL}{SENTINEL}"), false).is_err());
    }

    /// Qwen's ChatML as Jinja, the shape llama.cpp already knows.
    const CHATML_JINJA: &str = "{%- for message in messages %}{{ '<|im_start|>' + message['role'] + '\\n' + message['content'] + '<|im_end|>\\n' }}{%- endfor %}{%- if add_generation_prompt %}{{ '<|im_start|>assistant\\n' }}{%- endif %}";

    /// Gemma 3's own template: the system prompt folded into the first user
    /// turn, roles checked to alternate, the content trimmed.
    const GEMMA_3: &str = "{{ bos_token }}\n{%- if messages[0]['role'] == 'system' -%}\n{%- set first_user_prefix = messages[0]['content'] + '\\n\\n' -%}\n{%- set loop_messages = messages[1:] -%}\n{%- else -%}\n{%- set first_user_prefix = \"\" -%}\n{%- set loop_messages = messages -%}\n{%- endif -%}\n{%- for message in loop_messages -%}\n{%- if (message['role'] == 'user') != (loop.index0 % 2 == 0) -%}\n{{ raise_exception(\"Conversation roles must alternate user/assistant/user/assistant/...\") }}\n{%- endif -%}\n{%- if (message['role'] == 'assistant') -%}{%- set role = \"model\" -%}{%- else -%}{%- set role = message['role'] -%}{%- endif -%}\n{{ '<start_of_turn>' + role + '\\n' + (first_user_prefix if loop.first else \"\") }}\n{%- if message['content'] is string -%}{{ message['content'] | trim }}{%- endif -%}\n{{ '<end_of_turn>\\n' }}\n{%- endfor -%}\n{%- if add_generation_prompt -%}{{ '<start_of_turn>model\\n' }}{%- endif -%}";

    /// Gemma 2's, which refuses a system turn outright.
    const GEMMA_2: &str = "{{ bos_token }}{% if messages[0]['role'] == 'system' %}{{ raise_exception('System role not supported') }}{% endif %}{% for message in messages %}{% if (message['role'] == 'assistant') %}{% set role = 'model' %}{% else %}{% set role = message['role'] %}{% endif %}{{ '<start_of_turn>' + role + '\\n' + message['content'] | trim + '<end_of_turn>\\n' }}{% endfor %}{% if add_generation_prompt %}{{'<start_of_turn>model\\n'}}{% endif %}";

    /// A template in marks llama.cpp has no name for, written with Python's
    /// methods, a namespace, a `break`, `tojson`, `strftime_now` and a switch
    /// for thinking: the shape a new model's template takes.
    const UNKNOWN: &str = "{{ bos_token }}{%- set ns = namespace(system='') -%}{%- for m in messages -%}{%- if m.role == 'system' -%}{%- set ns.system = m.content.strip() -%}{%- break -%}{%- endif -%}{%- endfor -%}<|turn>system\nToday is {{ strftime_now('%d %B %Y') }}. {{ ns.system }}<turn|>\n{%- for m in messages if m.role != 'system' -%}<|turn>{{ m.role }}\n{{ m.content }}<turn|>\n{%- endfor -%}{%- if add_generation_prompt -%}<|turn>model\n{%- if not enable_thinking -%}<|think|><|/think|>{%- endif -%}{%- endif -%}{{ '' if messages|tojson else '' }}";

    #[test]
    fn a_known_template_renders_as_llama_cpp_would() {
        let rendered = render_template(CHATML_JINJA, "You format notes.", SENTINEL, "", "", false).unwrap();
        assert_eq!(rendered, CHATML);
    }

    #[test]
    fn gemma_3_folds_the_system_prompt_into_the_users_turn() {
        let rendered = render_template(GEMMA_3, "You format notes.\n", SENTINEL, "<bos>", "<eos>", false).unwrap();
        assert_eq!(rendered, format!("<bos><start_of_turn>user\nYou format notes.\n\n\n{SENTINEL}<end_of_turn>\n<start_of_turn>model\n"));
        let framed = frame(&rendered, false).unwrap();
        assert!(framed.prefix.starts_with("<bos><start_of_turn>user\nYou format notes."));
        assert_eq!(framed.suffix, "<end_of_turn>\n<start_of_turn>model\n");
    }

    #[test]
    fn a_template_that_refuses_a_system_turn_has_it_at_the_head_of_the_users() {
        let rendered = render_template(GEMMA_2, "You format notes.", SENTINEL, "<bos>", "<eos>", false).unwrap();
        assert_eq!(rendered, format!("<bos><start_of_turn>user\nYou format notes.\n\n{SENTINEL}<end_of_turn>\n<start_of_turn>model\n"));
        assert!(frame(&rendered, false).is_ok());
    }

    #[test]
    fn a_template_llama_cpp_has_no_name_for_renders_with_pythons_methods() {
        let rendered = render_template(UNKNOWN, "  You format notes.  ", SENTINEL, "<bos>", "<eos>", false).unwrap();
        assert!(rendered.starts_with("<bos><|turn>system\nToday is "), "{rendered}");
        // Its `{%-` takes the line break before it, as Python's Jinja does.
        assert!(rendered.contains(". You format notes.<turn|><|turn>user\n"), "{rendered}");
        assert!(rendered.ends_with(&format!("{SENTINEL}<turn|><|turn>model<|think|><|/think|>")), "{rendered}");
        let thinking = render_template(UNKNOWN, "You format notes.", SENTINEL, "<bos>", "<eos>", true).unwrap();
        assert!(thinking.ends_with("<|turn>model"), "{thinking}");
        assert_eq!(frame(&rendered, false).unwrap().prefix.matches(SENTINEL).count(), 0);
    }

    #[test]
    fn a_template_that_cannot_be_read_says_so() {
        assert!(render_template("{% for %}", "s", SENTINEL, "", "", false).unwrap_err().contains("cannot be read"));
        let refuses = "{{ raise_exception('no') }}";
        assert!(render_template(refuses, "s", SENTINEL, "", "", false).unwrap_err().contains("cannot be rendered"));
    }

    #[test]
    fn todays_date_is_written_as_asked() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(20_727), (2026, 10, 1));
        let today = strftime_now("%Y-%m-%d %b %%");
        let (year, month, day) = civil_from_days((std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() / 86_400) as i64);
        assert!(today.starts_with(&format!("{year}-{month:02}-{day:02} ")), "{today}");
        assert!(today.ends_with(" %"), "{today}");
    }

    #[test]
    fn context_joins_the_system_prompt_and_blank_context_does_not() {
        assert_eq!(system_text("Format.\n", Some("# Glyph\nA notes app.")), "Format.\n\n# Glyph\nA notes app.");
        assert_eq!(system_text("Format.", Some("  \n")), "Format.");
        assert_eq!(system_text("Format.", None), "Format.");
    }
}
