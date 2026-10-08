/// The inline items' extensions, in the order `src/app/editor/Editor.tsx` lists them: footnotes, tags, a to-do's
/// fields, counters, sums, a heading's progress, choices, links between notes, anchors and their pointers, a tap
/// on a to-do's box, the bookmark's line and, where asked for, the hint in an open first heading. Emoji names
/// (`:tada:`) are the extended markdown's, already in the base editor (`view/extended.dart`).
///
///     noteExtensions(formats: marks, more: <Extension>[markExtensions(marks), itemExtensions(wiki: options)])
library;

import '../state/state.dart';
import 'anchors.dart';
import 'bookmark_line.dart';
import 'choices.dart';
import 'counters.dart';
import 'footnotes.dart';
import 'heading_progress.dart';
import 'open_heading.dart';
import 'sums.dart';
import 'tags.dart';
import 'task_fields.dart';
import 'task_toggle.dart';
import 'wiki_links.dart';

export 'anchors.dart';
export 'bookmark_line.dart';
export 'box_taps.dart';
export 'choices.dart';
export 'counters.dart';
export 'field_chips.dart';
export 'field_items.dart';
export 'field_menu.dart';
export 'footnotes.dart';
export 'heading_progress.dart';
export 'open_heading.dart';
export 'sums.dart';
export 'tags.dart';
export 'task_fields.dart';
export 'task_toggle.dart';
export 'use_bookmark.dart';
export 'wiki_links.dart';

/// The items drawn in the words. `peek` is a card's preview, which takes no taps and draws no anchors (on the web
/// they come with the boards, which a card does not draw); `wiki` says how `[[Title]]` is looked up and opened,
/// and none draws no links; `openHeading` says `A name` in an open first heading.
Extension itemExtensions({WikiOptions? wiki, bool peek = false, bool openHeading = false}) => Extension.list(<Extension>[
  footnotes(),
  tags(),
  taskFields(),
  counters(),
  sums(),
  headingProgress(),
  choices(),
  if (wiki != null) wikiLinks(wiki),
  if (!peek) itemAnchors,
  if (!peek) taskToggle(),
  bookmarkRibbon(),
  if (openHeading) openHeadingExtension(),
]);

/// `A name` in an open first heading (`open_heading.dart` `openHeading`), under a name that does not collide with
/// [itemExtensions]' switch.
Extension openHeadingExtension() => openHeading();
