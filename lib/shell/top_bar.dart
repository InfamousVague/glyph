/// The four ways the top bar can be laid out (`TopBar`, core/preferences.ts; `TOP_BAR_STYLES`, shell/topBar.ts;
/// docs/DESIGN.md §178, cut from six in §180), in the order Settings offers them, each with the sentence Settings
/// says under its picture. What each one is, drawn, is notes/note_tabs.dart; this is what the shell needs to know of
/// them: how many lines the bar is ([barRows]).
enum TopBarStyle {
  classic('Classic', 'The controls on one line, the open notes as tabs on the next.'),
  ledger('Ledger', 'The tabs on top, as a browser has them; the open one holds its tools on the line below.'),
  masthead('Masthead', 'Words in place of rings, and the tabs as an index line under a rule.'),
  islands('Islands', 'No bar: three glass capsules float over the page, the tabs in one of them.');

  const TopBarStyle(this.label, this.hint);

  final String label;
  final String hint;

  /// The preference's word for it, which is also `data-topbar` on the page.
  String get id => name;

  /// The style a kept preference names; one this build does not know (a Strip or a Thumb chosen before the cut)
  /// reads as Classic.
  static TopBarStyle parse(Object? id) {
    for (final style in values) {
      if (style.name == id) return style;
    }
    return TopBarStyle.classic;
  }
}

/// How many lines the bar is, which is how tall it is (app.css `--app-tabs`, chosen by `data-tabs`).
enum BarRows {
  /// One line: the controls.
  on,

  /// Two: the controls with the tabs under them, or over them.
  rows;

  /// `data-tabs` on the page.
  String get stamp => name;
}

/// How many lines the bar is (`barRows`, shell/topBar.ts): one, or the controls with the tabs under them. The
/// Ledger's tab row is always drawn, with Home pinned in it, so it is always two. The rest are two only with a note
/// open.
BarRows barRows(TopBarStyle style, int open) {
  if (style == TopBarStyle.ledger) return BarRows.rows;
  return open > 0 ? BarRows.rows : BarRows.on;
}
