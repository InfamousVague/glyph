import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../net/crypto.dart';
import '../net/hub_carrier.dart' show NetSigner;

/// Share feedback (Matt, 2026-11-19: "add a "share feedback" button hovering in the topbar of the app it should be a
/// simple form which allows the user to upload screenshots and explain a bug, suggest a feature or a few other options
/// from a select dropdown and optionally provide their username automatically so we can give out bug bounties"): what
/// is sent, and the relay it goes to (relay/, which files it as a ticket on the feedback board).

/// What kind of feedback it is, as the relay names it.
enum FeedbackType {
  bug('bug', 'Bug'),
  feature('feature', 'Feature idea'),
  confusing('confusing', 'Something confusing'),
  praise('praise', 'Praise'),
  other('other', 'Other');

  const FeedbackType(this.wire, this.label);
  final String wire;
  final String label;
}

/// A screenshot going with the feedback: its name, kind and bytes.
class FeedbackShot {
  const FeedbackShot({required this.name, required this.mime, required this.bytes});
  final String name;
  final String mime;
  final Uint8List bytes;

  /// The kinds of picture the relay takes.
  static const mimes = {'image/png', 'image/jpeg', 'image/webp', 'image/gif'};
}

/// One piece of feedback: its kind, an optional title, the words, the username to be known by (for a bug bounty;
/// null where the person chose not to say it), and up to [mostShots] screenshots.
class FeedbackReport {
  const FeedbackReport({required this.type, this.title = '', required this.text, this.username, required this.platform, required this.version, this.shots = const []});
  final FeedbackType type;
  final String title;
  final String text;
  final String? username;
  final String platform;
  final String version;
  final List<FeedbackShot> shots;

  /// The relay's limits: what it would refuse is not sent.
  static const titleMost = 120, textMost = 5000, mostShots = 3, shotMost = 3 * 1024 * 1024, bodyMost = 10 * 1024 * 1024;

  /// What this device is, in the relay's words.
  static String get thisPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'iphone';
    if (Platform.isMacOS) return 'mac';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  /// The request's body: the words trimmed, the username without its @, each screenshot's bytes as base64.
  Map<String, Object?> toJson() {
    final name = username?.trim().replaceFirst(RegExp(r'^@'), '');
    return {
      'type': type.wire,
      'title': title.trim(),
      'text': text.trim(),
      // The username itself, only where the person said to include it; the relay checks it is this key's.
      if (name != null && name.isNotEmpty) 'username': name,
      'platform': platform,
      'version': version,
      'shots': [for (final s in shots) {'name': s.name, 'mime': s.mime, 'data': base64Encode(s.bytes)}],
    };
  }
}

/// Why the feedback didn't go: the relay's words, or that it could not be reached.
class FeedbackError implements Exception {
  FeedbackError(this.message, {this.status = 0});
  final String message;
  final int status;
  @override
  String toString() => message;
}

/// Where feedback goes on the relay at [hubUrl]: the same server, `/feedback` in place of `/hub` (as FilesApi.baseFor
/// finds `/files`).
Uri feedbackUrlFor(String hubUrl) {
  final u = Uri.parse(hubUrl.trim());
  final segments = [...u.pathSegments.where((s) => s.isNotEmpty)];
  if (segments.isNotEmpty && segments.last == 'hub') segments.removeLast();
  return u.replace(scheme: u.scheme == 'ws' ? 'http' : (u.scheme == 'wss' ? 'https' : u.scheme), pathSegments: [...segments, 'feedback'], query: null, fragment: null);
}

/// Sends [r] to the relay at [hubUrl], signed with this install's hub key [signer] (as a Files space's writes are):
/// the ticket's id the relay answers ("GMFB-12"). Throws a [FeedbackError] with the relay's words otherwise.
Future<String> sendFeedback(FeedbackReport r, {required NetSigner signer, required String hubUrl, HttpClient? client}) async {
  final shots = r.shots;
  if (shots.length > FeedbackReport.mostShots) throw FeedbackError('Up to ${FeedbackReport.mostShots} screenshots go with feedback.');
  if (shots.any((s) => s.bytes.length > FeedbackReport.shotMost)) throw FeedbackError('A screenshot is larger than 3 MB.');
  final text = r.text.trim();
  if (text.isEmpty) throw FeedbackError('Say what happened first.');
  if (text.length > FeedbackReport.textMost) throw FeedbackError('That\'s more than ${FeedbackReport.textMost} characters.');
  final body = utf8.encode(jsonEncode(r.toJson()));
  if (body.length > FeedbackReport.bodyMost) throw FeedbackError('The screenshots are too large together.');
  final url = feedbackUrlFor(hubUrl);
  final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));
  try {
    final req = await http.postUrl(url);
    // Signed over what the relay sees: the method, the path, the time and the body's hash.
    final time = DateTime.now().millisecondsSinceEpoch;
    final sha = NetCrypto.hex(NetCrypto.sha256(body));
    final sig = await signer.sign(utf8.encode('ghost-feedback v1\nPOST\n${url.path}\n$time\n$sha'));
    req.headers
      ..contentType = ContentType.json
      ..set('x-ghost-key', base64Encode(signer.publicKey))
      ..set('x-ghost-time', '$time')
      ..set('x-ghost-sig', base64Encode(sig));
    req.contentLength = body.length;
    req.add(body);
    final res = await req.close().timeout(const Duration(seconds: 60));
    final words = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(words) as Map).cast<String, dynamic>();
    } catch (_) {
      m = {};
    }
    if (res.statusCode >= 300 || m['ok'] != true) {
      final said = m['error'];
      throw FeedbackError(said is String && said.trim().isNotEmpty ? said : 'The server said ${res.statusCode}.', status: res.statusCode);
    }
    return '${m['id'] ?? ''}';
  } on FeedbackError {
    rethrow;
  } on SocketException {
    throw FeedbackError('Couldn\'t reach the server. Check your connection and try again.');
  } on HttpException {
    throw FeedbackError('Couldn\'t reach the server. Try again in a moment.');
  } on HandshakeException {
    throw FeedbackError('Couldn\'t reach the server securely.');
  } on TimeoutException {
    throw FeedbackError('The server didn\'t answer. Try again in a moment.');
  } finally {
    if (client == null) http.close();
  }
}
