/// The header toolbar's six versions, and the seam the top bar picks one through (Matt, 2026-10-28: "Add a few
/// ways to redo the header toolbar icons right now it's just a huge list of icons and is quite hard to work with
/// include versions with different iconography vibrant colors and different UI/UX add a developer setting to switch
/// between 5 versions"; and the sixth, after the contact sheet on 2.3.61: "Make a version that combines the command
/// center and grouped sections").
///
/// The bar's four styles (lib/shell/top_bar.dart: Classic, Ledger, Masthead, Islands) are layouts of one row of
/// rings; a version is what that row holds and how it is drawn - which controls stand out, which are gathered into
/// a pill or a menu, in what weight of glyph and on what ground. So the two go together: any version in any style,
/// the style saying where the row of controls is and what shape the tabs take, the version saying what the row is.
///
/// - **1, Today's bar** ([HeaderToolbarVersion.today]): the row as it was, every control its own ring. The bar draws
///   its own code for it and nothing here is asked, so its pictures are exactly what they were.
/// - **2, Grouped** (header/grouped_row.dart): the way around as one segmented pill, the note's few most used in a
///   second with the rest under •••, and the app's own - the bell, the organizations, Settings - behind one round
///   button for you, its dot the bell's.
/// - **3, Vibrant tiles** (header/tiles_row.dart): each control a small tile in its own hue, the Market's tiles'
///   colours, with a white filled glyph; fewer at once, the rest under a tile of •••, and a word beside each of the
///   note's on a wide window.
/// - **4, Command centre** (header/command_row.dart): Back, then a pill with the note's name that opens the command
///   palette, then one action and •••, whose menu has everything else in sections, each glyph in its colour.
/// - **5, Labelled** (header/labelled_row.dart): only what the screen is for, with words on a wide window: on a
///   note the view, Share and More; at home Search, New and Browse. The app's own are behind the round button for
///   you, and the bell is a dot on it.
/// - **6, Grouped command** (header/grouped_command_row.dart): Grouped's pills at the ends - the way around, the
///   note's own with •••, the button for you - and Command centre's title pill between them, opening the palette. On
///   a narrow window the pills keep the sidebar and Back, the view and •••, and the rest is one press away.
///
/// Every version keeps every control the bar was given within reach: in the row, or in a menu one press away
/// (test/shell/header_toolbar_test.dart presses for each). A control the bar was not given (simple mode's, a phone
/// reading a note's) is in no version. The labels a screen reader says are today's, word for word, in every one.
///
/// The choice is a developer's, of this device ([headerToolbarChoice], Settings › Developer › Header toolbar), and
/// the bar hears it: a change is the bar drawn again at once, nothing restarted.
library;

import 'package:flutter/widgets.dart';

import '../art/app_icon.dart' show LucideIcon;
import '../art/lucide.g.dart';
import '../core/preferences.dart' show DeviceWord;
import '../core/workspaces.dart' show OrgLike;
import '../note/note_tools.dart';
import 'header/command_row.dart';
import 'header/grouped_command_row.dart';
import 'header/grouped_row.dart';
import 'header/labelled_row.dart';
import 'header/tiles_row.dart';
import 'top_bar_tools.dart' show BarButton;

/// The six, in the order Developer offers them, each with the line said under its name there.
enum HeaderToolbarVersion {
  today('Today’s bar', 'Every control its own ring on one line, as the bar has been.'),
  grouped('Grouped', 'The way around in one pill, the note’s most used in another with the rest under •••, and the bell, teams and Settings behind your round button.'),
  tiles('Vibrant tiles', 'Each control a small tile in its own colour with a white glyph, fewer at once and the rest under •••; words beside the note’s on a wide window.'),
  command('Command centre', 'Back, the note’s name in a pill that opens the command palette, one action and •••, with everything else in its menu’s sections.'),
  labelled('Labelled', 'Only what the screen needs, with words on a wide window: view, Share and More on a note; Search, New and Browse at home. The bell is a dot on you.'),
  groupedCommand('Grouped command', 'Grouped’s pills at the ends and the note’s name between them in a pill that opens the command palette; on a phone the pills keep Back, the sidebar, the view and •••.');

  const HeaderToolbarVersion(this.label, this.hint);

  final String label;
  final String hint;

  /// Its number, as Matt counts them: today's is 1.
  int get number => index + 1;

  /// The word it is kept as.
  String get id => name;

  /// Whether its bar holds a search pill that opens the command palette: Command centre and Grouped command. Their
  /// home page then has no search field of its own, nor does the opened Fold's notes column, and the home page's
  /// Filters are a circle of the bar's after the pill (Matt, 2026-10-29, of Command centre on 2.3.68: "the search bar
  /// and filters is still showing on the homepage on mobile when it shouldn't"; until then only Grouped command did).
  bool get searchPill => this == command || this == groupedCommand;

  /// The version a kept word names; one this build does not know is today's.
  static HeaderToolbarVersion parse(Object? id) {
    for (final version in values) {
      if (version.name == id) return version;
    }
    return HeaderToolbarVersion.today;
  }
}

/// This device's choice, kept as `glyph-header-toolbar` and as nothing while it is today's: a developer's look at the
/// bar on the phone in his hand, so not a preference that travels to the account's other devices.
final DeviceWord headerToolbarChoice = DeviceWord('glyph-header-toolbar', fallback: HeaderToolbarVersion.today.id, words: {for (final version in HeaderToolbarVersion.values) version.id});

/// The version [headerToolbarChoice] says.
HeaderToolbarVersion get headerToolbarVersion => HeaderToolbarVersion.parse(headerToolbarChoice.value);

/// One control the bar was given, as words: what it is, what it says, what it draws and what a press does. Every
/// version draws the same ones; each draws them its own way.
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

  /// One of the Market's hues (lib/market/market_items.dart `marketHues`), for the versions that wear colour.
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

/// Everything the bar was given, sorted into what it is for, for a version to draw. Built by the bar
/// (lib/notes/note_tabs.dart) from its own fields; nothing in it is a version's.
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
    this.search,
    this.newNote,
    this.allNotes,
    this.organizations,
    this.orgs = const [],
    this.onOrganization,
    this.bell,
    this.settings,
    this.aside,
    this.presence,
    this.filters,
    this.tools,
    this.tail,
    this.title,
    this.atHome = false,
    this.unread = false,
    required this.fine,
    required this.room,
  });

  // The way around: and every note by folder, after the sidebar (Matt, 2026-10-29: "add a folder icon to the top near home and sidebar to show all notes in the folder / icon view").
  final HeaderAct? home, sidebar, folders, back, forward;

  /// The note's view switch, its spare actions in today's order (Share, History, Links, Comment, Bookmark, Pin,
  /// Archive, Speak), and its More, the sheet with all of them and the rest; null where no note is up.
  final HeaderAct? view;
  final List<HeaderAct> actions;
  final HeaderAct? more;

  /// What the home page asks of a bar that has room for it: the command palette, a new note, every note.
  final HeaderAct? search, newNote, allNotes;

  /// The app's own: the organizations (Settings' list, [organizations]; each one's dashboard, [orgs] by
  /// [onOrganization]), the bell, Settings, and the aside's toggle.
  final HeaderAct? organizations;
  final List<OrgLike> orgs;
  final ValueChanged<String>? onOrganization;
  final HeaderAct? bell, settings, aside;

  /// Who else is here: the Claude chip, drawn as it comes.
  final Widget? presence;

  /// The home page's Filters, handed to the bar to draw in its own look; null off the home page, and for a version
  /// that leaves them on the page (all but Grouped command).
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
  List<HeaderAct> get way => [?home, ?sidebar, ?folders, ?back, ?forward];

  /// The note's own, the view first.
  List<HeaderAct> get noteActs => [?view, ...actions];

  /// The app's own behind the button for you, in the order its menu has them.
  List<HeaderAct> get you => [?bell, ?organizations, ?settings];

  /// Whether the row has room for words: the opened Fold, a tablet, the Mac.
  bool get wide => room >= 600;
}

/// What a version draws on the row: the start, a middle that takes what is left (or nothing, the start and end
/// pushed apart), and the end. The bar lays them out for its style: on one line, or the Islands' capsules.
@immutable
class HeaderRow {
  const HeaderRow({this.lead = const [], this.centre, this.trail = const []});

  final List<Widget> lead;
  final Widget? centre;
  final List<Widget> trail;
}

/// Whether the window is a phone's width, narrower than the opened Fold: where the two versions with a search pill are
/// a small step larger (Matt, 2026-10-29: "Make the header icons and search bar slightly larger on mobile"), their
/// glyphs by [phoneGlyphStep] and their rings by the shell's `data-header='phone'` (lib/shell/app_shell.dart).
bool headerOnPhone(BuildContext context) => MediaQuery.sizeOf(context).width < phoneWidth;

/// The width under which [headerOnPhone] holds.
const double phoneWidth = 600;

/// How much larger the glyphs of a search pill's bar are on a phone's width.
const double phoneGlyphStep = 1.5;

/// Draws a version's row from the parts.
typedef HeaderRowBuilder = HeaderRow Function(BuildContext context, HeaderParts parts);

/// The one place a version is chosen: its row's builder, or null for today's, which the bar draws itself.
HeaderRowBuilder? headerRowFor(HeaderToolbarVersion version) => switch (version) {
      HeaderToolbarVersion.today => null,
      HeaderToolbarVersion.grouped => groupedRow,
      HeaderToolbarVersion.tiles => tilesRow,
      HeaderToolbarVersion.command => commandRow,
      HeaderToolbarVersion.labelled => labelledRow,
      HeaderToolbarVersion.groupedCommand => groupedCommandRow,
    };

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
