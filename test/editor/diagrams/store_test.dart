// The diagrams drawn and the line the rest wait in (lib/editor/diagrams/store.dart), with the web view stood in for
// (support.dart): one render at a time, each drawn once, a render nobody wants any more dropped before its turn,
// pictures kept in memory within a bound and in a folder across launches, and the channel's answers read.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';

import 'support.dart';

/// Lets the store's hops run: its look in the folder, the line, the answer handed on.
Future<void> settle() => pumpEventQueue();

/// Waits for `met`, for work that is real (a file written, read back).
Future<void> until(bool Function() met, {String? what}) async {
  for (var i = 0; i < 400 && !met(); i += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(met(), isTrue, reason: what ?? 'never happened');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the line', () {
    test('draws one diagram at a time, in the order asked, and draws what it has drawn once', () async {
      final bridge = HeldBridge();
      final store = DiagramStore(bridge: bridge, decode: smallPicture);
      final one = store.draw(askFor('graph one'), slot: 'a');
      final two = store.draw(askFor('graph two'), slot: 'b');
      await settle();
      // The second waits its turn: Mermaid keeps its settings in one place, and the page is one page.
      expect(bridge.codes, ['graph one']);
      bridge.finish(0);
      expect(await one, isA<DiagramPicture>());
      await settle();
      expect(bridge.codes, ['graph one', 'graph two']);
      bridge.finish(1);
      expect(await two, isA<DiagramPicture>());
      expect(bridge.most, 1);
      // The same diagram shown again, in another note, is not drawn again: it is there at once.
      expect(store.held(askFor('graph one')), isA<DiagramPicture>());
      expect(await store.draw(askFor('graph one'), slot: 'c'), isA<DiagramPicture>());
      expect(store.renders, 2);
    });

    test('two blocks that say the same thing are one render', () async {
      final bridge = HeldBridge();
      final store = DiagramStore(bridge: bridge, decode: smallPicture);
      final first = store.draw(askFor('graph same'), slot: 'a');
      final second = store.draw(askFor('graph same'), slot: 'b');
      await settle();
      bridge.finish(0);
      final pictures = [await first, await second];
      expect(pictures, everyElement(isA<DiagramPicture>()));
      // Each has a picture of its own to let go of.
      expect(identical((pictures[0]! as DiagramPicture).image, (pictures[1]! as DiagramPicture).image), isFalse);
      expect(bridge.asked.length, 1);
    });

    test('a block that asks again lets go of what it asked: a render still in line is dropped', () async {
      final bridge = HeldBridge();
      final store = DiagramStore(bridge: bridge, decode: smallPicture);
      final under = store.draw(askFor('graph under way'), slot: 'other');
      await settle();
      final first = store.draw(askFor('graph a'), slot: 'typed');
      await settle();
      final second = store.draw(askFor('graph ab'), slot: 'typed');
      // Let go of: answered with nothing, at once.
      expect(await first, isNull);
      bridge.finish(0);
      await under;
      await settle();
      // The web view is never asked for the one nobody waits for.
      expect(bridge.codes, ['graph under way', 'graph ab']);
      bridge.finish(1);
      expect(await second, isA<DiagramPicture>());
    });

    test('a diagram typed into while it is drawn costs the render under way and one more, however many letters', () async {
      final bridge = HeldBridge();
      final store = DiagramStore(bridge: bridge, decode: smallPicture);
      final answers = <Future<DiagramDrawing?>>[store.draw(askFor('graph'), slot: 'typed')];
      await settle();
      expect(bridge.codes, ['graph']);
      // Forty letters while the first render is in the web view.
      for (var i = 1; i <= 40; i += 1) {
        answers.add(store.draw(askFor('graph${'x' * i}'), slot: 'typed'));
        await settle();
      }
      expect(bridge.codes, ['graph']);
      bridge.finish(0);
      await settle();
      expect(bridge.codes, ['graph', 'graph${'x' * 40}']);
      bridge.finish(1);
      expect(await answers.last, isA<DiagramPicture>());
      // Every ask between was let go of. The one under way finished for nobody, and is kept all the same.
      for (final answer in answers.sublist(0, 40)) {
        expect(await answer, isNull);
      }
      expect(store.held(askFor('graph')), isA<DiagramPicture>());
      expect(store.renders, 2);
    });

    test('a block that has left the page is taken out of the line', () async {
      final bridge = HeldBridge();
      final store = DiagramStore(bridge: bridge, decode: smallPicture);
      final first = store.draw(askFor('graph first'), slot: 'a');
      await settle();
      final gone = store.draw(askFor('graph gone'), slot: 'b');
      final stays = store.draw(askFor('graph stays'), slot: 'c');
      await settle();
      store.forget('b');
      expect(await gone, isNull);
      bridge.finish(0);
      await first;
      await settle();
      expect(bridge.codes, ['graph first', 'graph stays']);
      bridge.finish(1);
      expect(await stays, isA<DiagramPicture>());
    });

    test('a diagram written wrong is kept as the page keeps it, and the ones behind it are drawn', () async {
      final bridge = HeldBridge();
      final store = DiagramStore(bridge: bridge, decode: smallPicture);
      final broken = store.draw(askFor('graph broken'), slot: 'a');
      final after = store.draw(askFor('graph after'), slot: 'b');
      await settle();
      bridge.fail(0, 'Parse error on line 2:\n...A -->\n------^');
      expect(((await broken)! as DiagramMistake).said, startsWith('Parse error on line 2:'));
      await settle();
      bridge.finish(1);
      expect(await after, isA<DiagramPicture>());
      // Asked again, it is not drawn again.
      expect((store.held(askFor('graph broken'))! as DiagramMistake).said, startsWith('Parse error'));
      expect(store.renders, 2);
    });

    test('a web view that throws is "could not be drawn here", and the line goes on', () async {
      final store = DiagramStore(bridge: _Throws(), decode: smallPicture);
      expect(((await store.draw(askFor('graph one'), slot: 'a'))! as DiagramMistake).said, '');
      expect(((await store.draw(askFor('graph two'), slot: 'a'))! as DiagramMistake).said, '');
    });
  });

  group('what is kept', () {
    test('a picture is its words, the way the page is painted, the room and the device, and this page of Mermaid', () {
      final key = askFor('graph LR').key;
      expect(askFor('graph LR').key, key);
      expect(askFor('graph TD').key, isNot(key));
      expect(askFor('graph LR', dark: true).key, isNot(key));
      expect(askFor('graph LR', room: 600).key, isNot(key));
      expect(key, startsWith('$diagramPage\n'));
      // A file's name is the key's, the same every time, and nothing of the note is in it.
      expect(diagramFile(key), diagramFile(askFor('graph LR').key));
      expect(diagramFile(key), matches(RegExp(r'^[0-9a-z]+-[0-9a-f]{16}\.diagram$')));
      expect(diagramFile(key), isNot(diagramFile(askFor('graph TD').key)));
    });

    test('memory is bounded: the least lately shown is let go, the one just drawn never', () async {
      final bridge = HeldBridge();
      // A test's picture is sixteen bytes: room for two.
      final store = DiagramStore(bridge: bridge, decode: smallPicture, memory: 32);
      for (final (index, name) in ['one', 'two', 'three'].indexed) {
        final made = store.draw(askFor('graph $name'), slot: name);
        await settle();
        bridge.finish(index);
        ((await made)! as DiagramPicture).dispose();
        // Shown again: the first is the last to go.
        if (name == 'two') (store.held(askFor('graph one'))! as DiagramPicture).dispose();
      }
      expect(store.held(askFor('graph two')), isNull);
      expect(store.held(askFor('graph one')), isNotNull);
      expect(store.held(askFor('graph three')), isNotNull);
      // One too big for the bound is still shown, and kept until the next.
      final small = DiagramStore(bridge: bridge, decode: smallPicture, memory: 1);
      final big = small.draw(askFor('graph big'), slot: 'a');
      await settle();
      bridge.finish(3);
      expect(await big, isA<DiagramPicture>());
      expect(small.held(askFor('graph big')), isNotNull);
    });

    test('a picture is kept in the folder, and a store opened again reads it without asking the web view', () async {
      final folder = Directory.systemTemp.createTempSync('ghost-diagrams');
      addTearDown(() => folder.deleteSync(recursive: true));
      final bridge = HeldBridge();
      final store = DiagramStore(bridge: bridge, folder: () async => folder.path, decode: smallPicture);
      final made = store.draw(askFor('graph kept'), slot: 'a');
      await until(() => bridge.asked.length == 1, what: 'the web view was asked');
      bridge.finish(0, block: const Size(390, 141.5), at: const Rect.fromLTWH(120.25, 11.5, 150, 118.5), scale: 2.625);
      expect(await made, isA<DiagramPicture>());
      final file = File('${folder.path}/diagrams/${diagramFile(askFor('graph kept').key)}');
      await until(file.existsSync, what: 'the picture was written');

      // The next launch.
      final again = HeldBridge();
      final opened = DiagramStore(bridge: again, folder: () async => folder.path, decode: smallPicture);
      final read = (await opened.draw(askFor('graph kept'), slot: 'a'))! as DiagramPicture;
      expect(read.block, const Size(390, 141.5));
      expect(read.at, const Rect.fromLTWH(120.25, 11.5, 150, 118.5));
      expect(read.scale, 2.625);
      expect(again.asked, isEmpty);
      expect((opened.reads, opened.renders), (1, 0));
      // And from then on it is in memory.
      expect(opened.held(askFor('graph kept')), isA<DiagramPicture>());

      // A mistake is never written, and a file that is not a picture is not believed.
      final wrong = opened.draw(askFor('graph wrong'), slot: 'b');
      await until(() => again.asked.length == 1);
      again.fail(0, 'Parse error');
      await wrong;
      expect(folder.listSync(recursive: true).whereType<File>().length, 1);
      file.writeAsBytesSync(Uint8List.fromList(<int>[1, 2, 3]));
      final third = HeldBridge();
      final spoiled = DiagramStore(bridge: third, folder: () async => folder.path, decode: smallPicture);
      final redrawn = spoiled.draw(askFor('graph kept'), slot: 'a');
      await until(() => third.asked.length == 1, what: 'a spoiled file is drawn again');
      third.finish(0);
      expect(await redrawn, isA<DiagramPicture>());
    });

    test('the folder is bounded: past its number, the ones shown longest ago are let go', () async {
      final folder = Directory.systemTemp.createTempSync('ghost-diagrams');
      addTearDown(() => folder.deleteSync(recursive: true));
      final dir = Directory('${folder.path}/diagrams')..createSync();
      for (var i = 0; i < 12; i += 1) {
        File('${dir.path}/old-$i.diagram')
          ..writeAsBytesSync(<int>[i])
          ..setLastModifiedSync(DateTime(2026, 1, 1 + i));
      }
      final bridge = HeldBridge();
      final store = DiagramStore(bridge: bridge, folder: () async => folder.path, decode: smallPicture, files: 10);
      final made = store.draw(askFor('graph new'), slot: 'a');
      await until(() => bridge.asked.length == 1);
      bridge.finish(0);
      await made;
      await until(() => dir.listSync().length == 8, what: 'the folder was thinned to four fifths of ten');
      final left = dir.listSync().map((entry) => entry.uri.pathSegments.last).toSet();
      expect(left, contains(diagramFile(askFor('graph new').key)));
      expect(left.containsAll(<String>['old-5.diagram', 'old-11.diagram']), isTrue);
      expect(left.contains('old-4.diagram'), isFalse);
    });
  });

  group('the channel', () {
    const channel = MethodChannel('ghost_md/diagrams');

    test('asks with the picture\'s number, the window\'s width and the page\'s question, and reads a picture', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return <String, Object?>{'png': Uint8List.fromList(<int>[1, 2, 3]), 'blockWidth': 390.0, 'blockHeight': 140, 'x': 120.5, 'y': 11.5, 'width': 149, 'height': 117.5, 'scale': 2.625};
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      final bridge = ChannelDiagramBridge();
      final drawn = (await bridge.draw(askFor('graph LR\n  A["quoted </script>"] --> B'))) as DiagramDrawn;
      expect(drawn.block, const Size(390, 140));
      expect(drawn.at, const Rect.fromLTWH(120.5, 11.5, 149, 117.5));
      expect(drawn.scale, 2.625);
      expect(drawn.png, <int>[1, 2, 3]);
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(calls.single.method, 'draw');
      expect(arguments['n'], 1);
      expect(arguments['viewport'], 390);
      // The page's question is JSON: the note's words are a string in it, never anything else.
      expect(arguments['ask'], contains(r'"code":"graph LR\n  A[\"quoted </script>\"] --> B"'));
      expect(arguments['ask'], contains('"n":1'));
      expect(arguments['ask'], contains('"dark":false'));
      // The next picture has the next number.
      await bridge.draw(askFor('graph TD'));
      expect((calls.last.arguments as Map<Object?, Object?>)['n'], 2);
    });

    test('reads a mistake as Mermaid said it, and anything else as "could not be drawn here"', () async {
      expect((ChannelDiagramBridge.answerOf(<String, Object?>{'failed': 'Parse error on line 2:'}) as DiagramFailed).said, 'Parse error on line 2:');
      expect((ChannelDiagramBridge.answerOf(<String, Object?>{'failed': ''}) as DiagramFailed).said, '');
      expect((ChannelDiagramBridge.answerOf(null) as DiagramFailed).said, '');
      expect((ChannelDiagramBridge.answerOf(<String, Object?>{'png': Uint8List(0), 'scale': 2}) as DiagramFailed).said, '');
      // A platform with nothing behind the channel.
      expect(((await ChannelDiagramBridge().draw(askFor('graph LR'))) as DiagramFailed).said, '');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'gone'));
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      expect(((await ChannelDiagramBridge().draw(askFor('graph LR'))) as DiagramFailed).said, '');
    });
  });
}

class _Throws implements DiagramBridge {
  @override
  Future<DiagramAnswer> draw(DiagramAsk ask) async => throw StateError('no web view');
}
