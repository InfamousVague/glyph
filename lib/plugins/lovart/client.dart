/// Lovart's agent, asked over its "Agent OpenAPI" at `lgw.lovart.ai` (docs/LOVART.md). Ported from the official skill's
/// client, `scripts/agent_skill.py` of github.com/lovartai/lovart-skill, as read on 2026-10-26: the API has no other
/// documentation, so that file is the ground truth and anything here that differs from it is a bug.
///
/// - **Signed.** Every request carries the access key and `hex(HMAC-SHA256(secret, "METHOD\npath\nseconds"))`, the path
///   without its query ([lovartSignature], [lovartHeaders]), signed again on each try. A browser's User-Agent goes
///   with it: Cloudflare in front of Lovart refuses a library's own. A POST carries an `Idempotency-Key`, the same on
///   each try, so a POST tried again is never two generations.
/// - **An envelope.** `{"code": 0, "message": …, "data": {…}}`; a code that is not 0 is a failure, and so is an HTTP
///   error, whose JSON says `message` (and `details`). Lovart's message is a sentence for the person: it is said as it
///   is ([LovartFailure]), with this app's own words only for a key refused (401).
/// - **A generation is a chat.** POST `/chat` with the prompt and the project answers a thread; `/chat/status` is
///   polled every 3 seconds until `done` (looked at again 5 seconds later, since the agent's helpers can start late),
///   then `/chat/result` holds the images, each a URL on `assets-persist.lovart.ai` fetched with Lovart's Referer.
///   Done with no image is the agent declining (moderation, or an answer in words): [LovartRefused], with its words.
/// - **Never a costly step unasked.** A result with `pending_confirmation` (a premium model, a video) waits for the
///   person's yes in Lovart: [LovartNeedsConfirmation], with the cost where Lovart says it. `/chat/confirm` is never
///   called from here.
/// - **No sizes.** Lovart takes no size, shape or count but in the prompt's words.
///
/// The clock and the wait are seams ([LovartClient.now], [LovartClient.sleep]), so a test runs the polling in no time.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show Hmac, sha256;

import '../../account/api.dart' show FetchRequest, FetchResponse;
import '../../core/ids.dart' show randomId;
import '../types.dart';
import 'manifest.dart' as lovart;

/// Where the API is.
const String lovartBase = 'https://lgw.lovart.ai';

/// What every path begins with.
const String lovartPrefix = '/v1/openapi';

/// The skill's own User-Agent: a browser's, which Cloudflare lets through.
const String lovartAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) LovartAgentSkill/1.0';

/// What an image is fetched with: Lovart's storage answers its own site.
const String lovartReferer = 'https://www.lovart.ai/';

/// How often a chat's status is asked, and how long after `done` it is asked again.
const Duration lovartPollEvery = Duration(seconds: 3);
const Duration lovartDoneSettle = Duration(seconds: 5);

/// How long a generation is waited for.
const Duration lovartTimeout = Duration(minutes: 5);

/// `hex(HMAC-SHA256(secret, "METHOD\npath\nseconds"))`: [path] is the request's path alone, no query.
String lovartSignature(String secret, String method, String path, int seconds) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$method\n$path\n$seconds')).toString();

/// Every header a request carries (`_sign` and `_request`): signed for [method] and [path] at [seconds].
Map<String, String> lovartHeaders({required String accessKey, required String secretKey, required String method, required String path, required int seconds, String? idempotencyKey}) => {
      'X-Access-Key': accessKey,
      'X-Timestamp': '$seconds',
      'X-Signature': lovartSignature(secretKey, method, path, seconds),
      'X-Signed-Method': method,
      'X-Signed-Path': path,
      'Content-Type': 'application/json',
      'User-Agent': lovartAgent,
      'Idempotency-Key': ?idempotencyKey,
    };

/// What Lovart refused, or what went wrong asking it, in a sentence a person can act on.
class LovartFailure implements Exception {
  const LovartFailure(this.message, {this.status, this.code});
  final String message;

  /// The HTTP status, where the failure was one.
  final int? status;

  /// Lovart's own code: 2012 credits or plan, 2011 a task already running.
  final int? code;

  /// The keys were refused.
  bool get badKeys => status == 401;

  @override
  String toString() => message;
}

/// Lovart's agent wants the person's yes before a costly step. Approved in Lovart, never here.
class LovartNeedsConfirmation extends LovartFailure {
  const LovartNeedsConfirmation({this.cost, required this.threadId})
      : super('Lovart wants your go-ahead before a costly step. Approve it in Lovart if you want it.');

  /// What Lovart estimates it costs, in credits, where it says.
  final num? cost;
  final String threadId;

  /// The sentence to say, with the cost where there is one.
  String get said => cost == null ? message : 'Lovart wants your go-ahead before a step costing about $cost credits. Approve it in Lovart if you want it.';
}

/// The agent finished without an image: it declined the prompt, or answered in words.
class LovartRefused extends LovartFailure {
  const LovartRefused(this.text) : super(text == '' ? 'Lovart made no image for that, and didn’t say why.' : 'Lovart made no image: $text');

  /// What the agent said, if anything.
  final String text;
}

/// The keys the plugin holds now, or null where either is missing (read [lovart.host]'s secrets warm).
({String access, String secret})? lovartKeys([PluginHost? via]) {
  final host = via ?? lovart.host;
  final access = host.secrets.held(lovart.accessKeySecret)?.trim() ?? '';
  final secret = host.secrets.held(lovart.secretKeySecret)?.trim() ?? '';
  return access.isEmpty || secret.isEmpty ? null : (access: access, secret: secret);
}

/// Whether both keys are kept.
bool hasLovartKeys([PluginHost? via]) => lovartKeys(via) != null;

/// An image's file ending by its first bytes, or null for none this app keeps: PNG, JPEG or WebP.
String? pictureExtension(Uint8List bytes) {
  if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47) return 'png';
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) return 'jpg';
  if (bytes.length >= 12 && ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' && ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') return 'webp';
  return null;
}

/// About how many Lovart credits one image costs: Matt's working estimate (2026-10-26: "Estimate about 6 credits per
/// image for now"). Lovart's API says nothing of a cost or a balance for an ordinary image; only a step it holds for
/// the person's yes carries an estimate (`pending_confirmation`'s `estimated_cost`, [LovartNeedsConfirmation.cost]).
/// So every sum the app says is this times the images, and always said as about ([aboutCredits]). The one place to
/// change it.
const int lovartCreditsPerImage = 6;

/// "about 144 credits", for [images] images at [lovartCreditsPerImage] each.
String aboutCredits(int images) => 'about ${images * lovartCreditsPerImage} credits';

/// The person's Lovart, with their keys.
class LovartClient {
  LovartClient({required this.accessKey, required this.secretKey, PluginHost? via, DateTime Function()? now, Future<void> Function(Duration wait)? sleep, String Function()? idempotency})
      : _host = via,
        now = now ?? DateTime.now,
        sleep = sleep ?? _wait,
        _idempotency = idempotency ?? (() => randomId().replaceAll('-', ''));

  /// The client with the keys kept, or null where there are none.
  static LovartClient? kept({PluginHost? via, DateTime Function()? now, Future<void> Function(Duration wait)? sleep}) {
    final keys = lovartKeys(via);
    return keys == null ? null : LovartClient(accessKey: keys.access, secretKey: keys.secret, via: via, now: now, sleep: sleep);
  }

  final String accessKey;
  final String secretKey;
  final PluginHost? _host;
  final DateTime Function() now;
  final Future<void> Function(Duration wait) sleep;
  final String Function() _idempotency;

  PluginHost get _on => _host ?? lovart.host;

  static Future<void> _wait(Duration wait) => Future<void>.delayed(wait);

  int get _seconds => now().millisecondsSinceEpoch ~/ 1000;

  /// One call: signed, tried again where the skill tries again (a GET three times on a gateway's hiccup; a 429 after
  /// the wait it asks), and answered as its `data`.
  Future<Map<String, Object?>> _call(String method, String path, {Map<String, Object?>? body, Map<String, String>? query}) async {
    final full = '$lovartPrefix$path';
    final url = Uri.parse('$lovartBase$full').replace(queryParameters: query);
    final tries = method == 'GET' ? 3 : 2;
    final idempotency = method == 'POST' ? _idempotency() : null;
    final bytes = body == null ? null : Uint8List.fromList(utf8.encode(jsonEncode(body)));
    for (var attempt = 0;; attempt += 1) {
      final last = attempt >= tries - 1;
      FetchResponse answer;
      try {
        answer = await _on.fetch(FetchRequest(method: method, url: url, headers: lovartHeaders(accessKey: accessKey, secretKey: secretKey, method: method, path: full, seconds: _seconds, idempotencyKey: idempotency), body: bytes));
      } on TimeoutException {
        if (method == 'GET' && !last) {
          await sleep(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        throw const LovartFailure('Lovart took too long to answer. Try again in a moment.');
      } on LovartFailure {
        rethrow;
      } catch (failure) {
        if (failure is Error) rethrow;
        if (method == 'GET' && !last) {
          await sleep(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        throw const LovartFailure('Lovart couldn’t be reached. Check the connection and try again.');
      }
      if (!answer.ok) {
        final again = answer.status == 429 || (method == 'GET' && (answer.status == 404 || answer.status == 502 || answer.status == 503));
        if (again && !last) {
          await sleep(_retryAfter(answer) ?? Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        throw _trouble(answer);
      }
      Object? decoded;
      try {
        decoded = jsonDecode(answer.text);
      } catch (_) {
        throw LovartFailure('Lovart answered something this app can’t read.', status: answer.status);
      }
      if (decoded is! Map) return const {};
      final code = decoded['code'];
      if (code is num && code != 0) {
        final said = decoded['message'];
        throw LovartFailure(said is String && said.isNotEmpty ? said : 'Lovart refused that (code $code).', code: code.toInt());
      }
      final data = decoded.containsKey('data') ? decoded['data'] : decoded;
      return data is Map ? data.cast<String, Object?>() : const {};
    }
  }

  /// `Retry-After` in seconds, at most a minute.
  static Duration? _retryAfter(FetchResponse answer) {
    final seconds = int.tryParse(answer.headers['retry-after']?.trim() ?? '');
    return seconds == null ? null : Duration(seconds: seconds.clamp(1, 60));
  }

  /// An HTTP error as the person should hear it: Lovart's own message, but for a key refused.
  static LovartFailure _trouble(FetchResponse answer) {
    var said = '';
    int? code;
    try {
      final Object? body = jsonDecode(answer.text);
      if (body is Map) {
        final message = body['message'] ?? body['error'];
        if (message is String) said = message.trim();
        final details = body['details'];
        if (details is String && details.trim().isNotEmpty) said = said.isEmpty ? details.trim() : '$said: ${details.trim()}';
        if (body['code'] is num) code = (body['code'] as num).toInt();
      }
    } catch (_) {
      // Not JSON: Lovart said nothing this can read.
    }
    final status = answer.status;
    if (status == 401) return LovartFailure('Lovart didn’t accept these keys. Copy both again from Lovart’s AK/SK Management.', status: status, code: code);
    if (status == 409 && said.isEmpty) return LovartFailure('Lovart is still busy with the last request. Try again when it is done.', status: status, code: code);
    if (status == 429 && said.isEmpty) return LovartFailure('Lovart is asking this device to slow down. Try again in a minute.', status: status, code: code);
    if (said.isNotEmpty) return LovartFailure(said, status: status, code: code);
    if (status == 402) return LovartFailure('Lovart says your plan or credits don’t cover this.', status: status, code: code);
    return LovartFailure('Lovart answered $status.', status: status, code: code);
  }

  /// Whether the keys work: `POST /mode/query`, which changes nothing. Null when they do, the failure when not.
  Future<LovartFailure?> check() async {
    try {
      await _call('POST', '/mode/query', body: const {});
      return null;
    } on LovartFailure catch (failure) {
      return failure;
    }
  }

  /// The project the images are made in: the one kept, while Lovart still has it, else a new one, kept.
  Future<String> ensureProject() async {
    final storage = _on.storage;
    final kept = storage.get<Object?>(lovart.projectKey, null);
    if (kept is String && kept.isNotEmpty) {
      try {
        final checked = await _call('GET', '/project/validate', query: {'project_id': kept});
        if (checked['valid'] == true) return kept;
      } on LovartFailure catch (failure) {
        if (failure.badKeys || failure.status == 402) rethrow;
        // Not known any more: a new one is made.
      }
    }
    final made = await _call('POST', '/project/save', body: const {'project_id': '', 'canvas': '', 'project_cover_list': <Object?>[], 'pic_count': 0, 'project_type': 3});
    final id = made['project_id'];
    if (id is! String || id.isEmpty) throw const LovartFailure('Lovart didn’t make a project to put the images in.');
    storage.set(lovart.projectKey, id);
    return id;
  }

  /// Starts a chat with [prompt] and answers its thread.
  Future<String> start(String prompt, {String? project}) async {
    final id = project ?? await ensureProject();
    final sent = await _call('POST', '/chat', body: {'prompt': prompt, 'project_id': id, 'mode': 'fast'});
    final thread = sent['thread_id'];
    if (thread is! String || thread.isEmpty) throw const LovartFailure('Lovart didn’t start on that.');
    return thread;
  }

  Future<String> _status(String thread) async {
    final status = (await _call('GET', '/chat/status', query: {'thread_id': thread}))['status'];
    return status is String ? status : 'running';
  }

  Future<Map<String, Object?>> _result(String thread) => _call('GET', '/chat/result', query: {'thread_id': thread});

  /// A result's ask for a yes, as a failure, or null.
  static LovartNeedsConfirmation? _pending(Map<String, Object?> result, String thread) {
    final pending = result['pending_confirmation'];
    if (pending == null || pending == false || (pending is Map && pending.isEmpty)) return null;
    num? cost;
    if (pending is Map) {
      for (final name in const ['estimated_cost', 'cost', 'credits']) {
        final value = pending[name];
        if (value is num) cost = value;
        if (value is String) cost = num.tryParse(value);
        if (cost != null) break;
      }
    }
    return LovartNeedsConfirmation(cost: cost, threadId: thread);
  }

  /// Waits for [thread] to finish, and answers its result (`poll`, then `get_result`).
  Future<Map<String, Object?>> finish(String thread, {Duration timeout = lovartTimeout}) async {
    final deadline = now().add(timeout);
    var polls = 0;
    while (now().isBefore(deadline)) {
      final status = await _status(thread);
      polls += 1;
      if (status == 'abort') throw const LovartFailure('Lovart stopped before it finished. Try again.');
      if (status == 'done') {
        await sleep(lovartDoneSettle);
        final again = await _status(thread);
        if (again == 'abort') throw const LovartFailure('Lovart stopped before it finished. Try again.');
        if (again == 'done') {
          final result = await _result(thread);
          final pending = _pending(result, thread);
          if (pending != null) throw pending;
          return result;
        }
      } else if (polls >= 7 && polls % 3 == 0) {
        // Twenty seconds in, now and then: a step waiting on the person's yes never finishes by itself.
        try {
          final pending = _pending(await _result(thread), thread);
          if (pending != null) throw pending;
        } on LovartNeedsConfirmation {
          rethrow;
        } on LovartFailure {
          // Asked again later.
        }
      }
      await sleep(lovartPollEvery);
    }
    throw LovartFailure('Lovart took more than ${timeout.inMinutes == 1 ? 'a minute' : '${timeout.inMinutes} minutes'}. What it made will be in your Lovart project.');
  }

  /// The images of a result, by their addresses, each once: the artifacts of type `image`.
  static List<Uri> imagesOf(Map<String, Object?> result) {
    final seen = <String>{};
    final out = <Uri>[];
    final items = result['items'];
    if (items is! List) return out;
    for (final item in items) {
      if (item is! Map) continue;
      final artifacts = item['artifacts'];
      if (artifacts is! List) continue;
      for (final artifact in artifacts) {
        if (artifact is! Map || artifact['type'] != 'image') continue;
        final content = artifact['content'];
        if (content is! String || !seen.add(content)) continue;
        final url = Uri.tryParse(content);
        if (url != null && url.scheme == 'https') out.add(url);
      }
    }
    return out;
  }

  /// What the agent said in words: its `assistant` items' text, together.
  static String wordsOf(Map<String, Object?> result) {
    final items = result['items'];
    if (items is! List) return '';
    return [
      for (final item in items)
        if (item is Map && item['text'] is String && (item['text'] as String).trim().isNotEmpty) (item['text'] as String).trim(),
    ].join('\n\n');
  }

  /// An image's bytes, fetched with Lovart's Referer; null for one that is not an image this app keeps.
  Future<Uint8List?> download(Uri url) async {
    final answer = await _on.fetch(FetchRequest(method: 'GET', url: url, headers: const {'User-Agent': lovartAgent, 'Referer': lovartReferer}));
    if (!answer.ok) throw LovartFailure('An image Lovart made couldn’t be fetched (${answer.status}).', status: answer.status);
    return pictureExtension(answer.bytes) == null ? null : answer.bytes;
  }

  /// Asks for [prompt], waits, and answers the images' bytes, PNG, JPEG or WebP. Throws a [LovartFailure]:
  /// [LovartRefused] where the agent made none, [LovartNeedsConfirmation] where it waits for the person's yes.
  Future<List<Uint8List>> generate(String prompt, {Duration timeout = lovartTimeout}) async {
    _on.need(Permission.network);
    final thread = await start(prompt);
    final result = await finish(thread, timeout: timeout);
    final urls = imagesOf(result);
    if (urls.isEmpty) throw LovartRefused(wordsOf(result));
    final images = <Uint8List>[];
    for (final url in urls) {
      // Only Lovart's own hosts: the manifest holds every request to them, and an address elsewhere is skipped.
      final host = url.host.toLowerCase();
      if (host != 'lovart.ai' && !host.endsWith('.lovart.ai')) continue;
      final bytes = await download(url);
      if (bytes != null) images.add(bytes);
    }
    if (images.isEmpty) throw const LovartFailure('Lovart’s images couldn’t be read as pictures.');
    return images;
  }
}

/// The client the actions and the meetings ask: the one with the kept keys, unless a test gives its own.
LovartClient? Function() lovartClient = () => LovartClient.kept();
