/// A value read from a module's own state, as something a screen can listen to: what `useSyncExternalStore` was to
/// the page's hooks (`useRun`, `useAnyRunning`, `useRunLog`).
///
/// A hook subscribed while its component was mounted and read the snapshot again on every tick of the store, drawing
/// only when the snapshot was a different value. This is the same with Flutter's own shape: a [ValueListenable]
/// whose [value] is always read live, which subscribes to the store while anything listens to it and stops when
/// nothing does, and which tells its listeners only when what it reads has changed. Nothing to dispose: with no
/// listener it holds nothing.
///
/// What differs: there is no web file for this; it is the three hooks' common half. Kept under lib/ai/support until
/// lib/core has a channel of its own for module state.
library;

import 'package:flutter/foundation.dart';

/// [read] as a listenable, following the store [subscribe] attaches to.
class Watched<T> extends ChangeNotifier implements ValueListenable<T> {
  Watched(this._read, this._subscribe);

  final T Function() _read;

  /// Attaches a listener to the store; answers the way to stop.
  final VoidCallback Function(VoidCallback listener) _subscribe;

  VoidCallback? _stop;
  T? _last;

  /// The value now, read from the store itself and never a copy that could be stale.
  @override
  T get value => _read();

  void _changed() {
    final now = _read();
    if (identical(now, _last) || now == _last) return;
    _last = now;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _last = _read();
      _stop = _subscribe(_changed);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _stop?.call();
      _stop = null;
      _last = null;
    }
  }
}
