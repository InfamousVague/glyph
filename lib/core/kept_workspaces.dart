/// Where the workspaces are kept: [WorkspaceStorage] over the preferences and this device's own key. A port of the
/// storage half of `src/app/core/workspaces.ts` ("Where a workspace lives": `fromPrefs`, `read`, `write`, and the
/// `onPreferences` listener).
///
/// The workspaces themselves, and which note is filed in each, are a preference (`preferences().workspaces`,
/// `{list: [{id, name, hue?}], notes: {note id: workspace id}}`), so they travel with the rest of a person's
/// settings to their other devices. The one thing that stays on the device is which workspace the list is filtered
/// by (`glyph-workspace-current`, a bare id): that is where you are looking, not what you have, and a phone
/// filtered to Home should not filter the desktop too.
///
/// A workspace made on another device arrives as a change to the preferences, so this is a [Listenable]: it tells
/// the [WorkspaceStore] over it to read the sheet again, once, when the kept workspaces change without its doing.
/// A write of its own is not heard back, and any other setting changing leaves the workspaces alone.
///
/// What differs: the web compares what the preferences hold with the sheet it has; here it is compared with what
/// the preferences last held, which is the same thing said from the other side. The set kept under the old
/// `glyph-workspaces` key, from before workspaces travelled, is the web's own history and is not read: this app
/// never kept one.
library;

import 'package:flutter/foundation.dart';

import 'preferences.dart';
import 'stored.dart';
import 'workspaces.dart';

/// The device's own key for the list's filter (`HERE`).
const String currentWorkspaceKey = 'glyph-workspace-current';

/// [WorkspaceStorage] kept in the preferences ([prefs]) and on the device ([stored]): the app's own unless a test
/// hands in others.
class KeptWorkspaceStorage extends ChangeNotifier implements WorkspaceStorage {
  KeptWorkspaceStorage({PreferencesStore? prefs, Stored? stored})
      : _prefs = prefs ?? preferences,
        _stored = stored {
    _seen = _prefs.value.workspaces;
    _prefs.addListener(_heard);
  }

  final PreferencesStore _prefs;
  final Stored? _stored;
  Stored get _device => _stored ?? stored;

  /// The workspaces the preferences held when this last looked.
  late KeptWorkspaces _seen;

  /// A write of our own is on its way through the preferences: not one to hear back (`ours`).
  bool _ours = false;

  void _heard() {
    final held = _prefs.value.workspaces;
    if (_ours) {
      _seen = held;
      return;
    }
    if (held == _seen) return;
    _seen = held;
    notifyListeners();
  }

  @override
  WorkspaceSheet read() {
    final held = _prefs.value.workspaces;
    _seen = held;
    return WorkspaceSheet(
      list: [for (final w in held.list) Workspace.kept(id: w.id, name: w.name, hue: w.hue, parent: w.parent)],
      notes: held.notes,
      // The store drops a filter that names no workspace.
      current: _device.readText(currentWorkspaceKey),
    );
  }

  @override
  void write(WorkspaceSheet sheet) {
    // The workspaces travel; the filter stays here.
    _ours = true;
    try {
      _prefs.update((now) => now.copyWith(
            workspaces: KeptWorkspaces(
              list: List.unmodifiable([for (final w in sheet.list) KeptWorkspace(id: w.id, name: w.name, hue: w.hue, parent: w.parent)]),
              notes: Map.unmodifiable(sheet.notes),
            ),
          ));
    } finally {
      _ours = false;
    }
    // No storage: the change holds for this run.
    final current = sheet.current;
    _device.writeText(currentWorkspaceKey, current == null || current.isEmpty ? null : current);
  }

  @override
  void dispose() {
    _prefs.removeListener(_heard);
    super.dispose();
  }
}
