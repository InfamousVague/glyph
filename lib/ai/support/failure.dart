/// A caught thing, as words a person can read. A port of `src/app/core/failure.ts`.
///
/// `catch` hands over anything. The page answered an Error's message, and the thing itself as text otherwise (a Tauri
/// command rejects with the string Rust returned).
///
/// What differs: Dart has no one Error with a message. A thing with a `message` that is text answers it (`StateError`,
/// `FormatException`, the library's `CoreError`, [AiFailure] in ai/backend.dart); an `Exception('words')`, whose text
/// Dart prefixes with its class, answers the words; anything else answers its own text. Kept under lib/ai until
/// lib/core has a failure.dart of its own, which this should become.
library;

final RegExp _exceptionLead = RegExp(r'^Exception: ');

/// [failure]'s message when it has one, and [failure] as text when it has not (`failureText`).
String failureText(Object? failure) {
  if (failure is String) return failure;
  if (failure == null) return 'null';
  try {
    final message = (failure as dynamic).message;
    if (message is String) return message;
  } catch (_) {
    // No message to read: its own text below.
  }
  return failure.toString().replaceFirst(_exceptionLead, '');
}
