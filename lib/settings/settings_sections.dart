import 'package:flutter/widgets.dart';

import '../account/ui_state.dart';
import '../core/mac_app.dart' show macAppStore;
import '../core/preferences.dart';
import '../art/art.dart' show AppIcon, Lucide;
import '../core/workspaces.dart' show Workspace;
import '../market/market_items.dart' show marketLanding;
import '../plugins/catalogue.dart' show catalogueOrder;
import '../plugins/registry.dart' show plugins;
import 'appearance_pane.dart';
import 'kit/settings_icons.dart';
import 'kit/settings_kit.dart';
import 'mode_cards.dart';
import '../plugins/things/things.dart' show thingsOn;
import '../plugins/todoist/todoist.dart' show todoistOn;
import 'panes/backup_pane.dart';
import 'panes/library_folder_pane.dart';
import 'panes/meetings_pane.dart';
import 'panes/about_pane.dart';
import 'panes/account_pane.dart';
import 'panes/ai_pane.dart';
import 'panes/cheat_sheet.dart';
import 'panes/daily_notes_pane.dart';
import 'panes/developer_pane.dart';
import 'panes/examples_pane.dart';
import 'panes/export_pane.dart';
import 'panes/import_pane.dart';
import 'panes/notifications_pane.dart';
import 'panes/organizations_pane.dart';
import 'panes/plugins_pane.dart';
import 'panes/recording_pane.dart';
import 'panes/settings_host.dart';
import 'panes/spec_pane.dart';
import 'panes/test_results_pane.dart';
import 'panes/workspaces_pane.dart';
import 'settings_screen.dart' show SettingsTarget;
import 'settings_search.dart';
import 'words.dart';

/// What a section's row and its search words may depend on: the preferences as they stand, and what this device and
/// this window are. The readings come from the same stores the panes edit, so a row can never disagree with its
/// pane.
@immutable
class SettingsFacts {
  const SettingsFacts({
    required this.prefs,
    required this.wide,
    required this.haptics,
    required this.android,
    required this.ios,
    required this.developer,
    this.workspaces,
    this.updates,
    this.features = const SettingsFeatures(),
    this.services,
    this.sharedLinks = false,
  });

  final Preferences prefs;

  /// The account, where the app has one to hand Settings ([AccountScope]); null reads as before there was one.
  final AccountServices? services;

  /// Whether the account has anything shared by a link, which is when Account draws that card.
  final bool sharedLinks;

  /// Whether someone is signed in: the account's word where there is one, else [SettingsFeatures.signedIn].
  bool get signedIn => services?.signedIn ?? features.signedIn;

  /// How many workspaces the sheet's store holds; null reads the preferences' own.
  final int? workspaces;

  /// What About says of this build; null until the app has an updater.
  final SettingsUpdates? updates;

  /// What the features that are not ported yet would say (the account, the models, the tests' report).
  final SettingsFeatures features;

  /// Whether the window has room for the sidebar (`useSidebar`).
  final bool wide;

  /// Whether this device has a motor (`hapticsAvailable`).
  final bool haptics;
  final bool android;
  final bool ios;

  /// Whether developer mode is on (settings/developerMode.ts).
  final bool developer;

  /// Simple mode (GHST-103): the sections a new person needs; the rest wait behind Advanced ([simpleSections]).
  bool get simple => prefs.simple;
}

/// One row of [settingsSections]: a section of the web app's Settings as SettingsSheet.tsx lists it, with the web
/// file its page comes from and, once that page is ported, the page.
@immutable
class SettingsSectionSpec {
  const SettingsSectionSpec({
    required this.id,
    required this.label,
    required this.glyph,
    required this.group,
    required this.webFile,
    this.words,
    this.summary,
    this.settings,
    this.where,
    this.listed = true,
    this.parent,
    this.hue,
    this.pane,
    this.icon,
    this.searched = true,
  });

  final String id;
  final String label;
  final SettingsGlyph glyph;

  /// Rows with the same group share one card.
  final int group;

  /// The file under the web app's `src/app/` whose page this is.
  final String webFile;

  /// Other words the search finds the section by.
  final String? words;

  /// The row's second line. Null where the web's reading needs something Flutter does not have yet (the account, the
  /// model, the version).
  final String Function(SettingsFacts facts)? summary;

  /// The settings on its page, by the names the page gives them (its `.findable.ts`).
  final List<SettingsFindable> Function(SettingsFacts facts)? settings;

  /// Whether it is among the sections at all; null is always.
  final bool Function(SettingsFacts facts)? where;

  /// False keeps it off the list: a sub-page, opened from a row on its [parent]'s page, or found by the search.
  final bool listed;
  final String? parent;

  /// Its colour where it brings its own; otherwise the one kept for its id, or grey (settings_screen.dart).
  final String? hue;

  /// Its page. Null until it is ported, and the section then opens on a page that says so.
  final WidgetBuilder? pane;

  /// Its own icon at a size, in place of [glyph]: a plugin's, on its row of the list (the port's own).
  final Widget Function(double size)? icon;

  /// False keeps it out of the search's results (`SettingsSection.searched`).
  final bool searched;
}

String _static(String line, SettingsFacts _) => line;

/// Every section of the web app's Settings, in the list's order (SettingsSheet.tsx `sections`), in one table: the
/// rows on a phone, and the sub-pages off the list. A page that is ported has its [SettingsSectionSpec.pane] (the
/// pages are lib/settings/panes/, each built with what the sheet hands it, `X.hosted`); the rest name the web file
/// they will come from. To port a page, write it and put it here.
///
/// The rows: who you are and what leaves the phone (Account, and beside it Organizations, Workspaces, Notifications
/// and Meetings); how much of the app there is and how it looks, moves and feels (Appearance, on a card of its own
/// under Account's); where the notes are and the ways to carry them off (Library folder, Backup, Export); what
/// happens to a recording (Recording) and the model (AI); what reaches beyond the phone (Plugins); the app itself
/// (About); and the hidden pages (Developer, Test results) once unlocked. Appearance stood after Export, beside
/// Recording and AI, until Matt, 2026-10-24: "move the simple or advanced toggle under appearance and move appearnce
/// up in the settings to under account".
///
/// What differs from the web original:
/// - The account is the [AccountServices] the sheet finds over it ([SettingsFacts.services]). With none, Account
///   reads "Not signed in", Organizations "Signed out", and each lists what a signed-out page draws.
/// - Library folder and Backup are their pages, each over what Settings was handed for it
///   (`SettingsFeatures.libraryFolder`, `.backup`); until the root hands one, each says what the web's page says
///   where it cannot (an app to update, a device backups are not on).
/// - AI's reading is the chosen model and what it takes to get, from the catalogue; About's is the version alone
///   until the app has an updater; Test results' is "No report yet" until a report is built in.
/// - The plugins are not Settings' any more: their catalogue is the Market, a place of the app's own (Matt,
///   2026-10-26: "move the plugins section out of the settings (leaving plugin specific settings to own their
///   settings) add the plugins setting to the market page"; lib/market/market_screen.dart). Its card on the list
///   keeps the Market's row, which shuts Settings and opens it, and a row for each added plugin's own page
///   ([pluginPageSections]), read from the app's registry (lib/plugins/registry.dart `plugins`). So this table is
///   read afresh each time it is asked for, where the web built its list on every draw, and the sheet draws it
///   again whenever a plugin's switch moves. A link to what was Plugins (`plugins`, `plugins/<id>`) lands in the
///   Market ([settingsLanding], and the sheet's `onMarket`).
/// - "The app" is always true here: the web asked whether it ran inside Tauri, to leave a browser's rows out.
/// - Simple or advanced (GHST-103, the port's own), the choice the walkthrough asks, is Appearance's first card for
///   later (lib/settings/mode_cards.dart). It headed the list as a page of its own on a card of its own from
///   2026-10-18 until Matt, 2026-10-24: "move the simple or advanced toggle under appearance"; its id still lands,
///   on the card ([settingsAliases]). In Simple ([SettingsFacts.simple]) the list is [simpleSections] and no more:
///   the rest of the rows, and every plugin's page, pass out of `where` until Advanced is chosen again, and what is
///   not among the sections is not found by the search either, since the sheet lists a section's settings only once
///   it is in.
List<SettingsSectionSpec> get settingsSections => [
      for (final spec in _sections) ...[
        spec,
        if (spec.id == marketSectionId) ...pluginPageSections(),
      ],
    ];

/// The card the Market's row and the plugins' own pages share on the list, between AI's and About's.
const int pluginsGroup = 5;

/// The Market's row on Settings' list (lib/market/market_screen.dart), where Plugins was.
const String marketSectionId = 'market';

/// The card Appearance has to itself, under Account's (Matt, 2026-10-24: "move appearnce up in the settings to under
/// account"). Its own rather than a row of Account's: that card is who you are and what leaves the phone, and a row
/// in the middle of it would split it in two, since consecutive rows of one group are what share a card.
const int appearanceGroup = 6;

/// Ids that were a page once and are a card on another page now, each to its page and the card there, lit as a
/// search's find is: a link from outside or from a page that still says the old id lands where the thing is now
/// ([settingsLanding]). `experience`, Simple or advanced's page until 2026-10-24, is Appearance's Mode card.
const Map<String, ({String id, String setting})> settingsAliases = {'experience': (id: 'theme', setting: 'Mode')};

/// Where [target] lands: itself, or for an id of [settingsAliases] the page and the card it names, unless the link
/// named a card of its own. What was Plugins, and a plugin's page in it, is the Market's row, for a Settings with
/// nowhere to send the link on to (the sheet hands it to the Market itself where it can).
SettingsTarget settingsLanding(SettingsTarget target) {
  if (marketLanding(target.id) != null) return SettingsTarget(marketSectionId, nonce: target.nonce);
  final alias = settingsAliases[target.id];
  return alias == null ? target : SettingsTarget(alias.id, setting: target.setting ?? alias.setting, nonce: target.nonce);
}

/// The sections Simple keeps (Matt, 2026-10-18): who you are and what reaches you (with Meetings, which was a card of
/// Account's until GHST-110), how it looks with the choice itself on its first card, and the app itself with its
/// cheat sheet. Appearance is never put away: the way back to Advanced is on it. Everything else, Organizations, Workspaces, Library folder, Backup,
/// Export, Recording, AI, the Market and the plugins' pages, the Specification and the Examples, waits behind Advanced; Developer and Test
/// results answer to their own switch alone. The ids, so a test can hold the table to the list.
const Set<String> simpleSections = {'account', 'notifications', 'meetings', 'theme', 'about', 'cheatsheet', 'developer', 'test-results'};

/// `where` for a section Simple puts away: the one gate, AND-ed with the section's own where it has one.
bool _advanced(SettingsFacts facts) => !facts.simple;

/// Each added plugin's own page, a row of Settings' list on the Market's card (Matt, 2026-10-18: "move plugin
/// settings to their own page under settings"; and 2026-10-26: "leaving plugin specific settings to own their
/// settings"): in the plugin's own icon and colour, read by its own summary, and
/// found by the search by the plugin's name, what it does, and what its page lists. In the catalogue's order (by
/// category, then by name: Claude, Lovart; Calendar, Contacts, Place reminders; Things, Todoist; Discord, GitHub,
/// Notion, Slack, Webhooks). A plugin switched off, or held off by Local only, has no row and no page; its page in
/// the Market offers Add. The page itself is the plugin's, with a word at its foot on where the plugin is in the
/// Market ([PluginSettingsPage]). Its id is `plugin:<id>` ([pluginPageId]), which links into Settings land on.
///
/// What differs from the web original: there, each was a sub-page behind its card on Plugins, which is where it was
/// here too until 2026-10-18.
List<SettingsSectionSpec> pluginPageSections() => [
      for (final plugin in catalogueOrder(plugins.enabled()))
        if (plugin.settings case final own?)
          SettingsSectionSpec(
            id: pluginPageId(plugin.manifest.id),
            label: plugin.manifest.name,
            words: plugin.manifest.description,
            glyph: SettingsGlyph.puzzle,
            icon: (size) => pluginIcon(plugin, size),
            group: pluginsGroup,
            webFile: 'plugins/PluginsPane.tsx',
            summary: (facts) => own.summary(),
            settings: (facts) => own.settings,
            // Plugins are what Simple hides, each one's page with the Market.
            where: _advanced,
            hue: own.hue,
            pane: (context) => PluginSettingsPage(plugin: plugin),
          ),
    ];

final List<SettingsSectionSpec> _sections = [
  // Who you are, first and on its own card: it is what a person opens Settings for on a new phone.
  SettingsSectionSpec(
    id: 'account',
    label: 'Account',
    words: 'sign in login handle encrypted sync',
    glyph: SettingsGlyph.circleUser,
    group: 0,
    webFile: 'settings/AccountPane.tsx',
    // Local only holds the sync off, so the line says it is on.
    summary: (facts) => accountSummary(facts.prefs, facts.services),
    settings: (facts) => accountFindable(signedIn: facts.signedIn, ported: facts.services != null, shared: facts.sharedLinks),
    pane: AccountPane.hosted,
  ),
  // The teams the account is in: its own row under Account; one sentence signed out.
  SettingsSectionSpec(
    id: 'organizations',
    label: 'Organizations',
    words: 'teams team org invitations invite members',
    glyph: SettingsGlyph.userGroup,
    group: 0,
    webFile: 'settings/OrganizationsPane.tsx',
    // Teams are Advanced's ("boards, databases, canvases, AI, teams").
    where: _advanced,
    summary: (facts) => organizationsSummary(facts.services),
    settings: (facts) => organizationsFindable(signedIn: facts.services?.signedIn ?? false),
    pane: OrganizationsPane.hosted,
  ),
  // Every workspace, to rename, colour or delete: beside Organizations, whose workspaces it lists too.
  SettingsSectionSpec(
    id: 'workspaces',
    label: 'Workspaces',
    words: 'workspace folders spaces delete remove rename colour color',
    glyph: SettingsGlyph.folder,
    group: 0,
    webFile: 'settings/WorkspacesPane.tsx',
    where: _advanced,
    // The count from the store the page edits, so the row can never disagree with it.
    summary: (facts) => workspaceSummary(facts.workspaces ?? facts.prefs.workspaces.list.length),
    settings: (facts) => workspacesFindable,
    pane: WorkspacesPane.hosted,
  ),
  // Where today's note goes and what it starts from (lib/notes/daily_notes.dart): a page behind Workspaces, the
  // folders it is filed in, off the list so the list stays the web's, and found by the search. The port's own,
  // 2026-10-16; it has no page in tauri/.
  SettingsSectionSpec(
    id: 'daily',
    label: 'Daily notes',
    words: 'daily note today journal date template folder',
    glyph: SettingsGlyph.calendarDays,
    group: 0,
    webFile: 'settings/WorkspacesPane.tsx',
    // With its parent.
    where: _advanced,
    summary: (facts) => dailyNotesSummary(facts.prefs, [for (final w in facts.prefs.workspaces.list) Workspace(id: w.id, name: w.name)]),
    settings: (facts) => dailyNotesFindable,
    pane: DailyNotesPane.hosted,
    listed: false,
    parent: 'workspaces',
  ),
  // What reaches you: beside Account on the first card, in the coral the shell kept free.
  SettingsSectionSpec(
    id: 'notifications',
    label: 'Notifications',
    words: 'notify alerts bell invites invitations team claude mute',
    glyph: SettingsGlyph.bell,
    group: 0,
    webFile: 'settings/NotificationsPane.tsx',
    summary: (facts) => notificationsSummary(facts.prefs.notifications),
    settings: (facts) => notificationsFindable(orgs: facts.services != null ? facts.services!.joined.isNotEmpty : facts.features.orgs.isNotEmpty),
    pane: NotificationsPane.hosted,
  ),
  // Ghost in meetings, a section of its own after the card on Account it was (Matt, 2026-10-23: "Make the meeting
  // section its own section in settings and move the invite card to the top"). Only where the account's service has
  // the bot; kept in Simple, as Account's card was. The port's own: the web app has no such page.
  SettingsSectionSpec(
    id: 'meetings',
    label: 'Meetings',
    words: 'meet google meeting ghost bot invite join record transcribe calendar notetaker',
    glyph: SettingsGlyph.users,
    group: 0,
    webFile: 'settings/AccountPane.tsx',
    where: (facts) => meetingsOffered(facts.services),
    summary: (facts) => meetingsSummary(facts.services),
    settings: (facts) => meetingsFindable(facts.services),
    pane: MeetingsPane.hosted,
  ),
  // How much of the app there is and how it looks, moves and feels: on a card of its own under Account's (Matt,
  // 2026-10-24: "move the simple or advanced toggle under appearance and move appearnce up in the settings to under
  // account"). No `where`: in Simple its first card is the way back to the rest, so it is never put away.
  SettingsSectionSpec(
    id: 'theme',
    label: 'Appearance',
    // Feel was a page's name until §138: its movement and its touch are cards here now. The mode's words since
    // 2026-10-24, when its page became the first card here.
    words: 'theme look feel mode simple advanced',
    glyph: SettingsGlyph.sunMoon,
    group: appearanceGroup,
    webFile: 'settings/AppearancePane.tsx',
    // The mode first, as the page has it, then the looks.
    summary: (facts) => '${experienceSummary(facts.prefs)} · ${appearanceSummary(facts.prefs)}',
    // In Simple the page is the mode, the theme and the text size alone, and so is what the search finds on it.
    settings: (facts) => appearanceFindable(wide: facts.wide, haptics: facts.haptics, simple: facts.simple),
    pane: (context) => const AppearancePane(),
  ),
  // Where the notes are, and the two ways to carry them off: a card of their own, where the app keeps its notes in
  // files (not an iPhone), and Export everywhere.
  SettingsSectionSpec(
    id: 'library',
    label: 'Library folder',
    words: 'library folder where notes are kept obsidian vault icloud dropbox syncthing move',
    glyph: SettingsGlyph.folderOpen,
    group: 1,
    webFile: 'settings/LibraryFolderPane.tsx',
    where: (facts) => !facts.ios && _advanced(facts),
    summary: (facts) => _static('Where your notes are kept', facts),
    settings: (facts) => libraryFolderFindable,
    pane: LibraryFolderPane.hosted,
  ),
  // Every note onto a removable drive, as plain files.
  SettingsSectionSpec(
    id: 'backup',
    label: 'Backup',
    words: 'back up backup usb drive sd card removable external disk copy save',
    glyph: SettingsGlyph.hardDriveUpload,
    group: 1,
    webFile: 'settings/BackupPane.tsx',
    // Not in the Mac App Store's build ([macAppStore]): a sandboxed app cannot ask the Mac which disks are
    // removable (the core asks `diskutil`) nor write a drive by its path, so the page is left out rather than
    // shown empty. Export is the way to a copy there.
    where: (facts) => backupOffered(ios: facts.ios) && _advanced(facts),
    summary: (facts) => _static('To a USB drive or SD card', facts),
    settings: (facts) => backupFindable,
    pane: BackupPane.hosted,
  ),
  // Everything as one zip to carry away.
  SettingsSectionSpec(
    id: 'export',
    label: 'Export',
    words: 'export zip archive everything usb drive save copy',
    glyph: SettingsGlyph.hardDriveDownload,
    group: 1,
    webFile: 'settings/ExportCard.tsx',
    where: _advanced,
    // An iPhone exports nothing yet, and its page says so (export_pane.dart): the row does not promise a zip.
    summary: (facts) => _static(facts.ios ? 'Not on iPhone yet' : 'Everything as one zip', facts),
    settings: (facts) => exportFindable,
    pane: ExportPane.hosted,
  ),
  // Notes from another app, into a workspace of their own: a page behind Export's Import row, on Android and the Mac,
  // which have a picker for a folder. The app's own: the web app has no such page, so its file is Export's. Obsidian
  // and Evernote are always here; Todoist and Things while their plugins are on (lib/plugins/todoist, things).
  SettingsSectionSpec(
    id: 'import',
    label: 'Import',
    words: 'import obsidian vault evernote enex move from another app bring in',
    glyph: SettingsGlyph.folderInput,
    group: 1,
    webFile: 'settings/ExportCard.tsx',
    where: (facts) => !facts.ios && _advanced(facts),
    summary: (facts) => importSummary(importKinds()),
    settings: (facts) => importFindableOf(importKinds()),
    pane: (context) => ImportPane.hosted(context, kinds: importKinds()),
    listed: false,
    parent: 'export',
  ),
  // Where a recorder runs: Android, and the desktop app.
  SettingsSectionSpec(
    id: 'recording',
    label: 'Recording',
    words: 'voice microphone mic dictate',
    glyph: SettingsGlyph.mic,
    group: 2,
    webFile: 'settings/RecordingPane.tsx',
    where: (facts) => !facts.ios && _advanced(facts),
    // What a take becomes: better words, or the words as heard.
    summary: (facts) => recordingSummary(facts.prefs),
    settings: (facts) => recordingFindable(android: facts.android),
    pane: RecordingPane.hosted,
  ),
  // The model and how it fills a note: its own section where a model runs, never an iPhone.
  SettingsSectionSpec(
    id: 'ai',
    label: 'AI',
    words: 'model llm fill blanks format summarize enhance',
    glyph: SettingsGlyph.sparkles,
    group: 2,
    webFile: 'settings/AiPane.tsx',
    where: (facts) => !facts.ios && _advanced(facts),
    summary: (facts) => aiSummary(facts.prefs, facts.features.models),
    settings: (facts) => aiFindable,
    pane: AiPane.hosted,
  ),
  // The Market (lib/market/market_screen.dart), first on a card of its own, with each added plugin's page after it
  // (settingsSections): its row shuts Settings and opens the Market, where the plugins, themes and fonts are.
  SettingsSectionSpec(
    id: marketSectionId,
    label: 'Market',
    words: 'plugins plugin extensions integrations add-ons marketplace catalogue store browse install add themes fonts',
    glyph: SettingsGlyph.puzzle,
    icon: (size) => AppIcon(Lucide.store, size: size),
    group: pluginsGroup,
    webFile: 'plugins/PluginsPane.tsx',
    where: _advanced,
    summary: (facts) => pluginsSummary(plugins),
    pane: MarketPane.hosted,
  ),
  SettingsSectionSpec(
    id: 'about',
    label: 'About',
    words: 'version help',
    glyph: SettingsGlyph.info,
    group: 3,
    webFile: 'settings/AboutPane.tsx',
    // The version and where it stands, now that updates live on this page too.
    summary: (facts) => aboutSummary(facts.updates),
    settings: (facts) => aboutFindable(updates: facts.updates != null, alerts: facts.updates?.alerts != null, whatsNew: facts.updates?.store != 'appstore'),
    pane: AboutPane.hosted,
  ),
  // Help, not settings: pages behind About's Help card, still searched, and found by their own names alone.
  SettingsSectionSpec(
    id: 'cheatsheet',
    label: 'Cheat sheet',
    // "Formatting cheat sheet" is its name in a note's More sheet, and was About's row's.
    words: 'markdown syntax marks help formatting',
    glyph: SettingsGlyph.bookOpen,
    group: 3,
    webFile: 'guide/CheatSheet.tsx',
    summary: (facts) => _static('Every mark you can type', facts),
    // Every mark it shows, so looking for "bold" or "spoiler" lands on it.
    settings: (facts) => cheatSheetFindable(),
    pane: (context) => const CheatSheet(),
    listed: false,
    parent: 'about',
  ),
  SettingsSectionSpec(
    id: 'spec',
    label: 'Specification',
    words: 'markdown spec commonmark gfm syntax extensions fills reference',
    glyph: SettingsGlyph.fileCode,
    group: 3,
    webFile: 'settings/SpecPane.tsx',
    // The specification and the examples are the whole app's: About's Help keeps the cheat sheet alone in Simple.
    where: _advanced,
    summary: (facts) => _static('Every extension and fill, defined', facts),
    settings: (facts) => specFindable(),
    pane: SpecPane.hosted,
    listed: false,
    parent: 'about',
  ),
  SettingsSectionSpec(
    id: 'examples',
    label: 'Examples',
    words: 'sample example',
    glyph: SettingsGlyph.shapes,
    group: 3,
    webFile: 'settings/ExamplesPane.tsx',
    where: _advanced,
    // As About's row says it.
    summary: (facts) => _static('A sample note, a board and two canvases', facts),
    settings: (facts) => examplesFindable,
    pane: ExamplesPane.hosted,
    listed: false,
    parent: 'about',
  ),
  // The hidden pages, only once unlocked.
  SettingsSectionSpec(
    id: 'developer',
    label: 'Developer',
    words: 'debug',
    glyph: SettingsGlyph.terminal,
    group: 4,
    webFile: 'settings/DeveloperPane.tsx',
    where: (facts) => facts.developer,
    summary: (facts) => _static('Benches, reset', facts),
    settings: (facts) => developerFindable,
    pane: DeveloperPane.hosted,
  ),
  SettingsSectionSpec(
    id: 'test-results',
    label: 'Test results',
    words: 'tests report',
    glyph: SettingsGlyph.flaskConical,
    group: 4,
    webFile: 'settings/TestResultsPane.tsx',
    where: (facts) => facts.developer,
    summary: (facts) => reportSummary(facts.features.testReport == null ? null : TestReport.of(facts.features.testReport!), buildSource: facts.features.testBuildSource),
    pane: TestResultsPane.hosted,
  ),
];

/// The page of a section that has none yet: what it is, and the web file it will be ported from.
class SettingsNotPorted extends StatelessWidget {
  const SettingsNotPorted({super.key, required this.spec});
  final SettingsSectionSpec spec;

  @override
  Widget build(BuildContext context) => PaneBody(children: [SettingsNotPortedCard(spec: spec)]);
}

/// The card [SettingsNotPorted] is, for a page that is ported in part and says so among its own cards.
class SettingsNotPortedCard extends StatelessWidget {
  const SettingsNotPortedCard({super.key, required this.spec});
  final SettingsSectionSpec spec;

  @override
  Widget build(BuildContext context) => SettingsEmpty(
        icon: SettingsIcon(spec.glyph, size: 20),
        title: 'Not ported yet',
        body: Text('${spec.label} is still the web app’s. Its page will come from src/app/${spec.webFile}.'),
      );
}

/// The imports Settings › Import offers: Obsidian's and Evernote's, and Todoist's and Things' while their plugins
/// are on.
List<ImportKind> importKinds() => [ImportKind.obsidian, ImportKind.evernote, if (todoistOn()) ImportKind.todoist, if (thingsOn()) ImportKind.things];

/// Import's line: where it brings notes from.
String importSummary(List<ImportKind> kinds) {
  final names = [
    for (final kind in kinds)
      switch (kind) {
        ImportKind.obsidian => 'Obsidian',
        ImportKind.evernote => 'Evernote',
        ImportKind.todoist => 'Todoist',
        ImportKind.things => 'Things',
      },
  ];
  if (names.length <= 1) return names.isEmpty ? 'Nothing to import' : 'From ${names.single}';
  return 'From ${names.sublist(0, names.length - 1).join(', ')} or ${names.last}';
}

/// Whether Settings has a Backup page: not on an iPhone, and not in the Mac App Store's build.
bool backupOffered({required bool ios, bool? macStore}) => !ios && !(macStore ?? macAppStore);
