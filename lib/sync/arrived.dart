/// The rows a pass of the feed brought, told to whoever asked to hear. A port of
/// `src/app/core/notifications/arrived.ts`.
///
/// The seam that lets something outside the core act on new news without the core naming it: on the web the Slack
/// plugin is the first, and an organization's news can go to a channel the person chose for it.
///
/// Told after every look at the feed (the sync engine's doing, when there is one), beside the phone's own
/// notifications, with the same two things: `before`, the cursor the pass began at, and the rows as this device
/// now keeps them. Which rows are new is the listener's to decide, by the same rule the phone uses: a row above
/// `before`, and nothing at all from a device's first look (`before` of 0), which would be its whole history. A
/// listener that throws or fails is its own trouble; the pass goes on.
library;

import 'dart:async';

import '../core/notifications.dart';

/// Hears a pass's rows (`ArrivedListener`).
typedef ArrivedListener = FutureOr<void> Function(int before, List<FeedNotification> rows);

final Set<ArrivedListener> _listeners = {};

/// Hears every pass's rows from now on; answers the way to stop (`onArrived`).
void Function() onArrived(ArrivedListener listener) {
  _listeners.add(listener);
  return () => _listeners.remove(listener);
}

/// A pass of the feed is done: every listener is told, and none can stop the others or the pass (`tellArrived`).
void tellArrived(int before, List<FeedNotification> rows) {
  for (final listener in _listeners.toList()) {
    try {
      final told = listener(before, rows);
      if (told is Future<void>) unawaited(told.catchError((Object _) {}));
    } catch (_) {
      // A listener's failure is its own; the next one is still told.
    }
  }
}
