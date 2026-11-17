import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'p256.dart';
import 'sha256.dart';

/// A Files space's store (Matt, 2026-11-17: "add full functionality for filesharing in a space when the space is
/// designated a Files Space"). A Files space has to work while whoever added a file is away, and the hub holds nothing
/// for a room, so the files are kept here, on the relay's disk, under `/files/<space>`.
///
/// - **What it sees.** Blobs and their sizes, and the hub name of whoever wrote each. Every file is sealed on the phone
///   before it leaves (AES-256-GCM in chunks, lib/net/file_seal.dart in the app) with a key in the file's own
///   description, and that description is sealed in turn with a key made from the space's seed, which never comes
///   here. The list of what a space holds is a log of sealed operations it keeps in order and hands back.
/// - **Who gets in.** Every request carries `Authorization: Ghost <token>`, the space's token, made from its seed; the
///   first to name a space sets it, as a hub room's is (hub.dart). Every write is also signed with the writer's hub
///   key, the same P-256 key the hub knows them by: `X-Ghost-Key` (33 bytes, base64), `X-Ghost-Time` (ms) and
///   `X-Ghost-Sig` over [signedWords]. So a blob is written, finished and removed only by whoever started it, or by the
///   space's owner (the key named when it was made).
/// - **Memory.** Nothing big is held: a chunk is streamed to disk as it arrives and hashed as it goes, and a read is
///   streamed from disk with Range, so a 2 GB file passes through a relay held to 300 MB.
/// - **Limits** ([FilesConfig], from the environment): how big a file may be, how much a space may hold, how much all
///   spaces together, how many spaces one name may make, and how many writes a minute.
/// - **Who may fill it.** A space and its keys cost nothing to make, so the limits are on what is written, not only on
///   who signs: a space's log counts against its room and the whole store's as its files do (and has a cap of its
///   own), a room promised to a file that never gets a byte is let go after ten minutes, and how many spaces and how
///   many unfinished bytes one address may have going is limited as well as one key ([FilesConfig]).
/// - **What goes by itself.** A blob left unfinished for a day (one that never got a byte, ten minutes); a space nobody
///   has opened for ninety days.
///
/// Layout: `<dir>/<space>/meta.json` (its token's hash, owner, blobs), `log.jsonl` (one sealed operation a line), and
/// `blobs/<id>` (`<id>.part` while it is being written).
class Files {
  Files({required this.dir, this.config = const FilesConfig(), DateTime Function()? now, Random? random, this.verbose = false})
      : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  final Directory dir;
  final FilesConfig config;
  final bool verbose;
  final DateTime Function() _now;
  final Random _random;

  /// What a write is signed over: these words, the method, the path with its query, the time and the body's SHA-256.
  static String signedWords(String method, String path, int time, String bodySha) => 'ghost-files v1\n$method\n$path\n$time\n$bodySha';

  /// How far a write's time may be from the relay's.
  static const skew = Duration(minutes: 10);

  /// The most a log page hands back: this many operations, or [pageBytes] of them, whichever comes first.
  static const page = 500;
  static const pageBytes = 1 << 20;

  /// Log lines between the marks of where they start in the file, so a page is read from near where it begins.
  static const _markEvery = 256;

  /// How many log pages may be read at once; more are asked to come back.
  static const _readersAtOnce = 4;
  int _readers = 0;

  /// Spaces made today by each address, and the day counted.
  final Map<String, int> _madeBy = {};
  String _madeDay = '';

  final Map<String, _Space> _spaces = {};
  final Map<String, int> _replays = {};
  final Map<String, int> _writes = {};
  int _minute = 0;
  int _used = 0;
  Timer? _sweeper;

  int get spaces => _spaces.length;

  /// Bytes held (files and lists), and promised to blobs still being written, across every space.
  int get used => _used;

  /// The address a request came from: what Caddy, the one proxy in front, says it was; else the connection's own.
  static String addressOf(HttpRequest r) {
    final said = r.headers.value('x-forwarded-for')?.split(',').first.trim();
    return said != null && said.isNotEmpty ? said : (r.connectionInfo?.remoteAddress.address ?? '');
  }

  /// Unfinished bytes promised to blobs whose room was asked for from [ip].
  int _promisedTo(String ip) {
    var n = 0;
    for (final s in _spaces.values) {
      for (final b in s.blobs.values) {
        if (!b.done && b.ip == ip) n += b.size - b.have;
      }
    }
    return n;
  }

  void _say(String what) {
    if (verbose) stdout.writeln('${_now().toIso8601String()} files $what');
  }

  Future<void> start() async {
    await _load();
    _sweeper ??= Timer.periodic(const Duration(minutes: 10), (_) => unawaited(sweep()));
  }

  void stop() {
    _sweeper?.cancel();
    _sweeper = null;
    for (final s in _spaces.values) {
      _saveNow(s);
    }
  }

  static final _hexOnly = RegExp(r'^[0-9a-f]+$');
  static bool _hex(Object? text, int length) => text is String && text.length == length && _hexOnly.hasMatch(text);
  String _day() => _now().toUtc().toIso8601String().substring(0, 10);

  // --- what is kept ----------------------------------------------------------------------------------------------------

  Directory _dirOf(String id) => Directory('${dir.path}/$id');
  File _blobFile(String space, String id, {bool part = false}) => File('${dir.path}/$space/blobs/$id${part ? '.part' : ''}');

  Future<void> _load() async {
    if (!dir.existsSync()) return;
    await for (final e in dir.list()) {
      final id = e.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
      if (e is! Directory || !_hex(id, 32)) continue;
      final meta = File('${e.path}/meta.json');
      if (!meta.existsSync()) continue;
      try {
        final s = _Space.fromJson(id!, jsonDecode(meta.readAsStringSync()) as Map);
        // What a blob being written has is no more than the last save said: a piece written since may be one whose
        // signature was never checked (the relay stopped in the middle of it), so the file is cut back to that.
        for (final b in s.blobs.values.where((b) => !b.done)) {
          final f = _blobFile(id, b.id, part: true);
          final length = f.existsSync() ? f.lengthSync() : 0;
          b.have = min(min(length, b.have), b.size);
          if (length > b.have) {
            try {
              final raf = f.openSync(mode: FileMode.append)..truncateSync(b.have);
              raf.closeSync();
            } catch (_) {}
          }
        }
        // The list: its bytes count against the space's room, and its last number is its count of lines (saved
        // lazily, so the lines are what to go by).
        final log = File('${e.path}/log.jsonl');
        if (log.existsSync()) {
          s.logBytes = log.lengthSync();
          s.used += s.logBytes;
          var lines = 0;
          await for (final _ in log.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
            lines++;
          }
          s.seq = max(s.seq, lines);
        }
        s.blobs.removeWhere((_, b) => b.done && !_blobFile(id, b.id).existsSync());
        _spaces[id] = s;
        _used += s.used;
      } catch (err) {
        stderr.writeln('files: $id/meta.json could not be read: $err');
      }
    }
    await sweep();
  }

  void _saveNow(_Space s) {
    s.saver?.cancel();
    s.saver = null;
    // A space removed meanwhile is not brought back by a save that was still to come.
    if (s.removed) return;
    try {
      final d = _dirOf(s.id)..createSync(recursive: true);
      final tmp = File('${d.path}/meta.json.tmp')..writeAsStringSync(jsonEncode(s.toJson()));
      tmp.renameSync('${d.path}/meta.json');
    } catch (err) {
      stderr.writeln('files: ${s.id.substring(0, 6)}/meta.json could not be written: $err');
    }
  }

  void _saveSoon(_Space s) {
    if (s.removed) return;
    s.saver?.cancel();
    s.saver = Timer(const Duration(seconds: 2), () => _saveNow(s));
  }

  // --- answering -------------------------------------------------------------------------------------------------------

  Future<void> _answer(HttpRequest r, int status, [Map<String, Object?>? body]) async {
    try {
      r.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..headers.set('Cache-Control', 'no-store')
        ..write(jsonEncode(body ?? const {}));
      await r.response.close();
    } catch (_) {}
  }

  Future<void> _refuse(HttpRequest r, int status, String why) => _answer(r, status, {'err': why});

  /// How long a body may pause between pieces before the request is given up on: a body trickled a byte at a time
  /// would otherwise hold its blob (and a connection) for ever.
  static const bodyPause = Duration(seconds: 30);

  /// Reads a small body whole: null where it is longer than [most].
  Future<List<int>?> _small(HttpRequest r, int most) async {
    if (r.contentLength > most) return null;
    final out = BytesBuilder(copy: false);
    await for (final piece in r.timeout(bodyPause)) {
      out.add(piece);
      if (out.length > most) return null;
    }
    return out.takeBytes();
  }

  /// Who signed [r], having checked their signature over [bodySha]: null where it does not check out.
  _Who? _who(HttpRequest r, String bodySha) {
    try {
      final key = base64Decode(r.headers.value('x-ghost-key') ?? '');
      final sig = base64Decode(r.headers.value('x-ghost-sig') ?? '');
      final time = int.parse(r.headers.value('x-ghost-time') ?? '');
      final now = _now().millisecondsSinceEpoch;
      if ((now - time).abs() > skew.inMilliseconds) return null;
      final words = signedWords(r.method, r.uri.toString(), time, bodySha);
      // Remembered by what was signed, not by the signature: a signature has a twin (s and n - s) that checks out as
      // well, which a cache of signatures would let through once more.
      final said = hexOf(sha256([...key, ...utf8.encode(words)]));
      if (_replays.containsKey(said)) return null;
      // Full (a flood of fresh keys): no write is taken until it empties, rather than forgetting recent ones, which
      // would let a captured request be sent again.
      if (_replays.length >= 100000) return null;
      if (!P256.verify(key, utf8.encode(words), sig)) return null;
      _replays[said] = time;
      return _Who(hexOf(sha256(key).sublist(0, 16)), hexOf(key));
    } catch (_) {
      return null;
    }
  }

  /// Whether [id] may write once more this minute.
  bool _allowed(String id) {
    final minute = _now().millisecondsSinceEpoch ~/ 60000;
    if (minute != _minute) {
      _minute = minute;
      _writes.clear();
    }
    final n = (_writes[id] ?? 0) + 1;
    _writes[id] = n;
    return n <= config.writesPerMinute;
  }

  /// Takes a request under `/files` (the relay hands over any address whose first part is `files`).
  Future<void> handle(HttpRequest r) async {
    try {
      await _handle(r);
    } catch (err) {
      _say('error: $err');
      await _refuse(r, HttpStatus.internalServerError, 'Something went wrong.');
    }
  }

  Future<void> _handle(HttpRequest r) async {
    final parts = r.uri.pathSegments.where((s) => s.isNotEmpty).skip(1).toList();
    if (parts.isEmpty) {
      return _answer(r, HttpStatus.ok, {'files': 1, 'maxFile': config.maxFile, 'quota': config.spaceQuota});
    }
    final id = parts[0];
    if (!_hex(id, 32)) return _refuse(r, HttpStatus.notFound, 'No such space.');
    final auth = r.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final token = auth.startsWith('Ghost ') ? auth.substring(6).trim() : '';
    if (!_hex(token, 64)) return _refuse(r, HttpStatus.unauthorized, 'No token.');
    final hash = hexOf(sha256(utf8.encode(token)));
    final method = r.method;
    var s = _spaces[id];

    // Making a space, or finding the one there is.
    if (parts.length == 1 && method == 'PUT') {
      final body = await _small(r, 4096);
      if (body == null) return _refuse(r, HttpStatus.requestEntityTooLarge, 'Too big.');
      final who = _who(r, hexOf(sha256(body)));
      if (who == null) return _refuse(r, HttpStatus.unauthorized, 'Bad signature.');
      // The owner the body names is taken only from the owner themselves (the signer's own key): anyone else opening
      // the space first can't make themselves its owner, and the owner opening it later becomes it.
      String named = '';
      try {
        final o = (jsonDecode(utf8.decode(body)) as Map)['owner'];
        if (o is String && RegExp(r'^0[23][0-9a-f]{64}$').hasMatch(o)) named = o;
      } catch (_) {}
      final owner = named == who.key ? named : '';
      if (s != null) {
        if (s.hash != hash) return _refuse(r, HttpStatus.forbidden, 'Refused.');
        if (s.owner.isEmpty && owner.isNotEmpty) {
          s.owner = owner;
          _saveSoon(s);
        }
        _touch(s);
        return _answer(r, HttpStatus.ok, _info(s));
      }
      if (!_allowed(who.id)) return _refuse(r, HttpStatus.tooManyRequests, 'Slow down.');
      if (_spaces.values.where((x) => x.by == who.id).length >= config.spacesPerId) return _refuse(r, HttpStatus.forbidden, 'Too many Files spaces made by this device.');
      // And by address: a fresh key costs nothing, an address does.
      final ip = addressOf(r);
      if (_madeDay != _day()) {
        _madeDay = _day();
        _madeBy.clear();
      }
      if ((_madeBy[ip] ?? 0) >= config.spacesPerAddress) return _refuse(r, HttpStatus.tooManyRequests, 'Too many Files spaces made from here today.');
      if (_spaces.length >= config.maxSpaces) return _refuse(r, HttpStatus.insufficientStorage, 'Full.');
      _madeBy[ip] = (_madeBy[ip] ?? 0) + 1;
      s = _spaces[id] = _Space(id: id, hash: hash, owner: owner, by: who.id, created: _now().millisecondsSinceEpoch, day: _day());
      Directory('${_dirOf(id).path}/blobs').createSync(recursive: true);
      _saveNow(s);
      _say('${id.substring(0, 6)} made');
      return _answer(r, HttpStatus.created, _info(s));
    }
    if (s == null) return _refuse(r, HttpStatus.notFound, 'No such space.');
    if (s.hash != hash) return _refuse(r, HttpStatus.forbidden, 'Refused.');
    _touch(s);

    if (parts.length == 1) {
      if (method == 'GET') return _answer(r, HttpStatus.ok, _info(s));
      if (method == 'DELETE') {
        final who = _who(r, hexOf(sha256(const [])));
        if (who == null) return _refuse(r, HttpStatus.unauthorized, 'Bad signature.');
        // Only a known owner: with none named, nobody may (not even whoever opened it first, who may not be its owner).
        if (s.owner.isEmpty || who.key != s.owner) return _refuse(r, HttpStatus.forbidden, 'Only the space\'s owner can remove it.');
        _remove(s, 'removed');
        return _answer(r, HttpStatus.ok, {'ok': true});
      }
      return _refuse(r, HttpStatus.methodNotAllowed, 'No.');
    }

    switch (parts[1]) {
      case 'log' when parts.length == 2 && method == 'GET':
        return _readLog(r, s);
      case 'log' when parts.length == 2 && method == 'POST':
        final body = await _small(r, config.maxOp);
        if (body == null || body.isEmpty) return _refuse(r, HttpStatus.requestEntityTooLarge, 'An operation is at most ${config.maxOp} bytes.');
        final who = _who(r, hexOf(sha256(body)));
        if (who == null) return _refuse(r, HttpStatus.unauthorized, 'Bad signature.');
        if (!_allowed(who.id)) return _refuse(r, HttpStatus.tooManyRequests, 'Slow down.');
        if (s.seq >= config.maxOps) return _refuse(r, HttpStatus.insufficientStorage, 'This space\'s list is full.');
        final seq = s.seq + 1;
        final line = utf8.encode('${jsonEncode({'s': seq, 'by': who.id, 'at': _now().millisecondsSinceEpoch, 'o': base64Encode(body)})}\n');
        // The list takes room as its files do: in the space's, in the whole store's, and under a cap of its own.
        if (s.logBytes + line.length > config.maxLogBytes) return _refuse(r, HttpStatus.insufficientStorage, 'This space\'s list is full.');
        if (s.used + line.length > config.spaceQuota) return _refuse(r, HttpStatus.insufficientStorage, 'This space is full.');
        if (_used + line.length > config.total) return _refuse(r, HttpStatus.insufficientStorage, 'The files server is full.');
        final log = File('${_dirOf(s.id).path}/log.jsonl');
        final at = s.logBytes;
        await log.writeAsBytes(line, mode: FileMode.append, flush: true);
        if (s.removed) return _refuse(r, HttpStatus.notFound, 'No such space.');
        final marks = s.marks;
        if ((seq - 1) % _markEvery == 0 && marks != null && marks.length == (seq - 1) ~/ _markEvery) marks.add(at);
        s.seq = seq;
        s.logBytes += line.length;
        s.used += line.length;
        _used += line.length;
        // Its number is its count of lines, read again at a restart: the save need not happen on every line.
        _saveSoon(s);
        return _answer(r, HttpStatus.ok, {'seq': seq});
      case 'blobs' when parts.length == 2 && method == 'POST':
        final body = await _small(r, 1024);
        if (body == null) return _refuse(r, HttpStatus.requestEntityTooLarge, 'Too big.');
        final who = _who(r, hexOf(sha256(body)));
        if (who == null) return _refuse(r, HttpStatus.unauthorized, 'Bad signature.');
        if (!_allowed(who.id)) return _refuse(r, HttpStatus.tooManyRequests, 'Slow down.');
        int size;
        try {
          size = ((jsonDecode(utf8.decode(body)) as Map)['size'] as num).toInt();
        } catch (_) {
          return _refuse(r, HttpStatus.badRequest, 'No size.');
        }
        if (size < 16) return _refuse(r, HttpStatus.badRequest, 'Too small.');
        if (size > config.maxFile) return _refuse(r, HttpStatus.requestEntityTooLarge, 'A file may be at most ${config.maxFile} bytes.');
        if (s.used + size > config.spaceQuota) return _refuse(r, HttpStatus.insufficientStorage, 'This space is full.');
        if (_used + size > config.total) return _refuse(r, HttpStatus.insufficientStorage, 'The files server is full.');
        if (s.blobs.length >= config.maxBlobs) return _refuse(r, HttpStatus.insufficientStorage, 'This space holds as many files as it can.');
        // Room promised and not yet written, per address: a room asked for and never filled holds the store's room
        // from everyone else (it is let go after ten minutes without a byte, a day with some).
        final ip = addressOf(r);
        if (_promisedTo(ip) + size > config.promisedPerAddress) return _refuse(r, HttpStatus.tooManyRequests, 'Too many files on their way from here. Finish those first.');
        final bid = hexOf([for (var i = 0; i < 16; i++) _random.nextInt(256)]);
        final b = s.blobs[bid] = _Blob(id: bid, by: who.id, size: size, at: _now().millisecondsSinceEpoch)..ip = ip;
        s.used += size;
        _used += size;
        Directory('${_dirOf(s.id).path}/blobs').createSync(recursive: true);
        _blobFile(s.id, bid, part: true).writeAsBytesSync(const []);
        _saveNow(s);
        return _answer(r, HttpStatus.created, {'id': b.id, 'have': 0});
      case 'blobs' when parts.length >= 3:
        final b = s.blobs[parts[2]];
        if (b == null) return _refuse(r, HttpStatus.notFound, 'No such file.');
        if (parts.length == 3 && (method == 'GET' || method == 'HEAD')) return _readBlob(r, s, b);
        if (parts.length == 3 && method == 'PUT') return _writeBlob(r, s, b);
        if (parts.length == 3 && method == 'DELETE') {
          final who = _who(r, hexOf(sha256(const [])));
          if (who == null) return _refuse(r, HttpStatus.unauthorized, 'Bad signature.');
          if (who.id != b.by && (s.owner.isEmpty || who.key != s.owner)) return _refuse(r, HttpStatus.forbidden, 'Only whoever added it, or the space\'s owner, can remove it.');
          _dropBlob(s, b);
          _saveNow(s);
          return _answer(r, HttpStatus.ok, {'ok': true});
        }
        if (parts.length == 4 && parts[3] == 'state' && method == 'GET') return _answer(r, HttpStatus.ok, {'have': b.have, 'size': b.size, 'done': b.done});
        if (parts.length == 4 && parts[3] == 'done' && method == 'POST') {
          await _small(r, 1024);
          final who = _who(r, hexOf(sha256(const [])));
          if (who == null) return _refuse(r, HttpStatus.unauthorized, 'Bad signature.');
          if (who.id != b.by) return _refuse(r, HttpStatus.forbidden, 'Not yours.');
          if (b.done) return _answer(r, HttpStatus.ok, {'have': b.have, 'done': true});
          if (b.writing || b.have != b.size) return _refuse(r, HttpStatus.conflict, 'Not all of it is here yet.');
          await _blobFile(s.id, b.id, part: true).rename(_blobFile(s.id, b.id).path);
          b.done = true;
          _saveNow(s);
          return _answer(r, HttpStatus.ok, {'have': b.have, 'done': true});
        }
    }
    return _refuse(r, HttpStatus.notFound, 'No.');
  }

  Map<String, Object?> _info(_Space s) => {
        'seq': s.seq,
        'used': s.used,
        'quota': config.spaceQuota,
        'maxFile': config.maxFile,
        'files': s.blobs.values.where((b) => b.done).length,
        'owner': s.owner,
      };

  void _touch(_Space s) {
    final today = _day();
    if (s.day == today) return;
    s.day = today;
    _saveSoon(s);
  }

  /// A page of the log after `?after=`: at most [page] operations or [pageBytes] of them. Read from the mark nearest
  /// before where it starts ([_Space.marks]), not from the first line, and written out as the lines are on disk
  /// (each is already JSON), never decoded and held as maps: a page of big operations held three times over (maps,
  /// the encoded text, the bytes sent) came to over 100 MB, and a few at once took the relay past its memory.
  Future<void> _readLog(HttpRequest r, _Space s) async {
    final after = max(0, int.tryParse(r.uri.queryParameters['after'] ?? '0') ?? 0);
    final f = File('${_dirOf(s.id).path}/log.jsonl');
    if (after >= s.seq || !f.existsSync()) return _answer(r, HttpStatus.ok, {'ops': const [], 'seq': s.seq, 'more': false});
    if (_readers >= _readersAtOnce) {
      r.response.headers.set('Retry-After', '2');
      return _refuse(r, HttpStatus.serviceUnavailable, 'Busy. Try again in a moment.');
    }
    _readers++;
    try {
      final marks = s.marks ??= await _marksOf(f);
      final k = min(after ~/ _markEvery, marks.length - 1);
      var seq = k * _markEvery;
      final lines = <String>[];
      var bytes = 0;
      var more = false;
      await for (final line in f.openRead(marks[k]).transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        seq++;
        if (seq <= after) continue;
        if (lines.length >= page || (lines.isNotEmpty && bytes + line.length > pageBytes)) {
          more = true;
          break;
        }
        lines.add(line);
        bytes += line.length;
      }
      try {
        r.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..headers.set('Cache-Control', 'no-store')
          ..write('{"ops":[')
          ..write(lines.join(','))
          ..write('],"seq":${s.seq},"more":$more}');
        await r.response.close();
      } catch (_) {}
    } finally {
      _readers--;
    }
  }

  /// Where every [_markEvery]th line of a log starts (the first at 0), from one pass over it.
  Future<List<int>> _marksOf(File f) async {
    final marks = <int>[0];
    var at = 0, n = 0;
    await for (final chunk in f.openRead()) {
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] != 10) continue;
        n++;
        if (n % _markEvery == 0) marks.add(at + i + 1);
      }
      at += chunk.length;
    }
    return marks;
  }

  /// A blob, whole or the part a Range asks for, streamed from the disk.
  Future<void> _readBlob(HttpRequest r, _Space s, _Blob b) async {
    if (!b.done) return _refuse(r, HttpStatus.conflict, 'Not all of it is here yet.');
    final f = _blobFile(s.id, b.id);
    final length = f.lengthSync();
    var start = 0, end = length - 1;
    final range = r.headers.value(HttpHeaders.rangeHeader);
    final m = range == null ? null : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
    if (range != null) {
      if (m == null || (m.group(1)!.isEmpty && m.group(2)!.isEmpty)) return _rangeRefused(r, length);
      // Figures too long to be a number are no range (416), not an error.
      final a = m.group(1)!.isEmpty ? null : int.tryParse(m.group(1)!), z = m.group(2)!.isEmpty ? null : int.tryParse(m.group(2)!);
      if ((m.group(1)!.isNotEmpty && a == null) || (m.group(2)!.isNotEmpty && z == null)) return _rangeRefused(r, length);
      if (a == null) {
        // The last n bytes.
        start = max(0, length - z!);
      } else {
        start = a;
        if (z != null) end = min(end, z);
      }
      if (start >= length || start > end) return _rangeRefused(r, length);
    }
    final res = r.response
      ..statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent
      ..headers.contentType = ContentType.binary
      ..headers.set('Accept-Ranges', 'bytes')
      ..headers.set('Cache-Control', 'no-store')
      ..contentLength = end - start + 1;
    if (range != null) res.headers.set('Content-Range', 'bytes $start-$end/$length');
    if (r.method == 'HEAD') return res.close();
    try {
      await f.openRead(start, end + 1).pipe(res);
    } catch (_) {}
  }

  Future<void> _rangeRefused(HttpRequest r, int length) async {
    r.response
      ..statusCode = HttpStatus.requestedRangeNotSatisfiable
      ..headers.set('Content-Range', 'bytes */$length');
    await r.response.close();
  }

  /// A piece of a blob, at `?offset=` (which must be where it has got to), streamed to the disk and hashed as it goes;
  /// the signature over the hash is checked at the end, and a piece that does not check out is cut back off.
  Future<void> _writeBlob(HttpRequest r, _Space s, _Blob b) async {
    final offset = int.tryParse(r.uri.queryParameters['offset'] ?? '');
    if (b.done) return _answer(r, HttpStatus.conflict, {'err': 'Already finished.', 'have': b.have, 'done': true});
    if (offset == null || offset != b.have || b.writing) return _answer(r, HttpStatus.conflict, {'err': 'Send from where it has got to.', 'have': b.have});
    if (r.contentLength > config.maxBody) return _refuse(r, HttpStatus.requestEntityTooLarge, 'A piece is at most ${config.maxBody} bytes.');
    // Who it is is known only once the body's hash is: the key is checked against the blob's writer first.
    List<int> key;
    try {
      key = base64Decode(r.headers.value('x-ghost-key') ?? '');
    } catch (_) {
      key = const [];
    }
    if (key.isEmpty || hexOf(sha256(key).sublist(0, 16)) != b.by) return _refuse(r, HttpStatus.forbidden, 'Not yours.');
    final idOfWriter = b.by;
    if (!_allowed(idOfWriter)) return _refuse(r, HttpStatus.tooManyRequests, 'Slow down.');
    b.writing = true;
    final file = _blobFile(s.id, b.id, part: true);
    RandomAccessFile? raf;
    var written = 0;
    var tooMuch = false;
    final hash = Sha256();
    try {
      raf = await file.open(mode: FileMode.append);
      await raf.truncate(offset);
      await raf.setPosition(offset);
      await for (final piece in r.timeout(bodyPause)) {
        if (written + piece.length > config.maxBody || offset + written + piece.length > b.size) {
          tooMuch = true;
          break;
        }
        hash.add(piece);
        await raf.writeFrom(piece);
        written += piece.length;
      }
      final who = tooMuch ? null : _who(r, hexOf(hash.close()));
      if (tooMuch || who == null || who.id != b.by) {
        await raf.truncate(offset);
        await raf.close();
        raf = null;
        b.writing = false;
        return await (tooMuch ? _refuse(r, HttpStatus.requestEntityTooLarge, 'More than the file was said to be.') : _refuse(r, HttpStatus.unauthorized, 'Bad signature.'));
      }
      await raf.flush();
      await raf.close();
      raf = null;
      b.writing = false;
      // Removed meanwhile (the space, or the blob): nothing to keep, and no save to bring it back.
      if (s.removed || s.blobs[b.id] != b) return await _refuse(r, HttpStatus.notFound, 'No such file.');
      b.have = offset + written;
      b.at = _now().millisecondsSinceEpoch;
      _saveSoon(s);
      return await _answer(r, HttpStatus.ok, {'have': b.have});
    } catch (err) {
      // Cut short (the phone lost its connection): the piece is cut back off, so what is kept always ends where a whole
      // piece did, at a chunk's edge, which the next try starts from.
      try {
        await raf?.truncate(offset);
        await raf?.close();
      } catch (_) {}
      b.have = offset;
      b.writing = false;
      rethrow;
    }
  }

  void _dropBlob(_Space s, _Blob b) {
    s.blobs.remove(b.id);
    s.used -= b.size;
    _used -= b.size;
    for (final f in [_blobFile(s.id, b.id), _blobFile(s.id, b.id, part: true)]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  void _remove(_Space s, String why) {
    _spaces.remove(s.id);
    s.removed = true;
    s.saver?.cancel();
    _used -= s.used;
    try {
      _dirOf(s.id).deleteSync(recursive: true);
    } catch (_) {}
    _say('${s.id.substring(0, 6)} $why');
  }

  /// Blobs left unfinished for [FilesConfig.partLife], and spaces nobody has opened for [FilesConfig.idleLife].
  Future<void> sweep() async {
    final now = _now();
    final cutoff = now.subtract(config.idleLife).toUtc().toIso8601String().substring(0, 10);
    final stale = now.subtract(config.partLife).millisecondsSinceEpoch;
    for (final s in _spaces.values.toList()) {
      if (s.day.compareTo(cutoff) < 0) {
        _remove(s, 'unused');
        continue;
      }
      // A room promised and never given a byte goes after ten minutes; one with some, after [FilesConfig.partLife].
      final empty = now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch;
      final old = s.blobs.values.where((b) => !b.done && !b.writing && (b.at < stale || (b.have == 0 && b.at < empty))).toList();
      for (final b in old) {
        _dropBlob(s, b);
      }
      if (old.isNotEmpty) _saveNow(s);
    }
    final oldest = now.subtract(skew * 2).millisecondsSinceEpoch;
    _replays.removeWhere((_, at) => at < oldest);
  }
}

/// What the files store may hold, from the environment where it is set (`GHOST_FILES_*`, tool/deploy-relay.mjs).
class FilesConfig {
  const FilesConfig({
    this.maxFile = 2 << 30,
    this.spaceQuota = 2 << 30,
    this.total = 20 << 30,
    this.spacesPerId = 20,
    this.idleDays = 90,
    this.writesPerMinute = 600,
    this.maxBody = 8 << 20,
    this.maxOp = 32 << 10,
    this.maxOps = 20000,
    this.maxLogBytes = 16 << 20,
    this.maxBlobs = 10000,
    this.maxSpaces = 100000,
    this.partHours = 24,
    this.spacesPerAddress = 20,
    this.promisedPerAddress = 4 << 30,
  });

  /// The largest blob (a sealed file: its size and 16 bytes a chunk), in bytes.
  final int maxFile;

  /// What one space may hold, in bytes.
  final int spaceQuota;

  /// What every space together may hold, in bytes: the box's disk is shared with everything else on it.
  final int total;

  /// How many spaces one device's key may make.
  final int spacesPerId;
  final int idleDays;
  final int writesPerMinute;

  /// The most one request may carry: a file goes up as a run of pieces no bigger than this.
  final int maxBody;

  /// The largest sealed operation in a space's log: room for a file's description with its small picture (at most
  /// 18 KB, about 24 KB as base64) and no more.
  final int maxOp;
  final int maxOps;

  /// The most a space's log may hold on disk, in bytes; it counts against [spaceQuota] and [total] too.
  final int maxLogBytes;

  /// How many spaces one address may make in a day, and how many bytes of unfinished files it may have promised.
  final int spacesPerAddress;
  final int promisedPerAddress;
  final int maxBlobs;
  final int maxSpaces;
  final int partHours;

  Duration get idleLife => Duration(days: idleDays);
  Duration get partLife => Duration(hours: partHours);

  factory FilesConfig.fromEnvironment(Map<String, String> env) {
    int read(String name, int fallback) {
      final v = int.tryParse(env[name]?.trim() ?? '');
      return v == null || v <= 0 ? fallback : v;
    }

    const d = FilesConfig();
    return FilesConfig(
      maxFile: read('GHOST_FILES_MAX_FILE', d.maxFile),
      spaceQuota: read('GHOST_FILES_SPACE_QUOTA', d.spaceQuota),
      total: read('GHOST_FILES_TOTAL', d.total),
      spacesPerId: read('GHOST_FILES_SPACES_PER_ID', d.spacesPerId),
      idleDays: read('GHOST_FILES_IDLE_DAYS', d.idleDays),
      writesPerMinute: read('GHOST_FILES_WRITES_PER_MINUTE', d.writesPerMinute),
    );
  }
}

class _Who {
  _Who(this.id, this.key);

  /// The hub name of the key, and the key in hex.
  final String id;
  final String key;
}

class _Space {
  _Space({required this.id, required this.hash, required this.owner, required this.by, required this.created, required this.day, this.seq = 0});
  final String id;

  /// SHA-256 of its token, in hex.
  final String hash;

  /// The owner's public key (hex), who may remove anyone's file; empty until the owner opens it themselves.
  String owner;

  /// The hub name of the device that made it.
  final String by;
  final int created;

  /// The day (UTC) it was last opened.
  String day;
  int seq;
  int used = 0;

  /// How many bytes its log holds (counted in [used] too).
  int logBytes = 0;

  /// Where every few lines of its log start (Files._marksOf); null until a page is first read.
  List<int>? marks;

  /// Taken away: a save still to come does nothing.
  bool removed = false;
  final Map<String, _Blob> blobs = {};
  Timer? saver;

  Map<String, Object?> toJson() => {
        'v': 1,
        'h': hash,
        'o': owner,
        'by': by,
        'c': created,
        'd': day,
        'seq': seq,
        'blobs': [for (final b in blobs.values) b.toJson()],
      };

  factory _Space.fromJson(String id, Map j) {
    final s = _Space(id: id, hash: j['h'] as String, owner: (j['o'] as String?) ?? '', by: (j['by'] as String?) ?? '', created: (j['c'] as num?)?.toInt() ?? 0, day: j['d'] as String, seq: (j['seq'] as num?)?.toInt() ?? 0);
    for (final b in (j['blobs'] as List? ?? const [])) {
      final blob = _Blob.fromJson(b as Map);
      s.blobs[blob.id] = blob;
      s.used += blob.size;
    }
    return s;
  }
}

class _Blob {
  _Blob({required this.id, required this.by, required this.size, required this.at, this.have = 0, this.done = false});
  final String id;
  final String by;
  final int size;
  int have;
  bool done;

  /// When it was last written to (ms): one being written that has gone quiet for a day is let go.
  int at;
  bool writing = false;

  /// The address its room was asked for from (not kept: it only limits what one address has going).
  String ip = '';

  Map<String, Object?> toJson() => {'id': id, 'by': by, 'z': size, 'h': have, if (done) 'done': 1, 'at': at};
  factory _Blob.fromJson(Map j) =>
      _Blob(id: j['id'] as String, by: j['by'] as String, size: (j['z'] as num).toInt(), have: (j['h'] as num?)?.toInt() ?? 0, done: j['done'] == 1, at: (j['at'] as num?)?.toInt() ?? 0);
}
