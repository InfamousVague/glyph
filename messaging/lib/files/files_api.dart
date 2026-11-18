import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../net/crypto.dart';
import '../net/hub_carrier.dart' show NetSigner;

/// Why the files server said no: its words, and what it answered (a 409 says where an upload has got to in [have]).
class FilesError implements Exception {
  FilesError(this.status, this.message, {this.have, this.seq});
  final int status;
  final String message;
  final int? have;

  /// Where the log has got to, said with a 409 to an entry sent with `?after=` that the log has moved past.
  final int? seq;

  /// The server could not be reached at all.
  bool get offline => status == 0;
  @override
  String toString() => message;
}

/// A Files space's files on the relay (relay/lib/files.dart), spoken to over plain HTTPS: its token on every request,
/// and every write signed with this install's hub key ([NetSigner], the key it is known by in the space's roster).
class FilesApi {
  FilesApi({required this.base, required this.space, required this.token, required this.signer, HttpClient? client}) : _http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  /// Where the files are served: `https://gogho.st/files` for the relay at `wss://gogho.st/hub`.
  final Uri base;

  /// The relay's name for the space's files, and its token (both from the seed: FileSeal.filesRoom / filesToken).
  final String space;
  final String token;
  final NetSigner signer;
  final HttpClient _http;

  /// Where the files of the relay at [hubUrl] are: the same server, `/files` in place of `/hub`.
  static Uri baseFor(String hubUrl) {
    final u = Uri.parse(hubUrl.trim());
    final segments = [...u.pathSegments.where((s) => s.isNotEmpty)];
    if (segments.isNotEmpty && segments.last == 'hub') segments.removeLast();
    return u.replace(scheme: u.scheme == 'ws' ? 'http' : (u.scheme == 'wss' ? 'https' : u.scheme), pathSegments: [...segments, 'files'], query: null, fragment: null);
  }

  String _path(String rest) => '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/$space$rest';

  Future<HttpClientRequest> _open(String method, String rest, {List<int>? signBody, bool sayHash = false}) async {
    final path = _path(rest);
    final req = await _http.openUrl(method, base.replace(path: path.split('?').first, query: path.contains('?') ? path.substring(path.indexOf('?') + 1) : null));
    req.headers.set(HttpHeaders.authorizationHeader, 'Ghost $token');
    if (signBody != null) {
      // Signed over what the relay sees: the method, the path with its query, the time and the body's hash.
      final time = DateTime.now().millisecondsSinceEpoch;
      final sha = NetCrypto.hex(NetCrypto.sha256(signBody));
      final words = 'ghost-files v1\n$method\n$path\n$time\n$sha';
      final sig = await signer.sign(utf8.encode(words));
      req.headers
        ..set('x-ghost-key', base64Encode(signer.publicKey))
        ..set('x-ghost-time', '$time')
        ..set('x-ghost-sig', base64Encode(sig));
      // A blob's piece says its hash and length up front, so the relay checks the signature before it reads the body
      // (Matt, 2026-11-17: "Finish the missing pieces that went unfinished"). The words signed are the same as ever, so
      // a relay from before this reads the headers as nothing and checks the signature at the end, as it did.
      if (sayHash) {
        req.headers
          ..set('x-ghost-body-sha256', sha)
          ..set('x-ghost-body-length', '${signBody.length}');
      }
    }
    return req;
  }

  Future<Map<String, dynamic>> _json(HttpClientResponse res) async {
    final text = await res.transform(utf8.decoder).join();
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(text) as Map).cast<String, dynamic>();
    } catch (_) {
      m = {};
    }
    if (res.statusCode >= 300) throw FilesError(res.statusCode, m['err'] is String ? m['err'] as String : 'The files server said ${res.statusCode}.', have: (m['have'] as num?)?.toInt(), seq: (m['seq'] as num?)?.toInt());
    return m;
  }

  Future<Map<String, dynamic>> _call(String method, String rest, {List<int>? body, bool sign = false, bool sayHash = false}) async {
    try {
      final req = await _open(method, rest, signBody: sign ? (body ?? const []) : null, sayHash: sayHash);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      } else {
        req.contentLength = 0;
      }
      return await _json(await req.close());
    } on FilesError {
      rethrow;
    } on SocketException catch (e) {
      throw FilesError(0, 'Can\'t reach the files server (${e.osError?.message ?? e.message}).');
    } on HttpException catch (e) {
      throw FilesError(0, 'Can\'t reach the files server (${e.message}).');
    } on TimeoutException {
      throw FilesError(0, 'The files server didn\'t answer.');
    } on HandshakeException {
      throw FilesError(0, 'Can\'t reach the files server securely.');
    }
  }

  /// Makes the space on the relay, or finds it: [owner] (the space owner's public key, hex) may remove anyone's file.
  /// [rv], from the owner's or an admin's device, says the space's newest roster revision (FilesStore._statement), so the
  /// relay refuses an older roster shown to it later; signed with the rest of the request.
  Future<FilesInfo> ensure({String owner = '', Map<String, Object?>? rv}) async =>
      FilesInfo.from(await _call('PUT', '', body: utf8.encode(jsonEncode({'owner': owner, 'rv': ?rv})), sign: true));

  Future<FilesInfo> info() async => FilesInfo.from(await _call('GET', ''));

  /// The log's entries after [after]: each `{s, by, at, o}` with `o` the sealed operation in base64.
  Future<({List<Map<String, dynamic>> ops, int seq, bool more})> log({int after = 0}) async {
    final m = await _call('GET', '/log?after=$after');
    return (ops: [for (final o in (m['ops'] as List? ?? const [])) (o as Map).cast<String, dynamic>()], seq: (m['seq'] as num?)?.toInt() ?? 0, more: m['more'] == true);
  }

  /// Adds a sealed operation to the log: its number. With [after] (the last entry this device has read, which the
  /// entry is signed with), it goes right after that one or the relay answers 409 with where the log has got to.
  Future<int> append(Uint8List sealed, {int? after}) async => ((await _call('POST', after == null ? '/log' : '/log?after=$after', body: sealed, sign: true))['seq'] as num).toInt();

  /// Room for a sealed file of [size] bytes: its blob's id. `pre` says every piece of it will say its hash up front
  /// ([put]), so the relay refuses one that doesn't before reading it; a relay from before reads past it.
  Future<String> newBlob(int size) async => (await _call('POST', '/blobs', body: utf8.encode(jsonEncode({'size': size, 'pre': true})), sign: true))['id'] as String;

  Future<({int have, int size, bool done})> state(String blob) async {
    final m = await _call('GET', '/blobs/$blob/state');
    return (have: (m['have'] as num).toInt(), size: (m['size'] as num).toInt(), done: m['done'] == true);
  }

  /// A piece of a blob at [offset] (where it has got to): what it has after.
  Future<int> put(String blob, int offset, Uint8List bytes) async => ((await _call('PUT', '/blobs/$blob?offset=$offset', body: bytes, sign: true, sayHash: true))['have'] as num).toInt();

  Future<void> done(String blob) => _call('POST', '/blobs/$blob/done', sign: true);

  /// Lets [blob] go on the relay: this device's own, or the owner's; or anyone's, as a moderator or admin, with the
  /// space's [roster] (as for [ensure]) that says so.
  Future<void> deleteBlob(String blob, {Map<String, Object?>? roster}) => _call('DELETE', '/blobs/$blob', body: roster == null ? null : utf8.encode(jsonEncode({'roster': roster})), sign: true);

  /// The blob from [start] on (to [end], inclusive, where given), as it streams in. Throws a [FilesError] for a refusal.
  Future<Stream<List<int>>> read(String blob, {int start = 0, int? end}) async {
    try {
      final req = await _open('GET', '/blobs/$blob');
      if (start > 0 || end != null) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${end ?? ''}');
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok && res.statusCode != HttpStatus.partialContent) await _json(res);
      if (start > 0 && res.statusCode == HttpStatus.ok) {
        // A server that ignored the Range: what was had is skipped.
        var skip = start;
        return res.map((piece) {
          if (skip <= 0) return piece;
          if (piece.length <= skip) {
            skip -= piece.length;
            return const <int>[];
          }
          final rest = piece.sublist(skip);
          skip = 0;
          return rest;
        });
      }
      return res;
    } on FilesError {
      rethrow;
    } on SocketException catch (e) {
      throw FilesError(0, 'Can\'t reach the files server (${e.osError?.message ?? e.message}).');
    } on HttpException catch (e) {
      throw FilesError(0, 'Can\'t reach the files server (${e.message}).');
    }
  }

  void close() => _http.close(force: true);

  /// Lets its connections go once what is under way on them is done (a client replaced, not stopped).
  void closeIdle() => _http.close();
}

/// What the relay says of a space: how much it holds and may hold, the largest file, and the log's last number.
class FilesInfo {
  const FilesInfo({this.seq = 0, this.used = 0, this.quota = 0, this.maxFile = 0, this.files = 0, this.owner = '', this.rv = 0, this.cas = false});
  final int seq, used, quota, maxFile, files;
  final String owner;

  /// The newest roster revision the relay has believed for the space (0 from a relay from before rosters).
  final int rv;

  /// Whether the relay puts an entry sent with `?after=` only right there (relay/lib/files.dart): then a signed entry
  /// out of its place was moved by the relay (FilesList.read).
  final bool cas;
  factory FilesInfo.from(Map<String, dynamic> m) => FilesInfo(
        seq: (m['seq'] as num?)?.toInt() ?? 0,
        used: (m['used'] as num?)?.toInt() ?? 0,
        quota: (m['quota'] as num?)?.toInt() ?? 0,
        maxFile: (m['maxFile'] as num?)?.toInt() ?? 0,
        files: (m['files'] as num?)?.toInt() ?? 0,
        owner: m['owner'] is String ? m['owner'] as String : '',
        rv: (m['rv'] as num?)?.toInt() ?? 0,
        cas: m['cas'] == 1,
      );
  Map<String, Object?> toJson() => {'seq': seq, 'used': used, 'quota': quota, 'maxFile': maxFile, 'files': files};
}
