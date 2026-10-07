// Port of the web app's src/app/settings/sectionSteps.ts: where Settings goes, as pure answers
// (settings_screen.dart draws them): which sections are rows on the list, which cards they cluster into, where back
// steps from a page, what a left swipe re-enters, and the word the head says for the way back.
//
// Two depths (docs/DESIGN.md §138). A pane is a row on the list. A sub-page (`listed: false`, with a `parent`) is
// not: it is opened from a row on its parent's page, and it is still searched. Back steps a sub-page to its parent,
// a pane to the list, and the list closes Settings. Nothing differs from the web original but the names' case.

/// What these answers read of a section (`SectionPlace`).
abstract interface class SectionPlace {
  String get id;
  String get label;
  int get group;

  /// False keeps it off the list: a sub-page, opened from its parent's page or from the search.
  bool get listed;

  /// The section a sub-page steps back to, and the row that is current in the split view while it shows.
  String? get parent;
}

/// Where back goes (`stepBack`'s answer): to a page, to the list, or out of Settings.
sealed class BackStep {
  const BackStep();
}

/// Back leaves Settings (`'close'`).
class BackCloses extends BackStep {
  const BackCloses();
}

/// Back shows [id]'s page, or the list where it is null.
class BackTo extends BackStep {
  const BackTo(this.id);
  final String? id;
}

/// The sections that are rows on the list, in their order (`listedOf`).
List<S> listedOf<S extends SectionPlace>(List<S> sections) => [
      for (final section in sections)
        if (section.listed) section,
    ];

/// The listed sections clustered into cards (`clustersOf`): consecutive rows of one group share a card.
List<List<S>> clustersOf<S extends SectionPlace>(List<S> sections) {
  final groups = <List<S>>[];
  for (final section in listedOf(sections)) {
    if (groups.isNotEmpty && groups.last.first.group == section.group) {
      groups.last.add(section);
    } else {
      groups.add([section]);
    }
  }
  return groups;
}

S? _byId<S extends SectionPlace>(List<S> sections, String? id) {
  if (id == null) return null;
  for (final section in sections) {
    if (section.id == id) return section;
  }
  return null;
}

/// A sub-page's parent, when it has one that is among the sections.
S? _parentOf<S extends SectionPlace>(List<S> sections, S? section) => _byId(sections, section?.parent);

/// Where back goes from [activeId] (`stepBack`): a sub-page steps to its parent; a pane, or a sub-page whose parent
/// is not there, to the list; the list closes.
BackStep stepBack<S extends SectionPlace>(List<S> sections, String? activeId) {
  if (activeId == null) return const BackCloses();
  return BackTo(_parentOf(sections, _byId(sections, activeId))?.id);
}

/// What a left swipe re-enters (`stepForward`): the page back just left, when it is still a section and the swipe is
/// made from where back landed (its parent, or the list for a pane). Anything else stays put, which is null.
String? stepForward<S extends SectionPlace>(List<S> sections, String? activeId, String? left) {
  if (left == null) return null;
  final leftSection = _byId(sections, left);
  if (leftSection == null) return null;
  final from = _parentOf(sections, leftSection)?.id;
  return from == activeId ? left : null;
}

/// The word in the head over a page, for where back goes (`backWord`): the parent's name over a sub-page, else the
/// screen's own, [root].
String backWord<S extends SectionPlace>(List<S> sections, S? active, [String root = 'Settings']) => _parentOf(sections, active)?.label ?? root;

/// The row that is current in the split view's column while [shown] is on the right (`currentRow`): its parent's
/// for a sub-page.
String? currentRow<S extends SectionPlace>(List<S> sections, S? shown) {
  if (shown == null) return null;
  return _parentOf(sections, shown)?.id ?? shown.id;
}
