//! What a deleted note takes with it besides its file, from three files of `../glyph/src-tauri/src` that name
//! `tauri::` types and so cannot be included whole: `images.rs`, `videos.rs` and `recordings.rs`. And, the same
//! way, what a reset removes (`reset.rs`), how the library's folder is moved (`library_commands.rs`) what a
//! backup is asked (`backup_commands.rs`) and what an export is (`export_commands.rs`).
//!
//! Each file here is the lines its command needs, copied unchanged between two marks. The test reads the
//! originals and looks for every copied item in them, so a rule changed there (which names are a picture's, how
//! a body names one) fails here until it is copied again.

pub mod backup_commands;
pub mod export_commands;
pub mod images;
pub mod library_commands;
pub mod recordings;
pub mod reset;
pub mod videos;

#[cfg(test)]
mod tests {
    /// Every item between the marks of `copy`, found word for word in `original`.
    fn held(copy: &str, original: &str) {
        let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../glyph/src-tauri/src").join(original);
        let source = std::fs::read_to_string(&source).unwrap_or_else(|e| panic!("{}: {e}", source.display()));
        let copied = copy.split("// copied:begin\n").nth(1).and_then(|rest| rest.split("// copied:end").next()).expect("the marks");
        let items: Vec<&str> = copied.split("\n\n").map(str::trim).filter(|item| !item.is_empty()).collect();
        assert!(!items.is_empty());
        for item in items {
            assert!(source.contains(item), "{original} no longer has, word for word:\n{item}");
        }
    }

    #[test]
    fn the_copies_are_the_tauri_apps_own_lines() {
        held(include_str!("images.rs"), "images.rs");
        held(include_str!("videos.rs"), "videos.rs");
        held(include_str!("recordings.rs"), "recordings.rs");
        held(include_str!("reset.rs"), "reset.rs");
        held(include_str!("library_commands.rs"), "library_commands.rs");
        held(include_str!("backup_commands.rs"), "backup_commands.rs");
        held(include_str!("export_commands.rs"), "export_commands.rs");
    }

    #[test]
    fn a_body_names_its_pictures_and_films() {
        let body = "![a](image/one.jpg) ![b](image/../two.jpg) ![a](image/one.jpg)\n[![video 0:03](image/poster.png)](video/film.mp4)\n";
        assert_eq!(super::images::referenced(body), ["one.jpg", "poster.png"]);
        assert_eq!(super::videos::referenced(body), ["film.mp4"]);
        assert!(super::recordings::recording_file(std::path::Path::new("r"), "../x").is_none());
    }
}
