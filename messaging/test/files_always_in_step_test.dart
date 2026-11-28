// A Files space kept current with no page open, and its folder on a computer kept in step all the time (Matt,
// 2026-11-27: "Files only seem to sync when we click in and out of the files space instead of keeping the folder on the
// desktop in sync always and showing the correct file counts without having to click a file space to refresh it").
//
// Before, a space's list was read and listened for only while its page showed (FilesStore.open), and a synced folder
// was looked at when its page was opened and every four minutes. Here: the files store following a space against the
// relay's own files service on this machine, with a stand-in for the hub's rooms; and a synced folder against a real
// temporary folder and the system's own watch of it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/files/files_api.dart';
import 'package:ghost_messaging/files/files_http.dart';
import 'package:ghost_messaging/files/files_store.dart';
import 'package:ghost_messaging/files/folder_sync.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/file_seal.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/voice/channels.dart' show Voice;
import 'package:ghost_messaging/voice/voice.dart';
import 'package:ghost_relay/files.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/relay.dart';

/// The hub's rooms between the test's devices: what one sends to a room the others get, unless they are [FakeRoute.deaf]
/// (the relay lost for them); and a device told it is in a room again ([FakeRoute.cameBack]).
class FakeHub {
  final List<FakeRoute> routes = [];
}

class FakeRoute implements VoiceRoute {
  FakeRoute(this.hub, this.me) {
    hub.routes.add(this);
  }
  final FakeHub hub;
  @override
  final String me;
  final _packets = StreamController<({String room, String from, Uint8List bytes})>.broadcast();
  final _events = StreamController<RoomEvent>.broadcast();

  /// Hears nothing said in any room: the relay is lost for this device.
  bool deaf = false;

  /// The relay puts this device back in [room], as it does every room after it was lost and came back.
  void cameBack(String room) => _events.add(RoomEvent(room, members: const []));

  @override
  Future<List<String>> join(String room, String token) async => const [];
  @override
  void leave(String room) {}
  @override
  void send(String room, Uint8List bytes) {
    for (final r in hub.routes) {
      if (r != this && !r.deaf) r._packets.add((room: room, from: me, bytes: bytes));
    }
  }

  @override
  void look(String room, String token) {}
  @override
  void unlook(String room) {}
  @override
  Stream<RoomEvent> get events => _events.stream;
  @override
  Stream<({String room, String from, Uint8List bytes})> get packets => _packets.stream;
  @override
  Stream<({String room, List<String> members})> get looks => const Stream.empty();
}

/// The app's way to the relay, counted, and with the answers to a reading of the log held back while [hold] is set:
/// the relay has answered by then, so what the answer holds is what the log was at that moment.
class HeldHttp implements FilesHttp {
  HeldHttp(this.box);
  final HeldBox box;
  final FilesHttp _inner = defaultFilesHttp();

  @override
  Future<FilesAnswer> send(String method, Uri url, Map<String, String> headers, List<int>? body) async {
    box.sent++;
    final answer = await _inner.send(method, url, headers, body);
    final hold = box.hold;
    if (hold != null && method == 'GET' && url.path.endsWith('/log')) {
      box.held++;
      await hold.future;
    }
    return answer;
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

class HeldBox {
  Completer<void>? hold;
  int sent = 0, held = 0;
}

Future<void> until(bool Function() test, {String? reason, Duration most = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(most);
  while (!test()) {
    if (DateTime.now().isAfter(end)) fail('waited too long${reason == null ? '' : ': $reason'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A drive in memory, counted: files by id, each with its bytes (as test/folder_sync_test.dart's).
class FakeDrive implements SyncDrive {
  FakeDrive(this.dir, {this.id = 'drive-1'});
  final Directory dir;
  final Map<String, (DriveFile, List<int>)> files = {};
  int _n = 0, lists = 0;
  bool reachable = true;
  @override
  final String id;
  @override
  int maxFile = 0;
  @override
  int? free;

  DriveFile put(String path, String text) {
    final bytes = utf8.encode(text);
    final f = DriveFile(id: 'f${++_n}', path: path, size: bytes.length, sha: crypto.sha256.convert(bytes).toString(), at: _n);
    files[f.id] = (f, bytes);
    return f;
  }

  void remove(String path) => files.removeWhere((_, v) => v.$1.path == path);
  List<String> get paths => [for (final v in files.values) v.$1.path]..sort();
  String? newest(String path) {
    final of = files.values.where((v) => v.$1.path == path).toList()..sort((a, b) => b.$1.at.compareTo(a.$1.at));
    return of.isEmpty ? null : utf8.decode(of.first.$2);
  }

  @override
  Future<bool> delete(DriveFile f) async {
    files.remove(f.id);
    return true;
  }

  @override
  Future<List<DriveFile>?> list() async {
    lists++;
    return reachable ? [for (final v in files.values) v.$1] : null;
  }

  @override
  Future<DriveFile?> upload(String local, String? folder, String name) async => put(folder == null ? name : '$folder/$name', File(local).readAsStringSync());

  @override
  Future<String> fetch(DriveFile f) async {
    final at = File('${dir.path}/cache/${f.id}')..parent.createSync(recursive: true);
    at.writeAsBytesSync(files[f.id]!.$2);
    return at.path;
  }
}

void main() {
  group('a Files space followed with no page open', () {
    late Directory dir;
    late Relay relay;
    late Uri base;
    final maya = KeysSigner(NetKeys.generate()), sam = KeysSigner(NetKeys.generate());
    late VoiceChannel space;
    late FakeHub hub;
    final stores = <FilesStore>[];
    final routes = <FilesStore, FakeRoute>{};

    VoiceChannel spaceOf(String name) => VoiceChannel(seed: NetCrypto.hex(NetCrypto.randomBytes(32)), name: name, kind: SpaceKind.files, owner: NetCrypto.hex(maya.publicKey));

    FilesStore device(KeysSigner who, String name, {Uri? at, HeldBox? box}) {
      final route = FakeRoute(hub, who.id);
      final s = FilesStore.forTest(base: at ?? base, signer: who, data: Directory('${dir.path}/$name'), route: route, name: name, piece: 2, http: box == null ? null : () => HeldHttp(box));
      stores.add(s);
      routes[s] = route;
      return s;
    }

    File fileOf(String name, String text) => File('${dir.path}/in/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

    /// [name] added to [c] from [from], and there in its own list.
    Future<void> add(FilesStore from, VoiceChannel c, String name) async {
      from.upload(c, [fileOf(name, 'what $name holds').path]);
      await until(() => from.of(c).files.values.any((f) => f.name == name), reason: 'adding $name: ${from.transfers.firstOrNull?.error}');
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ghost-files-follow');
      hub = FakeHub();
      space = spaceOf('Drop box');
      relay = Relay(files: Files(dir: Directory('${dir.path}/relay')));
      base = Uri.parse('http://127.0.0.1:${await relay.start(port: 0)}/files');
    });

    tearDown(() async {
      for (final s in stores) {
        await s.clear();
      }
      stores.clear();
      routes.clear();
      await relay.stop();
      await dir.delete(recursive: true);
    });

    test('its count is right as others add and remove, with its page never opened, and is there from the start of the next run', () async {
      final a = device(maya, 'Maya'), b = device(sam, 'Sam');
      await a.start();
      expect(b.heldCount(space), isNull, reason: 'nothing is known of it yet');
      final news = <String>[];
      final heard = b.news.listen(news.add);
      b.follow([space]);
      // Read once as it is taken up: an empty space is known to be empty.
      await until(() => b.heldCount(space) == 0);
      await add(a, space, 'report.txt');
      // Sam never opened the space: told in its chat room all the same.
      await until(() => b.heldCount(space) == 1);
      await add(a, space, 'plan.txt');
      await until(() => b.heldCount(space) == 2);
      expect(await a.delete(space, a.of(space).files.values.firstWhere((f) => f.name == 'plan.txt')), isTrue);
      await until(() => b.heldCount(space) == 1);
      expect(b.of(space).files.values.single.name, 'report.txt');
      // Each change was said, by the relay's name for the space's files, for whoever keeps a folder in step with it.
      expect(news.toSet(), {FileSeal.filesRoom(space.seed)});
      expect(news.length, greaterThanOrEqualTo(3));
      // And nothing is said of a reading that found nothing new.
      final said = news.length;
      await b.of(space).refresh();
      expect(news.length, said);
      await heard.cancel();

      // The app opened again, the relay not there yet: the count is the one kept, before anything is asked of it.
      b.of(space).flushKept();
      final again = FilesStore.forTest(base: Uri.parse('http://127.0.0.1:1/files'), signer: sam, data: Directory('${dir.path}/Sam'));
      stores.add(again);
      expect(again.heldCount(space), isNull);
      again.follow([space]);
      await until(() => again.heldCount(space) == 1);
    });

    // The relay holds each device to a number of spaces made (relay/lib/files.dart, spacesPerId). Every device in a
    // space follows it as the app starts: a reading that made the space, as opening its page does, would have whoever
    // started first make every space nobody had opened yet.
    test('following a space nobody has opened does not make it on the relay; it is empty until someone opens it', () async {
      final b = device(sam, 'Sam');
      final api = FilesApi(base: base, space: FileSeal.filesRoom(space.seed), token: FileSeal.filesToken(space.seed), signer: sam);
      Future<int> there() async {
        try {
          await api.info();
          return 200;
        } on FilesError catch (e) {
          return e.status;
        }
      }

      b.follow([space]);
      await until(() => b.heldCount(space) == 0);
      expect(b.of(space).error, isNull);
      expect(await there(), HttpStatus.notFound, reason: 'looked at, not made');
      // Heard to come back into its room: looked at again, and still not made.
      routes[b]!.cameBack(space.chatRoom);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await there(), HttpStatus.notFound);
      // Its page opened: made then, as it always was.
      await b.open(space);
      expect(await there(), 200);
      b.close(space);
    });

    test('a word that comes while the log is being read is not lost: the log is read once more', () async {
      final box = HeldBox();
      final a = device(maya, 'Maya'), b = device(sam, 'Sam', box: box);
      await a.start();
      b.follow([space]);
      await until(() => b.heldCount(space) == 0);
      // Sam's next reading of the log is held back once the relay has answered it: it holds the first file alone.
      box.hold = Completer<void>();
      await add(a, space, 'one.txt');
      await until(() => box.held == 1, reason: 'Sam reads the log on hearing of the first file');
      // The second is added, and said, while that reading is still under way.
      await add(a, space, 'two.txt');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(box.held, 1, reason: 'one reading at a time');
      final hold = box.hold!;
      box.hold = null;
      hold.complete();
      // Before, the second word was taken for the reading under way, and the file waited for the next word of any kind.
      await until(() => b.heldCount(space) == 2, most: const Duration(seconds: 10));
    });

    test('what was added while the relay was lost is read as this device comes back into the room, and said', () async {
      final a = device(maya, 'Maya'), b = device(sam, 'Sam');
      await a.start();
      b.follow([space]);
      await until(() => b.heldCount(space) == 0);
      routes[b]!.deaf = true;
      await add(a, space, 'missed.txt');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(b.heldCount(space), 0, reason: 'the word never reached it');
      final news = <String>[];
      final heard = b.news.listen(news.add);
      routes[b]!
        ..deaf = false
        ..cameBack(space.chatRoom);
      await until(() => b.heldCount(space) == 1);
      await until(() => news.isNotEmpty);
      // Back in a room with nothing new in it is said too: the relay is in reach again for what waited here.
      news.clear();
      routes[b]!.cameBack(space.chatRoom);
      await until(() => news.isNotEmpty);
      expect(b.heldCount(space), 1);
      await heard.cancel();
    });

    test('a space let go of is no longer listened to; one opened still is, while it is open', () async {
      final a = device(maya, 'Maya'), b = device(sam, 'Sam');
      await a.start();
      b.follow([space]);
      await until(() => b.heldCount(space) == 0);
      b.follow(const []);
      await add(a, space, 'one.txt');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(b.heldCount(space), 0, reason: 'not followed, not open: nothing is read');
      await b.open(space);
      expect(b.heldCount(space), 1);
      await add(a, space, 'two.txt');
      await until(() => b.heldCount(space) == 2);
      b.close(space);
      await add(a, space, 'three.txt');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(b.heldCount(space), 2);
      // Followed again while it was open, it goes on being listened to once the page closes.
      await b.open(space);
      b.follow([space]);
      await until(() => b.heldCount(space) == 3);
      b.close(space);
      await add(a, space, 'four.txt');
      await until(() => b.heldCount(space) == 4);
    });

    test('with the relay out of reach one followed space finds that out, not each of them; each is read as it comes back', () async {
      final box = HeldBox();
      final a = device(maya, 'Maya');
      // Sam's store is pointed where nothing answers.
      final away = device(sam, 'Sam', at: Uri.parse('http://127.0.0.1:1/files'), box: box);
      final spaces = [for (var i = 0; i < 5; i++) spaceOf('Space $i')];
      await a.start();
      for (final c in spaces) {
        await add(a, c, 'in ${c.name}.txt');
      }
      away.follow(spaces);
      await until(() => box.sent > 0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(box.sent, 1, reason: 'the first asked and found the relay away; the other four wait for it');
      expect([for (final c in spaces) away.heldCount(c)], everyElement(isNull));

      // The same five on a store that reaches the relay, heard to come back into each room: all read, one at a time.
      final b = device(sam, 'Sam again');
      b.follow(spaces);
      for (final c in spaces) {
        routes[b]!.cameBack(c.chatRoom);
      }
      await until(() => spaces.every((c) => b.heldCount(c) == 1));
    });
  });

  // The app's own store and the app's own list of spaces (Voice): what FilesStore.start hangs on them.
  test('the app\'s own store follows every Files space this device is in from the moment it starts, and one it comes into later', () async {
    final dir = await Directory.systemTemp.createTemp('ghost-files-voice');
    final relay = Relay(files: Files(dir: Directory('${dir.path}/relay')));
    final base = Uri.parse('http://127.0.0.1:${await relay.start(port: 0)}/files');
    final maya = KeysSigner(NetKeys.generate()), sam = KeysSigner(NetKeys.generate());
    VoiceChannel spaceOf(String name, [SpaceKind kind = SpaceKind.files]) => VoiceChannel(seed: NetCrypto.hex(NetCrypto.randomBytes(32)), name: name, kind: kind, owner: NetCrypto.hex(maya.publicKey));
    final first = spaceOf('Drop box'), later = spaceOf('Later'), talk = spaceOf('Lounge', SpaceKind.voice);
    final hub = FakeHub();
    final a = FilesStore.forTest(base: base, signer: maya, data: Directory('${dir.path}/Maya'), route: FakeRoute(hub, maya.id), name: 'Maya', piece: 2);
    final b = FilesStore.forTest(base: base, signer: sam, data: Directory('${dir.path}/Sam'), route: FakeRoute(hub, sam.id), name: 'Sam', piece: 2);
    Future<void> add(VoiceChannel c, String name) async {
      final f = File('${dir.path}/in/$name')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('what $name holds');
      a.upload(c, [f.path]);
      await until(() => a.of(c).files.values.any((f) => f.name == name), reason: 'adding $name: ${a.transfers.firstOrNull?.error}');
    }

    final v = Voice.instance;
    final hadOwn = v.own, hadStore = FilesStore.instance;
    try {
      await a.start();
      await add(first, 'one.txt');
      await add(later, 'early.txt');
      v.own = [first, talk];
      FilesStore.instance = b;
      // As the app does as it opens (lib/main.dart, lib/desktop/main.dart): nothing else is asked of the store here.
      await b.start();
      await until(() => b.heldCount(first) == 1);
      expect(b.heldCount(talk), isNull, reason: 'only a Files space is followed');
      expect(b.heldCount(later), isNull, reason: 'not this device\'s yet');
      await add(first, 'two.txt');
      await until(() => b.heldCount(first) == 2);
      // This device comes into another Files space, and Voice says its spaces changed.
      v.own = [first, talk, later];
      v.view(null);
      await until(() => b.heldCount(later) == 1);
      // And leaves the first: no longer listened to.
      v.own = [talk, later];
      v.view(null);
      await add(first, 'three.txt');
      await add(later, 'late.txt');
      await until(() => b.heldCount(later) == 2);
      expect(b.heldCount(first), 2);
    } finally {
      v.own = hadOwn;
      v.view(null);
      FilesStore.instance = hadStore;
      await a.clear();
      await b.clear();
      await relay.stop();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  // The same over the relay's own hub, with the app's own carrier for it: what a stand-in for the rooms can only say
  // it does. The word that a log has grown is a packet in the space's chat room, which the app stays in for every
  // space (Voice holds each one's chat); and coming back after the connection was lost is the hub's answer to the
  // room being joined again, which the carrier does by itself.
  test('over the real hub: a followed space hears of a file in its chat room, and reads what it missed once the lost connection is back', () async {
    final dir = await Directory.systemTemp.createTemp('ghost-files-hub');
    final relay = Relay(hub: Hub(), files: Files(dir: Directory('${dir.path}/relay')));
    final url = 'ws://127.0.0.1:${await relay.start(port: 0)}/hub';
    final maya = KeysSigner(NetKeys.generate()), sam = KeysSigner(NetKeys.generate());
    final space = VoiceChannel(seed: NetCrypto.hex(NetCrypto.randomBytes(32)), name: 'Drop box', kind: SpaceKind.files, owner: NetCrypto.hex(maya.publicKey));
    final hubs = [for (final who in [maya, sam]) HubCarrier(url: url, signer: who, retry: const Duration(milliseconds: 40))];
    final stores = [
      for (final (i, who) in [maya, sam].indexed)
        FilesStore.forTest(base: FilesApi.baseFor(url), signer: who, data: Directory('${dir.path}/$i'), route: HubVoiceRoute(hubs[i]), name: i == 0 ? 'Maya' : 'Sam', piece: 2),
    ];
    final a = stores[0], b = stores[1];
    Future<void> add(String name) async {
      final f = File('${dir.path}/in/$name')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('what $name holds');
      a.upload(space, [f.path]);
      await until(() => a.of(space).files.values.any((f) => f.name == name), reason: 'adding $name: ${a.transfers.firstOrNull?.error}');
    }

    try {
      for (final h in hubs) {
        await h.start();
        await until(() => h.state.value == CarrierState.up, reason: h.problem);
        // As Voice does for every space this device is in.
        await h.join(space.chatRoom, space.chatToken);
      }
      await a.start();
      b.follow([space]);
      await until(() => b.heldCount(space) == 0);
      await add('one.txt');
      await until(() => b.heldCount(space) == 1);

      // Sam's connection lost: what is said in the room meanwhile never reaches it.
      await hubs[1].stop();
      await add('two.txt');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(b.heldCount(space), 1);
      final news = <String>[];
      final heard = b.news.listen(news.add);
      // Back: the carrier joins its rooms again by itself, and the hub's answer is what has the log read.
      await hubs[1].start();
      await until(() => b.heldCount(space) == 2, most: const Duration(seconds: 15));
      expect(news, contains(FileSeal.filesRoom(space.seed)));
      await heard.cancel();
      // And it hears the next one as it happens again.
      await add('three.txt');
      await until(() => b.heldCount(space) == 3);
    } finally {
      for (final s in stores) {
        await s.clear();
      }
      for (final h in hubs) {
        await h.stop();
      }
      await relay.stop();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  group('a synced folder kept in step all the time', () {
    late Directory tmp;
    late String root;
    late FakeDrive drive;
    final made = <FolderSync>[];

    File local(String path) => File('$root/$path');
    void write(String path, String text) => local(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

    FolderSync sync({SyncDrive? d, String? space, Duration quiet = const Duration(milliseconds: 250), Duration retry = const Duration(milliseconds: 60), int walkMost = 20000}) {
      final s = FolderSync(
        data: () => Directory('${tmp.path}/app/folder-sync'),
        drive: () async => d ?? drive,
        home: () => '${tmp.path}/home',
        own: () => ['${tmp.path}/app'],
        // No clock's pass, and none as it starts, unless the test asks: what happens here follows a change.
        every: const Duration(hours: 1),
        first: const Duration(hours: 1),
        look: const Duration(hours: 1),
        quiet: quiet,
        settle: const Duration(milliseconds: 40),
        retry: retry,
        walkMost: walkMost,
        space: space,
        driveName: space == null ? 'My files' : 'Team files',
      );
      made.add(s);
      return s;
    }

    Future<void> idle(FolderSync s) => until(() => !s.running);

    setUp(() {
      tmp = Directory(Directory.systemTemp.createTempSync('ghost-folder-live').resolveSymbolicLinksSync());
      root = FolderSyncEngine.resolve((Directory('${tmp.path}/Synced')..createSync()).path)!;
      drive = FakeDrive(tmp);
    });
    tearDown(() async {
      for (final s in made) {
        s.dispose();
      }
      // A pass still under way ends before the folder goes.
      await until(() => made.every((s) => !s.running));
      made.clear();
      // What a watch still had to say is let go before the folder is.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      tmp.deleteSync(recursive: true);
    });

    test('a file put in the folder goes up by itself; changed, the newer replaces it; removed, it is removed there', () async {
      final s = sync()..start();
      expect(s.choose(root), isNull);
      await idle(s);
      // Nobody opens a page or asks for a pass from here on.
      write('notes.txt', 'first');
      await until(() => drive.paths.contains('notes.txt'), reason: s.line);
      write('Papers/lease.txt', 'the lease');
      await until(() => drive.paths.contains('Papers/lease.txt'), reason: s.line);
      await until(() => s.line == 'In step.');
      write('notes.txt', 'second, and longer');
      await until(() => drive.newest('notes.txt') == 'second, and longer', reason: s.line);
      local('notes.txt').deleteSync();
      await until(() => !drive.paths.contains('notes.txt'), reason: s.line);
      await until(() => s.line == 'In step.');
      expect(drive.paths, ['Papers/lease.txt']);
    });

    test('a folder never started is looked at only when asked, as before', () async {
      final s = sync();
      expect(s.choose(root), isNull);
      await idle(s);
      final lists = drive.lists;
      write('notes.txt', 'first');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(drive.lists, lists, reason: 'the folder\'s own change said nothing');
      // Asked, it still looks.
      s.soon(Duration.zero);
      await until(() => drive.lists == lists + 1);
      await idle(s);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(drive.lists, lists + 1, reason: 'and nothing follows by itself');
    });

    test('word that the drive changed brings the file down, and the pass\'s own writing starts no pass of its own', () async {
      final s = sync(space: 'abc123')..start();
      FolderSync.putSpace('abc123', s);
      addTearDown(() => FolderSync.putSpace('abc123', null));
      expect(s.choose(root), isNull);
      await idle(s);
      drive.put('Shared/plan.txt', 'the plan');
      // The files store's word, by the relay's name for the space's files.
      FolderSync.heard('abc123');
      await until(() => local('Shared/plan.txt').existsSync(), reason: s.line);
      expect(local('Shared/plan.txt').readAsStringSync(), 'the plan');
      await idle(s);
      final lists = drive.lists;
      // The folder and the file the pass made are its own doing: nothing follows them. (A change of someone else's does:
      // the test before this one.)
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(drive.lists, lists, reason: 'no pass followed the pass\'s own writing');
      // Word of another space is not this folder's.
      FolderSync.heard('someone-elses');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(drive.lists, lists);
      // Removed there: moved aside here, by itself, and that too is the pass's own doing.
      drive.remove('Shared/plan.txt');
      FolderSync.heard('abc123');
      await until(() => !local('Shared/plan.txt').existsSync(), reason: s.line);
      expect(File('$root/${FolderSyncEngine.binName}/Shared/plan.txt').readAsStringSync(), 'the plan');
    });

    test('asked for while a pass runs, another follows it', () async {
      final slow = _SlowDrive(tmp);
      final s = sync(d: slow)..start();
      expect(s.choose(root), isNull);
      await until(() => slow.waiting != null, reason: 'the first pass is listing the drive');
      // Added while the pass is past the point of seeing it.
      slow.inner.put('late.txt', 'late');
      s.soon(Duration.zero);
      // A timer set after that one fires after it: the asking has come, and found the pass running.
      await Future<void>.delayed(Duration.zero);
      expect(s.running, isTrue);
      slow.release();
      await until(() => local('late.txt').existsSync(), reason: s.line);
    });

    test('a drive that can\'t be reached is tried again soon by itself, a few times and no more', () async {
      drive.reachable = false;
      final s = sync(retry: const Duration(milliseconds: 40))..start();
      expect(s.choose(root), isNull);
      await until(() => s.line == 'Stopped: My files can\'t be reached right now.');
      // 40, 80, 160 and 320 ms after one another, then left to the clock's pass and to whatever says something changed.
      await until(() => drive.lists >= 5, reason: '${drive.lists} passes');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(drive.lists, 5);
      // Back in reach: the next thing to change gets through, and the tries are there again for the next time.
      drive.reachable = true;
      write('notes.txt', 'first');
      await until(() => drive.paths.contains('notes.txt'), reason: s.line);
      await until(() => s.line == 'In step.');
      drive.reachable = false;
      final before = drive.lists;
      s.soon(Duration.zero);
      await until(() => drive.lists >= before + 5, reason: '${drive.lists - before} passes');
    });

    test('a file still being written when a pass looks is taken by one that follows by itself', () async {
      final s = sync(quiet: const Duration(milliseconds: 1200));
      expect(s.choose(root), isNull);
      await idle(s);
      s.start();
      write('big.bin', 'still coming');
      // A pass asked for at once (the page opened, say) leaves it out as still being written.
      await s.pass();
      expect(s.last!.unsettled, isTrue, reason: '${s.last!.skipped}');
      expect(drive.paths, isEmpty);
      await until(() => drive.paths.contains('big.bin'), reason: s.line);
      await until(() => s.line == 'In step.');
    });

    // Two ways a folder could have been walked without a pause, for nothing.
    test('a folder with more files than a pass looks at is not walked again and again', () async {
      for (var i = 0; i < 6; i++) {
        write('f$i.txt', 'file $i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final s = sync(walkMost: 3)..start();
      expect(s.choose(root), isNull);
      // The first pass sends the three it looked at and says there is more; the next finds nothing of those to move,
      // and says "more" again, as every pass of such a folder will. It is left there, for the clock's own pass.
      await until(() => drive.paths.length == 3, reason: s.line);
      await idle(s);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final lists = drive.lists;
      expect(lists, lessThanOrEqualTo(3), reason: 'the one that moved them, and one after it');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(drive.lists, lists);
      expect(s.last!.capped, isTrue);
    });

    test('a file written to without a pause is looked at less and less often, and taken once it is still', () async {
      final s = sync(quiet: const Duration(milliseconds: 120))..start();
      expect(s.choose(root), isNull);
      await idle(s);
      final lists = drive.lists;
      final began = DateTime.now();
      // Written to every 30 ms for some three seconds, and looked at as it begins (its page opened, say).
      final f = local('log.txt')..writeAsStringSync('0');
      unawaited(s.pass());
      for (var i = 1; i <= 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        f.writeAsStringSync('$i' * 3, mode: FileMode.append);
      }
      final took = DateTime.now().difference(began);
      // Each look that finds it still being written waits twice as long for the next: a handful in three seconds, where
      // one every 160 ms would be about twenty (and more the longer the writing took).
      expect(drive.lists - lists, lessThanOrEqualTo(10), reason: 'in ${took.inMilliseconds} ms');
      expect(took.inMilliseconds ~/ 160, greaterThan(10), reason: 'the writing took long enough to tell the two apart');
      expect(drive.paths, isEmpty, reason: 'never sent half written');
      // Still at last: sent, whole.
      await until(() => drive.newest('log.txt') == f.readAsStringSync(), reason: s.line);
    });

    test('Stop syncing stops the watching; another folder chosen is the one watched', () async {
      final s = sync()..start();
      expect(s.choose(root), isNull);
      await idle(s);
      s.stop();
      final lists = drive.lists;
      write('after.txt', 'after stopping');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(drive.lists, lists);
      expect(drive.paths, isEmpty);
      final other = FolderSyncEngine.resolve((Directory('${tmp.path}/Other')..createSync()).path)!;
      expect(s.choose(other), isNull);
      await idle(s);
      File('$other/here.txt').writeAsStringSync('in the other');
      await until(() => drive.paths.contains('here.txt'), reason: s.line);
      expect(drive.paths, ['here.txt'], reason: 'the folder let go of is not looked at');
    });

    test('a pass says which folders it walked, for a watch of one folder at a time', () async {
      write('a.txt', 'a');
      write('Papers/lease.txt', 'lease');
      write('Papers/2026/tax.txt', 'tax');
      write('.hidden/x.txt', 'x');
      final r = await FolderSyncEngine(root: root, drive: drive, state: SyncState(File('${tmp.path}/app/state.json')), now: () => DateTime.now().add(const Duration(hours: 1))).run();
      expect(r.folders, ['Papers', 'Papers/2026']);
    });
  });

  group('the two together', () {
    test('a file added to a space on one computer lands in the folder on another, and one put in that folder reaches the first, with no page opened on either', () async {
      final dir = Directory(Directory.systemTemp.createTempSync('ghost-files-live').resolveSymbolicLinksSync());
      final relay = Relay(files: Files(dir: Directory('${dir.path}/relay')));
      final base = Uri.parse('http://127.0.0.1:${await relay.start(port: 0)}/files');
      final maya = KeysSigner(NetKeys.generate()), sam = KeysSigner(NetKeys.generate());
      final space = VoiceChannel(seed: NetCrypto.hex(NetCrypto.randomBytes(32)), name: 'Team files', kind: SpaceKind.files, owner: NetCrypto.hex(maya.publicKey));
      final room = FileSeal.filesRoom(space.seed);
      final hub = FakeHub();
      final a = FilesStore.forTest(base: base, signer: maya, data: Directory('${dir.path}/Maya'), route: FakeRoute(hub, maya.id), name: 'Maya', piece: 2);
      final b = FilesStore.forTest(base: base, signer: sam, data: Directory('${dir.path}/Sam'), route: FakeRoute(hub, sam.id), name: 'Sam', piece: 2);
      final folder = FolderSyncEngine.resolve((Directory('${dir.path}/Sam folder')..createSync()).path)!;
      // Sam's computer: the space followed, a folder chosen for it, and the store's word reaching the folder, as the
      // app's own does (FolderSync.start).
      final s = FolderSync(
        data: () => Directory('${dir.path}/Sam app/folder-sync'),
        drive: () async => StoreDrive(b, space, tick: const Duration(milliseconds: 20), name: space.name),
        home: () => '${dir.path}/home',
        own: () => ['${dir.path}/Sam app'],
        every: const Duration(hours: 1),
        first: const Duration(hours: 1),
        quiet: const Duration(milliseconds: 300),
        settle: const Duration(milliseconds: 40),
        space: room,
        driveName: space.name,
      );
      FolderSync.putSpace(room, s);
      final word = b.news.listen(FolderSync.heard);
      try {
        await a.start();
        await b.start();
        a.follow([space]);
        b.follow([space]);
        await until(() => a.heldCount(space) == 0 && b.heldCount(space) == 0);
        s.start();
        expect(s.choose(folder), isNull);
        await until(() => !s.running);

        // Maya adds a file in the app. Sam's folder has it, with Sam's page for the space never opened.
        final from = File('${dir.path}/in/report.txt')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('the report');
        a.upload(space, [from.path]);
        await until(() => File('$folder/report.txt').existsSync(), reason: s.line);
        expect(File('$folder/report.txt').readAsStringSync(), 'the report');
        expect(b.heldCount(space), 1);

        // Sam drops a file in the folder. Maya's count for the space is two, with nothing opened or pressed.
        File('$folder/answer.txt').writeAsStringSync('the answer');
        await until(() => a.heldCount(space) == 2, reason: s.line);
        expect([for (final f in a.of(space).files.values) f.name]..sort(), ['answer.txt', 'report.txt']);
        await until(() => s.line == 'In step.', reason: s.line);
      } finally {
        await word.cancel();
        FolderSync.putSpace(room, null);
        s.dispose();
        await a.clear();
        await b.clear();
        await relay.stop();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        dir.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}

/// A drive whose listing waits to be let go, once: a pass caught part way.
class _SlowDrive implements SyncDrive {
  _SlowDrive(Directory dir) : inner = FakeDrive(dir);
  final FakeDrive inner;
  Completer<void>? waiting;
  bool _held = false;

  void release() => waiting?.complete();

  @override
  String get id => inner.id;
  @override
  int get maxFile => inner.maxFile;
  @override
  int? get free => inner.free;

  @override
  Future<List<DriveFile>?> list() async {
    // What is there as the pass begins; the first pass is then held before it does anything with it.
    final listed = await inner.list();
    if (!_held) {
      _held = true;
      waiting = Completer<void>();
      await waiting!.future;
    }
    return listed;
  }

  @override
  Future<DriveFile?> upload(String local, String? folder, String name) => inner.upload(local, folder, name);
  @override
  Future<String> fetch(DriveFile f) => inner.fetch(f);
  @override
  Future<bool> delete(DriveFile f) => inner.delete(f);
}
