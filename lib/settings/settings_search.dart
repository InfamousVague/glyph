// Port of the web app's src/app/settings/settingsSearch.ts: what a few typed words find among Settings' sections,
// and among the settings inside them.
//
// Every word typed has to be found, in any order, each at the start of a word of what it is matched against, so
// "dark" finds "On the dark page" and "sm ed" finds "Smoke at the edges", but "ark" finds nothing. A section is
// found by its name, its state line and its own extra words; a setting by its name and its own extra words, and it
// is shown with its section's name under it, so "smoke" says which of two pages each smoke is on.
//
// What differs from the web original: `findSetting`, which read the page's DOM for the element naming a setting, is
// `SettingsFinder.find` (kit/settings_kit.dart): the kit's parts say their own names to the page they are on.

/// A setting inside a section, as its page names it (`SettingsFindable`): the name has to be the row's or the card's
/// words on that page, so opening it can find it there.
class SettingsFindable {
  const SettingsFindable(this.name, [this.words]);

  final String name;

  /// Other words someone might look for it by: "font" for Family.
  final String? words;
}

/// What the search reads of a section (`SearchableSection`).
abstract interface class SearchableSection {
  String get id;
  String get label;
  String? get summary;
  String? get words;
  List<SettingsFindable> get settings;
}

/// One thing the search found (`SettingsHit`): a section, or a setting inside it.
class SettingsHit<S extends SearchableSection> {
  const SettingsHit(this.section, [this.setting]);

  final S section;

  /// The setting found inside it, or null when the section itself was.
  final String? setting;
}

/// Lower case, with curly quotes and apostrophes made straight, so what is typed matches what is drawn (`fold`).
String fold(String text) => text.toLowerCase().replaceAll(RegExp('[‘’]'), "'").replaceAll(RegExp('[“”]'), '"');

final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// The words of a text, split wherever a letter or a digit isn't: "Ghost.md's guess" is ghost, md, s, guess.
List<String> _wordsOf(String text) => fold(text).split(_notWord).where((word) => word.isNotEmpty).toList();

/// Whether every typed word starts one of the words of the texts.
bool _matches(List<String> typed, List<String?> texts) {
  final words = [
    for (final text in texts)
      if (text != null && text.isNotEmpty) ..._wordsOf(text),
  ];
  return typed.every((want) => words.any((word) => word.startsWith(want)));
}

/// What the words find, in the list's order (`searchSettings`): each section found by itself, then each setting found
/// inside it. A section found by its name is not repeated for every setting of its that also matches the words; its
/// settings are shown only when the section's name alone wouldn't have found it.
List<SettingsHit<S>> searchSettings<S extends SearchableSection>(List<S> sections, String query) {
  final typed = _wordsOf(query);
  if (typed.isEmpty) return const [];
  final hits = <SettingsHit<S>>[];
  for (final section in sections) {
    final byName = _matches(typed, [section.label]);
    if (byName || _matches(typed, [section.label, section.summary, section.words])) hits.add(SettingsHit(section));
    if (byName) continue;
    for (final setting in section.settings) {
      if (_matches(typed, [setting.name, setting.words])) hits.add(SettingsHit(section, setting.name));
    }
  }
  return hits;
}
