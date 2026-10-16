import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/shared_files.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/share/share_in.dart';
import 'package:ghost_md/share/share_in_keep.dart';

/// Something shared from another app (lib/share/share_in.dart, share_in_keep.dart), with the activity stood in for as
/// ShareIn.kt answers on `ghost_md/share`: what a share becomes as Markdown, the name a new note is given, where an
/// addition goes, the shares taken once each whether they started the app or came while it ran, and the writing of
/// each into the library.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  SharedIn share({String? text, String? subject, String? title, List<SharedItem> items = const [], int unread = 0}) => SharedIn(id: 's${text.hashCode}', text: text, subject: subject, title: title, items: items, unread: unread);

  group('what a share becomes', () {
    test('a link, with the page’s title the share carried, and without one', () {
      final page = share(text: 'https://example.com/a/b?c=1', subject: 'Example Domain');
      expect(sharedLink(page), 'https://example.com/a/b?c=1');
      expect(sharedTitle(page), 'Example Domain');
      expect(sharedMarkdown(page), '[Example Domain](https://example.com/a/b?c=1)');
      expect(sharedNoteBody(sharedTitle(page), sharedMarkdown(page)), '# Example Domain\n\n[Example Domain](https://example.com/a/b?c=1)\n');
      final bare = share(text: ' https://www.example.org/x \n');
      expect(sharedTitle(bare), 'example.org');
      expect(sharedMarkdown(bare), '<https://www.example.org/x>');
      // A title with brackets in it, and an address with a parenthesis.
      expect(sharedMarkdown(share(text: 'https://en.wikipedia.org/wiki/Ghost_(film)', subject: 'Ghost [1990] - Wikipedia')), r'[Ghost \[1990\] - Wikipedia](<https://en.wikipedia.org/wiki/Ghost_(film)>)');
      expect(sharedTitle(share(text: 'https://x.com', subject: 'https://x.com')), 'x.com', reason: 'a subject that is the address is no title');
    });

    test('words, named by their subject or their first line', () {
      final mail = share(text: 'Meet at the station.\nBring the tickets.', subject: 'Saturday');
      expect(sharedTitle(mail), 'Saturday');
      expect(sharedNoteBody(sharedTitle(mail), sharedMarkdown(mail)), '# Saturday\n\nMeet at the station.\nBring the tickets.\n');
      final words = share(text: '# Groceries\n- eggs\n- milk');
      expect(sharedTitle(words), 'Groceries');
      expect(sharedNoteBody(sharedTitle(words), sharedMarkdown(words)), '# Groceries\n- eggs\n- milk\n', reason: 'already opens with its name');
      expect(sharedTitle(share(text: 'Read this https://example.com/post later')), 'Read this https://example.com/post later');
      expect(sharedMarkdown(share(text: 'Read this https://example.com/post later')), 'Read this https://example.com/post later');
      expect(sharedTitle(share(text: 'a ' * 100)).length, lessThanOrEqualTo(121));
    });

    test('pictures and files, named by the first one', () {
      final photos = share(items: const [SharedItem(picture: true, path: '/c/1.jpg', name: 'IMG_2041.HEIC'), SharedItem(picture: false, path: '/c/a.pdf', name: 'Lease.pdf')]);
      expect(sharedTitle(photos), 'IMG_2041');
      expect(sharedMarkdown(photos, ['![](image/p.jpg)', '[Lease.pdf](file/f.pdf)']), '![](image/p.jpg)\n\n[Lease.pdf](file/f.pdf)');
      expect(sharedTitle(share()), 'Shared');
    });

    test('added at a note’s end, above its comments', () {
      expect(sharedAppended('# Plan\n\nOne.\n\n\n', '[x](https://x.com)'), '# Plan\n\nOne.\n\n[x](https://x.com)\n');
      expect(sharedAppended('', 'Two.'), 'Two.\n');
      const commented = 'The ==venue==[^c1] is booked.\n\n```comments\nc1 matt 2026-10-04T19:00:12Z\nWhich hall?\n```\n';
      expect(sharedAppended(commented, 'Shared.'), 'The ==venue==[^c1] is booked.\n\nShared.\n\n```comments\nc1 matt 2026-10-04T19:00:12Z\nWhich hall?\n```\n');
    });

    test('a share as the phone says it', () {
      final read = SharedIn.fromJson(jsonDecode('{"id":"a1","text":"Hi","subject":"","mime":"image/*","unread":1,"items":[{"kind":"picture","path":"/c/p.jpg","name":"p.jpg","size":5},{"kind":"file","path":"","name":"x"},{"kind":"file","path":"/c/x.pdf"}]}'))!;
      expect((read.id, read.text, read.subject, read.unread), ('a1', 'Hi', null, 1));
      expect(read.items.map((i) => (i.picture, i.path, i.name)), [(true, '/c/p.jpg', 'p.jpg'), (false, '/c/x.pdf', 'Shared file')]);
      expect(SharedIn.fromJson({'text': 'no id'}), isNull);
      expect(SharedIn.fromJson('nope'), isNull);
    });
  });

  group('the phone’s shares', () {
    late List<String> kept;
    late int done;
    setUp(() {
      kept = [];
      done = 0;
      messenger.setMockMethodCallHandler(shareInChannel, (call) async {
        switch (call.method) {
          case 'take':
            final handed = List<String>.of(kept);
            kept.clear();
            return handed;
          case 'done':
            done += 1;
            return null;
        }
        throw MissingPluginException();
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(shareInChannel, null));

    String json(String id, String text) => jsonEncode({'id': id, 'text': text, 'mime': 'text/plain', 'items': [], 'unread': 0});

    test('the share that started the app once the notes are read, one that comes while it runs, each once', () async {
      kept.add(json('a', 'First'));
      final shares = PhoneShares();
      addTearDown(shares.dispose);
      final opened = <String>[];
      final stop = followShares((share) => opened.add(share.text!), shares);
      await pumpEventQueue();
      expect(opened, ['First']);
      kept.addAll([json('b', 'Second'), json('b', 'Second again'), 'not json', json('c', '   ')]);
      await messenger.handlePlatformMessage(shareInChannel.name, codec.encodeMethodCall(const MethodCall('arrived')), (_) {});
      await pumpEventQueue();
      expect(opened, ['First', 'Second'], reason: 'a share is opened once, and one with nothing in it not at all');
      await shares.done();
      expect(done, 1);
      stop();
      kept.add(json('d', 'After'));
      await messenger.handlePlatformMessage(shareInChannel.name, codec.encodeMethodCall(const MethodCall('arrived')), (_) {});
      await pumpEventQueue();
      expect(opened, ['First', 'Second']);
    });

    test('a run with no phone half has none, and nowhere to go back to', () async {
      messenger.setMockMethodCallHandler(shareInChannel, null);
      final shares = PhoneShares();
      addTearDown(shares.dispose);
      expect(await shares.take(), isEmpty);
      await shares.done();
    });
  });

  group('kept in the library', () {
    late SampleLibrary library;
    late WorkspaceStore workspaces;
    late Directory data;
    late ShareKeeper keeper;
    late MemoryStored kept;
    final adopted = <String>[];

    setUp(() {
      library = SampleLibrary([const Note(id: 'plan', body: '# Plan\n\nOne.\n', createdAt: 1, updatedAt: 1)]);
      workspaces = WorkspaceStore();
      data = Directory.systemTemp.createTempSync('ghost-share-');
      kept = MemoryStored();
      adopted.clear();
      keeper = ShareKeeper(
        library: library,
        workspaces: workspaces,
        adoptPicture: (path) async {
          adopted.add(path);
          return 'p${adopted.length}.jpg';
        },
        keepFile: (source, name) => storeSharedFile(source, name: name, dataDir: data.path),
        kept: kept,
      );
    });
    tearDown(() => data.deleteSync(recursive: true));

    File cached(String name, List<int> bytes) => File('${data.path}/cache-$name')..writeAsBytesSync(bytes);

    test('a new note, its picture adopted as the editor’s are, its file kept and linked, filed where chosen', () async {
      final pdf = cached('Lease.pdf', utf8.encode('%PDF lease'));
      final photo = cached('1.jpg', [0xFF, 0xD8, 0xFF]);
      final home = workspaces.addWorkspace('Home')!;
      final made = await keeper.keepNew(
        share(text: 'https://example.com', subject: 'Example', items: [SharedItem(picture: true, path: photo.path, name: 'IMG.jpg'), SharedItem(picture: false, path: pdf.path, name: 'Lease.pdf')], unread: 1),
        title: 'Flat lease',
        workspaceId: home.id,
      );
      final body = made.note.body;
      expect(body, startsWith('# Flat lease\n\n[Example](https://example.com)\n\n![](image/p1.jpg)\n\n[Lease.pdf](file/'));
      final ref = RegExp(r'\(file/([0-9a-f-]{36}\.pdf)\)').firstMatch(body)!.group(1)!;
      expect(File('${data.path}/$sharedFilesFolder/$ref').readAsStringSync(), '%PDF lease');
      expect(pdf.existsSync(), isFalse, reason: 'the cache’s copy is moved, not left behind');
      expect(adopted, [photo.path]);
      expect(made.failed, 1, reason: 'what the phone could not read');
      expect(workspaces.value.of[made.note.id], home.id);
    });

    test('added to a note, remembered first next time', () async {
      final made = await keeper.keepOnto(share(text: 'Call the agent.'), 'plan');
      expect(made.note.body, '# Plan\n\nOne.\n\nCall the agent.\n');
      expect(library.noteOf('plan')!.body, '# Plan\n\nOne.\n\nCall the agent.\n');
      expect(keeper.recent(), ['plan']);
      for (var i = 0; i < 7; i++) {
        library.value = [...library.value, Note(id: 'n$i', body: 'N$i', createdAt: 1, updatedAt: 1)];
        await keeper.keepOnto(share(text: 'x$i'), 'n$i');
      }
      expect(keeper.recent(), ['n6', 'n5', 'n4', 'n3', 'n2']);
      await expectLater(keeper.keepOnto(share(text: 'x'), 'gone'), throwsA(isA<StateError>()));
    });

    test('a file that cannot be kept is counted, the rest still saved; Cancel lets the copies go', () async {
      final made = await keeper.keepNew(share(text: 'Words', items: const [SharedItem(picture: false, path: '/nowhere/x.bin', name: 'x.bin')]), title: '');
      expect(made.failed, 1);
      expect(made.note.body, 'Words\n', reason: 'its words open with its name already');
      final photo = cached('2.jpg', Uint8List(3));
      await keeper.discard(share(items: [SharedItem(picture: true, path: photo.path, name: '2.jpg')]));
      expect(photo.existsSync(), isFalse);
    });
  });
}
