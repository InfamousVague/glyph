import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/build_facts.dart';
import '../../core/preferences.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import '../settings_sheet.dart' show developerMode;
import 'pane_parts.dart';
import 'settings_host.dart';
import '../../core/iphone_app.dart' show recordsVoice;

/// The version this app is, as pubspec.yaml has it (a test holds the two together). About draws it when no updater
/// has said which build this is. The build that goes to the App Store has no updater to say, and is told its
/// version outright (`--dart-define=GHOST_VERSION=2.0.5`, tool/cutover-build-ios.sh), so About on an iPhone reads
/// what the store's page reads; told nothing, it is pubspec's, as it always was.
const String ghostVersion = String.fromEnvironment('GHOST_VERSION', defaultValue: '0.1.0');

/// The book's name and how many chapters it has (guidebook/guidebook.ts `GUIDE_TITLE`, `GUIDE_CHAPTERS`, as the web
/// app counted them on 2026-10-07).
const String guideTitle = 'Ghost.md: The Guide';
const int guideChapters = 44;

/// What Settings' search finds on About (`findable`, src/app/settings/AboutPane.findable.ts), by the names the page
/// draws, in its order. The cheat sheet, the specification and the examples are pages of their own, found by their
/// own names. The updates' names are listed where the page draws them: with an updater, and What's new not for a
/// copy from the App Store.
/// Whether About offers Ghost.md: The Guide. Not on an iPhone (Matt, 2026-10-13, before the Flutter build went to
/// the App Store): the book is the manual of the whole product, and its chapters are about recording, the side
/// key, the Fold, the Mac and how the Android app is built and updated, none of which an iPhone has. A copy an
/// account already holds still syncs and reads as the notebook it is.
bool get offersGuideBook => recordsVoice;

List<SettingsFindable> aboutFindable({required bool updates, required bool alerts, required bool whatsNew}) => [
      if (updates) const SettingsFindable('Updates', 'update check upgrade install'),
      // Android's own switch, drawn only where the activity has alerts to switch.
      if (alerts) const SettingsFindable('Update alerts', 'notifications notify'),
      const SettingsFindable('Ghost.md Academy', 'learn tutorial lessons'),
      const SettingsFindable('The welcome walkthrough', 'guide onboarding set-up first launch side key how to talk to ghost.md voice commands cues hey ghost keyword'),
      if (offersGuideBook) const SettingsFindable(guideTitle, 'guide manual help book notebook chapters add'),
      if (updates && whatsNew) const SettingsFindable("What's new", 'changelog releases'),
    ];

/// The Updates card's one row in the app: the first of these that is true (settings/updateLines.ts `updatesStatus`).
String updatesStatus(SettingsUpdates updates) {
  if (updates.checking) return 'Checking for updates.';
  if (updates.downloading != null) return 'Downloading Ghost.md ${updates.downloading}.';
  if (updates.installable != null) return 'Ghost.md ${updates.installable} is ready to install.';
  if (updates.ready) return 'A new version is downloaded.';
  if (updates.lastError != null) return "Couldn't check for updates: ${updates.lastError}";
  if (updates.checked) return 'Up to date.';
  return 'Not checked yet.';
}

/// About's reading in the list of sections, after the version: the same ladder, shorter (`updatesSummary`).
String updatesSummary(SettingsUpdates updates) {
  // An iPhone's copy checks nothing (Matt, 2026-10-13): its row says whose its updates are, as its page does.
  if (updates.store == 'appstore') return 'Updates through the App Store';
  if (updates.checking) return 'Checking';
  if (updates.installable != null) return '${updates.installable} ready to install';
  if (updates.ready) return 'New version downloaded';
  if (updates.lastError != null) return "Couldn't check";
  return updates.checked ? 'Up to date' : 'Not checked yet';
}

/// The line under the version: how this build got here, when it was built, the app it runs in, and where its updates
/// come from (`buildLine`, for the app).
String buildLine(SettingsUpdates updates) => [
      updates.overTheAir ? 'Updated over the air' : 'Built into the app',
      updates.built ?? 'unknown build',
      if (updates.nativeVersion != null) 'app ${updates.nativeVersion}',
      if (updates.staging) 'staging build, updates off' else if (updates.sourceHost != null) 'updates from ${updates.sourceHost}',
    ].join(' · ');

/// About's row in the list: the version and where it stands.
String aboutSummary(SettingsUpdates? updates) => updates == null ? ghostVersion : '${updates.version} · ${updatesSummary(updates)}';

/// Presses on the version needed to unlock the developer tools (settings/developerMode.ts `KNOCKS_WANTED`).
const int knocksWanted = 7;
const int _knockGapMs = 900;
int _knocks = 0;
int _lastKnock = 0;

/// Counts a press; answers how many remain, 0 on the press that completes the run (`countKnock`). Module state, as
/// the web's, because the page is built anew whenever the sections are.
int countKnock([int? now]) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  _knocks = at - _lastKnock > _knockGapMs ? 1 : _knocks + 1;
  _lastKnock = at;
  if (_knocks < knocksWanted) return knocksWanted - _knocks;
  _knocks = 0;
  return 0;
}

/// Port of `AboutPane` (src/app/settings/AboutPane.tsx) with the two parts of AboutUpdates.tsx: the version, big, then
/// where this build stands and how to move it on, then help, then every release published.
///
/// The version is also the door to the developer tools: seven presses on it, the way Android's own are unlocked,
/// with a countdown from the third press so somebody who knows the gesture knows it is working.
///
/// What differs from the web original:
/// - [updates] may be null, and is until the app has an updater (stage 9): the hero is then the version alone, and
///   the Updates card, its words and What's new are not drawn (nor listed for the search). With one, they are the
///   web's: the card's one row, Reload, Install and Check for updates, Android's alerts switch, and the releases.
///   The web's card for a browser ("You're on the web version") has no place in an app.
/// - Help's rows run callbacks that may be null (the Academy, the walkthrough and the book are later stages); such a
///   row is drawn and cannot be pressed. The three that open another page of Settings always can.
/// - The releases are handed in already read (`SettingsUpdates.releases`), where the page fetched them itself.
class AboutPane extends StatelessWidget {
  const AboutPane({super.key, this.updates, this.onGuide, this.onGuideBook, this.onAcademy, this.onOpen, this.developer});

  final SettingsUpdates? updates;

  /// Opens the welcome walkthrough on its first page.
  final VoidCallback? onGuide;

  /// Adds Ghost.md: The Guide, the book, and opens its index.
  final VoidCallback? onGuideBook;
  final VoidCallback? onAcademy;

  /// Lands on another page of Settings: the cheat sheet, the examples, and Developer at the seventh press.
  final void Function(String id)? onOpen;

  /// The developer switch the seventh press turns on; the app's own when null.
  final DeviceFlag? developer;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return AboutPane(updates: host?.updates, onGuide: host?.onGuide, onGuideBook: host?.onGuideBook, onAcademy: host?.onAcademy, onOpen: host == null ? null : (id) => host.go(id));
  }

  void _knock(BuildContext context) {
    final toast = GlacierToast.of(context);
    final left = countKnock();
    if (left == 0) {
      (developer ?? developerMode).set(true);
      HapticsProvider.of(context)(HapticKind.success);
      toast.toast(message: const Text('Developer settings are on.'), duration: const Duration(milliseconds: 1800));
      onOpen?.call('developer');
      return;
    }
    if (left <= knocksWanted - 3) {
      toast.toast(message: Text('$left more ${left == 1 ? 'tap' : 'taps'} for developer settings.'), duration: const Duration(milliseconds: 1000));
    }
  }

  @override
  Widget build(BuildContext context) {
    final updates = this.updates;
    SettingRow help(LucideIcon icon, String label, String hint, VoidCallback? onPress) =>
        SettingRow(icon: AppIcon(icon, size: 20), label: label, hint: Text(hint), onPress: onPress ?? () {}, disabled: onPress == null);
    final open = onOpen;
    return PaneBody(
      children: [
        PaneSection(
          children: [PaneHero(title: updates?.version ?? ghostVersion, meta: updates == null ? null : Text(buildLine(updates)), onPress: () => _knock(context))],
        ),
        if (updates != null) ...updatesSection(updates),
        PaneSection(
          title: 'Help',
          children: [
            help(Lucide.graduationCap, 'Ghost.md Academy', 'Markdown taught a mark at a time. It shows you one, you type your own, and you watch it format.', onAcademy),
            // What guide/pages.ts shows: four pages, the last of which offers the Academy.
            help(Lucide.bookOpen, 'The welcome walkthrough', recordsVoice ? 'The pages from the first launch: the theme, the model, and where the rest is taught.' : 'The pages from the first launch: the theme, and where the rest is taught.', onGuide),
            help(Lucide.listChecks, 'Cheat sheet', 'Every mark you can type, and what it looks like, on one page.', open == null ? null : () => open('cheatsheet')),
            help(Lucide.fileCode, 'Specification', 'Exactly how every extension and AI fill is written, and the standard Markdown under them.', open == null ? null : () => open('spec')),
            if (offersGuideBook) help(Lucide.bookOpenText, guideTitle, 'The whole app in $guideChapters short chapters. Added to your notes the first time, and opened after that.', onGuideBook),
            help(Lucide.shapes, 'Examples', 'A sample note, a board and two canvases, to add to your notes.', open == null ? null : () => open('examples')),
          ],
        ),
        // The releases are over-the-air builds, which an iPhone never runs: the App Store says what's new there.
        if (updates != null && updates.store != 'appstore') releasesSection(updates),
        // What this build is made of, as the build itself knows it: for saying which one a thing was seen in. Last on the
        // page, under everything the web app's About has (the owner asked for it on 2026-10-11; the page has none).
        PaneSection(
          title: 'This build',
          children: [
            for (final fact in buildFacts(version: updates?.version ?? ghostVersion, updatesFrom: updates?.sourceHost))
              SettingRow(label: fact.name, hint: Text(fact.words)),
          ],
        ),
      ],
    );
  }
}

/// Updates, as a part of the About page (AboutUpdates.tsx `UpdatesSection`): where this build stands, the words that
/// move it on, and the alerts switch.
List<Widget> updatesSection(SettingsUpdates updates) {
  // From the App Store: it updates the app, and there is nothing to check here.
  if (updates.store == 'appstore') {
    return const [
      PaneSection(title: 'Updates', children: [SettingRow(label: 'Ghost.md updates through the App Store.')]),
    ];
  }
  final alerts = updates.alerts;
  return [
    PaneSection(
      title: 'Updates',
      footer: updates.store == 'play' ? const Text('New versions of the app itself come through the Play Store.') : null,
      children: [SettingRow(label: updatesStatus(updates))],
    ),
    PaneActions(
      children: [
        if (updates.ready) RowAction(onPress: updates.onReload ?? () {}, disabled: updates.onReload == null, child: const Text('Reload')),
        if (updates.installable != null) RowAction(onPress: updates.onInstall ?? () {}, disabled: updates.onInstall == null, child: Text('Install ${updates.installable}')),
        RowAction(onPress: updates.onCheck ?? () {}, disabled: updates.checking || updates.onCheck == null, child: const Text('Check for updates')),
      ],
    ),
    if (alerts != null)
      PaneSection(
        title: 'Alerts',
        children: [
          SettingRow(
            label: 'Update alerts',
            hint: Text(
              alerts.blocked
                  ? "It's on, but Android is blocking Ghost.md's notifications. Allow them in the app's system settings."
                  : 'Get a notification when a new version is out, even when Ghost.md is closed.',
            ),
            control: GlacierSwitch(ariaLabel: 'Update alerts', checked: alerts.on, onCheckedChange: alerts.onChange),
          ),
        ],
      ),
  ];
}

/// What's new, as the foot of the About page (AboutUpdates.tsx `ReleasesSection`): every release published, newest
/// first, with the one running marked.
Widget releasesSection(SettingsUpdates updates) {
  final releases = updates.releases;
  if (releases.isEmpty) {
    final reading = updates.readingReleases;
    return PaneSection(
      title: "What's new",
      children: [
        SettingRow(
          label: reading ? 'Reading the updates…' : 'No updates to show yet.',
          hint: reading ? null : const Text('They are read from where Ghost.md takes its updates.'),
        ),
      ],
    );
  }
  final store = updates.store != null;
  // One group, a row a release: on the About page the list is the foot of it, not a page of cards of its own.
  return PaneSection(
    title: "What's new",
    description: Text(store ? 'Every update, newest first.' : 'Every update, newest first. A version with an app number needs installing.'),
    children: [
      for (final release in releases)
        SettingRow(
          key: ValueKey(release.build),
          label: release.build == updates.runningBuild ? "${release.version} · you're on this one" : release.version,
          value: Text(release.when),
          hint: Text([if (release.notes.isNotEmpty) release.notes, if (release.apk != null && !store) 'Installed as Ghost.md ${release.apk}.'].join(' ')),
        ),
    ],
  );
}
