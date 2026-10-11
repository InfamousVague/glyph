/// The stylesheets the token engine reads after the kit's own, in the order the web app's page loads them
/// (tool/sync-design.sh copies them from tauri/).
///
/// In a file of their own, which imports nothing: a test's screen and a gallery's entry point read the sheets from
/// here, and so compile what they draw and not the whole app with it (they were main.dart's, and whatever took them
/// from there took every screen, the account and the core's wiring along). It is also what lets tool/check.sh tell
/// which tests a change can reach.
const appStyleSheets = ['assets/css/ink.css', 'assets/css/app.css', 'assets/css/typefaces.css'];
