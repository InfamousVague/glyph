/// The way the app asks its Rust core for anything: a command by the name the web app's `invoke` used, its arguments
/// as the JSON object the page sent (camelCase keys), and the answer as decoded JSON. docs/STAGE3.md lists the
/// commands. The real one crosses FFI on a worker isolate (ghost_core.dart); a test hands in a fake.
library;

/// Asks the core. Completes with the decoded `ok` value, or throws [CoreError] with the core's own sentence.
typedef CoreInvoke = Future<Object?> Function(String command, [Map<String, Object?> args]);

/// The core said no: the sentence a Tauri command's `Err(String)` carried.
class CoreError implements Exception {
  const CoreError(this.message);
  final String message;

  @override
  String toString() => message;
}
