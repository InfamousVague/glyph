import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' show SHA256Digest;

import '../desktop/store.dart' show DeskStore;
import '../me/me.dart';
import '../net/crypto.dart';
import '../net/file_seal.dart';
import '../net/hub_carrier.dart' show NetSigner;
import '../voice/channels.dart';
import '../voice/roles.dart';
import '../voice/voice.dart';
import 'file_kinds.dart';
import 'files_api.dart';
import 'files_model.dart';

export 'file_kinds.dart';
export 'files_api.dart' show FilesError, FilesInfo;
export 'files_model.dart';

/// A Files space's files on this device (Matt, 2026-11-17: "add full functionality for filesharing in a space when the
/// space is designated a Files Space"): the list each space's log makes, files going up and coming down with their
/// progress, and what is kept between runs.
///
/// - **The list** is the space's log on the relay (relay/lib/files.dart), read from where this device last got to and
///   kept on disk, so the list shows at once and offline. Each entry is opened with the space's files key and read
///   under the space's roles ([RosterRules]): every device reads the same log under the same roster and gets the same
///   list. Someone without the right to rename or remove a file has their entry skipped everywhere.
/// - **Live.** When a device adds to the log it says `{"t": "files", "seq": n}` in the space's chat room, sealed with
///   the space's key; everyone with the space open reads the log again. An older build ignores the word. A device that
///   was away catches up from its last number on opening, and an open space looks again every [poll] besides.
/// - **Going up** ([upload]): one file at a time, sealed in chunks (lib/net/file_seal.dart) a few megabytes a request.
///   The queue is kept on disk, so a file half sent when the app closes picks up where the relay says it got to.
///   On a phone the picked file is first copied into the app's own folder ([FilePlatform.keep]), since Android's
///   permission to read what was picked ends with the app. Once it is all there it is added to the log, and a line is
///   said in the space's chat ("Maya added report.pdf (2.1 MB)") so older builds see something.
/// - **Coming down** ([fetch]): opened chunk by chunk into a file of its own as it comes, so a download cut short goes on
///   from the last whole chunk, then checked against the SHA-256 its description gives.
class FilesStore extends ChangeNotifier {
  FilesStore._({
    required Uri? Function() base,
    required NetSigner? Function() signer,
    required String? Function() me,
    required Directory Function() data,
    required Directory Function() cache,
    required VoiceRoute? Function() route,
    required FilesRules Function(VoiceChannel c) rules,
    required String Function() myName,
    void Function(VoiceChannel c, String words)? announce,
    this.thumbnails = true,
    this.piece = 16,
    this.poll = const Duration(seconds: 45),
  })  : _base = base,
        _signer = signer,
        _me = me,
        _data = data,
        _cache = cache,
        _route = route,
        _rules = rules,
        _myName = myName,
        _announce = announce;

  /// The app's: the relay the spaces' rooms are on, this install's hub key, the space's roster.
  static FilesStore instance = FilesStore._live();

  factory FilesStore._live() => FilesStore._(
        base: () {
          final r = Voice.instance.route;
          final hub = r is HubVoiceRoute ? r.hub.url : null;
          return hub == null ? null : FilesApi.baseFor(hub);
        },
        signer: () => Voice.instance.signer,
        me: () => Voice.instance.me,
        data: () => Directory('${_appDir().path}/space-files'),
        cache: () => Directory('${_cacheDir().path}/space-files'),
        route: () => Voice.instance.route,
        rules: (c) {
          final room = Voice.instance.hangoutFor(c);
          return room == null ? OwnerRules(_ownerId(c)) : RosterRules(room.roster);
        },
        myName: _myNameOf,
        announce: (c, words) {
          final room = Voice.instance.hangoutFor(c);
          if (room != null && room.opened && room.can(Perm.chat)) room.send(words);
        },
      );

  /// For a test: a store on [base] (a relay of the test's own), signing with [signer], keeping things in [data].
  @visibleForTesting
  factory FilesStore.forTest({
    required Uri? base,
    required NetSigner signer,
    required Directory data,
    Directory? cache,
    VoiceRoute? route,
    FilesRules Function(VoiceChannel c)? rules,
    String name = 'Tester',
    int piece = 16,
    Duration poll = const Duration(seconds: 45),
    void Function(VoiceChannel c, String words)? announce,
  }) =>
      FilesStore._(
        base: () => base,
        signer: () => signer,
        me: () => signer.id,
        data: () => data,
        cache: () => cache ?? Directory('${data.path}/cache'),
        route: () => route,
        rules: rules ?? (c) => OwnerRules(_ownerId(c)),
        myName: () => name,
        announce: announce,
        thumbnails: false,
        piece: piece,
        poll: poll,
      );

  final Uri? Function() _base;
  final NetSigner? Function() _signer;
  final String? Function() _me;
  final Directory Function() _data;
  final Directory Function() _cache;
  final VoiceRoute? Function() _route;
  final FilesRules Function(VoiceChannel c) _rules;
  final String Function() _myName;
  final void Function(VoiceChannel c, String words)? _announce;

  /// Small pictures of pictures added (dart:ui): off in a test without an engine.
  final bool thumbnails;

  /// How many chunks go up in one request (16 of 256 KB: 4 MB, under the relay's 8 MB a request).
  final int piece;
  final Duration poll;

  static String? _ownerId(VoiceChannel c) => c.owner.isEmpty ? null : NetCrypto.idOf(NetCrypto.unhex(c.owner));

  static String _myNameOf() {
    final v = Voice.instance;
    // What this device's hangout rooms are told it is called.
    for (final c in v.channels) {
      final room = v.hangoutFor(c);
      if (room != null && room.name.isNotEmpty) return room.name;
    }
    final me = Me.instance;
    return me.displayName.isNotEmpty ? me.displayName : (me.username == null ? '' : '@${me.username}');
  }

  static Directory _appDir() {
    if (Platform.isAndroid) return Directory('${Directory.systemTemp.parent.path}/files');
    return DeskStore.defaultDir();
  }

  static Directory _cacheDir() {
    if (Platform.isAndroid) return Directory.systemTemp;
    final home = Platform.environment['HOME'];
    if (Platform.isMacOS && home != null) return Directory('$home/Library/Caches/Ghost Messaging');
    return Directory('${DeskStore.defaultDir().path}/cache');
  }

  final Map<String, FilesSpace> _spaces = {};

  /// Files going up and coming down, oldest first.
  final List<Transfer> transfers = [];
  bool _started = false;

  /// The space [c]'s files as this device has them.
  FilesSpace of(VoiceChannel c) => _spaces.putIfAbsent(c.seed, () => FilesSpace._(c, this).._load());

  /// How many files [c] holds, where its list is already held on this device (opened or read once); null where not.
  /// Reads nothing from disk, so a circle's list can show it on every rebuild.
  int? heldCount(VoiceChannel c) {
    final s = _spaces[c.seed];
    return s == null || !s.ready ? null : s.files.length;
  }

  /// For a picture or a test: [files] as [c]'s, with no relay.
  @visibleForTesting
  void put(VoiceChannel c, List<SpaceFile> files, {Set<String> folders = const {}, FilesInfo? info}) {
    final s = of(c);
    var seq = 0;
    s._log = [
      for (final f in files) LoggedOp(seq: ++seq, by: f.by, at: f.at, op: FileOp.add(f)),
      for (final d in folders) LoggedOp(seq: ++seq, by: f0(files)?.by ?? '', at: 0, op: FileOp.folder(d)),
    ];
    s.seq = seq;
    s.info = info;
    s._reread();
    s._kept = true;
    notifyListeners();
  }

  static SpaceFile? f0(List<SpaceFile> files) => files.firstOrNull;

  /// For a picture or a test: a transfer shown as it would be.
  @visibleForTesting
  void putTransfer(Transfer t) {
    transfers.add(t);
    notifyListeners();
  }

  /// For a test: everything forgotten.
  @visibleForTesting
  Future<void> clear() async {
    for (final s in _spaces.values) {
      s._dispose();
    }
    _spaces.clear();
    for (final t in transfers) {
      t._cancel = true;
    }
    transfers.clear();
    _started = false;
    notifyListeners();
  }

  /// Picks up what was going up when the app last closed.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final f = File('${_data().path}/queue.json');
      if (f.existsSync()) {
        for (final j in (jsonDecode(await f.readAsString()) as List)) {
          final t = Transfer._fromJson(j);
          if (t != null && !transfers.any((x) => x.id == t.id)) transfers.add(t);
        }
      }
    } catch (_) {}
    if (transfers.isNotEmpty) {
      notifyListeners();
      _pump();
    }
    // The relay coming (or a computer's own hub connecting): what waited for it goes on.
    if (identical(this, instance)) Voice.instance.addListener(_voiceChanged);
  }

  void _voiceChanged() {
    if (_base() == null) return;
    for (final s in _spaces.values.where((s) => s._holds > 0)) {
      s._listen();
      // Voice says something changed many times a minute: an unreachable relay is asked again at most every ten seconds.
      final due = DateTime.now().difference(s._tried) > const Duration(seconds: 10);
      if (s._waiting || (due && s.error != null && s.error!.offline)) unawaited(s.refresh());
    }
    final waiting = transfers.where((t) => t.up && t.state == TransferState.waiting).toList();
    for (final t in waiting) {
      t.state = TransferState.queued;
    }
    if (waiting.isNotEmpty) _pump();
  }

  Timer? _notifySoon;

  void _changed() => notifyListeners();

  /// Told at most every 120 ms while a transfer moves.
  void _moved() {
    _notifySoon ??= Timer(const Duration(milliseconds: 120), () {
      _notifySoon = null;
      notifyListeners();
    });
  }

  Future<void> _saveQueue() async {
    try {
      final d = _data()..createSync(recursive: true);
      final tmp = File('${d.path}/queue.json.tmp');
      await tmp.writeAsString(jsonEncode([for (final t in transfers) if (t.up && t.state != TransferState.done) t._toJson()]));
      await tmp.rename('${d.path}/queue.json');
    } catch (_) {}
  }

  final Map<String, FilesApi> _apis = {};

  FilesApi? _api(VoiceChannel c) {
    final base = _base();
    final signer = _signer();
    if (base == null || signer == null) return null;
    final room = FileSeal.filesRoom(c.seed);
    final had = _apis[room];
    if (had != null && had.base == base && identical(had.signer, signer)) return had;
    // The one it replaces lets its connections go, rather than keeping them open for as long as the app runs.
    had?.closeIdle();
    return _apis[room] = FilesApi(base: base, space: room, token: FileSeal.filesToken(c.seed), signer: signer);
  }

  /// Opens [c] while something shows it: its list read and kept current. [close] when done.
  Future<void> open(VoiceChannel c) async {
    final s = of(c);
    s._holds++;
    s._listen();
    s._poller ??= Timer.periodic(poll, (_) => unawaited(s.refresh()));
    await s.refresh();
  }

  void close(VoiceChannel c) {
    final s = _spaces[c.seed];
    if (s == null || s._holds == 0) return;
    if (--s._holds == 0) {
      s._poller?.cancel();
      s._poller = null;
      s._sub?.cancel();
      s._sub = null;
    }
  }

  /// Whether this device may add files to [c].
  bool canUpload(VoiceChannel c) {
    final me = _me();
    return me == null || _rules(c).mayAdd(me);
  }

  /// Whether this device may rename, move or remove [f].
  bool canChange(VoiceChannel c, SpaceFile f) {
    final me = _me();
    return me != null && _rules(c).mayChange(me, f);
  }

  bool canFolder(VoiceChannel c) {
    final me = _me();
    return me != null && _rules(c).mayFolder(me);
  }

  // --- the log -----------------------------------------------------------------------------------------------------

  Future<bool> _write(VoiceChannel c, Map<String, Object?> op) async {
    final api = _api(c);
    final s = of(c);
    if (api == null) {
      s.error = FilesError(0, 'Not connected to the relay yet.');
      notifyListeners();
      return false;
    }
    try {
      await s._ensure(api);
      final seq = await api.append(FileOp.seal(FileSeal.filesKey(c.seed), op));
      await s.refresh();
      _ping(c, seq);
      return true;
    } on FilesError catch (e) {
      s.error = e;
      notifyListeners();
      return false;
    }
  }

  /// Tells everyone with [c] open that its log has [seq] now.
  void _ping(VoiceChannel c, int seq) {
    try {
      _route()?.send(c.chatRoom, NetCrypto.seal(c.key, utf8.encode(jsonEncode({'t': 'files', 'seq': seq}))));
    } catch (_) {}
  }

  Future<bool> rename(VoiceChannel c, SpaceFile f, String name) async {
    final n = SpaceFile.cleanName(name);
    if (n.isEmpty || n == f.name || !canChange(c, f)) return false;
    return _write(c, FileOp.rename(f.id, n));
  }

  Future<bool> move(VoiceChannel c, SpaceFile f, String? folder) async {
    final d = SpaceFile.cleanFolder(folder);
    if (d == f.folder || !canChange(c, f)) return false;
    return _write(c, FileOp.move(f.id, d));
  }

  Future<bool> newFolder(VoiceChannel c, String name) async {
    final d = SpaceFile.cleanFolder(name);
    if (d == null || of(c).folders.contains(d)) return false;
    return _write(c, FileOp.folder(d));
  }

  Future<bool> removeFolder(VoiceChannel c, String name) => _write(c, FileOp.unfolder(name));

  /// Removes [f] from the list, and its sealed blob from the relay where this device may (whoever added it, or the
  /// space's owner: the relay holds to that). Someone with Manage files above the uploader takes it off everyone's list;
  /// the relay lets the blob go once the space is unused.
  Future<bool> delete(VoiceChannel c, SpaceFile f) async {
    if (!canChange(c, f)) return false;
    final ok = await _write(c, FileOp.delete(f.id));
    if (!ok) return false;
    final me = _me();
    if (me == f.by || me == _ownerId(c)) {
      try {
        await _api(c)?.deleteBlob(f.id);
      } catch (_) {}
    }
    _forgetCached(f);
    return true;
  }

  // --- going up ------------------------------------------------------------------------------------------------------

  /// Adds files at [paths] (on this device) to [c], in [folder]. [owned] marks copies the app made (a phone's picks),
  /// which go once they are up.
  void upload(VoiceChannel c, List<String> paths, {String? folder, bool owned = false}) {
    for (final p in paths) {
      final f = File(p);
      if (!f.existsSync()) continue;
      final name = SpaceFile.cleanName(p.split(Platform.pathSeparator).last.split('/').last);
      transfers.add(Transfer._up(
        space: c,
        path: p,
        name: name.isEmpty ? 'File' : name,
        size: f.lengthSync(),
        mime: FileKind.mimeOf(name),
        folder: SpaceFile.cleanFolder(folder),
        owned: owned,
      ));
    }
    notifyListeners();
    unawaited(_saveQueue());
    _pump();
  }

  bool _pumping = false;

  void _pump() {
    if (_pumping) return;
    _pumping = true;
    unawaited(() async {
      try {
        while (true) {
          // Waiting ones are tried again by the timer below, not at once.
          final t = transfers.where((t) => t.up && t.state == TransferState.queued && !t._cancel).firstOrNull;
          if (t == null) break;
          await _runUpload(t);
        }
      } finally {
        _pumping = false;
      }
      // What waits for the relay is tried again in a while.
      final waiting = transfers.where((t) => t.up && t.state == TransferState.waiting && !t._held).toList();
      if (waiting.isNotEmpty) {
        for (final t in waiting) {
          t._held = true;
        }
        Timer(Duration(seconds: math.min(60, 5 * (1 << math.min(4, waiting.first.tries - 1)))), () {
          for (final t in waiting) {
            t._held = false;
            if (t.state == TransferState.waiting && !t._cancel) t.state = TransferState.queued;
          }
          _pump();
        });
      }
    }());
  }

  Future<void> _runUpload(Transfer t) async {
    final c = t.space;
    final api = _api(c);
    if (api == null) {
      t._wait('Waiting for the relay');
      notifyListeners();
      return;
    }
    final file = File(t.path!);
    if (!file.existsSync()) {
      t._fail('The file isn\'t there any more.');
      await _settle(t);
      return;
    }
    t.state = TransferState.running;
    t.error = null;
    notifyListeners();
    final s = of(c);
    try {
      await s._ensure(api);
      // Failures no retry can mend say so (no Try again): a file over the limit, and a space without the room for it.
      // The limit is said per file, so it does not read as the space's own room (the storage bar shows that).
      if (s.info != null && s.info!.maxFile > 0 && FileSeal.sealedSize(t.size) > s.info!.maxFile) {
        t._fail('Too big: files can be up to ${fileSize(s.info!.maxFile)} each.', retryable: false);
        await _settle(t);
        return;
      }
      if (t.blob == null && s.info != null && s.info!.quota > 0 && s.info!.used + FileSeal.sealedSize(t.size) > s.info!.quota) {
        t._fail('Not enough room left in this space.', retryable: false);
        await _settle(t);
        return;
      }
      // The same file as when it was sealed before, or nothing is sent: a chunk sealed again under its nonce must say
      // the same words, or the key would be given away.
      final modified = file.lastModifiedSync().millisecondsSinceEpoch;
      if (t.sha != null && (t.modified != modified || file.lengthSync() != t.size)) {
        t._fail('The file changed while it was going up. Add it again.');
        await _settle(t);
        return;
      }
      t.modified = modified;
      if (t.sha == null) {
        t.status = 'Getting it ready';
        notifyListeners();
        final path = t.path!;
        t.sha = await _shaAside(path);
        t.fileKey ??= NetCrypto.randomBytes(32);
        t.prefix ??= NetCrypto.randomBytes(8);
        if (thumbnails && FileKind.of(t.name, t.mime) == FileKind.image && t.size <= 40 << 20) {
          final made = await _thumbnail(path);
          t.thumb = made?.png;
          t.width = made?.width ?? 0;
          t.height = made?.height ?? 0;
        }
        await _saveQueue();
      }
      final sealed = FileSeal.sealedSize(t.size);
      var have = 0;
      if (t.blob != null) {
        try {
          final st = await api.state(t.blob!);
          have = st.done ? sealed : st.have;
        } on FilesError catch (e) {
          // Let go of by the relay (a day unfinished): started again.
          if (e.status != HttpStatus.notFound) rethrow;
          t.blob = null;
        }
      }
      t.blob ??= await api.newBlob(sealed);
      await _saveQueue();
      // Picking up part way on a file this app doesn't hold its own copy of (a computer's own file, where it lies): the
      // chunks still to go are sealed under the same key and nonces as before, so they must be the same words. A file
      // changed in place keeps its length and, on some disks, its time; only its hash tells. Changed, it is not sent on
      // (sealing other words under a nonce already used would give the key away).
      Future<bool> unchanged() async => t.owned || await _shaAside(t.path!) == t.sha;
      if (have > 0 && !await unchanged()) {
        t._fail('The file changed while it was going up. Add it again.', retryable: false);
        await _settle(t);
        return;
      }
      t.status = null;
      final raf = await file.open();
      try {
        const step = FileSeal.chunk + FileSeal.tag;
        while (have < sealed) {
          if (t._cancel) break;
          final first = have ~/ step;
          final count = math.min(piece, FileSeal.chunks(t.size) - first);
          final from = first * FileSeal.chunk;
          final length = math.min(t.size - from, count * FileSeal.chunk);
          await raf.setPosition(from);
          final plain = await raf.read(length);
          if (plain.length != length) throw const FileSystemException('The file changed while it was going up.');
          final run = SealRun(key: t.fileKey!, prefix: t.prefix!, fileId: t.blob!, size: t.size, first: first, plain: plain);
          final sealedRun = run.plain.length > 64 * 1024 ? await _sealAside(run) : FileSeal.sealRun(run);
          // Where the relay has part of a chunk (a restart in the middle of a write), the rest of it: sealing the same
          // chunk again under the same nonce gives the same bytes, so what was there joins up with what follows.
          final skip = have - first * step;
          final bytes = skip > 0 ? Uint8List.sublistView(sealedRun, skip) : sealedRun;
          try {
            have = await api.put(t.blob!, have, bytes);
          } on FilesError catch (e) {
            if (e.status == HttpStatus.conflict && e.have != null) {
              // Told to go back (the relay kept less than was sent): what is sealed again must be what was.
              if (e.have! < have && !await unchanged()) throw const FileSystemException('The file changed while it was going up. Add it again.');
              have = e.have!;
              continue;
            }
            rethrow;
          }
          t.done = math.min(t.size, (have / sealed * t.size).round());
          _moved();
        }
      } finally {
        await raf.close();
      }
      if (t._cancel) return;
      await api.done(t.blob!);
      final me = _signer()!.id;
      final f = SpaceFile(
        id: t.blob!,
        name: t.name,
        size: t.size,
        mime: t.mime,
        sha: t.sha!,
        key: t.fileKey!,
        prefix: t.prefix!,
        by: me,
        byName: _myName(),
        at: DateTime.now().millisecondsSinceEpoch,
        folder: t.folder,
        thumb: t.thumb,
        width: t.width,
        height: t.height,
      );
      final seq = await api.append(FileOp.seal(FileSeal.filesKey(c.seed), FileOp.add(f)));
      // This device has the file already: kept as if it had come down, so it opens at once.
      await _keepLocal(t, f);
      // Listed before it is called done: whoever watches the upload finds the file in the list once it is.
      await s.refresh();
      t.state = TransferState.done;
      t.done = t.size;
      _ping(c, seq);
      _announce?.call(c, '${f.byName.isEmpty ? 'Someone' : f.byName} added ${f.name} (${fileSize(f.size)})');
      await _settle(t);
    } on FilesError catch (e) {
      if (e.offline || e.status >= 500 && e.status != HttpStatus.insufficientStorage) {
        t._wait(e.message);
      } else if (e.status == HttpStatus.requestEntityTooLarge) {
        t._fail(s.info != null && s.info!.maxFile > 0 ? 'Too big: files can be up to ${fileSize(s.info!.maxFile)} each.' : 'Too big for this space.', retryable: false);
        await _settle(t);
      } else if (e.status == HttpStatus.insufficientStorage && e.message.contains('This space')) {
        t._fail('Not enough room left in this space.', retryable: false);
        await _settle(t);
      } else {
        t._fail(e.message);
        await _settle(t);
      }
      notifyListeners();
    } on FileSystemException catch (e) {
      t._fail(e.message.isEmpty ? 'The file couldn\'t be read.' : e.message);
      await _settle(t);
    }
  }

  /// A finished or failed upload: off the queue on disk, and (done) off the list a moment later.
  Future<void> _settle(Transfer t) async {
    await _saveQueue();
    notifyListeners();
    if (t.state == TransferState.done) {
      if (t.owned) _deleteQuietly(t.path!);
      Timer(const Duration(seconds: 3), () {
        transfers.remove(t);
        notifyListeners();
      });
    }
  }

  Future<void> _keepLocal(Transfer t, SpaceFile f) async {
    try {
      final at = File(cachedPath(f));
      await at.parent.create(recursive: true);
      if (t.owned) {
        await File(t.path!).rename(at.path);
      } else if (t.size <= 64 << 20) {
        await File(t.path!).copy(at.path);
      }
    } catch (_) {}
  }

  /// Stops [t]: an upload's blob is let go on the relay; a download's part is deleted.
  Future<void> cancel(Transfer t) async {
    t._cancel = true;
    transfers.remove(t);
    notifyListeners();
    if (t.up) {
      await _saveQueue();
      if (t.blob != null) {
        try {
          await _api(t.space)?.deleteBlob(t.blob!);
        } catch (_) {}
      }
      if (t.owned) _deleteQuietly(t.path!);
    } else {
      final f = t.file;
      if (f != null) _deleteQuietly(_partPath(f));
      t._done?.completeError(FilesError(-1, 'Stopped.'));
      _downloads.remove(t.file?.id);
    }
  }

  /// Tries [t] again where it failed.
  void retry(Transfer t) {
    if (!t.up) return;
    t.state = TransferState.queued;
    t.error = null;
    t.tries = 0;
    notifyListeners();
    _pump();
  }

  // --- coming down ---------------------------------------------------------------------------------------------------

  /// Where [f] is kept on this device once it has come down: a folder of its own, under its own name.
  String cachedPath(SpaceFile f) => '${_cache().path}/${f.id}/${f.name.replaceAll(RegExp(r'[/\\:]'), '_')}';
  String _partPath(SpaceFile f) => '${_cache().path}/${f.id}.part';

  /// [f]'s file on this device, where it has come down already.
  String? cached(SpaceFile f) {
    final p = cachedPath(f);
    if (File(p).existsSync()) return p;
    // Renamed since it came down: the one there under its old name.
    final dir = Directory('${_cache().path}/${f.id}');
    if (!dir.existsSync()) return null;
    final other = dir.listSync().whereType<File>().firstOrNull;
    if (other == null) return null;
    try {
      return other.renameSync(p).path;
    } catch (_) {
      return other.path;
    }
  }

  void _forgetCached(SpaceFile f) {
    try {
      final dir = Directory('${_cache().path}/${f.id}');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
    _deleteQuietly(_partPath(f));
  }

  final Map<String, Transfer> _downloads = {};

  /// The download of [f] under way, if one is.
  Transfer? downloading(SpaceFile f) => _downloads[f.id];

  /// [f] on this device: there already, or brought down (its progress in [transfers]). Its path.
  Future<String> fetch(VoiceChannel c, SpaceFile f) {
    final have = cached(f);
    if (have != null) return Future.value(have);
    final going = _downloads[f.id];
    if (going != null) return going._done!.future;
    final t = Transfer._down(space: c, file: f);
    _downloads[f.id] = t;
    transfers.add(t);
    notifyListeners();
    unawaited(_runDownload(t));
    return t._done!.future;
  }

  Future<void> _runDownload(Transfer t) async {
    final c = t.space;
    final f = t.file!;
    final api = _api(c);
    if (api == null) {
      _endDownload(t, error: FilesError(0, 'Not connected to the relay yet.'));
      return;
    }
    final part = File(_partPath(f));
    RandomAccessFile? out;
    try {
      await part.parent.create(recursive: true);
      out = await part.open(mode: FileMode.append);
      final chunks = FileSeal.chunks(f.size, chunkSize: f.chunk);
      // What came before: whole chunks only.
      var whole = (await out.length()) ~/ f.chunk;
      if (whole >= chunks) whole = chunks - 1;
      await out.truncate(whole * f.chunk);
      await out.setPosition(whole * f.chunk);
      t.done = whole * f.chunk;
      t.state = TransferState.running;
      _moved();
      final stream = await api.read(f.id, start: FileSeal.sealedOffset(whole, chunkSize: f.chunk));
      final step = f.chunk + FileSeal.tag;
      final lastLen = FileSeal.plainLength(chunks - 1, f.size, chunkSize: f.chunk) + FileSeal.tag;
      // Opened up to 16 chunks at a time (4 MB) as they come: the next piece is not read while a lot is being opened.
      int lotOf(int i) => math.min(16, chunks - i);
      int bytesOf(int i) => lotOf(i) == chunks - i ? (lotOf(i) - 1) * step + lastLen : lotOf(i) * step;
      final buffer = BytesBuilder(copy: false);
      var index = whole;
      await for (final piece in stream) {
        if (t._cancel) throw FilesError(-1, 'Stopped.');
        buffer.add(piece);
        while (index < chunks && buffer.length >= bytesOf(index)) {
          final need = bytesOf(index), lot = lotOf(index), first = index;
          final bytes = buffer.takeBytes();
          buffer.add(Uint8List.sublistView(bytes, need));
          final run = OpenRun(key: f.key, prefix: f.prefix, fileId: f.id, size: f.size, first: first, sealed: Uint8List.sublistView(bytes, 0, need), chunkSize: f.chunk);
          final plain = need > 64 * 1024 ? await _openAside(run) : FileSeal.openRun(run);
          if (plain == null) throw FilesError(-2, 'The file didn\'t open: it was changed on the way, or isn\'t whole.');
          await out.writeFrom(plain);
          index += lot;
          t.done = math.min(f.size, t.done + plain.length);
          _moved();
        }
      }
      if (index < chunks) throw FilesError(-2, 'The file came down short.');
      await out.flush();
      await out.close();
      out = null;
      if (f.sha.isNotEmpty) {
        final path = part.path;
        final sha = await _shaAside(path);
        if (sha != f.sha) {
          _deleteQuietly(part.path);
          throw FilesError(-2, 'The file came down different from what was added.');
        }
      }
      final at = File(cachedPath(f));
      await at.parent.create(recursive: true);
      await part.rename(at.path);
      // Marked as come from the internet, as a browser's download is, so the system's own checks (Gatekeeper, the
      // Windows SmartScreen) still look at it if it is opened from its folder.
      await markFromInternet(at.path);
      t.state = TransferState.done;
      t.done = f.size;
      _endDownload(t, path: at.path);
    } catch (e) {
      try {
        await out?.close();
      } catch (_) {}
      _endDownload(t, error: e is FilesError ? e : FilesError(0, '$e'));
    }
  }

  void _endDownload(Transfer t, {String? path, FilesError? error}) {
    _downloads.remove(t.file?.id);
    transfers.remove(t);
    notifyListeners();
    final done = t._done!;
    if (done.isCompleted) return;
    if (path != null) {
      done.complete(path);
    } else {
      // Nobody may be waiting: the error is still taken, so it is not one nobody handled.
      done.future.ignore();
      done.completeError(error ?? FilesError(0, 'Stopped.'));
    }
  }

  static void _deleteQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// A small PNG of the picture at [path], no more than 160 across and 18 KB: what the grid shows before it comes down.
  static Future<({Uint8List png, int width, int height})?> _thumbnail(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final full = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(full);
      final w = desc.width, h = desc.height;
      desc.dispose();
      full.dispose();
      for (final side in [160, 120, 88, 64]) {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: w >= h ? side : null, targetHeight: h > w ? side : null);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        codec.dispose();
        if (data == null) return null;
        final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        if (png.length <= 18 * 1024) return (png: Uint8List.fromList(png), width: w, height: h);
      }
    } catch (_) {}
    return null;
  }
}

// The heavy work on an isolate of its own, from functions at the top so that what crosses is the one argument and
// nothing of the store around it (a closure made inside a method carries that method's whole context with it).
/// Marks the file at [path] as downloaded from the internet: the quarantine attribute on a Mac, the Zone.Identifier
/// stream (zone 3, the internet) on Windows. Nothing elsewhere; a failure is no matter (the file is still there).
Future<void> markFromInternet(String path) async {
  try {
    if (Platform.isMacOS) {
      final secs = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toRadixString(16);
      await Process.run('xattr', ['-w', 'com.apple.quarantine', '0081;$secs;Ghost Messaging;', path]);
    } else if (Platform.isWindows) {
      await File('$path:Zone.Identifier').writeAsString('[ZoneTransfer]\r\nZoneId=3\r\n');
    }
  } catch (_) {}
}

Future<String> _shaAside(String path) => Isolate.run(() => shaOfFile(path));
Future<Uint8List> _sealAside(SealRun run) => Isolate.run(() => FileSeal.sealRun(run));
Future<Uint8List?> _openAside(OpenRun run) => Isolate.run(() => FileSeal.openRun(run));

/// The SHA-256 of the file at [path], in hex, read a megabyte at a time: run on another isolate.
String shaOfFile(String path) {
  final digest = SHA256Digest();
  final raf = File(path).openSync();
  try {
    final buf = Uint8List(1 << 20);
    while (true) {
      final n = raf.readIntoSync(buf);
      if (n <= 0) break;
      digest.update(buf, 0, n);
    }
  } finally {
    raf.closeSync();
  }
  final out = Uint8List(32);
  digest.doFinal(out, 0);
  return NetCrypto.hex(out);
}

/// What the roster of a space's chat room says of its files (lib/voice/roles.dart): adding needs Add files; renaming,
/// moving and removing someone else's needs Manage files and a higher role, or being the owner. A space from before
/// roles (no owner) lets everyone add and change their own.
class RosterRules implements FilesRules {
  const RosterRules(this.roster);
  final Roster roster;

  @override
  bool mayAdd(String by) => !roster.hasOwner ? !roster.banned.contains(by) : roster.can(by, Perm.uploadFiles);

  @override
  bool mayChange(String by, SpaceFile file) {
    if (roster.banned.contains(by)) return false;
    if (by == file.by || roster.isOwner(by)) return true;
    return roster.hasOwner && roster.can(by, Perm.manageFiles) && roster.outranks(by, file.by);
  }

  @override
  bool mayFolder(String by) => mayAdd(by);
}

/// One space's files on this device.
class FilesSpace {
  FilesSpace._(this.channel, this._store);
  final VoiceChannel channel;
  final FilesStore _store;

  /// The log's last number this device has read.
  int seq = 0;
  List<LoggedOp> _log = const [];
  FilesList _list = FilesList.read(const [], const OwnerRules(null));

  /// What the relay last said of the space: how much it holds and may.
  FilesInfo? info;

  /// Why the list could not be read just now; it shows what was kept.
  FilesError? error;
  bool loading = false;

  /// Whether a list was ever had (from disk or the relay): an empty space and one not read yet look different.
  bool _kept = false;
  bool get ready => _kept;

  int _holds = 0;
  Timer? _poller;
  StreamSubscription<Object?>? _sub;
  bool _ensured = false;
  Future<void>? _refreshing;

  /// Read while there was no relay to read from: read again as soon as there is.
  bool _waiting = false;
  DateTime _tried = DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, SpaceFile> get files => _list.files;
  Set<String> get folders => {..._list.folders};
  int get bytes => _list.bytes;

  File get _file => File('${_store._data().path}/spaces/${FileSeal.filesRoom(channel.seed)}.json');

  void _load() {
    try {
      final f = _file;
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync()) as Map;
      _log = [for (final e in (j['log'] as List? ?? const [])) ?LoggedOp.fromJson(e)];
      seq = (j['seq'] as num?)?.toInt() ?? 0;
      if (j['info'] is Map) info = FilesInfo.from((j['info'] as Map).cast<String, dynamic>());
      _kept = true;
      _reread();
    } catch (_) {}
  }

  void _save() {
    try {
      final f = _file;
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.tmp')..writeAsStringSync(jsonEncode({'seq': seq, 'log': [for (final e in _log) e.toJson()], if (info != null) 'info': info!.toJson()}));
      tmp.renameSync(f.path);
    } catch (_) {}
  }

  /// Reads the list again from the log, under the roster as it is now.
  void _reread() => _list = FilesList.read(_log, _store._rules(channel));

  Future<void> _ensure(FilesApi api) async {
    if (_ensured) return;
    info = await api.ensure(owner: channel.owner);
    // The relay names the owner only from the owner's own request; one that names someone else is not this space's.
    final held = info?.owner ?? '';
    if (held.isNotEmpty && channel.owner.isNotEmpty && held != channel.owner) throw FilesError(HttpStatus.forbidden, 'This space\'s files are held by someone else.');
    _ensured = true;
  }

  /// Reads what the log has after [seq], and what the relay says of the space.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    _tried = DateTime.now();
    final api = _store._api(channel);
    if (api == null) {
      // Before the relay is connected (the app just opened): the list kept is shown as it is, and it is read again as
      // the relay comes (FilesStore._voiceChanged). Only a space never read says why it is empty.
      error = _kept ? null : FilesError(0, 'Not connected to the relay yet.');
      _waiting = true;
      _reread();
      _store._changed();
      return;
    }
    loading = true;
    _waiting = false;
    _store._changed();
    try {
      await _ensure(api);
      final key = FileSeal.filesKey(channel.seed);
      final fresh = <LoggedOp>[];
      var more = true;
      while (more) {
        final page = await api.log(after: seq);
        for (final o in page.ops) {
          final s = (o['s'] as num).toInt();
          if (s <= seq) continue;
          List<int> sealed;
          try {
            sealed = base64Decode(o['o'] as String);
          } catch (_) {
            sealed = const [];
          }
          fresh.add(LoggedOp(seq: s, by: '${o['by']}', at: (o['at'] as num?)?.toInt() ?? 0, op: FileOp.open(key, sealed)));
          seq = s;
        }
        more = page.more && page.ops.isNotEmpty;
      }
      info = await api.info();
      if (fresh.isNotEmpty) _log = [..._log, ...fresh];
      error = null;
      _kept = true;
      _reread();
      _save();
    } on FilesError catch (e) {
      error = e;
      _reread();
    } finally {
      loading = false;
      _store._changed();
    }
  }

  /// Listens in the space's chat room for others saying the log has grown.
  void _listen() {
    if (_sub != null) return;
    final route = _store._route();
    if (route == null) return;
    _sub = route.packets.where((p) => p.room == channel.chatRoom).listen((p) {
      final clear = NetCrypto.open(channel.key, p.bytes);
      if (clear == null) return;
      try {
        final m = jsonDecode(utf8.decode(clear)) as Map;
        if (m['t'] == 'files' && (m['seq'] is! int || (m['seq'] as int) > seq)) unawaited(refresh());
      } catch (_) {}
    });
  }

  void _dispose() {
    _poller?.cancel();
    _sub?.cancel();
  }
}

enum TransferState { queued, running, waiting, failed, done }

/// A file going up or coming down: how far it has got.
class Transfer {
  Transfer._up({required this.space, required String this.path, required this.name, required this.size, required this.mime, this.folder, this.owned = false})
      : up = true,
        file = null,
        id = '${space.seed}:${DateTime.now().microsecondsSinceEpoch}:$path';

  Transfer._down({required this.space, required SpaceFile this.file})
      : up = false,
        path = null,
        name = file.name,
        size = file.size,
        mime = file.mime,
        folder = file.folder,
        owned = false,
        id = '${space.seed}:${file.id}',
        _done = Completer<String>();

  /// For a picture or a test: one shown part way.
  @visibleForTesting
  Transfer.shown({required this.space, required this.name, required this.size, this.done = 0, this.up = true, this.state = TransferState.running, this.error, this.retryable = true})
      : path = null,
        file = null,
        mime = FileKind.mimeOf(name),
        folder = null,
        owned = false,
        id = '${space.seed}:$name';

  /// Which transfer this is, for a list's key.
  final String id;
  final bool up;
  final VoiceChannel space;
  final String? path;
  final SpaceFile? file;
  final String name;
  final int size;
  final String mime;
  final String? folder;
  final bool owned;

  int done = 0;
  TransferState state = TransferState.queued;

  /// Why it stopped, or what it is waiting for.
  String? error;

  /// What it is doing before it moves (hashing a big file).
  String? status;
  int tries = 0;

  // An upload's sealing, kept so it picks up where it was.
  String? sha;
  Uint8List? fileKey;
  Uint8List? prefix;
  String? blob;
  Uint8List? thumb;
  int width = 0, height = 0;

  /// When the file was last changed as it was sealed: a file changed since is not sent on.
  int? modified;

  bool _cancel = false;
  bool _held = false;
  Completer<String>? _done;

  double get progress => size <= 0 ? (state == TransferState.done ? 1 : 0) : (done / size).clamp(0.0, 1.0);

  void _wait(String why) {
    state = TransferState.waiting;
    status = null;
    error = why;
    tries++;
  }

  /// Whether trying again could mend a failure: not for a file over the limit or a space without the room for it.
  bool retryable = true;

  void _fail(String why, {bool retryable = true}) {
    state = TransferState.failed;
    status = null;
    error = why;
    this.retryable = retryable;
  }

  Map<String, Object?> _toJson() => {
        'c': {...space.toJson(), 'k': space.kind.wire, if (space.circle != null) 'ci': space.circle},
        'p': path,
        'n': name,
        'z': size,
        'm': mime,
        if (folder != null) 'd': folder,
        if (owned) 'own': 1,
        if (sha != null) 'h': sha,
        if (fileKey != null) 'k': base64Encode(fileKey!),
        if (prefix != null) 'x': base64Encode(prefix!),
        if (blob != null) 'b': blob,
        if (modified != null) 'mt': modified,
        if (thumb != null) 'th': base64Encode(thumb!),
        if (width > 0) 'w': width,
        if (height > 0) 'ht': height,
        if (state == TransferState.failed) 'err': error,
        if (state == TransferState.failed && !retryable) 'nr': 1,
      };

  static Transfer? _fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final cj = j['c'] as Map;
      final base = VoiceChannel.fromJson(cj);
      if (base == null) return null;
      final c = VoiceChannel(seed: base.seed, name: base.name, owner: base.owner, kind: SpaceKind.files, circle: cj['ci'] as String?);
      final t = Transfer._up(space: c, path: j['p'] as String, name: j['n'] as String, size: (j['z'] as num).toInt(), mime: j['m'] as String, folder: j['d'] as String?, owned: j['own'] == 1);
      t.sha = j['h'] as String?;
      if (j['k'] is String) t.fileKey = base64Decode(j['k'] as String);
      if (j['x'] is String) t.prefix = base64Decode(j['x'] as String);
      t.blob = j['b'] as String?;
      t.modified = (j['mt'] as num?)?.toInt();
      if (j['th'] is String) t.thumb = base64Decode(j['th'] as String);
      t.width = (j['w'] as num?)?.toInt() ?? 0;
      t.height = (j['ht'] as num?)?.toInt() ?? 0;
      if (j['err'] is String) t._fail(j['err'] as String, retryable: j['nr'] != 1);
      return t;
    } catch (_) {
      return null;
    }
  }
}
