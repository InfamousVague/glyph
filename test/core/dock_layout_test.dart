import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/sync/prefs.dart' show pickSynced, syncedPrefs;

/// The dock editor's choice as it is kept (lib/core/dock_layout.dart): nothing chosen is today's dock, a choice
/// survives a store and a sync, and Settings is never hidden. Matt, 2026-10-27: "build the dock editor".
void main() {
  /// Every button a page of notes can be handed, head to foot, as the root hands them.
  const all = ['claude', 'talk', 'search', 'add', 'speak', 'market', 'settings'];

  group('the dock as it was', () {
    test('is the default: the order the dock has always had, nothing hidden', () {
      expect(Preferences.defaults.dock, DockPrefs.defaults);
      expect(DockLayout.defaults.resolved, ['claude', 'talk', 'search', 'add', 'speak', 'market', 'settings']);
      expect(DockLayout.defaults.isDefault, isTrue);
      // One microphone, as before: Talk where it is given, Speak where it is not.
      expect(DockLayout.defaults.arrange(all), ['claude', 'talk', 'search', 'add', 'market', 'settings']);
      expect(DockLayout.defaults.arrange(['search', 'add', 'speak', 'settings']), ['search', 'add', 'speak', 'settings']);
    });

    test('reads a store that never had a dock, or a broken one, as the default', () {
      expect(Preferences.fromJson(<String, Object?>{}).dock, DockPrefs.defaults);
      expect(Preferences.fromJson({'dock': 'yes'}).dock, DockPrefs.defaults);
      expect(Preferences.fromJson({'dock': {'order': 4, 'hidden': null, 'wide': 'no'}}).dock, DockPrefs.defaults);
      expect(Preferences.defaults.toJson()['dock'], {'order': <String>[], 'hidden': <String>[]});
    });
  });

  group('a dock chosen', () {
    final chosen = DockPrefs(
      phone: DockLayout.defaults.moved('settings', 0).showing('market', false),
      wide: DockLayout.defaults.showing('claude', false),
    );

    test('round-trips through the stored JSON', () {
      final kept = Preferences.defaults.copyWith(dock: chosen);
      final read = Preferences.fromJson(jsonDecode(jsonEncode(kept.toJson())));
      expect(read.dock, chosen);
      expect(read.dock.phone.resolved.first, 'settings');
      expect(read.dock.phone.hidden, ['market']);
      expect(read.dock.wide!.hidden, ['claude']);
      expect(read, kept);
    });

    test('travels with the rest of the settings', () {
      expect(syncedPrefs, contains('dock'));
      expect(pickSynced(Preferences.defaults.copyWith(dock: chosen).toJson()), containsPair('dock', chosen.toJson()));
    });

    test('a wide window draws its own dock where there is one, and the phone’s where there is not', () {
      expect(chosen.layoutFor(wide: true), chosen.wide);
      expect(chosen.layoutFor(wide: false), chosen.phone);
      expect(chosen.withWide(null).layoutFor(wide: true), chosen.phone);
    });

    test('orders the app’s buttons and leaves a page’s own rings where they were', () {
      final layout = DockLayout.defaults.moved('talk', 0).moved('claude', 6);
      expect(layout.arrange(all), ['talk', 'search', 'add', 'market', 'settings', 'claude']);
      // A note's dock: Claude and Talk swap in their two places, the note's rings stay, less its mic under Talk.
      expect(layout.arrange(['claude', 'talk', 'note-find', 'note-speak', 'note-add', 'note-options']), ['talk', 'claude', 'note-find', 'note-add', 'note-options']);
    });

    test('with Talk hidden, Speak is the dock’s microphone again, a page of notes’ and a note’s', () {
      final layout = DockLayout.defaults.showing('talk', false);
      expect(layout.arrange(all), ['claude', 'search', 'add', 'speak', 'market', 'settings']);
      expect(layout.arrange(['claude', 'talk', 'note-find', 'note-speak', 'note-options']), ['claude', 'note-find', 'note-speak', 'note-options']);
    });

    test('a button from a later build, or one the store left out, lands after the one it follows by default', () {
      final read = DockLayout.fromJson({
        'order': ['settings', 'add', 'claude', 'nonsense', 'add'],
        'hidden': ['nonsense'],
      });
      expect(read.order, ['settings', 'add', 'claude']);
      expect(read.hidden, isEmpty);
      // Talk after Claude and Search after Talk; Speak after +, and the Market after Speak.
      expect(read.resolved, ['settings', 'add', 'speak', 'market', 'claude', 'talk', 'search']);
    });
  });

  group('Settings', () {
    test('cannot be hidden: the switch is refused, and a store that hid it shows it', () {
      expect(DockLayout.defaults.showing('settings', false), DockLayout.defaults);
      final read = DockLayout.fromJson({
        'hidden': ['settings', 'search'],
      });
      expect(read.hidden, ['search']);
      expect(read.shows('settings'), isTrue);
      final everything = dockButtonIds.fold(DockLayout.defaults, (layout, id) => layout.showing(id, false));
      expect(everything.arrange(all), ['settings']);
    });
  });
}
