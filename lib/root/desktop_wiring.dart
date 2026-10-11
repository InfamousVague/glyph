/// A desktop's keys and the Mac's menu bar, answered by the root (lib/shell/desktop/desktop_commands.dart says
/// which key is which). Ports the page's own `keydown` listener in App.tsx (docs/DESIGN.md §144 and §210 of
/// ../glyph) and adds the two the Mac's menu names beside them.
///
/// - **New note** (Command-N): a new blank note, as + › Note makes one. Only on a place (home, All notes, a note,
///   an organization), never over a recording or the Academy; and not while a sheet, the palette or Settings is
///   open over the page, whose own keys come first (`isPlace(screen)` and no `[aria-modal="true"]` on the page).
/// - **Sync** (Command-R): "there is no pull to refresh on mac". The same refresh the pull does, then a toast:
///   "Synced", "Still syncing" past five seconds, or why not.
/// - **The palette** and **Settings**, from the menu: the kit's own key opens the first, and the header's cog the
///   second.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../shell/desktop/desktop_commands.dart';

/// How long Command-R waits before it says the sync is still going (§210).
const Duration stillSyncingAfter = Duration(seconds: 5);

/// What a sync left, for Command-R's toast (`syncStatusNow()` on the page): the phase and, for an error, its words.
typedef SyncSaid = ({String phase, String? message});

/// The toast Command-R ends with (App.tsx `refreshByKey`).
String syncToast(SyncSaid now) => switch (now.phase) {
      'error' => now.message ?? 'Could not sync.',
      'syncing' => 'Still syncing',
      _ => 'Synced',
    };

/// Answers the desktop's commands until the function given back is called.
///
/// [onPlace] is whether the screen is a place and [covered] whether something modal is over it. [refresh] is the
/// pull's own (the list read again, and a sync where there is an account); [status] what the sync says after.
VoidCallback wireDesktopCommands({
  required bool Function() onPlace,
  required bool Function() covered,
  required VoidCallback newNote,
  required Future<void> Function() refresh,
  required SyncSaid Function() status,
  required void Function(String message) say,
  required VoidCallback palette,
  required VoidCallback settings,
  DesktopCommands? commands,
  Duration patience = stillSyncingAfter,
}) {
  final set = commands ?? desktopCommands;
  set.covered = covered;
  var syncing = false;
  final stops = [
    set.on(DesktopCommand.newNote, () {
      if (!onPlace() || covered()) return false;
      newNote();
      return true;
    }),
    set.on(DesktopCommand.sync, () {
      // Held down or pressed again while one runs: the one refresh, and one toast.
      if (syncing) return true;
      syncing = true;
      unawaited(() async {
        try {
          await refresh().timeout(patience, onTimeout: () {});
          say(syncToast(status()));
        } catch (failure) {
          say(syncToast((phase: 'error', message: null)));
        } finally {
          syncing = false;
        }
      }());
      return true;
    }),
    set.on(DesktopCommand.palette, () {
      palette();
      return true;
    }),
    set.on(DesktopCommand.settings, () {
      if (covered()) return false;
      settings();
      return true;
    }),
  ];
  return () {
    if (identical(set.covered, covered)) set.covered = null;
    for (final stop in stops) {
      stop();
    }
  };
}
