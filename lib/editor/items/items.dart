/// The inline items' extensions, in the order `src/app/editor/Editor.tsx` lists them: footnotes, tags, a to-do's
/// fields, counters, sums, a heading's progress, choices, links between notes, anchors and their pointers, a tap
/// on a to-do's box, the bookmark's line and, where asked for, the hint in an open first heading; and, where the
/// note desk gives them, the plugins' side of a note: the swipe on an item, the quiet words after lines, and a
/// linked to-do's box following its task. Emoji names
/// (`:tada:`) are the extended markdown's, already in the base editor (`view/extended.dart`).
///
///     noteExtensions(formats: marks, more: <Extension>[markExtensions(marks), itemExtensions(wiki: options)])
library;

import '../state/state.dart';
import 'anchors.dart';
import 'bookmark_line.dart';
import 'choices.dart';
import 'counters.dart';
import 'done_sync.dart';
import 'footnotes.dart';
import 'heading_progress.dart';
import 'open_heading.dart';
import 'suggestions.dart';
import 'sums.dart';
import 'swipe_items.dart';
import 'tags.dart';
import 'task_fields.dart';
import 'task_toggle.dart';
import 'wiki_links.dart';

export 'anchors.dart';
export 'bookmark_line.dart';
export 'box_taps.dart';
export 'choices.dart';
export 'counters.dart';
export 'done_sync.dart';
export 'field_chips.dart';
export 'field_items.dart';
export 'field_menu.dart';
export 'footnotes.dart';
export 'heading_progress.dart';
export 'mark_menu.dart';
export 'mark_reads.dart';
export 'note_plugins.dart';
export 'open_heading.dart';
export 'suggestions.dart';
export 'sums.dart';
export 'swipe_items.dart';
export 'tags.dart';
export 'task_fields.dart';
export 'task_toggle.dart';
export 'use_bookmark.dart';
export 'wiki_links.dart';

/// The items drawn in the words. `peek` is a card's preview, which takes no taps and draws no anchors (on the web
/// they come with the boards, which a card does not draw); `wiki` says how `[[Title]]` is looked up and opened,
/// and none draws no links; `openHeading` says `A name` in an open first heading. The plugins' side, none of it on
/// a card: `swipe` is the action a swipe on an item runs right now (swipe_items.dart), `suggest` the words offered
/// on the note's lines (suggestions.dart), and `doneSyncs` keeps a linked to-do's box and its task in step
/// (done_sync.dart); note_plugins.dart makes the first two from the plugins' registry.
Extension itemExtensions({
  WikiOptions? wiki,
  bool peek = false,
  bool openHeading = false,
  SwipeAction? Function()? swipe,
  List<LineSuggestion> Function(String body)? suggest,
  bool doneSyncs = false,
}) => Extension.list(<Extension>[
  footnotes(),
  tags(),
  taskFields(),
  counters(),
  sums(),
  headingProgress(),
  choices(),
  if (wiki != null) wikiLinks(wiki),
  if (!peek) itemAnchors,
  if (!peek && swipe != null) swipeItemAction(action: swipe),
  if (!peek && suggest != null) lineSuggestions(suggest: suggest),
  if (!peek) taskToggle(),
  if (!peek && doneSyncs) doneSync(),
  bookmarkRibbon(),
  if (openHeading) openHeadingExtension(),
]);

/// `A name` in an open first heading (`open_heading.dart` `openHeading`), under a name that does not collide with
/// [itemExtensions]' switch.
Extension openHeadingExtension() => openHeading();
