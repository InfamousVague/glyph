/// The one 404 that is not an answer (docs/TEAMS.md, "Not yet"). A port of `src/app/core/account/notYet.ts`.
///
/// What differs: the page reads `status` and `body` off whatever was thrown, so its own `ApiError` and the MCP
/// server's error both ask it; Dart has no such reading of a stranger's fields, so anything that wants to be asked
/// says so by being a [Refusal], which [ApiError] (api.dart) is.
library;

/// What the service answers for a route it does not have (server/src/main.rs): the one 404 that is not an answer
/// (`NO_SUCH_ROUTE`).
const String noSuchRoute = 'no such route';

/// Something thrown that carries a refusal: the status the service answered, and the body it answered with.
abstract interface class Refusal {
  int get status;
  Object? get body;
}

/// The service's words in a refusal's body, `{ error }`, or null where the body is not one (`wordsOf`).
String? wordsOf(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  return error is String ? error : null;
}

/// Whether a refusal means the service does not have the route yet (`notYet`): the organizations and notifications
/// routes ship on the service first, and against an older service the app must stay quiet rather than show a
/// failure. Not yet is a 404 whose body is the service's `{ error: 'no such route' }`, or no service body at all (a
/// proxy's 404). Every other 404 is an answer in the service's words - "No one has that handle.", "You were not
/// invited." - and is shown as one.
bool notYet(Object? failure) {
  if (failure is! Refusal || failure.status != 404) return false;
  final words = wordsOf(failure.body);
  return words == null || words == noSuchRoute;
}
