/// The header toolbar: the seam the top bar draws its line of controls through, and the one way it is drawn, **Grouped
/// command** (header/grouped_command_row.dart).
///
/// There were six versions from 2026-10-28 (Matt: "Add a few ways to redo the header toolbar icons right now it's just
/// a huge list of icons and is quite hard to work with include versions with different iconography vibrant colors and
/// different UI/UX add a developer setting to switch between 5 versions"; and the sixth, after the contact sheet on
/// 2.3.61: "Make a version that combines the command center and grouped sections"), picked under Settings › Developer ›
/// Header toolbar: today's bar, every control its own ring; Grouped; Vibrant tiles; Command centre; Labelled; and
/// Grouped command, the default from 2026-10-29 (Matt: "make the grouped command the default header layout"). The
/// contact sheet ended with Grouped command on 2026-11-01 (Matt: "Please look through the app and see if there are
/// other settings that can be simplified removed or moved to a plugin for extra configuration, we currently have too
/// many appearance settings for different title bar layouts and stuff"): the other five and the picker went, and the
/// pieces Grouped command took from Grouped and Command centre live in its own file. A device that had chosen another
/// keeps the word under `glyph-header-toolbar`, and nothing reads it.
///
/// The bar's four styles (lib/shell/top_bar.dart: Classic, Ledger, Masthead, Islands) stay: they are where the line
/// sits and what shape the tabs take, and the line is the same in each.
///
/// The line keeps every control the bar was given within reach: in the row, or in a menu one press away
/// (test/shell/header_toolbar_test.dart presses for each). A control the bar was not given (simple mode's, a phone
/// reading a note's) is not there. The labels a screen reader says are the old bar's, word for word.
library;

import 'package:flutter/widgets.dart';

import '../art/app_icon.dart' show LucideIcon;
import '../art/lucide.g.dart';
import '../core/workspaces.dart' show OrgLike;
import '../note/note_tools.dart';
import 'top_bar_tools.dart' show BarButton;

/// One control the bar was given, as words: what it is, what it says, what it draws and what a press does.
@immutable
class HeaderAct {
  const HeaderAct({
    required this.id,
    required this.label,
    required this.word,
    required this.hue,
    this.icon,
    this.house = false,
    this.mirrored = false,
    required this.onPress,
    this.on = false,
    this.toggled,
    this.expanded,
    this.current = false,
    this.dot = false,
    this.count,
    this.toggle,
  });

  /// Its name in the bar: `home`, `sidebar`, `share` … The key it is drawn under is `header:<id>` ([keyOf]).
  final String id;

  /// What a screen reader says: today's bar's own words.
  final String label;

  /// A word or two for beside it or in a menu: Home, Notes, Share.
  final String word;

  /// One of the Market's hues (lib/market/market_items.dart `marketHues`), which its glyph wears in a menu of •••.
  final String hue;

  /// The glyph, by Lucide's name, drawn in the chosen pack; or the app's own house ([house]).
  final LucideIcon? icon;
  final bool house;

  /// The aside's toggle is the sidebar's glyph reversed.
  final bool mirrored;

  /// Null draws it dead, where today's ring is dead (Back with nowhere to go back to).
  final VoidCallback? onPress;

  /// On now: the sidebar showing, Home the page, the bookmark set, something unread.
  final bool on;

  /// A toggle's `aria-pressed`: the bookmark, the pin. Null for what is not a toggle.
  final bool? toggled;

  /// Where it opens something: whether that is open.
  final bool? expanded;

  /// `aria-current="page"`.
  final bool current;

  /// The bell's gold dot.
  final bool dot;

  /// A number worn small at its corner: the notes that link here.
  final int? count;

  /// The floating card it opens (lib/notes/floating_card.dart `sidebarToggle` …), whose own press it is.
  final String? toggle;

  /// The key it is drawn under, in the row or in a menu.
  static Key keyOf(String id) => ValueKey<String>('header:$id');

  Key get key => keyOf(id);
}

/// Everything the bar was given, sorted into what it is for, for the line to draw. Built by the bar
/// (lib/notes/note_tabs.dart) from its own fields.
@immutable
class HeaderParts {
  const HeaderParts({
    this.home,
    this.sidebar,
    this.folders,
    this.back,
    this.forward,
    this.view,
    this.actions = const [],
    this.more,
    this.menu,
    this.search,
    this.newNote,
    this.allNotes,
    this.organizations,
    this.orgs = const [],
    this.onOrganization,
    this.bell,
    this.settings,
    this.academy,
    this.aside,
    this.presence,
    this.activity,
    this.filters,
    this.tools,
    this.tail,
    this.title,
    this.atHome = false,
    this.unread = false,
    required this.fine,
    required this.room,
  });

  // The way around; and every note by folder (Matt, 2026-10-29: "add a folder icon to the top near home and sidebar to
  // show all notes in the folder / icon view"), which is under ••• now, not in the row ([kept]).
  final HeaderAct? home, sidebar, folders, back, forward;

  /// The note's view switch, its spare actions in today's order (Share, History, Links, Comment, Bookmark, Pin,
  /// Archive, Speak), and its More, the sheet with all of them and the rest; null where no note is up.
  final HeaderAct? view;
  final List<HeaderAct> actions;
  final HeaderAct? more;

  /// The More sheet's rows, for ••• to list in place of More alone (NoteToolsModel.menu); null where no note is up.
  final List<NoteMenuGroup> Function()? menu;

  /// What the home page asks of a bar that has room for it: the command palette, a new note, every note.
  final HeaderAct? search, newNote, allNotes;

  /// The app's own: the organizations (Settings' list, [organizations]; each one's dashboard, [orgs] by
  /// [onOrganization]), the bell, Settings, and the aside's toggle.
  final HeaderAct? organizations;
  final List<OrgLike> orgs;
  final ValueChanged<String>? onOrganization;
  final HeaderAct? bell, settings, aside;

  /// Ghost Academy (Matt, 2026-11-02: "add the academy to the top bar to the left of profile"): a circle of its own
  /// just before the button for you where the row has room, under ••• where it has not.
  final HeaderAct? academy;

  /// Who else is here: the Claude chip, drawn as it comes.
  final Widget? presence;

  /// The ring of the app's running work (lib/activity/activity_ring.dart; docs/ACTIVITY.md), beside the button for
  /// you; the app hands it always, grey while nothing runs, so its room is kept (null only where a caller has no ring
  /// to give, as the web's page and some tests).
  final Widget? activity;

  /// The home page's Filters, handed to the bar to draw in its own look, a circle after the title pill; null off the
  /// home page.
  final BarButton? filters;

  /// A screen's own controls handed as widgets with no model: drawn as they come, so nothing is lost.
  final Widget? tools, tail;

  /// The open note's title, for the Command centre's pill.
  final String? title;
  final bool atHome;
  final bool unread;

  /// A mouse rather than a finger: hints on hover, ⌘K said.
  final bool fine;

  /// How wide the row is.
  final double room;

  /// A note's screen is up and handed its tools as a model.
  bool get onNote => view != null;

  /// The way around, in today's order.
  List<HeaderAct> get way => [?home, ?sidebar, ?back, ?forward];

  /// What the line keeps under its ••• rather than in its row, at the menu's top (Matt, 2026-10-29: "Put the
  /// all files folder icon under the more menu as well as the + button in the header"): every note by folder, then a
  /// new note. ⌘N and the palette's commands make a note as they did; the home page's dock keeps its +.
  List<HeaderAct> get kept => [?folders, ?newNote];

  /// The note's own, the view first.
  List<HeaderAct> get noteActs => [?view, ...actions];

  /// The app's own behind the button for you, in the order its menu has them.
  List<HeaderAct> get you => [?bell, ?organizations, ?settings];

  /// Whether the row has room for words: the opened Fold, a tablet, the Mac.
  bool get wide => room >= 600;
}

/// What the line draws on the row: the start, a middle that takes what is left (or nothing, the start and end
/// pushed apart), and the end. The bar lays them out for its style: on one line, or the Islands' capsules.
@immutable
class HeaderRow {
  const HeaderRow({this.lead = const [], this.centre, this.trail = const []});

  final List<Widget> lead;
  final Widget? centre;
  final List<Widget> trail;
}

/// Whether the window is a phone's width, narrower than the opened Fold: where the line is a small step larger (Matt, 2026-10-29: "Make the header icons and search bar slightly larger on mobile"), their
/// glyphs by [phoneGlyphStep] and their rings by the shell's `data-header='phone'` (lib/shell/app_shell.dart).
bool headerOnPhone(BuildContext context) => MediaQuery.sizeOf(context).width < phoneWidth;

/// The width under which [headerOnPhone] holds.
const double phoneWidth = 600;

/// How much larger the line's glyphs are on a phone's width.
const double phoneGlyphStep = 1.5;

// ---- the note's tools as acts ------------------------------------------------------------------------------------

/// The hue and the short word each of the note's actions wears, by its id ([ToolAction.id]).
const Map<String, (String, String)> _actionLooks = {
  'share': ('green', 'Share'),
  'history': ('purple', 'History'),
  'links': ('mint', 'Links'),
  'comment': ('coral', 'Comment'),
  'bookmark': ('yellow', 'Bookmark'),
  'pin': ('rose', 'Pin'),
  'archive': ('orange', 'Archive'),
  'speak': ('red', 'Speak'),
};

/// The note's tools as acts: the view switch, its spare actions, its More.
({HeaderAct view, List<HeaderAct> actions, HeaderAct more}) noteActsOf(NoteToolsModel model) {
  final words = viewSwitchWords(model.kind, page: model.page);
  return (
    view: HeaderAct(id: 'view', label: words.label, word: words.title, hue: 'amber', icon: model.page ? Lucide.bookOpen : Lucide.code, onPress: model.switchable ? model.onSwitch : null),
    actions: [
      for (final action in model.actions)
        HeaderAct(
          id: action.id,
          label: action.label,
          word: action.id == 'pin' && (action.on ?? false) ? 'Unpin' : (_actionLooks[action.id]?.$2 ?? action.label),
          hue: _actionLooks[action.id]?.$1 ?? 'indigo',
          icon: action.icon,
          onPress: action.onPress,
          on: action.on ?? false,
          toggled: action.on,
          count: action.count,
        ),
    ],
    more: HeaderAct(id: 'more', label: 'More for this note', word: 'More for this note…', hue: 'indigo', icon: Lucide.ellipsisVertical, onPress: model.onMore),
  );
}
