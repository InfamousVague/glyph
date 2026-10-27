/// Which of the dock's buttons are drawn, and in what order: the dock editor's choice (Settings, Appearance, Dock).
/// Matt, 2026-10-27: "build the dock editor", from docs/ideas/CUSTOMIZATION_AND_SOUNDS.md idea 9: "Choose and order
/// the floating dock's buttons (Claude, search, +, mic, Market, Settings), and which sit on the phone versus the Fold.
/// The dock is now fixed."
///
///     DockLayout   one dock's order and the buttons it hides
///     DockPrefs    the phone's dock, and the wide window's where it has its own
///
/// Kept with the preferences (lib/core/preferences.dart `Preferences.dock`) and synced with them, so a dock chosen on
/// the phone is the dock on the Mac too. Nothing chosen is today's dock exactly: [dockButtonIds]' order, nothing
/// hidden.
///
/// A page's own rings (a note's Find and Add, an organization's Invite, a canvas's Fit) are not the editor's: they
/// keep their places, and only the app's buttons among them are ordered and hidden ([DockLayout.arrange]).
library;

import 'package:flutter/foundation.dart';

/// The app's own buttons, head to foot as the dock has always drawn them (docs/DOCK.md): Claude, Talk to Claude,
/// Search, + (Write a note), Speak, the Market and Settings. Their ids are the rings' (`dock-<id>`), and Claude's and
/// Talk's are the dock's own names for its two seams.
const List<String> dockButtonIds = ['claude', 'talk', 'search', 'add', 'speak', 'market', 'settings'];

/// The buttons the editor will not hide. Settings: on a phone the dock's cog is the one way to Settings that is always
/// in reach, and a dock with every other button switched off still has to lead somewhere to switch them back.
const Set<String> dockKeptIds = {'settings'};

/// The microphones that give way to Talk to Claude: one microphone only (GHST-104; Matt, 2026-10-18: "there should
/// only be one microphone icon"). With Talk hidden in the editor, Speak is the dock's microphone again.
const Set<String> dockSpeakIds = {'speak', 'note-speak'};

/// One dock's choice: its buttons' order, and the ones it hides. An empty [order] is the default order, so a store
/// that chose nothing writes nothing but two empty lists.
@immutable
class DockLayout {
  const DockLayout({this.order = const [], this.hidden = const []});

  /// As stored, made whole: only the app's own ids, each once; anything else is the default.
  factory DockLayout.fromJson(Object? raw) {
    final held = raw is Map ? raw : const <Object?, Object?>{};
    List<String> ids(Object? list) {
      if (list is! List) return const [];
      final seen = <String>{};
      return List.unmodifiable([
        for (final id in list)
          if (id is String && dockButtonIds.contains(id) && seen.add(id)) id,
      ]);
    }

    // A kept button hidden by another build, or by hand, is drawn anyway.
    return DockLayout(order: ids(held['order']), hidden: List.unmodifiable(ids(held['hidden']).where((id) => !dockKeptIds.contains(id))));
  }

  /// The buttons head to foot, by id; empty for [dockButtonIds]' own order.
  final List<String> order;

  /// The buttons not drawn, by id. Never one of [dockKeptIds].
  final List<String> hidden;

  static const DockLayout defaults = DockLayout();

  /// Whether this is the dock as it always was.
  bool get isDefault => listEquals(resolved, dockButtonIds) && hidden.isEmpty;

  /// Every one of the app's buttons, head to foot: [order], with any it does not name (a button a later build added,
  /// or a store from before it) put back after the button it follows by default, so it lands where it always stood.
  List<String> get resolved {
    final out = [for (final id in order) if (dockButtonIds.contains(id)) id];
    for (var i = 0; i < dockButtonIds.length; i += 1) {
      final id = dockButtonIds[i];
      if (out.contains(id)) continue;
      // After the nearest button above it by default that is placed; at the head when none is.
      var at = 0;
      for (var j = i - 1; j >= 0; j -= 1) {
        final before = out.indexOf(dockButtonIds[j]);
        if (before >= 0) {
          at = before + 1;
          break;
        }
      }
      out.insert(at, id);
    }
    return out;
  }

  /// Whether [id] is drawn: an id that is not one of the app's buttons always is.
  bool shows(String id) => dockKeptIds.contains(id) || !hidden.contains(id);

  /// [ids], a page's rings head to foot, as this dock draws them: the app's buttons among them in [resolved]'s order,
  /// in the places those buttons held, less the hidden ones; a page's own rings where they were. Then one microphone:
  /// where Talk to Claude is drawn, Speak (a page of notes') and a note's own mic are not.
  List<String> arrange(List<String> ids) {
    final rank = resolved;
    final ours = [for (final id in ids) if (rank.contains(id)) id]..sort((a, b) => rank.indexOf(a).compareTo(rank.indexOf(b)));
    var next = 0;
    final out = <String>[];
    for (final id in ids) {
      if (!rank.contains(id)) {
        out.add(id);
        continue;
      }
      final mine = ours[next];
      next += 1;
      if (shows(mine)) out.add(mine);
    }
    if (out.contains('talk')) out.removeWhere(dockSpeakIds.contains);
    return out;
  }

  /// [id] moved to [to] in [resolved].
  DockLayout moved(String id, int to) {
    final now = [...resolved];
    if (!now.remove(id)) return this;
    now.insert(to.clamp(0, now.length), id);
    return DockLayout(order: List.unmodifiable(now), hidden: hidden);
  }

  /// [id] shown or hidden. A kept button stays shown.
  DockLayout showing(String id, bool shown) {
    if (dockKeptIds.contains(id) || !dockButtonIds.contains(id)) return this;
    final next = [for (final h in hidden) if (h != id) h];
    if (!shown) next.add(id);
    return DockLayout(order: order, hidden: List.unmodifiable(next));
  }

  Map<String, Object?> toJson() => {'order': order, 'hidden': hidden};

  @override
  bool operator ==(Object other) => other is DockLayout && listEquals(resolved, other.resolved) && setEquals(hidden.toSet(), other.hidden.toSet());

  @override
  int get hashCode => Object.hash(Object.hashAll(resolved), Object.hashAllUnordered(hidden));

  @override
  String toString() => 'DockLayout(${resolved.join(' ')}${hidden.isEmpty ? '' : ' less ${hidden.join(' ')}'})';
}

/// The dock on a phone, and on a wide window (the Fold opened, a tablet, a desktop) where it has its own. The idea
/// asked for "which sit on the phone versus the Fold": until a wide dock is chosen, [wide] is null and a wide window
/// draws the phone's.
@immutable
class DockPrefs {
  const DockPrefs({this.phone = DockLayout.defaults, this.wide});

  /// As stored, made whole (`{"order": [...], "hidden": [...], "wide": {...}}`): the phone's dock is the object's own
  /// two lists, so a store that only ever had one dock reads the same.
  factory DockPrefs.fromJson(Object? raw) {
    final held = raw is Map ? raw : const <Object?, Object?>{};
    final wide = held['wide'];
    return DockPrefs(phone: DockLayout.fromJson(held), wide: wide is Map ? DockLayout.fromJson(wide) : null);
  }

  final DockLayout phone;

  /// The wide window's own dock; null where it draws the phone's.
  final DockLayout? wide;

  static const DockPrefs defaults = DockPrefs();

  /// The dock a window draws: [wide] for a wide one, where there is one.
  DockLayout layoutFor({required bool wide}) => wide ? (this.wide ?? phone) : phone;

  DockPrefs withPhone(DockLayout phone) => DockPrefs(phone: phone, wide: wide);

  DockPrefs withWide(DockLayout? wide) => DockPrefs(phone: phone, wide: wide);

  Map<String, Object?> toJson() => {...phone.toJson(), if (wide != null) 'wide': wide!.toJson()};

  @override
  bool operator ==(Object other) => other is DockPrefs && other.phone == phone && other.wide == wide;

  @override
  int get hashCode => Object.hash(phone, wide);
}
