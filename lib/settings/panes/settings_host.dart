import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/backup.dart' show Backups;
import '../../core/export_all.dart' show ExportAll;
import '../../core/library_folder.dart' show LibraryFolder;
import '../../core/place_tags.dart' show PlaceTags;
import '../../core/preferences.dart';
import '../../core/workspaces.dart';
import '../../export/ghostex_calls.dart' show Ghostex;
import '../../importer/importer.dart' show Importer;
import '../settings_screen.dart' show SettingsTarget;

/// A release as What's new lists it (core/changelog.ts `Release`, already put in words).
@immutable
class SettingsRelease {
  const SettingsRelease({required this.build, required this.version, required this.when, this.notes = '', this.apk});

  /// The build's stamp, which is how the one running is told.
  final String build;
  final String version;

  /// When it was published, as the row says it (`releaseWhen`).
  final String when;
  final String notes;

  /// The app version it has to be installed as, where it is more than a page.
  final String? apk;
}

/// Whether the phone raises an alert for a new version (settings/useUpdateAlerts.ts).
@immutable
class SettingsUpdateAlerts {
  const SettingsUpdateAlerts({required this.on, this.blocked = false, required this.onChange});
  final bool on;

  /// On here, and kept from showing by the phone.
  final bool blocked;
  final ValueChanged<bool> onChange;
}

/// What About says of this build and the ones after it (core/ota.ts `Updates`, as far as the page reads it). The
/// app's updater makes one and hands it to Settings; until there is one, About draws the version alone.
@immutable
class SettingsUpdates {
  const SettingsUpdates({
    required this.version,
    this.built,
    this.nativeVersion,
    this.sourceHost,
    this.overTheAir = false,
    this.staging = false,
    this.store,
    this.checking = false,
    this.ready = false,
    this.lastError,
    this.checked = false,
    this.downloading,
    this.installable,
    this.onCheck,
    this.onReload,
    this.onInstall,
    this.alerts,
    this.releases = const [],
    this.readingReleases = false,
    this.runningBuild,
  });

  final String version;

  /// When this build was made, in words (`describeBuild`); null is "unknown build".
  final String? built;

  /// The app the page runs in (`status.nativeVersion`).
  final String? nativeVersion;

  /// Where its updates come from (`sourceHost`).
  final String? sourceHost;

  /// Whether this build arrived over the air rather than inside the app.
  final bool overTheAir;
  final bool staging;

  /// `play`, `appstore`, or null for a build from the site (`storeOf`).
  final String? store;
  final bool checking;

  /// A new version is downloaded and waits for a reload.
  final bool ready;
  final String? lastError;

  /// Whether it has checked at all.
  final bool checked;

  /// The version of an app being downloaded.
  final String? downloading;

  /// The version of an app that can be installed (`installable`).
  final String? installable;
  final VoidCallback? onCheck;
  final VoidCallback? onReload;
  final VoidCallback? onInstall;

  /// Android's own alerts; null where there are none to switch.
  final SettingsUpdateAlerts? alerts;
  final List<SettingsRelease> releases;
  final bool readingReleases;

  /// The build that is running, for the mark in What's new.
  final String? runningBuild;
}

/// A model in the catalogue as the AI page draws it (core/ai.ts `ModelChoice` with `ModelInfo.present`).
@immutable
class SettingsModelsState {
  const SettingsModelsState({this.present = const {}, this.running, this.downloading, this.received = 0, this.total = 0, this.problem, this.cannotRun = const {}});

  /// The ids of the models on this device.
  final Set<String> present;

  /// The model that runs (ai/available.ts `modelFor`): the chosen one when it is here, else its stand-in.
  final String? running;

  /// The id of the model being fetched, with the bytes so far.
  final String? downloading;
  final int received;
  final int total;
  final String? problem;

  /// Models that are here and that this build cannot run (core/runnable.ts).
  final Set<String> cannotRun;
}

/// A way into an account, as the form asks for it (AccountPane.tsx `useWayIn`'s submit): the mode is `in`, `up` or
/// `recover`. Answers the recovery codes a new or recovered account is given, or null for a plain sign-in, and
/// throws what went wrong as words.
typedef SettingsWayIn = Future<List<String>?> Function({required String mode, required String handle, required String password, String? code});

/// What the pages of Settings ask of features that have no Flutter port yet: each is null until its feature is
/// here, and the row that would use it is then drawn and cannot be pressed (or, for a state, reads as "nothing
/// yet"). Hand one to `SettingsSheet(features:)` as the features arrive.
@immutable
class SettingsFeatures {
  const SettingsFeatures({
    this.signedIn = false,
    this.onWayIn,
    this.orgs = const [],
    this.libraryFolder,
    this.backup,
    this.export,
    this.importer,
    this.ghostex,
    this.models,
    this.onGetModel,
    this.onRemoveModel,
    this.meetings = false,
    this.canNotifyMeetings = false,
    this.onAllowMeetingNotices,
    this.meetingSound = false,
    this.meetingSoundWhy,
    this.tapes,
    this.countingTapes = false,
    this.oldTapes = 0,
    this.onCountTapes,
    this.onRemoveOldAudio,
    this.onSmokeBench,
    this.onPlayScene,
    this.onReset,
    this.onLocate,
    this.cannotLocate,
    this.places,
    this.testReport,
    this.testBuildSource,
    this.testNow,
  });

  /// Whether an account is signed in on this device (core/account/account.ts). The signed-in pages are not ported:
  /// with this true, Account and Organizations say so.
  final bool signedIn;

  /// Signs in, makes an account or recovers one.
  final SettingsWayIn? onWayIn;

  /// The organizations the account is a member of, for Notifications' mutes.
  final List<SettingsOrg> orgs;

  /// Where the library is and the calls that move it (core/libraryFolder.ts): Settings › Library folder. Null is a
  /// build that keeps the notes in its own folder only.
  final LibraryFolder? libraryFolder;

  /// The drives a backup can go to and the backup itself (core/backup.ts): Settings › Backup. Null is a device
  /// backups are not on.
  final Backups? backup;

  /// Everything as one zip, wherever the device's own save asks (core/exportAll.ts): Settings › Export. Null is a
  /// build that does not know how an export leaves: the row is drawn and cannot be pressed.
  final ExportAll? export;

  /// Notes from Obsidian and Evernote, chosen with the device's own picker (lib/importer/importer.dart): Settings ›
  /// Import. Null is a build with no library to import into: the rows are drawn and cannot be pressed.
  final Importer? importer;

  /// Everything as one .ghostex file and one read back (lib/export/ghostex_calls.dart): Settings › Account › Export
  /// everything and Settings › Import › A .ghostex file. Null is a build with no library: the rows cannot be pressed.
  final Ghostex? ghostex;

  /// What models are on this device; null until the model store is here, which reads as none.
  final SettingsModelsState? models;
  final void Function(String id)? onGetModel;
  final void Function(String id)? onRemoveModel;

  /// Whether this build has the meeting service (native generation 20): Recording's Meetings card and Remove.
  final bool meetings;

  /// Whether the phone may say when a meeting is written up.
  final bool canNotifyMeetings;

  /// Asks the phone to allow them; answers false when the phone refuses outright.
  final FutureOr<bool> Function()? onAllowMeetingNotices;

  /// Whether this device's own sound can go into a meeting, and why not when it cannot.
  final bool meetingSound;
  final String? meetingSoundWhy;

  /// How many bytes the tapes whose audio is on this device take (settings/tapes.ts `tapeBytes` of `tapesHere`);
  /// null, with no tape store, reads as none.
  final int? tapes;

  /// Whether the notes have yet to be read, so there is no saying what the tapes take: the card reads "Your tapes
  /// are being counted." until they are (`notes === null`, before the page's `listNotes()` answered).
  final bool countingTapes;

  /// How many of them are older than a month (`oldTapes`).
  final int oldTapes;

  /// Asks each tape's file whether it is on this device, as the Tapes card is put up (tapes/useTape.ts
  /// `headStatus`): one that says it is not, a synced note whose audio stayed where it was made, has left [tapes]
  /// and [oldTapes] once the files have answered.
  final VoidCallback? onCountTapes;

  /// Removes the audio of the old ones, and answers how many went.
  final Future<int> Function()? onRemoveOldAudio;

  /// Developer's benches and resets.
  final VoidCallback? onSmokeBench;
  final void Function(String readings)? onPlayScene;
  final Future<void> Function({required bool models})? onReset;

  /// Asks for a fix once, as tagging is switched on (core/location.ts `locate`).
  final VoidCallback? onLocate;

  /// Why this device cannot tag a note, as the row says it; null when it can.
  final String? cannotLocate;

  /// The places notes keep (lib/core/place_tags.dart): given, the Location card asks for its one fix itself, says
  /// why this device cannot tag, and says a refusal under the card with the way to the phone's settings.
  final PlaceTags? places;

  /// The tests' report built into the app (diag/testReport.ts `REPORT`), as its JSON; null is a build without one.
  final Map<String, Object?>? testReport;

  /// This build's source fingerprint, to check the report against (`BUILD_SOURCE`); null for a development build.
  final String? testBuildSource;

  /// The moment Test results says "8 hr ago" from; now when null. A picture of the page gives its own, so it is the
  /// same picture tomorrow.
  final DateTime? testNow;
}

/// An organization as Notifications lists it to mute.
@immutable
class SettingsOrg {
  const SettingsOrg({required this.id, required this.name, required this.members});
  final String id;
  final String name;
  final int members;
}

/// What the sheet hands every page under it: the way to another page of Settings (`go`, the web's `onOpen`), the
/// workspaces, and the callbacks the web's sheet took as props. A page drawn outside Settings finds none and uses
/// what it was constructed with.
class SettingsHost extends InheritedWidget {
  const SettingsHost({
    super.key,
    required this.go,
    required this.workspaces,
    this.updates,
    this.features = const SettingsFeatures(),
    this.onGuide,
    this.onSample,
    this.onGuideBook,
    this.onBoard,
    this.onCanvas,
    this.onHowCanvas,
    this.onAcademy,
    this.onOrganization,
    this.onOpenLink,
    this.notesInWorkspace,
    this.onTrashNotes,
    required super.child,
  });

  /// Lands on a section, and on a setting there when one is named.
  final void Function(String id, {String? setting}) go;
  final WorkspaceStore workspaces;
  final SettingsUpdates? updates;
  final SettingsFeatures features;
  final VoidCallback? onGuide;
  final VoidCallback? onSample;
  final VoidCallback? onGuideBook;
  final VoidCallback? onBoard;
  final VoidCallback? onCanvas;
  final VoidCallback? onHowCanvas;
  final VoidCallback? onAcademy;
  final void Function(String orgId)? onOrganization;

  /// Opens a link outside the app (core/linkPreview.ts `openLink`).
  final void Function(String url)? onOpenLink;

  /// The ids of the notes a workspace's delete would ask about, and the way to put them in the trash.
  final List<String> Function(String workspaceId)? notesInWorkspace;
  final void Function(List<String> noteIds)? onTrashNotes;

  static SettingsHost? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsHost>();

  // The callbacks are closures the shell makes anew on every build, so there is nothing worth comparing: a page
  // that reads the host is built again whenever the sheet is.
  @override
  bool updateShouldNotify(SettingsHost old) => true;
}

/// The workspaces as the preferences keep them (`Preferences.workspaces`), for a [WorkspaceStore]: the list and the
/// filings travel with the person, as the web's do, and the list's filter is held for this run. It is what Settings
/// uses when no store is handed to it, so its row and its page read one thing.
class PreferencesWorkspaceStorage implements WorkspaceStorage {
  PreferencesWorkspaceStorage(this.store);

  final PreferencesStore store;
  String? _current;

  @override
  WorkspaceSheet read() {
    final kept = store.value.workspaces;
    return WorkspaceSheet(
      list: [for (final w in kept.list) Workspace.kept(id: w.id, name: w.name, hue: w.hue, parent: w.parent)],
      notes: kept.notes,
      current: _current,
    );
  }

  @override
  void write(WorkspaceSheet sheet) {
    _current = sheet.current;
    final next = KeptWorkspaces(
      list: [for (final w in sheet.list) KeptWorkspace(id: w.id, name: w.name, hue: w.hue, parent: w.parent)],
      notes: Map.unmodifiable(sheet.notes),
    );
    if (next != store.value.workspaces) store.update((now) => now.copyWith(workspaces: next));
  }
}

/// A row's target, for a page that sends the person on: `onOpen({ id, setting })`.
SettingsTarget settingsTargetNow(String id, {String? setting}) => SettingsTarget(id, setting: setting, nonce: DateTime.now().microsecondsSinceEpoch);
