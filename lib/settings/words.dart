import '../claude/store_neutral.dart';
import '../core/preferences.dart';

// Port of the web app's src/app/settings/words.ts: what Settings calls each value of a preference, in one place for
// both of the places that say it, the pane's own control (a segment, a card, a swatch) and the section's reading in
// the list (settings_sheet.dart). Each map is written in the order its control shows the values.
//
// What differs from the web original: the maps are keyed by the preference's word as a string, so a value added to
// lib/core/preferences.dart without a word here is caught by test/settings/words_test.dart rather than by the
// compiler. The code themes' names (editor/codeThemes.ts `CODE_THEMES_LIGHT`, `CODE_THEMES_DARK`) are kept here too
// until the editor is ported.

/// `SIZE_WORDS`.
const Map<String, String> sizeWords = {'large': 'Large', 'larger': 'Larger', 'largest': 'Largest'};

/// `FACE_WORDS`.
const Map<String, String> faceWords = {'maple': 'Maple Mono', 'fira': 'Fira Code', 'inter': 'Inter', 'noto': 'Noto', 'plex': 'Plex'};

/// `DENSITY_WORDS`: how much air the app gives itself, the kit's own density stops in Ghost.md's words. Two stops
/// either side of Comfortable, which is the kit's own default and the app's.
const Map<String, String> densityWords = {
  'extra-compact': 'Tightest',
  'compact': 'Tight',
  'comfortable': 'Comfortable',
  'spacious': 'Roomy',
  'more-space': 'Roomiest',
};

/// `ROUNDING_WORDS`: how round the app's corners are drawn.
const Map<String, String> roundingWords = {'square': 'Square', 'soft': 'Soft', 'round': 'Round', 'rounder': 'Roundest'};

/// `SPEED_WORDS`.
const Map<String, String> speedWords = {'relaxed': 'Relaxed', 'normal': 'Normal', 'brisk': 'Brisk'};

/// `ACCENT_WORDS`: each accent by name, for the finger that cannot see the colour as well as for the list's reading.
const Map<String, String> accentWords = {
  'ink': 'Ink',
  'graphite': 'Graphite',
  'red': 'Red',
  'amber': 'Amber',
  'green': 'Green',
  'teal': 'Teal',
  'purple': 'Purple',
};

/// `THEME_WORDS`.
const Map<String, String> themeWords = {'system': 'System', 'light': 'Light', 'dark': 'Dark', 'dawn': 'Dawn', 'boreal': 'Boreal', 'ember': 'Ember'};

/// The interface-size steps in words (`WORDS`, ScaleCards.tsx): "85%", not "0.85".
final Map<double, String> scaleWords = {0.85: '85%', 0.925: '93%', 1: 'Default', 1.1: '110%', 1.25: '125%'};

/// `CODE_THEMES_LIGHT` and `CODE_THEMES_DARK` (editor/codeThemes.ts), by their names.
const Map<String, String> codeLightWords = {'pastel': 'Pastel', 'ink': 'Ink', 'github': 'GitHub', 'solarized': 'Solarized'};
const Map<String, String> codeDarkWords = {'pastel': 'Pastel', 'ink': 'Ink', 'one-dark': 'One Dark', 'dracula': 'Dracula', 'nord': 'Nord'};

/// How the sidebar opens, in words (`SIDEBAR_MODES`, AppearancePane.tsx).
const Map<String, String> sidebarWords = {'popover': 'Popover', 'docked': 'Docked'};

/// Appearance's row in the list (SettingsSheet.tsx): the page and the note's face, then anything else that has been
/// moved off its default.
String appearanceSummary(Preferences prefs) {
  const d = Preferences.defaults;
  final faces = prefs.faces;
  return [
    themeWords[prefs.theme],
    // A store-neutral picture names no typeface's maker (lib/claude/store_neutral.dart).
    storeNeutral ? 'Monospace' : faceWords[faces.note],
    // The size as it is kept when it has no word: the preferences settle the faces on reading, not the size.
    prefs.textSize == d.textSize ? null : (sizeWords[prefs.textSize] ?? prefs.textSize),
    faces.ui == d.typeface ? null : faceWords[faces.ui],
    prefs.accent == 'ink' ? null : accentWords[prefs.accent],
    // The density is not settled on reading either: one with no word is said as it is kept.
    prefs.density == 'comfortable' ? null : (densityWords[prefs.density] ?? prefs.density),
    prefs.rounding == 'round' ? null : roundingWords[prefs.rounding],
  ].whereType<String>().where((word) => word.isNotEmpty).join(' · ');
}
