//! Slack, from the phone: the channels' incoming webhooks, kept where no page
//! can read them back, and the one post a page may ask for.
//!
//! Matt chose webhooks for the Slack plugin ("include #6 as a plugin as well as
//! #5", where #5 was a meeting's summary or a note posted to a channel when the
//! person chooses): no sign-in and no server, the post goes straight from the
//! device. Two reasons it is native:
//!
//! - hooks.slack.com does not answer a web page's cross-origin requests, and
//!   the page runs at `http://tauri.localhost`, so a `fetch` from there fails;
//! - a webhook URL is a secret (whoever has it can post to the channel), so it
//!   is written here once, to `slack.json` in the app's own data directory, and
//!   the page only ever names a channel by the id it gave it. The page keeps
//!   the names; this file keeps id to URL.
//!
//! Every URL is held to Slack's own webhook hosts and paths (`allowed_webhook`)
//! when it is kept and again when it is posted to, and a post follows no
//! redirect, so a kept webhook cannot be turned into a request anywhere else.
//!
//! THE CONTRACT WITH THE PAGE (native generation 25):
//!
//! - `slack_channels() -> string[]`: the ids that have a webhook kept.
//! - `slack_save_channel({ id, url })`: kept, or refused in a sentence.
//! - `slack_forget_channel({ id })`: gone; one never kept is already gone.
//! - `slack_post({ id, payload })`: `payload` is the JSON Slack takes
//!   (`{ text }`), posted to that id's webhook; Ok, or why not as a sentence.

// iOS answers `slack_post` with its refusal (unsupported.rs), so what only the
// post uses is unused there by design.
#![cfg_attr(target_os = "ios", allow(dead_code))]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tauri::AppHandle;

#[cfg(target_os = "ios")]
use crate::unsupported::{on_ios, SLACK};

const FILE: &str = "slack.json";

/// The two kinds of webhook Slack hands out: an app's incoming webhook and a
/// Workflow Builder trigger. Nothing else is ever posted to.
const WEBHOOK_PREFIXES: [&str; 2] = ["https://hooks.slack.com/services/", "https://hooks.slack.com/workflows/"];

/// Slack's limit on a message is 40,000 characters; anything near this is
/// not a message the page meant to send.
const MOST_BYTES: usize = 200_000;

/// What `slack.json` holds: each channel's id, as the page made it, to its webhook.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct Kept {
    #[serde(default)]
    channels: BTreeMap<String, String>,
}

/// Where the webhooks live: `<app_data_dir>/slack.json`.
pub fn webhooks_path(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(crate::paths::data_dir(app)?.join(FILE))
}

/// Whether `url` is a Slack webhook: https, hooks.slack.com, under
/// `/services/` or `/workflows/`, and nothing after that but the letters,
/// digits, dashes, underscores and slashes Slack's tokens are made of. No
/// query, no fragment, no `..`, no user before the host.
pub fn allowed_webhook(url: &str) -> bool {
    let Some(rest) = WEBHOOK_PREFIXES.iter().find_map(|prefix| url.strip_prefix(prefix)) else { return false };
    !rest.is_empty() && rest.len() <= 256 && !rest.contains("..") && rest.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '/'))
}

/// An id the page made for a channel: a uuid, or anything as plain.
fn allowed_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 64 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

fn read_kept(path: &Path) -> Kept {
    crate::fsx::read_json_or(path, Kept::default())
}

/// The webhooks as the file at `path`, born readable by this app's user only.
fn write_kept(path: &Path, kept: &Kept) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("cannot make {}: {e}", dir.display()))?;
    }
    let text = serde_json::to_string(kept).map_err(|e| e.to_string())?;
    crate::fsx::write_private(path, text.as_bytes()).map_err(|e| format!("cannot keep the Slack webhook: {e}"))
}

fn save_channel(path: &Path, id: &str, url: &str) -> Result<(), String> {
    if !allowed_id(id) {
        return Err("That isn't a channel Ghost.md made.".into());
    }
    let url = url.trim();
    if !allowed_webhook(url) {
        return Err("That isn't a Slack incoming webhook. It starts with https://hooks.slack.com/services/.".into());
    }
    let mut kept = read_kept(path);
    kept.channels.insert(id.to_string(), url.to_string());
    write_kept(path, &kept)
}

fn forget_channel(path: &Path, id: &str) -> Result<(), String> {
    let mut kept = read_kept(path);
    if kept.channels.remove(id).is_none() {
        return Ok(());
    }
    if kept.channels.is_empty() {
        return crate::fsx::remove_file_if_present(path).map_err(|e| format!("cannot forget the Slack webhook: {e}"));
    }
    write_kept(path, &kept)
}

/// The webhook to post to for `id`, held to the allow-list again: a file
/// edited by hand is not a way round it.
fn webhook_for(path: &Path, id: &str) -> Result<String, String> {
    let url = read_kept(path)
        .channels
        .remove(id)
        .ok_or("This channel's webhook isn't on this device. Add the channel again in Settings › Plugins › Slack.")?;
    if !allowed_webhook(&url) {
        return Err("That isn't a Slack incoming webhook. It starts with https://hooks.slack.com/services/.".into());
    }
    Ok(url)
}

/// Slack's answer to a post, as Ok or the reason in a sentence. A webhook
/// answers `ok` with 200, and otherwise a status and a short code in the body
/// (`no_service`, `channel_is_archived`, ...).
fn slack_answer(status: u16, body: &str) -> Result<(), String> {
    let code = body.trim();
    if (200..300).contains(&status) {
        return Ok(());
    }
    Err(match (status, code) {
        (_, "channel_is_archived") | (410, _) => "That Slack channel is archived, so nothing can be posted to it.".into(),
        (_, "no_service" | "no_team" | "channel_not_found" | "team_disabled") | (404, _) => {
            "Slack no longer knows this webhook. Make a new one in Slack and add the channel again.".into()
        }
        (_, "action_prohibited" | "posting_to_general_channel_denied") | (403, _) => {
            "Slack refused the post. The webhook's app may have been removed, or may not post there.".into()
        }
        (_, "invalid_payload" | "too_many_attachments") | (400, _) => "Slack couldn't read the message.".into(),
        (429, _) => "Slack asked for fewer posts. Try again in a minute.".into(),
        (500..=599, _) => "Slack had a problem. Try again in a moment.".into(),
        _ => format!("Slack answered {status}."),
    })
}

#[tauri::command]
pub fn slack_channels(app: AppHandle) -> Vec<String> {
    let Ok(path) = webhooks_path(&app) else { return Vec::new() };
    read_kept(&path).channels.into_keys().collect()
}

#[tauri::command]
pub fn slack_save_channel(app: AppHandle, id: String, url: String) -> Result<(), String> {
    save_channel(&webhooks_path(&app)?, &id, &url)
}

#[tauri::command]
pub fn slack_forget_channel(app: AppHandle, id: String) -> Result<(), String> {
    let Ok(path) = webhooks_path(&app) else { return Ok(()) };
    forget_channel(&path, &id)
}

#[tauri::command]
pub async fn slack_post(app: AppHandle, id: String, payload: Value) -> Result<(), String> {
    #[cfg(target_os = "ios")]
    return on_ios(SLACK, (app, id, payload));
    #[cfg(not(target_os = "ios"))]
    {
        let url = webhook_for(&webhooks_path(&app)?, &id)?;
        let body = serde_json::to_vec(&payload).map_err(|e| e.to_string())?;
        if body.len() > MOST_BYTES {
            return Err("That is too long for one Slack message.".into());
        }
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(20))
            // The allow-list is the URL asked for; a redirect would be somewhere else.
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|e| format!("cannot make an HTTP client: {e}"))?;
        let response = client
            .post(url)
            .header("Content-Type", "application/json")
            .body(body)
            .send()
            .await
            .map_err(|e| if e.is_timeout() { "Slack took too long to answer. Try again.".to_string() } else { "Slack couldn't be reached. Check the connection.".to_string() })?;
        let status = response.status().as_u16();
        let text = response.text().await.unwrap_or_default();
        slack_answer(status, &text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn only_slacks_webhooks_are_posted_to() {
        assert!(allowed_webhook("https://hooks.slack.com/services/T000/B000/XXXXXXXX"));
        assert!(allowed_webhook("https://hooks.slack.com/workflows/T000/A000/123/abc_DEF-9"));
        assert!(!allowed_webhook("http://hooks.slack.com/services/T000/B000/XXXX"), "never in the clear");
        assert!(!allowed_webhook("https://hooks.slack.com.evil.example/services/T000/B000/XXXX"));
        assert!(!allowed_webhook("https://evil.example/https://hooks.slack.com/services/T000"));
        assert!(!allowed_webhook("https://user@hooks.slack.com/services/T000/B000/XXXX"));
        assert!(!allowed_webhook("https://hooks.slack.com/api/chat.postMessage"));
        assert!(!allowed_webhook("https://hooks.slack.com/services/"), "a prefix alone is not a webhook");
        assert!(!allowed_webhook("https://hooks.slack.com/services/../api/T000"));
        assert!(!allowed_webhook("https://hooks.slack.com/services/T000/B000/XXXX?redirect=evil"));
        assert!(!allowed_webhook("https://hooks.slack.com/services/T000/B000/XXXX#x"));
        assert!(!allowed_webhook("https://HOOKS.SLACK.COM/services/T000/B000/XXXX"), "spelled as Slack hands it out");
        assert!(!allowed_webhook(" https://hooks.slack.com/services/T000/B000/XXXX"), "trimmed before it is asked");
    }

    #[test]
    fn a_webhook_is_kept_private_by_its_id_and_forgotten_whole() {
        let root = TempDir::new("slack");
        let path = root.join("data").join(FILE);
        save_channel(&path, "a1", " https://hooks.slack.com/services/T0/B0/aaa ").unwrap();
        save_channel(&path, "b2", "https://hooks.slack.com/services/T0/B0/bbb").unwrap();
        assert_eq!(webhook_for(&path, "a1").unwrap(), "https://hooks.slack.com/services/T0/B0/aaa", "kept trimmed");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600, "never readable by anyone else");
        }
        assert!(save_channel(&path, "c3", "https://example.com/hook").unwrap_err().contains("isn't a Slack incoming webhook"));
        assert!(save_channel(&path, "../x", "https://hooks.slack.com/services/T0/B0/ccc").is_err());
        assert_eq!(read_kept(&path).channels.keys().collect::<Vec<_>>(), ["a1", "b2"]);

        forget_channel(&path, "a1").unwrap();
        assert!(webhook_for(&path, "a1").unwrap_err().contains("isn't on this device"));
        forget_channel(&path, "nobody").unwrap();
        forget_channel(&path, "b2").unwrap();
        assert!(!path.exists(), "the last one forgotten takes the file");
    }

    #[test]
    fn a_hand_edited_file_is_held_to_the_list_too() {
        let root = TempDir::new("slack-edited");
        let path = root.join(FILE);
        std::fs::write(&path, br#"{"channels":{"a1":"https://evil.example/collect"}}"#).unwrap();
        assert!(webhook_for(&path, "a1").is_err());
        std::fs::write(&path, b"{ half a file").unwrap();
        assert!(read_kept(&path).channels.is_empty(), "an unreadable file keeps nothing");
    }

    #[test]
    fn slacks_answers_are_sentences() {
        assert_eq!(slack_answer(200, "ok"), Ok(()));
        assert!(slack_answer(404, "no_service").unwrap_err().starts_with("Slack no longer knows this webhook."));
        assert!(slack_answer(410, "channel_is_archived").unwrap_err().contains("archived"));
        assert!(slack_answer(403, "action_prohibited").unwrap_err().starts_with("Slack refused the post."));
        assert_eq!(slack_answer(400, "invalid_payload").unwrap_err(), "Slack couldn't read the message.");
        assert!(slack_answer(429, "").unwrap_err().contains("Try again in a minute"));
        assert!(slack_answer(503, "").unwrap_err().starts_with("Slack had a problem."));
        assert_eq!(slack_answer(302, "").unwrap_err(), "Slack answered 302.", "a redirect is not followed, and not a success");
    }
}
