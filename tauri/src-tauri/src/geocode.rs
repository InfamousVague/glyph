//! The name of the place a tagged note was written, asked of OpenStreetMap's
//! Nominatim (Matt: "Add the ability to geotag notes and show a map card
//! embedded on the note"; the page's half is core/location.ts).
//!
//! - `geocode_place({ lat, lon, zoom, lang }) -> Nominatim's answer, as it came`
//!
//! Why Rust: Nominatim's usage policy asks for a User-Agent or Referer that
//! identifies the application, and says a library's stock one will not do. The
//! page cannot set a User-Agent (a forbidden header), the Android page's Referer
//! is `http://tauri.localhost/` and the Mac's page sends none, so the app asks
//! as itself. The page sends coordinates already rounded (three decimals, or two
//! for a rough tag), asks once per tag and a second apart, and reads the short
//! name out of the answer (core/geotag.ts `shortPlace`), so this stays a
//! passthrough: it builds the URL itself and accepts nothing else from the page.
//! Eight seconds, no redirects, a non-2xx is a refusal. Native generation 20.

// iOS answers every command here with its refusal (unsupported.rs), so the
// rest of the module is unused there by design, not by accident.
#![cfg_attr(target_os = "ios", allow(dead_code))]

#[cfg(target_os = "ios")]
use crate::unsupported::{on_ios, PLACE_NAMES};

/// The reverse lookup, at the two zooms the card draws: a street (15) or a district (12).
pub fn reverse_url(lat: f64, lon: f64, zoom: u8) -> Result<String, String> {
    if !lat.is_finite() || !lon.is_finite() || !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
        return Err("That isn't a place on Earth.".into());
    }
    if zoom != 12 && zoom != 15 {
        return Err("The map has no such zoom.".into());
    }
    Ok(format!("https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat={lat}&lon={lon}&zoom={zoom}&addressdetails=1"))
}

/// The language the name is asked in: the page's, kept to what an Accept-Language header may hold, else English.
pub fn accept_language(lang: &str) -> String {
    let clean: String = lang.chars().filter(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | ',' | ';' | '=' | '.' | ' ')).take(64).collect();
    if clean.trim().is_empty() {
        "en".to_string()
    } else {
        clean.trim().to_string()
    }
}

#[tauri::command]
pub async fn geocode_place(lat: f64, lon: f64, zoom: u8, lang: String) -> Result<serde_json::Value, String> {
    #[cfg(target_os = "ios")]
    return on_ios(PLACE_NAMES, (lat, lon, zoom, lang));
    #[cfg(not(target_os = "ios"))]
    {
        let url = reverse_url(lat, lon, zoom)?;
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(8))
            .redirect(reqwest::redirect::Policy::none())
            // The app, named, as Nominatim asks: the version and where to find out about it.
            .user_agent(concat!("GhostMd/", env!("CARGO_PKG_VERSION"), " (https://ghostmarkdown.com)"))
            .build()
            .map_err(|e| format!("cannot make an HTTP client: {e}"))?;
        let response = client
            .get(url)
            .header("Accept", "application/json")
            .header("Accept-Language", accept_language(&lang))
            .send()
            .await
            .map_err(|_| "OpenStreetMap couldn't be reached.".to_string())?;
        if !response.status().is_success() {
            return Err(format!("OpenStreetMap answered {}.", response.status().as_u16()));
        }
        let text = response.text().await.map_err(|_| "OpenStreetMap's answer couldn't be read.".to_string())?;
        serde_json::from_str(&text).map_err(|_| "OpenStreetMap's answer wasn't JSON.".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_the_lookup_from_a_place_and_a_zoom() {
        assert_eq!(
            reverse_url(51.507, -0.128, 15).unwrap(),
            "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=51.507&lon=-0.128&zoom=15&addressdetails=1"
        );
        assert_eq!(reverse_url(51.51, -0.13, 12).unwrap(), "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=51.51&lon=-0.13&zoom=12&addressdetails=1");
    }

    #[test]
    fn refuses_what_is_not_a_place_or_a_zoom_the_card_draws() {
        assert!(reverse_url(f64::NAN, 0.0, 15).is_err());
        assert!(reverse_url(0.0, f64::INFINITY, 15).is_err());
        assert!(reverse_url(91.0, 0.0, 15).is_err());
        assert!(reverse_url(0.0, -181.0, 15).is_err());
        assert!(reverse_url(0.0, 0.0, 14).is_err());
        assert!(reverse_url(0.0, 0.0, 0).is_err());
    }

    #[test]
    fn keeps_the_language_to_what_a_header_may_hold() {
        assert_eq!(accept_language("en-GB,en;q=0.9"), "en-GB,en;q=0.9");
        assert_eq!(accept_language(""), "en");
        assert_eq!(accept_language("\r\nX-Injected: yes"), "X-Injected yes");
    }
}
