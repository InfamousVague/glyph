/// The order a recorder is opened in. A port of `src/app/capture/launch.ts`.
///
/// What differs: nothing.
library;

/// Keep the capture screen unmounted until every deferred delete is durable. Its first effects immediately read
/// memo continuation and command candidates, so mounting first creates a real read-before-delete race.
Future<void> afterPendingDeletes(Future<void> Function() flush, void Function() mount) async {
  await flush();
  mount();
}
