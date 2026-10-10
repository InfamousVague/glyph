import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../account/ui_state.dart';
import '../core/preferences.dart';
import '../core/workspaces.dart';
import '../perf/frame_log.dart';
import 'kit/settings_icons.dart';
import 'panes/settings_host.dart';
import 'settings_screen.dart';
import 'settings_sections.dart';

export 'panes/settings_host.dart' show SettingsFeatures, SettingsModelsState, SettingsOrg, SettingsRelease, SettingsUpdateAlerts, SettingsUpdates, SettingsWayIn;

/// Whether the hidden pages are unlocked (settings/developerMode.ts, `glyph-developer`): this device's own switch,
/// flipped by seven presses on the version in About and by the switch on Developer.
final DeviceFlag developerMode = DeviceFlag('glyph-developer');

/// Port of `SettingsSheet` (src/app/settings/SettingsSheet.tsx): Settings itself, the sections and their live
/// one-line readings, handed to the screen that lists them ([SettingsScreen]). The sections are the table in
/// settings_sections.dart; this reads the facts they depend on (the preferences, the workspaces, the window, the
/// device) and answers the links into Settings, from outside and from one page to another.
///
/// Put it over the app's screens, under the app's `BackScope`, and give it [open] and [onClose]. [toCheatSheet],
/// [toModel] and [toPage] are asked from outside to open at a page: each is the moment it was asked for, so asking
/// twice opens it twice, and 0 or null is not asked.
///
/// The callbacks are the web sheet's props, and each may be null: the row that would run one is then drawn and
/// cannot be pressed. [onGuide], [onSample], [onGuideBook], [onBoard], [onCanvas], [onHowCanvas] and [onAcademy]
/// are About's Help and the Examples; [onOrganization] opens an organization's own screen.
///
/// What differs from the web original:
/// - [workspaces] is the store the Workspaces page edits and its row counts. The web had one for the whole app;
///   hand it the app's. Left out, Settings keeps one over the preferences' own (`Preferences.workspaces`), which is
///   where the web keeps them. [notesInWorkspace] and [onTrashNotes] are what a workspace's sheet asks of the
///   library: which notes a delete would ask about, and the way to put them in the trash.
/// - [updates] is null until the app has an updater: About then draws the version alone.
/// - [onOpenLink] opens a link outside the app (the web's `openLink`): the privacy policy, the base specifications.
/// - [features] is what the pages ask of features with no Flutter port yet (the account, the models, the recorder,
///   the benches, the resets, the export, the tests' report): see [SettingsFeatures].
/// - [split] is an addition, for a test or a shell that says the window's shape itself.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.open,
    required this.onClose,
    this.toCheatSheet = 0,
    this.toModel = 0,
    this.toPage,
    this.split,
    this.workspaces,
    this.notesInWorkspace,
    this.onTrashNotes,
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
  });

  final bool open;
  final VoidCallback onClose;

  /// Asked from outside to open at the cheat sheet: the Academy's summary sends people there.
  final int toCheatSheet;

  /// Asked from outside to open at the AI section's Model card, lit: the home page's "Get a model".
  final int toModel;

  /// Asked from outside to open at a page, by its id, as a link into Settings does.
  final SettingsTarget? toPage;

  /// Whether to draw the split view; null asks the window.
  final bool? split;

  /// The app's workspaces; Settings' own over the preferences when null.
  final WorkspaceStore? workspaces;

  /// The ids of the notes filed in a workspace that deleting it would ask about (those not already in the trash).
  final List<String> Function(String workspaceId)? notesInWorkspace;

  /// Puts these notes in the trash: a workspace's "Delete, and move the notes to Trash".
  final void Function(List<String> noteIds)? onTrashNotes;

  /// What About says of this build and the ones after it.
  final SettingsUpdates? updates;

  /// What the pages ask of features that are not ported yet.
  final SettingsFeatures features;

  /// Opens the welcome walkthrough on its first page (About › Help).
  final VoidCallback? onGuide;

  /// Makes the sample note, the one with every mark in it, and opens it.
  final VoidCallback? onSample;

  /// Adds Ghost.md: The Guide, once, and opens its index.
  final VoidCallback? onGuideBook;

  /// Adds the example board.
  final VoidCallback? onBoard;

  /// Adds the example canvas.
  final VoidCallback? onCanvas;

  /// Adds the canvas that says how Ghost.md works.
  final VoidCallback? onHowCanvas;

  /// Opens Ghost.md Academy.
  final VoidCallback? onAcademy;

  /// Opens an organization's own screen: the shell closes this sheet first.
  final void Function(String orgId)? onOrganization;

  /// Opens a link outside the app.
  final void Function(String url)? onOpenLink;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  SettingsTarget? _goTo;

  /// Settings' own workspaces, over the preferences, for when the app hands it none.
  WorkspaceStore? _ownSpaces;
  KeptWorkspaces? _kept;

  WorkspaceStore get _spaces => widget.workspaces ?? (_ownSpaces ??= WorkspaceStore(storage: PreferencesWorkspaceStorage(preferences)));

  @override
  void initState() {
    super.initState();
    _links(null);
    _kept = preferences.value.workspaces;
    preferences.addListener(_prefsChanged);
  }

  @override
  void didUpdateWidget(SettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _links(oldWidget);
  }

  @override
  void dispose() {
    preferences.removeListener(_prefsChanged);
    _ownSpaces?.dispose();
    super.dispose();
  }

  /// Another device's settings, or a reset, changed the workspaces under Settings' own store: it reads them again.
  void _prefsChanged() {
    final kept = preferences.value.workspaces;
    if (kept == _kept) return;
    _kept = kept;
    _ownSpaces?.reloadWorkspaces();
  }

  /// Each link once, when it is asked: the sheet comes up on that page rather than on the list of sections.
  void _links(SettingsSheet? was) {
    if (widget.toCheatSheet != 0 && widget.toCheatSheet != was?.toCheatSheet) _goTo = SettingsTarget('cheatsheet', nonce: widget.toCheatSheet);
    if (widget.toModel != 0 && widget.toModel != was?.toModel) _goTo = SettingsTarget('ai', setting: 'Model', nonce: widget.toModel);
    final page = widget.toPage;
    if (page != null && page.nonce != was?.toPage?.nonce) _goTo = SettingsTarget(page.id, setting: page.setting, nonce: page.nonce);
  }

  /// Lands on a section, and on a setting there when one is named (`go`): a row that opens a sub-page, or a word
  /// like "Local only".
  void _go(String id, {String? setting}) => setState(() => _goTo = settingsTargetNow(id, setting: setting));

  @override
  Widget build(BuildContext context) {
    final store = preferences;
    final wide = widget.split ?? settingsSplitFits(context);
    final spaces = _spaces;
    // The account, where the app put one over Settings: its rows and its pages read it, and are told when it changes.
    final services = AccountScope.maybeOf(context);
    return SettingsHost(
      go: _go,
      workspaces: spaces,
      updates: widget.updates,
      features: widget.features,
      onGuide: widget.onGuide,
      onSample: widget.onSample,
      onGuideBook: widget.onGuideBook,
      onBoard: widget.onBoard,
      onCanvas: widget.onCanvas,
      onHowCanvas: widget.onHowCanvas,
      onAcademy: widget.onAcademy,
      onOrganization: widget.onOrganization,
      onOpenLink: widget.onOpenLink,
      notesInWorkspace: widget.notesInWorkspace,
      onTrashNotes: widget.onTrashNotes,
      child: ListenableBuilder(
        listenable: Listenable.merge([store, developerMode, spaces, services?.changes]),
        builder: (context, _) {
          if (ghostPerf) Perf.count(widget.open ? 'settings.sheet.open' : 'settings.sheet.shut');
          // Shut, it draws nothing, and nothing is worked out for it: this is built again at every change of any
          // preference (a tab opened, a note filed, the row of open notes), and each time read every section's
          // line and listed every setting the search can find, the cheat sheet's hundred marks among them.
          if (!widget.open) return SettingsScreen(open: false, onClose: widget.onClose, sections: const <SettingsSection>[], goTo: _goTo, split: widget.split);
          final facts = SettingsFacts(
            prefs: store.value,
            wide: wide,
            haptics: hapticsAvailable(),
            android: defaultTargetPlatform == TargetPlatform.android,
            ios: defaultTargetPlatform == TargetPlatform.iOS,
            developer: developerMode.value,
            workspaces: spaces.value.list.length,
            updates: widget.updates,
            features: widget.features,
            services: services,
            sharedLinks: services != null && services.signedIn && (services.shares?.sharedLinks().isNotEmpty ?? false),
          );
          final sections = [
            for (final spec in settingsSections)
              if (spec.where?.call(facts) ?? true)
                SettingsSection(
                  id: spec.id,
                  label: spec.label,
                  words: spec.words,
                  settings: spec.settings?.call(facts) ?? const [],
                  icon: SettingsIcon(spec.glyph, size: 16),
                  content: spec.pane ?? (context) => SettingsNotPorted(spec: spec),
                  summary: spec.summary?.call(facts),
                  group: spec.group,
                  hue: spec.hue,
                  listed: spec.listed,
                  parent: spec.parent,
                ),
          ];
          return SettingsScreen(open: widget.open, onClose: widget.onClose, sections: sections, goTo: _goTo, split: widget.split);
        },
      ),
    );
  }
}
