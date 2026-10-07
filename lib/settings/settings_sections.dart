import 'package:flutter/widgets.dart';

import '../core/preferences.dart';
import 'appearance_pane.dart';
import 'kit/settings_icons.dart';
import 'kit/settings_kit.dart';
import 'settings_search.dart';
import 'words.dart';

/// What a section's row and its search words may depend on: the preferences as they stand, and what this device and
/// this window are. The readings come from the same stores the panes edit, so a row can never disagree with its
/// pane.
@immutable
class SettingsFacts {
  const SettingsFacts({required this.prefs, required this.wide, required this.haptics, required this.android, required this.ios, required this.developer});

  final Preferences prefs;

  /// Whether the window has room for the sidebar (`useSidebar`).
  final bool wide;

  /// Whether this device has a motor (`hapticsAvailable`).
  final bool haptics;
  final bool android;
  final bool ios;

  /// Whether developer mode is on (settings/developerMode.ts).
  final bool developer;
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
  /// plugins, the model, the version).
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
}

/// Workspaces' row in the list: how many there are (`workspaceSummary`).
String _workspaceSummary(int count) => count == 0
    ? 'None yet'
    : count == 1
        ? '1 workspace'
        : '$count workspaces';

String _static(String line, SettingsFacts _) => line;

/// The Privacy card's (AccountPane.findable.ts `privacy`), for the app, where a model runs.
const List<SettingsFindable> _privacy = [
  SettingsFindable('Privacy', 'what leaves the phone'),
  SettingsFindable('Local only', 'offline privacy network internet nothing leaves the phone'),
  SettingsFindable('Link previews', 'links url cards'),
  SettingsFindable('Look up blanks online', 'fill blank weather rates wikipedia web live internet'),
  SettingsFindable('Privacy policy', 'data privacy personal information policy'),
];

/// The Location card's (AccountPane.findable.ts `LOCATION`).
const List<SettingsFindable> _location = [
  SettingsFindable('Location', 'map place where geotag gps'),
  SettingsFindable('Map on a tagged note', 'openstreetmap tiles'),
  SettingsFindable('Place names', 'nominatim address geocode'),
  SettingsFindable('Tag new notes with my location', 'automatic gps position geotag place where front matter'),
];

/// Every section of the web app's Settings, in the list's order (SettingsSheet.tsx `sections`), in one table: the
/// rows on a phone, and the sub-pages off the list. A page that is ported has its [SettingsSectionSpec.pane]; the
/// rest name the web file they will come from. To port a page, write it and put it here.
///
/// The rows: who you are and what leaves the phone (Account, and beside it Organizations, Workspaces and
/// Notifications); where the notes are and the ways to carry them off (Library folder, Backup, Export); how it
/// looks, moves and feels (Appearance), what happens to a recording (Recording), the model (AI) and what reaches
/// beyond the phone (Plugins); the app itself (About); and the hidden pages (Developer, Test results) once unlocked.
///
/// What differs from the web original:
/// - There is no account yet, so Account reads "Not signed in", Organizations "Signed out", and each lists what a
///   signed-out page draws.
/// - Rows whose reading needs a store Flutter does not have are without their second line: AI (the model and what
///   it takes to get), Plugins (how many are on), About (the version and where it stands) and Test results.
/// - A switched-on plugin's own page, and the search words that are read from live lists (every plugin, every mark
///   on the cheat sheet, every definition of the specification), wait for those lists.
/// - "The app" is always true here: the web asked whether it ran inside Tauri, to leave a browser's rows out.
final List<SettingsSectionSpec> settingsSections = [
  // Who you are, first and on its own card: it is what a person opens Settings for on a new phone.
  SettingsSectionSpec(
    id: 'account',
    label: 'Account',
    words: 'sign in login handle encrypted sync',
    glyph: SettingsGlyph.circleUser,
    group: 0,
    webFile: 'settings/AccountPane.tsx',
    // Local only holds the sync off, so the line says it is on.
    summary: (facts) => 'Not signed in${facts.prefs.localOnly ? ' · Local only' : ''}',
    settings: (facts) => const [
      SettingsFindable('I have an account', 'sign in login'),
      SettingsFindable('Create an account', 'sign up register'),
      SettingsFindable('Lost the password', 'forgot recovery code reset'),
      ..._privacy,
      ..._location,
    ],
  ),
  // The teams the account is in: its own row under Account; one sentence signed out.
  SettingsSectionSpec(
    id: 'organizations',
    label: 'Organizations',
    words: 'teams team org invitations invite members',
    glyph: SettingsGlyph.userGroup,
    group: 0,
    webFile: 'settings/OrganizationsPane.tsx',
    summary: (facts) => 'Signed out',
  ),
  // Every workspace, to rename, colour or delete: beside Organizations, whose workspaces it lists too.
  SettingsSectionSpec(
    id: 'workspaces',
    label: 'Workspaces',
    words: 'workspace folders spaces delete remove rename colour color',
    glyph: SettingsGlyph.folder,
    group: 0,
    webFile: 'settings/WorkspacesPane.tsx',
    summary: (facts) => _workspaceSummary(facts.prefs.workspaces.list.length),
    settings: (facts) => const [
      SettingsFindable('Your workspaces', 'workspace rename colour color delete remove'),
      SettingsFindable('New workspace', 'create make add workspace'),
    ],
  ),
  // What reaches you: beside Account on the first card, in the coral the shell kept free.
  SettingsSectionSpec(
    id: 'notifications',
    label: 'Notifications',
    words: 'notify alerts bell invites invitations team claude mute',
    glyph: SettingsGlyph.bell,
    group: 0,
    webFile: 'settings/NotificationsPane.tsx',
    summary: (facts) => '${NotificationPrefs.categories.where(facts.prefs.notifications.isOn).length} of ${NotificationPrefs.categories.length} on',
    settings: (facts) => const [
      SettingsFindable('Team', 'organization members joined left removed renamed invitation accepted declined'),
      SettingsFindable('Claude', 'mcp ai note created edited appended journal rule'),
      SettingsFindable('Summaries', 'meeting written up summary recording'),
      SettingsFindable('Conflicts', 'sync kept twice both devices'),
    ],
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
    where: (facts) => !facts.ios,
    summary: (facts) => _static('Where your notes are kept', facts),
    settings: (facts) => const [
      SettingsFindable('Where your notes are', 'library folder choose move obsidian vault icloud dropbox syncthing backup drive'),
      SettingsFindable('Good to know', 'sync google drive index pictures recordings'),
    ],
  ),
  // Every note onto a removable drive, as plain files.
  SettingsSectionSpec(
    id: 'backup',
    label: 'Backup',
    words: 'back up backup usb drive sd card removable external disk copy save',
    glyph: SettingsGlyph.hardDriveUpload,
    group: 1,
    webFile: 'settings/BackupPane.tsx',
    where: (facts) => !facts.ios,
    summary: (facts) => _static('To a USB drive or SD card', facts),
  ),
  // Everything as one zip to carry away.
  SettingsSectionSpec(
    id: 'export',
    label: 'Export',
    words: 'export zip archive everything usb drive save copy',
    glyph: SettingsGlyph.hardDriveDownload,
    group: 1,
    webFile: 'settings/ExportCard.tsx',
    summary: (facts) => _static('Everything as one zip', facts),
    settings: (facts) => const [SettingsFindable('Export everything', 'backup back up usb drive stick zip archive copy save all notes')],
  ),
  SettingsSectionSpec(
    id: 'theme',
    label: 'Appearance',
    // Feel was a page's name until §138: its movement and its touch are cards here now.
    words: 'theme look feel',
    glyph: SettingsGlyph.sunMoon,
    group: 2,
    webFile: 'settings/AppearancePane.tsx',
    summary: (facts) => appearanceSummary(facts.prefs),
    settings: (facts) => appearanceFindable(wide: facts.wide, haptics: facts.haptics),
    pane: (context) => const AppearancePane(),
  ),
  // Where a recorder runs: Android, and the desktop app.
  SettingsSectionSpec(
    id: 'recording',
    label: 'Recording',
    words: 'voice microphone mic dictate',
    glyph: SettingsGlyph.mic,
    group: 2,
    webFile: 'settings/RecordingPane.tsx',
    where: (facts) => !facts.ios,
    // What a take becomes: better words, or the words as heard.
    summary: (facts) => facts.prefs.refine ? 'Better words' : 'Words as heard',
    settings: (facts) => [
      const SettingsFindable('Stop when I go quiet', 'silence auto stop'),
      const SettingsFindable('Review after recording', 'check transcript'),
      const SettingsFindable('Better words', 'refine clean up transcript'),
      const SettingsFindable('Summaries', 'summary meeting write-up minutes long voice notes'),
      if (facts.android) ...const [
        SettingsFindable('Include sound from other apps', 'system audio media games screen share meeting record'),
        SettingsFindable('Tell me when a meeting is written up', 'notification notify alert written up'),
        SettingsFindable('Write up straight away', 'meeting battery charging background'),
      ],
      // The desktop's own Meetings card: one switch, for the computer's sound.
      if (!facts.android) const SettingsFindable("Record the computer's sound too", 'system audio meeting call both sides zoom'),
      const SettingsFindable('Tapes', 'your tapes storage audio remove space'),
      const SettingsFindable('Remove audio older than a month', 'storage space delete recordings audio'),
    ],
  ),
  // The model and how it fills a note: its own section where a model runs, never an iPhone.
  SettingsSectionSpec(
    id: 'ai',
    label: 'AI',
    words: 'model llm fill blanks format summarize enhance',
    glyph: SettingsGlyph.sparkles,
    group: 2,
    webFile: 'settings/AiPane.tsx',
    where: (facts) => !facts.ios,
    settings: (facts) => const [
      SettingsFindable('Model', 'ai llm download formatting format enhance summarize choose your qwen gemma storage remove'),
      SettingsFindable('Fill blanks on their own', 'auto fill blanks automatic weather live facts idle'),
    ],
  ),
  SettingsSectionSpec(
    id: 'plugins',
    label: 'Plugins',
    words: 'extensions integrations add-ons',
    glyph: SettingsGlyph.puzzle,
    group: 2,
    webFile: 'plugins/PluginsPane.tsx',
  ),
  SettingsSectionSpec(
    id: 'about',
    label: 'About',
    words: 'version help',
    glyph: SettingsGlyph.info,
    group: 3,
    webFile: 'settings/AboutPane.tsx',
    settings: (facts) => [
      const SettingsFindable('Updates', 'update check upgrade install'),
      // Android's own switch, drawn only where the activity has alerts to switch.
      const SettingsFindable('Update alerts', 'notifications notify'),
      const SettingsFindable('Ghost.md Academy', 'learn tutorial lessons'),
      const SettingsFindable('The welcome walkthrough', 'guide onboarding set-up first launch side key how to talk to ghost.md voice commands cues hey ghost keyword'),
      const SettingsFindable('Ghost.md: The Guide', 'guide manual help book notebook chapters add'),
      // The App Store says what is new on an iPhone, so About draws no What's new there.
      if (!facts.ios) const SettingsFindable("What's new", 'changelog releases'),
    ],
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
    summary: (facts) => _static('Every extension and fill, defined', facts),
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
    // As About's row says it.
    summary: (facts) => _static('A sample note, a board and two canvases', facts),
    settings: (facts) => const [
      SettingsFindable('Add the sample note', 'example sample'),
      SettingsFindable('Add the example board', 'example kanban'),
      SettingsFindable('Add the example canvas', 'example obsidian'),
      SettingsFindable('Add the “How Ghost.md works” canvas', 'example canvas how it works'),
    ],
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
    settings: (facts) => const [
      SettingsFindable('Window', 'inset screen engine'),
      SettingsFindable('Smoke bench', 'wisp performance frames'),
      SettingsFindable('Play the scene', 'scene bench thermal heat readings'),
      SettingsFindable('Developer settings', 'mode'),
      SettingsFindable('Reset local data', 'clear erase'),
      SettingsFindable('Reset everything', 'clear erase models'),
    ],
  ),
  SettingsSectionSpec(
    id: 'test-results',
    label: 'Test results',
    words: 'tests report',
    glyph: SettingsGlyph.flaskConical,
    group: 4,
    webFile: 'settings/TestResultsPane.tsx',
    where: (facts) => facts.developer,
  ),
];

/// The page of a section that has none yet: what it is, and the web file it will be ported from.
class SettingsNotPorted extends StatelessWidget {
  const SettingsNotPorted({super.key, required this.spec});
  final SettingsSectionSpec spec;

  @override
  Widget build(BuildContext context) => PaneBody(
        children: [
          SettingsEmpty(
            icon: SettingsIcon(spec.glyph, size: 20),
            title: 'Not ported yet',
            body: Text('${spec.label} is still the web app’s. Its page will come from src/app/${spec.webFile}.'),
          ),
        ],
      );
}
