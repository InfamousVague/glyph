//! Fixed contract for voice-command inference.
//!
//! The model may translate one utterance into append/create/none strings. It
//! never sees note ids or bodies and can never return offsets or Markdown
//! structure decisions. Returned content is untrusted literal user text; the
//! application serializer escapes it before inserting Markdown.

use serde::{Deserialize, Serialize};

pub const MAX_TARGET_CHARS: usize = 120;
pub const MAX_CONTENT_CHARS: usize = 4_000;

/// Native-owned grammar. No caller can provide or modify it.
pub const GRAMMAR: &str = r#"
root ::= ws (append | create | none) ws
append ::= "{" ws "\"action\"" ws ":" ws "\"append\"" ws "," ws "\"target\"" ws ":" ws string ws "," ws "\"content\"" ws ":" ws string ws "," ws "\"placement\"" ws ":" ws placement ws "}"
create ::= "{" ws "\"action\"" ws ":" ws "\"create\"" ws "," ws "\"target\"" ws ":" ws string ws "," ws "\"content\"" ws ":" ws (string | "null") ws "}"
none ::= "{" ws "\"action\"" ws ":" ws "\"none\"" ws "," ws "\"reason\"" ws ":" ws reason ws "}"
placement ::= "\"bugs\"" | "\"tasks\"" | "\"list\"" | "\"notes\"" | "null"
reason ::= "\"unsupported\"" | "\"destructive\"" | "\"compound\"" | "\"unclear\""
string ::= "\"" chars "\""
chars ::= char*
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F])
ws ::= [ \t\n\r]*
"#;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "action", rename_all = "lowercase")]
pub enum CommandIntent {
    Append {
        target: String,
        content: String,
        placement: Option<Placement>,
    },
    Create {
        target: String,
        content: Option<String>,
    },
    None {
        reason: NoneReason,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Placement {
    Bugs,
    Tasks,
    List,
    Notes,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum NoneReason {
    Unsupported,
    Destructive,
    Compound,
    Unclear,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawIntent {
    action: String,
    #[serde(default)]
    target: Option<String>,
    #[serde(default)]
    content: Option<String>,
    #[serde(default)]
    placement: Option<Placement>,
    #[serde(default)]
    reason: Option<NoneReason>,
}

fn clean(value: String, max: usize, label: &str) -> Result<String, String> {
    let value = value.trim().to_string();
    let count = value.chars().count();
    if count == 0 || count > max || value.chars().any(char::is_control) {
        return Err(format!(
            "the inferred {label} is empty, too long, or contains control characters"
        ));
    }
    Ok(value)
}

/// Parses the entire model answer. Prose, fences, trailing JSON, unknown keys,
/// wrong field combinations, and truncated output all fail closed.
pub fn parse(text: &str, truncated: bool) -> Result<CommandIntent, String> {
    if truncated {
        return Err("the command inference was truncated".into());
    }
    let value: serde_json::Value = serde_json::from_str(text.trim())
        .map_err(|_| "the command inference was not exactly one valid object".to_string())?;
    let object = value
        .as_object()
        .ok_or_else(|| "the command inference was not an object".to_string())?;
    let action = object
        .get("action")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("");
    let expected: &[&str] = match action {
        "append" => &["action", "target", "content", "placement"],
        "create" => &["action", "target", "content"],
        "none" => &["action", "reason"],
        _ => return Err("the command inference used an unsupported action".into()),
    };
    if object.len() != expected.len() || expected.iter().any(|key| !object.contains_key(*key)) {
        return Err("the command inference used unsupported or missing fields".into());
    }
    let raw: RawIntent = serde_json::from_value(value)
        .map_err(|_| "the command inference fields had invalid types".to_string())?;
    match raw.action.as_str() {
        "append" if raw.reason.is_none() => Ok(CommandIntent::Append {
            target: clean(
                raw.target
                    .ok_or_else(|| "append has no target".to_string())?,
                MAX_TARGET_CHARS,
                "target",
            )?,
            content: clean(
                raw.content
                    .ok_or_else(|| "append has no content".to_string())?,
                MAX_CONTENT_CHARS,
                "content",
            )?,
            placement: raw.placement,
        }),
        "create" if raw.reason.is_none() && raw.placement.is_none() => Ok(CommandIntent::Create {
            target: clean(
                raw.target
                    .ok_or_else(|| "create has no title".to_string())?,
                MAX_TARGET_CHARS,
                "title",
            )?,
            content: raw
                .content
                .map(|content| clean(content, MAX_CONTENT_CHARS, "content"))
                .transpose()?,
        }),
        "none" if raw.target.is_none() && raw.content.is_none() && raw.placement.is_none() => {
            Ok(CommandIntent::None {
                reason: raw.reason.ok_or_else(|| "none has no reason".to_string())?,
            })
        }
        _ => Err("the command inference used an unsupported field combination".into()),
    }
}

/// A model is not asked to reinterpret requests outside the single safe set.
pub fn refusal(utterance: &str) -> Option<NoneReason> {
    let lower = utterance.to_lowercase();
    let destructive = [
        "delete",
        "remove",
        "erase",
        "destroy",
        "archive",
        "overwrite",
        "replace",
        "rename",
        "share",
        "email",
        "send ",
    ];
    if destructive.iter().any(|word| lower.contains(word)) {
        return Some(NoneReason::Destructive);
    }
    let action_words = lower
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| {
            matches!(
                *word,
                "add" | "append" | "put" | "create" | "make" | "start"
            )
        })
        .count();
    if lower.contains(" and then ") || lower.contains(';') || action_words > 1 {
        return Some(NoneReason::Compound);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_the_small_structured_set() {
        assert_eq!(
            parse(r#"{"action":"append","target":"Attack FM","content":"losing position at 42%","placement":"bugs"}"#, false).unwrap(),
            CommandIntent::Append { target: "Attack FM".into(), content: "losing position at 42%".into(), placement: Some(Placement::Bugs) }
        );
        assert_eq!(
            parse(
                r#"{"action":"create","target":"apartment stuff","content":null}"#,
                false
            )
            .unwrap(),
            CommandIntent::Create {
                target: "apartment stuff".into(),
                content: None
            }
        );
    }

    #[test]
    fn control_characters_fail_for_append_and_create_content() {
        for bad in [
            "{\"action\":\"append\",\"target\":\"AttackFM\",\"content\":\"bad\\nheading\",\"placement\":\"bugs\"}",
            "{\"action\":\"create\",\"target\":\"Safe\",\"content\":\"bad\\tcontent\"}",
            "{\"action\":\"append\",\"target\":\"AttackFM\",\"content\":\"bad\\u0000value\",\"placement\":\"bugs\"}",
        ] {
            assert!(parse(bad, false).is_err(), "{bad}");
        }
    }

    #[test]
    fn malformed_truncated_extra_and_wrong_shapes_fail_closed() {
        for bad in [
            r#"```json\n{"action":"none","reason":"unclear"}\n```"#,
            r#"{"action":"append","target":"x"}"#,
            r#"{"action":"create","target":"x","content":null,"id":"n1"}"#,
            r#"{"action":"none","reason":"unsupported"} trailing"#,
            r#"{"action":"delete","target":"x"}"#,
        ] {
            assert!(parse(bad, false).is_err(), "{bad}");
        }
        assert!(parse(r#"{"action":"none","reason":"unclear"}"#, true).is_err());
    }

    #[test]
    fn destructive_and_compound_requests_are_refused_before_inference() {
        assert_eq!(
            refusal("delete my work note"),
            Some(NoneReason::Destructive)
        );
        assert_eq!(
            refusal("create errands and then add milk to it"),
            Some(NoneReason::Compound)
        );
        assert_eq!(
            refusal("put a bug about losing position in Attack FM"),
            None
        );
    }
}
