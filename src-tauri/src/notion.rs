//! Notion, from the phone: keeping the account a person signed in with, and
//! making Notion API calls on the page's behalf.
//!
//! Why native at all: api.notion.com does not answer a web page's cross-origin
//! requests, and Glyph's page runs at `http://tauri.localhost`. So the page
//! says what to ask ("query this database", "create this page") and this
//! module asks, with the token only it holds, and hands back Notion's answer.
//!
//! The account comes from "Sign in with Notion": the page opens the sign-in
//! through glyph-api (server/src/notion.rs), collects the tokens from its
//! `claim`, and gives them here once, to be written to `notion.json` in the
//! app's own data directory, which no other app can read. The page never keeps
//! them; it can only ask whether there is an account and what its workspace is
//! called. A 401 from Notion is answered by refreshing through glyph-api once
//! and asking again.
//!
//! THE CONTRACT WITH THE PAGE (native generation 12):
//!
//! - `notion_save_account({ account })`: the claim's JSON, kept.
//! - `notion_account() -> { connected, workspaceName?, workspaceIcon? }`.
//! - `notion_disconnect()`: the file goes.
//! - `notion_request({ method, path, body? }) -> { status, body }`: `path` is
//!   below `https://api.notion.com/v1/` and must be one of the routes Glyph
//!   uses (search, databases, data_sources, pages, blocks, users/me).

// iOS answers every command here with its refusal (unsupported.rs), so the
// rest of the module is unused there by design, not by accident.
#![cfg_attr(target_os = "ios", allow(dead_code))]

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tauri::AppHandle;

#[cfg(target_os = "ios")]
use crate::unsupported::{on_ios, NOTION};

const NOTION_API: &str = "https://api.notion.com/v1/";
const NOTION_VERSION: &str = "2022-06-28";
const REFRESH: &str = "https://attack.fm/glyph/api/notion/refresh";
const FILE: &str = "notion.json";

/// What sign-in gave back, as glyph-api's claim spells it.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Account {
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
    #[serde(default)]
    pub bot_id: Option<String>,
    #[serde(default)]
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub workspace_name: Option<String>,
    #[serde(default)]
    pub workspace_icon: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountInfo {
    pub connected: bool,
    pub workspace_name: Option<String>,
    pub workspace_icon: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Answer {
    pub status: u16,
    pub body: Value,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    pub method: String,
    pub path: String,
    #[serde(default)]
    pub body: Option<Value>,
}

/// Where the account lives: `<app_data_dir>/notion.json`.
pub fn account_path(app: &AppHandle) -> Result<std::path::PathBuf, String> {
    Ok(crate::paths::data_dir(app)?.join(FILE))
}

fn read(app: &AppHandle) -> Option<Account> {
    read_account(&account_path(app).ok()?)
}

/// The account in the file at `path`, or `None` - signed out - for a file
/// that is missing, unreadable, or holds no token to call Notion with.
fn read_account(path: &std::path::Path) -> Option<Account> {
    crate::fsx::read_json::<Account>(path).filter(|a| !a.access_token.is_empty())
}

fn write(app: &AppHandle, account: &Account) -> Result<(), String> {
    write_account(&account_path(app)?, account)
}

/// The account as the file at `path`. Apart from `write` so a test can reach
/// it with no app around it.
fn write_account(path: &std::path::Path, account: &Account) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("cannot make {}: {e}", dir.display()))?;
    }
    let text = serde_json::to_string(account).map_err(|e| e.to_string())?;
    // Written beside and renamed over, so a crash never leaves half a token,
    // and born readable by this app's user only.
    crate::fsx::write_private(path, text.as_bytes()).map_err(|e| format!("cannot write the Notion account: {e}"))
}

/// The routes below /v1/ Glyph calls. Anything else is refused, so the page
/// cannot be turned into a general Notion client by accident.
pub fn allowed_path(path: &str) -> bool {
    let path = path.trim_start_matches('/');
    if path.contains("..") || path.contains("://") || path.starts_with('/') {
        return false;
    }
    ["search", "databases/", "data_sources/", "pages", "blocks/", "users/me"].iter().any(|prefix| path == prefix.trim_end_matches('/') || path.starts_with(prefix))
}

#[tauri::command]
pub fn notion_save_account(app: AppHandle, account: Account) -> Result<AccountInfo, String> {
    if account.access_token.is_empty() {
        return Err("Notion didn't give Glyph an access token.".into());
    }
    write(&app, &account)?;
    Ok(info(Some(&account)))
}

fn info(account: Option<&Account>) -> AccountInfo {
    AccountInfo {
        connected: account.is_some(),
        workspace_name: account.and_then(|a| a.workspace_name.clone()),
        workspace_icon: account.and_then(|a| a.workspace_icon.clone()),
    }
}

#[tauri::command]
pub fn notion_account(app: AppHandle) -> AccountInfo {
    info(read(&app).as_ref())
}

#[tauri::command]
pub fn notion_disconnect(app: AppHandle) -> Result<(), String> {
    let Ok(path) = account_path(&app) else { return Ok(()) };
    crate::fsx::remove_file_if_present(&path).map_err(|e| format!("cannot forget the Notion account: {e}"))
}

#[tauri::command]
pub async fn notion_request(app: AppHandle, request: Request) -> Result<Answer, String> {
    #[cfg(target_os = "ios")]
    return on_ios(NOTION, (app, request));
    #[cfg(not(target_os = "ios"))]
    {
        if !allowed_path(&request.path) {
            return Err(format!("Glyph doesn't call Notion's {} route.", request.path));
        }
        let method = match request.method.to_ascii_uppercase().as_str() {
            "GET" => reqwest::Method::GET,
            "POST" => reqwest::Method::POST,
            "PATCH" => reqwest::Method::PATCH,
            other => return Err(format!("Glyph doesn't send {other} to Notion.")),
        };
        let mut account = read(&app).ok_or("Glyph isn't signed in to Notion.")?;
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .map_err(|e| format!("cannot make an HTTP client: {e}"))?;

        let mut answer = send(&client, &method, &request, &account.access_token).await?;
        if answer.status == 401 {
            if let Some(refresh) = account.refresh_token.clone() {
                if let Ok(fresh) = refresh_account(&client, &refresh).await {
                    account = Account {
                        access_token: fresh.access_token,
                        refresh_token: fresh.refresh_token.or(account.refresh_token),
                        ..account
                    };
                    write(&app, &account)?;
                    answer = send(&client, &method, &request, &account.access_token).await?;
                }
            }
        }
        Ok(answer)
    }
}

#[cfg(not(target_os = "ios"))]
async fn send(client: &reqwest::Client, method: &reqwest::Method, request: &Request, token: &str) -> Result<Answer, String> {
    let url = format!("{NOTION_API}{}", request.path.trim_start_matches('/'));
    let mut builder = client
        .request(method.clone(), url)
        .header("Authorization", format!("Bearer {token}"))
        .header("Notion-Version", NOTION_VERSION);
    if let Some(body) = &request.body {
        builder = builder
            .header("Content-Type", "application/json")
            .body(serde_json::to_vec(body).map_err(|e| e.to_string())?);
    }
    let response = builder.send().await.map_err(|_| "Notion couldn't be reached. Check the connection.".to_string())?;
    let status = response.status().as_u16();
    let bytes = response.bytes().await.map_err(|e| format!("Notion's answer broke off: {e}"))?;
    let body = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    Ok(Answer { status, body })
}

#[cfg(not(target_os = "ios"))]
async fn refresh_account(client: &reqwest::Client, refresh_token: &str) -> Result<Account, String> {
    let response = client
        .post(REFRESH)
        .header("Content-Type", "application/json")
        .body(serde_json::to_vec(&serde_json::json!({ "refreshToken": refresh_token })).map_err(|e| e.to_string())?)
        .send()
        .await
        .map_err(|e| format!("cannot refresh the Notion sign-in: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("refreshing the Notion sign-in answered {}", response.status()));
    }
    let bytes = response.bytes().await.map_err(|e| e.to_string())?;
    serde_json::from_slice::<Account>(&bytes).map_err(|e| format!("an unreadable refresh: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn only_the_routes_glyph_uses() {
        assert!(allowed_path("search"));
        assert!(allowed_path("databases/abc123/query"));
        assert!(allowed_path("pages"));
        assert!(allowed_path("pages/abc123"));
        assert!(allowed_path("blocks/abc/children"));
        assert!(allowed_path("users/me"));
        assert!(!allowed_path("oauth/token"));
        assert!(!allowed_path("databases/../oauth/token"));
        assert!(!allowed_path("https://evil.example/"));
        assert!(!allowed_path("//evil.example"));
    }

    #[test]
    fn a_claim_reads_as_an_account() {
        let json = r#"{"accessToken":"secret_x","refreshToken":null,"botId":"b","workspaceId":"w","workspaceName":"AttackFM","workspaceIcon":null}"#;
        let account: Account = serde_json::from_str(json).unwrap();
        assert_eq!(account.workspace_name.as_deref(), Some("AttackFM"));
        assert_eq!(info(Some(&account)).workspace_name.as_deref(), Some("AttackFM"));
        assert!(!info(None).connected);
    }

    #[test]
    fn an_account_is_kept_whole_and_private_or_not_at_all() {
        let root = TempDir::new("notion");
        // A data folder not made yet: the first sign-in makes it.
        let dir = root.join("data");
        let path = dir.join(FILE);
        let account = Account { access_token: "secret_x".into(), ..Account::default() };
        write_account(&path, &account).unwrap();
        assert_eq!(crate::fsx::read_json::<Account>(&path).map(|a| a.access_token).as_deref(), Some("secret_x"));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600, "never readable by anyone else");
        }
        // A write that cannot land says so in one sentence and leaves nothing beside the file.
        let blocked = dir.join("blocked.json");
        std::fs::create_dir_all(blocked.join("inside")).unwrap();
        let error = write_account(&blocked, &account).unwrap_err();
        assert!(error.starts_with("cannot write the Notion account: "), "{error}");
        let mut left: Vec<_> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        left.sort();
        assert_eq!(left, ["blocked.json", FILE]);
    }

    #[test]
    fn signed_in_means_a_token_to_call_with() {
        let dir = TempDir::new("notion-read");
        let path = dir.join(FILE);
        assert!(read_account(&path).is_none(), "no file is signed out");
        std::fs::write(&path, br#"{"accessToken":"","workspaceName":"AttackFM"}"#).unwrap();
        assert!(read_account(&path).is_none(), "an empty token is signed out, whatever else the file says");
        std::fs::write(&path, b"{ half a file").unwrap();
        assert!(read_account(&path).is_none());
        std::fs::write(&path, br#"{"accessToken":"secret_x"}"#).unwrap();
        assert_eq!(read_account(&path).map(|a| a.access_token).as_deref(), Some("secret_x"), "the rest may be missing");
    }
}
