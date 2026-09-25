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

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tauri::{AppHandle, Manager};

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
pub fn account_path(app: &AppHandle) -> Option<std::path::PathBuf> {
    app.path().app_data_dir().ok().map(|dir| dir.join(FILE))
}

fn read(app: &AppHandle) -> Option<Account> {
    crate::fsx::read_json::<Account>(&account_path(app)?).filter(|a| !a.access_token.is_empty())
}

fn write(app: &AppHandle, account: &Account) -> Result<(), String> {
    let path = account_path(app).ok_or("no app data directory")?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("cannot make {}: {e}", dir.display()))?;
    }
    let text = serde_json::to_string(account).map_err(|e| e.to_string())?;
    // Written beside and renamed over, so a crash never leaves half a token,
    // and born readable by this app's user only.
    crate::fsx::write_private(&path, text.as_bytes()).map_err(|e| format!("cannot write the Notion account: {e}"))
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
    let Some(path) = account_path(&app) else { return Ok(()) };
    crate::fsx::remove_file_if_present(&path).map_err(|e| format!("cannot forget the Notion account: {e}"))
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn notion_request(_app: AppHandle, _request: Request) -> Result<Answer, String> {
    Err("Notion is not available on iOS yet.".into())
}

#[cfg(not(target_os = "ios"))]
#[tauri::command]
pub async fn notion_request(app: AppHandle, request: Request) -> Result<Answer, String> {
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
}
