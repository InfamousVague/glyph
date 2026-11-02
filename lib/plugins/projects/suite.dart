/// The project tools as one suite, and the one question every feature of theirs asks: is it on here (docs/PM_PLUGINS.md;
/// Matt, 2026-11-01: "Right now I think we have too many features by default, I'd like you to move the project
/// managment stuff like gantts and stuff into a suite of plugins that are disabled by default but when starting an org
/// it asks you which of the org based plugins you'd like to enable for gantts project managment and more").
///
/// **Where a switch is.** An organization's are its `orgs/<Org>/Home.md`'s `plugins:` (lib/core/page_tree.dart
/// `TeamspaceSettings.plugins`), so the team shares them and they are in the files. The person's own are the plugin
/// registry's switches (registry.dart, `glyph-plugins`), synced between their devices (lib/sync/connections.dart
/// `syncedSwitches`). A note in an organization's space asks its organization's; a personal note, the person's.
///
/// **The question.** [projectPluginOn] (`projectSuite.on`), with a note (its space decides), an organization, or neither
/// (the person's own). [ProjectSuite.anywhere] is on for the person or any organization of theirs: what the app-wide
/// rows ask (My tickets, Triage, the digest, the palette). The suite is a [Listenable] that tells its listeners when
/// any answer may have changed: a switch moved on this device or another, a team's home page written.
///
/// **Nothing names a note here.** The root hands the suite how to find a note's organization, an organization's list
/// and name, and how to write one ([ProjectSuite.new]); without them, as in a test that builds a screen alone, every
/// note is personal and only the registry answers.
///
/// The features are the app's own, not the plugins': the registry's extension points have no fence, palette row,
/// sidebar row or query view, so the tools add nothing through them and each feature asks here where it is drawn
/// (docs/PM_PLUGINS.md §5 lists every gate).
library;

import 'package:flutter/foundation.dart';

import '../../core/project_tools.dart';
import '../../core/stored.dart';
import '../automations/automations.dart' show automationsPlugin;
import '../boards/boards.dart' show boardsPlugin;
import '../forms/forms.dart' show formsPlugin;
import '../gantt/gantt.dart' show ganttPlugin;
import '../more/more_tools.dart' show isMoreTool, moreToolShortName;
import '../planning/planning.dart' show planningPlugin;
import '../registry.dart' show Registry, plugins;
import '../tickets/tickets.dart' show ticketsPlugin;
import '../time_tracking/time_tracking.dart' show timeTrackingPlugin;
import '../types.dart';

export '../../core/project_tools.dart';

/// The suite's plugins, in its order (project_tools.dart [projectTools]).
const List<GlyphPlugin> projectPlugins = [ticketsPlugin, planningPlugin, ganttPlugin, boardsPlugin, automationsPlugin, timeTrackingPlugin, formsPlugin];

/// One tool's plugin by its id; null for an id that is no tool's.
GlyphPlugin? projectPlugin(String id) {
  for (final plugin in projectPlugins) {
    if (plugin.manifest.id == id) return plugin;
  }
  return null;
}

/// A tool's name as a chip says it: "Gantt and timelines" is "Gantt". One of the more tools by its own short name
/// (lib/plugins/more/more_tools.dart), whose chips are these.
String toolShortName(String id) => switch (id) {
      ganttTool => 'Gantt',
      _ when isMoreTool(id) => moreToolShortName(id),
      _ => projectPlugin(id)?.manifest.name ?? id,
    };

/// Where this device keeps the banners put away (docs/PM_PLUGINS.md §6): organization to the tools it named.
const String toolBannersKey = 'glyph-tool-banners';

/// The suite's switches and their scope (see the library's doc).
class ProjectSuite extends ChangeNotifier {
  ProjectSuite({
    Registry Function()? registry,
    this.orgOfNote,
    this.listOf,
    this.orgIds,
    this.orgName,
    this.usedIn,
    this.writeOrg,
    Stored? stored,
  })  : _registry = registry ?? (() => plugins),
        _stored = stored;

  /// Every answer on, wherever it is asked: what the tests that test the features build their worlds with
  /// (test/flutter_test_config.dart sets it for every test; a test of the off state sets it back to false).
  static bool debugAllOn = false;

  final Registry Function() _registry;

  /// The organization a note is in, by its id: its workspace's, else the one its path is under; null for a personal
  /// note.
  final String? Function(String noteId)? orgOfNote;

  /// The tools an organization's home page lists (`TeamspaceSettings.plugins`); null for an organization this device
  /// knows nothing of yet, which is none on.
  final Set<String>? Function(String orgId)? listOf;

  /// The organizations of this device's account, for [anywhere].
  final Iterable<String> Function()? orgIds;

  /// An organization's name, for a chip's and a banner's words.
  final String? Function(String orgId)? orgName;

  /// The tools an organization's notes use (`NoteFacts.tools` of each), for its banner.
  final Set<String> Function(String orgId)? usedIn;

  /// Writes an organization's list: its home page's `plugins:`, the page made where there is none. Answers whether it
  /// was written.
  final Future<bool> Function(String orgId, Set<String> tools)? writeOrg;

  final Stored? _stored;

  final Map<String, Set<String>> _lists = {};
  Set<String>? _personal;
  Object? _said;
  Registry? _heard;

  // ---- the answers ---------------------------------------------------------------------------------------------------

  /// The person's own tools on: the registry's switches, a dependent only with Tickets.
  Set<String> get personal => _personal ??= () {
        final registry = _registry();
        return toolsOn([
          for (final id in projectTools)
            if (registry.byId(id) != null && registry.isEnabled(id)) id,
        ]);
      }();

  /// An organization's tools on.
  Set<String> orgList(String orgId) => _lists[orgId] ??= toolsOn(listOf?.call(orgId) ?? const {});

  /// The organization [noteId] is in, or [orgId] where it is said; null for the person's own space.
  String? orgFor({String? noteId, String? orgId}) => orgId ?? (noteId == null ? null : orgOfNote?.call(noteId));

  /// The tools on where [noteId] is, or in [orgId], or the person's own with neither.
  Set<String> onIn({String? noteId, String? orgId}) {
    if (debugAllOn) return projectTools.toSet();
    final org = orgFor(noteId: noteId, orgId: orgId);
    return org == null ? personal : orgList(org);
  }

  /// Whether tool [id] is on where [noteId] is, or in [orgId], or for the person with neither.
  bool on(String id, {String? noteId, String? orgId}) => onIn(noteId: noteId, orgId: orgId).contains(id);

  /// Whether tool [id] is on for the person or in any organization of theirs.
  bool anywhere(String id) {
    if (debugAllOn || personal.contains(id)) return true;
    for (final org in orgIds?.call() ?? const <String>[]) {
      if (orgList(org).contains(id)) return true;
    }
    return false;
  }

  /// The words a chip and a banner say for where a tool would be turned on: "for HelloTrade", or nothing for the
  /// person's own.
  String whereWords({String? noteId, String? orgId}) {
    final org = orgFor(noteId: noteId, orgId: orgId);
    if (org == null) return '';
    final name = orgName?.call(org)?.trim() ?? '';
    return name.isEmpty ? ' for the team' : ' for $name';
  }

  /// Whether a tool can be turned on from a chip where [noteId] is: always for the person's own; for an organization,
  /// where the root can write its home page.
  bool canTurnOn({String? noteId, String? orgId}) => orgFor(noteId: noteId, orgId: orgId) == null || writeOrg != null;

  // ---- moving the switches -------------------------------------------------------------------------------------------

  /// Turns [ids] on, with what they need, where [noteId] is or in [orgId] (the person's own with neither).
  Future<void> turnOn(Iterable<String> ids, {String? noteId, String? orgId}) async {
    final org = orgFor(noteId: noteId, orgId: orgId);
    final now = org == null ? personal : orgList(org);
    await setTools({...now, ...ids}, orgId: org);
  }

  /// Turns [id] off where [noteId] is or in [orgId]; Tickets takes the tools that need it with it (the caller warned).
  Future<void> turnOff(String id, {String? noteId, String? orgId}) async {
    final org = orgFor(noteId: noteId, orgId: orgId);
    final now = {...(org == null ? personal : orgList(org))}..remove(id);
    if (id == ticketsTool) now.removeAll(needTickets);
    await setTools(now, orgId: org);
  }

  /// Sets the tools on to exactly [tools] and what they need: an organization's home page, or the person's switches.
  Future<void> setTools(Set<String> tools, {String? orgId}) async {
    final next = withNeeds(tools).toSet();
    if (orgId == null) {
      final registry = _registry();
      for (final id in projectTools) {
        if (registry.byId(id) != null) registry.setEnabled(id, next.contains(id));
      }
      changed();
      return;
    }
    final write = writeOrg;
    if (write == null) return;
    if (await write(orgId, next)) {
      _lists[orgId] = toolsOn(next);
      changed(force: true);
    }
  }

  // ---- the banner --------------------------------------------------------------------------------------------------

  /// The tools an organization's notes use that its list does not have, in the suite's order: what its banner asks
  /// for (docs/PM_PLUGINS.md §6). A tool that needs Tickets brings Tickets with it.
  List<String> missingIn(String orgId) {
    if (debugAllOn) return const [];
    final used = usedIn?.call(orgId) ?? const <String>{};
    if (used.isEmpty) return const [];
    final on = orgList(orgId);
    return [for (final id in withNeeds(used)) if (!on.contains(id)) id];
  }

  /// The tools [used] (a note's own) that are off where [noteId] is, in the suite's order, with Tickets where they
  /// need it.
  List<String> missingFor(String noteId, Set<String> used) {
    if (debugAllOn || used.isEmpty) return const [];
    final on = onIn(noteId: noteId);
    return [for (final id in withNeeds(used)) if (!on.contains(id)) id];
  }

  static String _bannerKey(Iterable<String> tools) => (tools.toList()..sort()).join(',');

  Map<String, String> _banners() => (_stored ?? stored).read<Map<String, String>>(toolBannersKey, const {}, (raw) => raw is Map ? {for (final MapEntry(:key, :value) in raw.entries) if (key is String && value is String) key: value} : const {});

  /// Whether this device put away the banner asking for [tools] in [orgId]: put away for that list, so a tool newly
  /// missing asks again.
  bool bannerPutAway(String orgId, Iterable<String> tools) => _banners()[orgId] == _bannerKey(tools);

  /// Puts away, on this device, the banner asking for [tools] in [orgId].
  void putAwayBanner(String orgId, Iterable<String> tools) {
    (_stored ?? stored).write(toolBannersKey, {..._banners(), orgId: _bannerKey(tools)});
    notifyListeners();
  }

  // ---- hearing -------------------------------------------------------------------------------------------------------

  /// Reads the switches again, and tells the listeners where any answer may differ: the root asks it as the library
  /// and the workspaces change, and the registry's switches are heard by themselves.
  void changed({bool force = false}) {
    if (hasListeners) _hearRegistry();
    _lists.clear();
    _personal = null;
    final said = _signature();
    if (!force && said == _said) return;
    _said = said;
    notifyListeners();
  }

  String _signature() {
    final parts = <String>[personal.join(',')];
    for (final org in orgIds?.call() ?? const <String>[]) {
      parts.add('$org=${orgList(org).join(',')}');
    }
    return parts.join(';');
  }

  void _registryMoved() => changed();

  void _hearRegistry() {
    final now = _registry();
    if (identical(now, _heard)) return;
    _heard?.removeListener(_registryMoved);
    _heard = now..addListener(_registryMoved);
  }

  @override
  void addListener(VoidCallback listener) {
    _hearRegistry();
    _said ??= _signature();
    super.addListener(listener);
  }

  @override
  void dispose() {
    _heard?.removeListener(_registryMoved);
    super.dispose();
  }
}

ProjectSuite _suite = ProjectSuite();

/// The app's suite: the root's once it is up (lib/root/ghost_root.dart), else one that answers from the registry
/// alone.
ProjectSuite get projectSuite => _suite;

/// Makes [suite] the app's.
void useProjectSuite(ProjectSuite suite) => _suite = suite;

/// Whether project tool [id] is on where [noteId] is, or in [orgId], or for the person with neither
/// ([ProjectSuite.on]).
bool projectPluginOn(String id, {String? noteId, String? orgId}) => _suite.on(id, noteId: noteId, orgId: orgId);
