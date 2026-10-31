/// Notion, from the app: signing in, the boards a note can send its list to, and the tasks on them. A port of
/// `src/app/plugins/notion/client.ts` and, since nothing here has an origin to be refused by, of the Rust that
/// asked on the page's behalf (`src-tauri/src/notion.rs`).
///
/// Matt: link Notion boards so list items become Notion tasks, by swiping an item or a whole list at once.
///
/// - Signing in is "Sign in with Notion" through glyph-api (server/src/notion.rs): this makes a random state and
///   verifier, opens the browser at `start` with the verifier's SHA-256, and collects the tokens from `claim` when
///   the person comes back. Nothing comes back by a link: the app is brought to the front by hand, and asks.
/// - The tokens are kept in the device's secure store ([accountSecret]) and nowhere else. What the rest of the app
///   may know of them is [NotionAccount]: whether there is a sign-in, and what its workspace is called.
/// - Every Notion call is [notionRequest], with the token, to one of the routes Ghost.md uses ([allowedPath]). A
///   401 is answered by refreshing through glyph-api once and asking again.
/// - Which board a note sends to is a fact about this phone: the plugin's storage, `glyph-notion-links`, cleared by
///   a reset.
///
/// All of it through the plugin's host (lib/plugins/host.dart), so the two hosts, the one secret and the keys in the
/// manifest are all it can reach.
///
/// What differs:
/// - `notion_save_account`, `notion_account`, `notion_disconnect` and `notion_request` are [saveNotionAccount],
///   [notionAccount], [disconnectNotion] and [notionRequest]: Dart over `host.fetch` and `host.secrets`, with the
///   Rust's refusals in the Rust's words.
/// - A refresh goes to `$notionApi/refresh`, on ghostmarkdown.com, where the Rust still named the service's older
///   address (`attack.fm/glyph/api/notion/refresh`): the manifest lists ghostmarkdown.com alone, and the host
///   refuses any other.
/// - `isTauri()` has no counterpart: this is always the app. [notionAvailable] is the host's answer alone.
/// - `useNotionAccount` is [NotionAccountWatch], a [ChangeNotifier] a page makes and disposes; "the page became
///   visible" is the app coming back to the front (`AppLifecycleState.resumed`).
/// - What `collectNotionSignIn` answered as an account, `'pending'` or null is [NotionCollected].
/// - The module's state (the sign-in in flight, the last answer of [notionAvailable]) is kept for the app's life as
///   the page kept it for the page's; [resetNotionClient] is the tests' `vi.resetModules()`.
/// - [notionNow] is the clock, so a test moves time.
/// - A title cut to Notion's 2000 characters is never cut through the middle of one (the page's `slice` could
///   leave half a pair, which cannot be sent as UTF-8 from here).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../account/api.dart' show FetchRequest, FetchResponse;
import '../../core/bytes.dart' show toBase64Url;
import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/iphone_app.dart' show notOnIPhone;
import '../details_cache.dart' show failureWords;
import '../host.dart' show PluginPermissionError, pluginNotes;
import 'manifest.dart';
import 'sha256.dart';

// The API lives at /api (the /glyph/api base still works through the server's compat strip); core/account/api.ts.
String _api = 'https://ghostmarkdown.com/api/notion';

/// Where glyph-api's Notion routes are: `start`, `claim`, `refresh`.
String get notionApi => _api;

const String _notionApi = 'https://api.notion.com/v1/';

/// The version of Notion's API every call names (notion.rs `NOTION_VERSION`).
const String notionVersion = '2022-06-28';
const String _linksKey = 'glyph-notion-links';
const String _signInKey = 'glyph-notion-signin';

/// How long a call to Notion may take (notion.rs: a 30 second client).
const Duration _patience = Duration(seconds: 30);

/// The time, in milliseconds. A test's own, to move it.
int Function() notionNow = _clock;
int _clock() => DateTime.now().millisecondsSinceEpoch;

/// Something Notion, the service or this app said about a call that did not work, as the sentence a person reads.
class NotionFailure implements Exception {
  const NotionFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---- availability ----------------------------------------------------------------------------------------------

/// Whether this build can talk to Notion at all.
Future<bool> notionAvailable() async => _ready = await host.nativeReady();

bool _ready = false;
bool _asked = false;

/// The last answer of [notionAvailable], for code that cannot wait (a swipe deciding whether it counts). The page
/// asked as its module loaded; here the first of these asks (notion.dart asks as the plugin is made, which is at
/// launch), and what draws from the plugin is told when the answer is yes.
bool notionReadyNow() {
  if (!_asked) {
    _asked = true;
    unawaited(notionAvailable());
  }
  return _ready;
}

// ---- the account -----------------------------------------------------------------------------------------------

/// What the app may know of the sign-in (`NotionAccount`; notion.rs `AccountInfo`).
@immutable
class NotionAccount {
  const NotionAccount({required this.connected, this.workspaceName, this.workspaceIcon});

  static const NotionAccount signedOut = NotionAccount(connected: false);

  final bool connected;
  final String? workspaceName;
  final String? workspaceIcon;

  @override
  bool operator ==(Object other) => other is NotionAccount && other.connected == connected && other.workspaceName == workspaceName && other.workspaceIcon == workspaceIcon;

  @override
  int get hashCode => Object.hash(connected, workspaceName, workspaceIcon);

  @override
  String toString() => 'NotionAccount(connected: $connected, workspaceName: $workspaceName, workspaceIcon: $workspaceIcon)';
}

/// What sign-in gave back, as glyph-api's claim spells it (notion.rs `Account`). Private: the tokens leave this
/// file only in a request's `Authorization`.
class _Kept {
  const _Kept({required this.accessToken, this.refreshToken, this.botId, this.workspaceId, this.workspaceName, this.workspaceIcon});

  final String accessToken;
  final String? refreshToken;
  final String? botId;
  final String? workspaceId;
  final String? workspaceName;
  final String? workspaceIcon;

  /// The account in [raw], or null - signed out - for anything that holds no token to call Notion with.
  static _Kept? from(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['accessToken'];
    if (token is! String || token.isEmpty) return null;
    String? text(String name) => raw[name] is String ? raw[name] as String : null;
    return _Kept(accessToken: token, refreshToken: text('refreshToken'), botId: text('botId'), workspaceId: text('workspaceId'), workspaceName: text('workspaceName'), workspaceIcon: text('workspaceIcon'));
  }

  static _Kept? parse(String? text) {
    if (text == null) return null;
    try {
      return from(jsonDecode(text));
    } catch (_) {
      // Half a file is no account.
      return null;
    }
  }

  String get json => jsonEncode({'accessToken': accessToken, 'refreshToken': refreshToken, 'botId': botId, 'workspaceId': workspaceId, 'workspaceName': workspaceName, 'workspaceIcon': workspaceIcon});

  NotionAccount get info => NotionAccount(connected: true, workspaceName: workspaceName, workspaceIcon: workspaceIcon);
}

/// Keeps a claim's answer as the account (`notion_save_account`), and says what the app may know of it.
Future<NotionAccount> saveNotionAccount(Object? claim) async {
  final account = _Kept.from(claim);
  if (account == null) throw const NotionFailure("Notion didn't give Glyph an access token.");
  await host.secrets.write(accountSecret, account.json);
  return account.info;
}

/// The account (`notion_account`): signed out where there is none, or none that can be read.
Future<NotionAccount> notionAccount() async {
  if (!await notionAvailable()) return NotionAccount.signedOut;
  try {
    return _Kept.parse(await host.secrets.read(accountSecret))?.info ?? NotionAccount.signedOut;
  } catch (_) {
    return NotionAccount.signedOut;
  }
}

/// The account as the secure store was last seen to hold it, with no wait: signed out until the host's secrets
/// have been warmed (`host.secrets.warm()`, asked by the app's root at launch) or the account has been read once.
NotionAccount notionAccountNow() => _Kept.parse(host.secrets.held(accountSecret))?.info ?? NotionAccount.signedOut;

final Random _random = Random.secure();

String _randomToken() => toBase64Url(Uint8List.fromList([for (var i = 0; i < 32; i++) _random.nextInt(256)]));

/// The challenge the server recomputes from the verifier: its SHA-256, base64url without padding.
String challengeOf(String verifier) => toBase64Url(sha256(utf8.encode(verifier)));

typedef _Flight = ({String state, String verifier, int at});

/// Starts "Sign in with Notion": the browser opens at Notion's consent page. The state and verifier are remembered
/// so the sign-in can be collected after Ghost.md comes back to the front, even if the app was closed meanwhile.
Future<void> startNotionSignIn() async {
  if (!await notionAvailable()) throw const NotionFailure('Notion needs the newest Ghost.md. Install it from Settings > Updates.');
  final state = _randomToken();
  final verifier = _randomToken();
  final challenge = challengeOf(verifier);
  final at = notionNow();
  // Without storage the sign-in can still be collected in this run of the app.
  host.storage.set(_signInKey, {'state': state, 'verifier': verifier, 'at': at});
  _pendingSignIn = (state: state, verifier: verifier, at: at);
  await host.openUrl('$_api/start?state=${Uri.encodeComponent(state)}&challenge=${Uri.encodeComponent(challenge)}');
}

_Flight? _pendingSignIn;

_Flight? _signInInFlight() {
  if (_pendingSignIn != null) return _pendingSignIn;
  final saved = host.storage.get<Object?>(_signInKey, null);
  if (saved is Map && saved['state'] is String && saved['verifier'] is String && saved['at'] is num && notionNow() - (saved['at'] as num) < 10 * 60000) {
    return _pendingSignIn = (state: saved['state'] as String, verifier: saved['verifier'] as String, at: (saved['at'] as num).toInt());
  }
  return null;
}

void _forgetSignIn() {
  _pendingSignIn = null;
  host.storage.remove(_signInKey);
}

/// What collecting a sign-in found, when one was started.
sealed class NotionCollected {
  const NotionCollected();
}

/// The person is still on Notion's page (`'pending'`).
class NotionPending extends NotionCollected {
  const NotionPending();
}

/// The sign-in finished, and its account is kept.
class NotionSignedIn extends NotionCollected {
  const NotionSignedIn(this.account);
  final NotionAccount account;
}

/// Collects a finished sign-in: the account, or [NotionPending] while the person is still on Notion's page, or null
/// when none was started. A sign-in that was refused or failed says why.
Future<NotionCollected?> collectNotionSignIn() async {
  final flight = _signInInFlight();
  if (flight == null) return null;
  final response = await host.fetch(FetchRequest(
    method: 'POST',
    url: Uri.parse('$_api/claim'),
    headers: const {'Content-Type': 'application/json'},
    body: utf8.encode(jsonEncode({'state': flight.state, 'verifier': flight.verifier})),
  ));
  if (response.status == 202) return const NotionPending();
  final answer = _jsonOf(response);
  _forgetSignIn();
  if (!response.ok) throw NotionFailure(answer is Map && answer['error'] is String ? answer['error'] as String : 'Notion sign-in did not finish.');
  return NotionSignedIn(await saveNotionAccount(answer));
}

/// Forgets the sign-in (`notion_disconnect`), and one in flight.
Future<void> disconnectNotion() async {
  _forgetSignIn();
  if (await notionAvailable()) await host.secrets.write(accountSecret, null);
}

/// The account, kept current: re-read when the app comes back to the front, and a sign-in in flight collected then
/// (`useNotionAccount`). Make one with the page that shows it, and dispose it with the page.
class NotionAccountWatch extends ChangeNotifier with WidgetsBindingObserver {
  NotionAccountWatch() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  NotionAccount? _account;
  String? _problem;
  bool _gone = false;

  /// Null until the first answer.
  NotionAccount? get account => _account;

  /// Why the last sign-in did not finish.
  String? get problem => _problem;

  Future<void> refresh() async {
    try {
      final collected = await collectNotionSignIn();
      _set(collected is NotionSignedIn ? collected.account : await notionAccount(), null);
    } catch (failure) {
      final said = failureWords(failure);
      _set(await notionAccount(), said);
    }
  }

  void _set(NotionAccount account, String? problem) {
    if (_gone) return;
    _account = account;
    _problem = problem;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _gone = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// ---- calls -----------------------------------------------------------------------------------------------------

/// The routes below /v1/ Ghost.md calls (notion.rs `allowed_path`). Anything else is refused, so the app cannot be
/// turned into a general Notion client by an address in a note.
bool allowedPath(String path) {
  final under = path.replaceFirst(RegExp(r'^/+'), '');
  if (path.startsWith('//') || under.contains('..') || under.contains('://')) return false;
  const routes = ['search', 'databases/', 'data_sources/', 'pages', 'blocks/', 'users/me'];
  return routes.any((prefix) => under == prefix.replaceFirst(RegExp(r'/+$'), '') || under.startsWith(prefix));
}

Object? _jsonOf(FetchResponse response) {
  try {
    return jsonDecode(response.text);
  } catch (_) {
    // Not JSON (a proxy's page, nothing at all): no body, as the Rust read it.
    return null;
  }
}

Future<({int status, Object? body})> _send(String method, String path, Object? body, String token) async {
  final FetchResponse response;
  try {
    response = await host.fetch(FetchRequest(
      method: method,
      url: Uri.parse('$_notionApi${path.replaceFirst(RegExp(r'^/+'), '')}'),
      headers: {'Authorization': 'Bearer $token', 'Notion-Version': notionVersion, if (body != null) 'Content-Type': 'application/json'},
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      timeout: _patience,
    ));
  } on PluginPermissionError {
    rethrow;
  } catch (_) {
    throw const NotionFailure("Notion couldn't be reached. Check the connection.");
  }
  return (status: response.status, body: _jsonOf(response));
}

/// A fresh pair of tokens for a refresh token, through glyph-api; null when it would not give one.
Future<_Kept?> _refreshAccount(String refreshToken) async {
  try {
    final response = await host.fetch(FetchRequest(
      method: 'POST',
      url: Uri.parse('$_api/refresh'),
      headers: const {'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode({'refreshToken': refreshToken})),
      timeout: _patience,
    ));
    return response.ok ? _Kept.from(_jsonOf(response)) : null;
  } on PluginPermissionError {
    rethrow;
  } catch (_) {
    return null;
  }
}

/// What Notion answered, whatever its status (`notion_request`): the Rust's half of a call. [method] is GET, POST
/// or PATCH, and [path] is below `https://api.notion.com/v1/`. A 401 is answered by refreshing the sign-in once and
/// asking again; the fresh tokens are kept.
Future<({int status, Object? body})> notionAnswer(String method, String path, [Object? body]) async {
  // The Tauri app asks Notion from Rust, which is not built for an iPhone: its sentence there (core/iphone_app.dart).
  final notHere = notOnIPhone('notion');
  if (notHere != null) throw NotionFailure(notHere);
  if (!allowedPath(path)) throw NotionFailure("Glyph doesn't call Notion's $path route.");
  final verb = method.toUpperCase();
  if (verb != 'GET' && verb != 'POST' && verb != 'PATCH') throw NotionFailure("Glyph doesn't send $verb to Notion.");
  var account = _Kept.parse(await host.secrets.read(accountSecret));
  if (account == null) throw const NotionFailure("Glyph isn't signed in to Notion.");

  var answer = await _send(verb, path, body, account.accessToken);
  if (answer.status == 401) {
    final refresh = account.refreshToken;
    final fresh = refresh == null ? null : await _refreshAccount(refresh);
    if (fresh != null) {
      account = _Kept(
        accessToken: fresh.accessToken,
        refreshToken: fresh.refreshToken ?? account.refreshToken,
        botId: account.botId,
        workspaceId: account.workspaceId,
        workspaceName: account.workspaceName,
        workspaceIcon: account.workspaceIcon,
      );
      await host.secrets.write(accountSecret, account.json);
      answer = await _send(verb, path, body, account.accessToken);
    }
  }
  return answer;
}

/// A call to Notion's API, with Notion's refusals as sentences (`notionRequest`). Answers the body, as JSON read.
Future<Object?> notionRequest(String method, String path, [Object? body]) async {
  final answer = await notionAnswer(method, path, body);
  if (answer.status >= 400) {
    final said = answer.body;
    final message = said is Map && said['message'] is String ? said['message'] as String : null;
    if (answer.status == 401) throw const NotionFailure('Notion signed Ghost.md out. Sign in again in Settings › Notion.');
    if (answer.status == 404) {
      throw NotionFailure(path.startsWith('pages/') ? 'Notion can’t see that task. Share its board with Ghost.md in Notion.' : 'Notion can’t see that board. Share it with Ghost.md in Notion.');
    }
    throw NotionFailure(message ?? 'Notion answered ${answer.status}.');
  }
  return answer.body;
}

/// Plain text of a Notion rich text array.
String _plain(Object? rich) => rich is List ? [for (final r in rich) r is Map && r['plain_text'] is String ? r['plain_text'] as String : ''].join() : '';

/// What marks a task done on a board: a status or a checkbox, by its property's name.
@immutable
class DoneProperty {
  const DoneProperty(this.name, this.kind);
  final String name;

  /// `checkbox` or `status`.
  final String kind;

  Map<String, Object?> toJson() => {'name': name, 'kind': kind};

  static DoneProperty? fromJson(Object? raw) => raw is Map && raw['name'] is String && (raw['kind'] == 'checkbox' || raw['kind'] == 'status') ? DoneProperty(raw['name'] as String, raw['kind'] as String) : null;

  @override
  bool operator ==(Object other) => other is DoneProperty && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(name, kind);
}

/// A Notion database a note's list can be sent to (`Board`).
@immutable
class Board {
  const Board({required this.id, required this.title, required this.url, required this.titleProperty, this.doneProperty});

  final String id;
  final String title;
  final String url;

  /// The name of the board's title property: every database has exactly one.
  final String titleProperty;

  /// A checkbox or status property that marks a task done, if the board has one.
  final DoneProperty? doneProperty;

  /// As the page keeps one.
  Map<String, Object?> toJson() => {'id': id, 'title': title, 'url': url, 'titleProperty': titleProperty, 'doneProperty': doneProperty?.toJson()};

  /// Null for anything that is not a board as [toJson] writes one.
  static Board? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'], url = raw['url'], titleProperty = raw['titleProperty'];
    if (id is! String || title is! String || url is! String || titleProperty is! String) return null;
    return Board(id: id, title: title, url: url, titleProperty: titleProperty, doneProperty: DoneProperty.fromJson(raw['doneProperty']));
  }

  @override
  bool operator ==(Object other) => other is Board && other.id == id && other.title == title && other.url == url && other.titleProperty == titleProperty && other.doneProperty == doneProperty;

  @override
  int get hashCode => Object.hash(id, title, url, titleProperty, doneProperty);

  @override
  String toString() => 'Board(${jsonEncode(toJson())})';
}

Board _boardOf(Map<Object?, Object?> db) {
  final properties = db['properties'];
  final entries = properties is Map ? properties.entries.where((e) => e.key is String && e.value is Map).toList() : const <MapEntry<Object?, Object?>>[];
  String? named(String type) {
    for (final entry in entries) {
      if ((entry.value as Map)['type'] == type) return entry.key as String;
    }
    return null;
  }

  final status = named('status');
  final checkbox = named('checkbox');
  final title = _plain(db['title']);
  return Board(
    id: db['id'] is String ? db['id'] as String : '',
    url: db['url'] is String ? db['url'] as String : '',
    title: title.isNotEmpty ? title : 'Untitled board',
    titleProperty: named('title') ?? 'Name',
    // A status is preferred to a checkbox for done: it is what a board's columns are.
    doneProperty: status != null ? DoneProperty(status, 'status') : (checkbox != null ? DoneProperty(checkbox, 'checkbox') : null),
  );
}

/// Every board (database) the sign-in was given access to, recently edited first. One page of fifty, as the page
/// asks: a workspace that shared more shows its fifty most recently edited.
Future<List<Board>> listBoards() async {
  final found = await notionRequest('POST', 'search', {
    'filter': {'property': 'object', 'value': 'database'},
    'sort': {'direction': 'descending', 'timestamp': 'last_edited_time'},
    'page_size': 50,
  });
  final results = found is Map ? found['results'] : null;
  return [
    if (results is List)
      for (final db in results)
        if (db is Map) _boardOf(db),
  ];
}

/// A task made on a board (`Task`).
@immutable
class NotionTask {
  const NotionTask({required this.id, required this.title, required this.url});
  final String id;
  final String title;
  final String url;
}

/// The first [units] UTF-16 units of [text] (`slice(0, n)`), never half of a pair.
String _cut(String text, int units) {
  if (text.length <= units) return text;
  final end = text.codeUnitAt(units - 1) & 0xfc00 == 0xd800 ? units - 1 : units;
  return text.substring(0, end);
}

/// A title property's value: [title], cut to the 2000 characters Notion takes.
Map<String, Object?> titleValue(String title) => {
      'title': [
        {
          'type': 'text',
          'text': {'content': _cut(title, 2000)},
        },
      ],
    };

/// Makes a task on [board] and answers it, with its link.
Future<NotionTask> createTask(Board board, String title) async {
  final page = await notionRequest('POST', 'pages', {
    'parent': {'database_id': board.id},
    'properties': {board.titleProperty: titleValue(title)},
  });
  final made = page is Map ? page : const <Object?, Object?>{};
  return NotionTask(id: made['id'] is String ? made['id'] as String : '', title: title, url: made['url'] is String ? made['url'] as String : '');
}

// ---- which note sends to which board ---------------------------------------------------------------------------

Object? _linksRaw;
Map<String, Board> _links = const {};

/// Every note's board, by the note's id (`boardLinks`). Not to be changed: [linkBoard] writes.
Map<String, Board> boardLinks() {
  final raw = host.storage.get<Object?>(_linksKey, null);
  // Read on every draw of a note's marks: what storage answers is the same object until it is written.
  if (identical(raw, _linksRaw) && raw != null) return _links;
  _linksRaw = raw;
  return _links = Map.unmodifiable({
    if (raw is Map)
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && Board.fromJson(value) != null) key: Board.fromJson(value)!,
  });
}

/// The front matter key a note's board is written under (docs/MARKDOWN_FIRST.md §3.8; tauri/docs/LIBRARY.md reserves
/// it): the board's URL, so the note says where its list goes wherever the folder is opened.
const String notionBoardKey = 'notion-board';

final RegExp _boardIdIn = RegExp(r'([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?![0-9a-f])', caseSensitive: false);

/// The board a note sends to: this device's link first, else the one the note's own `notion-board:` names (the
/// device's storage was per device, so a note linked on the Mac said nothing on the phone; 2026-10-31). A board
/// known only from the note is read as its URL and id, titled by its URL, with Notion's default title property
/// (`Name`) until the picker is opened on it, which keeps the whole board here again.
Board? boardFor(String noteId) {
  final kept = boardLinks()[noteId];
  if (kept != null) return kept;
  final body = pluginNotes.bodyOf?.call(noteId);
  final said = body == null ? null : frontMatterValue(body, notionBoardKey)?.trim();
  if (said == null || said.isEmpty) return null;
  final id = _boardIdIn.firstMatch(said)?.group(1) ?? said;
  return Board(id: id, title: said, url: said.startsWith('http') ? said : '', titleProperty: 'Name');
}

/// Links [noteId] to [board]; null takes the note off Notion. Kept here, and written into the note as
/// `notion-board: <url>` for every other device and a folder opened elsewhere.
void linkBoard(String noteId, Board? board) {
  // A copy: what a read answers is shared with every other read of it (lib/plugins/host.dart).
  final links = {...boardLinks()};
  if (board != null) {
    links[noteId] = board;
  } else {
    links.remove(noteId);
  }
  host.storage.set(_linksKey, {for (final MapEntry(:key, :value) in links.entries) key: value.toJson()});
  final write = pluginNotes.setProperty;
  if (write != null) unawaited(write(noteId, notionBoardKey, board == null ? null : (board.url.isNotEmpty ? board.url : board.id)).catchError((Object _) {}));
}

// ---- for the tests ---------------------------------------------------------------------------------------------

/// Forgets what the page's module kept for the page's life: the sign-in in flight and the answer of
/// [notionAvailable]. The tests' `vi.resetModules()`.
@visibleForTesting
void resetNotionClient() {
  _pendingSignIn = null;
  _ready = false;
  _asked = false;
  _linksRaw = null;
  _links = const {};
  notionNow = _clock;
}
