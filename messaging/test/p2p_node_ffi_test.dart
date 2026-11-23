import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/p2p/node.dart';
import 'package:ghost_messaging/net/p2p/node_factory.dart';
import 'package:ghost_messaging/net/p2p/node_ffi.dart';

/// The direct network's core from Dart (lib/net/p2p/node_ffi.dart; docs/OPEN_NETWORK.md, section 2): two and three
/// real nodes in this one process, the Rust library and all (native/p2p), linked over this machine's own loopback
/// address with no link helper. What a [P2pNode] promises is held to here through the library itself; the library's
/// own tests (`cargo test` in native/p2p) hold it to the rest: a link helper, a peer that speaks wrongly, what an idle
/// node costs.
///
/// Skipped where the library is not built: `sh tool/build-p2p.sh mac` builds it where these look
/// (build/p2p/mac/libghost_p2p.dylib), and GHOST_P2P_LIB names one anywhere else.

/// Waits for [ok], however long the machine takes (half a minute at most: other builds share it), not for a length
/// of time.
Future<void> _until(bool Function() ok, String what) async {
  for (var i = 0; i < 6000 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ok(), isTrue, reason: what);
}

P2pConfig _config(int n) => P2pConfig(secret: Uint8List.fromList(List.filled(32, n)));

/// A node, let go of when the test is over.
IrohNode _node() {
  final node = IrohNode.make()!;
  addTearDown(node.dispose);
  return node;
}

/// A node that is up, with the key [n] makes.
Future<IrohNode> _up(int n) async {
  final node = _node();
  await node.start(_config(n));
  expect(node.state.value, P2pState.up, reason: node.problem);
  return node;
}

final _ipv4 = RegExp(r'^\d+\.\d+\.\d+\.\d+:(\d+)$');

/// Where [node] is, as another node on this machine dials it: the port it says, at the loopback address.
Future<Whereabouts> _here(IrohNode node) async {
  await _until(() => node.whereabouts.value?.addresses.any(_ipv4.hasMatch) ?? false, 'it never said where it is');
  final port = _ipv4.firstMatch(node.whereabouts.value!.addresses.firstWhere(_ipv4.hasMatch))!.group(1);
  return Whereabouts(addresses: ['127.0.0.1:$port']);
}

/// Everything a stream is handed, and whether it is done.
class _Heard {
  _Heard(P2pStream stream) {
    sub = stream.frames.listen(frames.add, onDone: () => done = true);
  }
  final frames = <Uint8List>[];
  late final StreamSubscription<Uint8List> sub;
  bool done = false;
}

/// The next stream another node opens to [node].
Future<P2pStream> _next(IrohNode node) => node.opened.first.timeout(const Duration(seconds: 30));

Matcher get _refused => throwsA(isA<P2pError>());

void main() {
  final skip = IrohNode.available ? false : 'The direct network\'s core is not built here: sh tool/build-p2p.sh mac';
  const patient = Timeout(Duration(minutes: 3));

  test('the factory makes a node of the core, and a node id is worked out with nothing started', () async {
    final node = makeP2pNode();
    expect(node, isA<IrohNode>());
    addTearDown((node as IrohNode).dispose);
    expect(node.state.value, P2pState.off);
    expect(node.nodeId, isNull);
    expect(node.whereabouts.value, isNull);
    final id = await node.idOf(_config(1).secret);
    expect(isNodeId(id), isTrue);
    expect(await node.idOf(_config(1).secret), id);
    expect(await node.idOf(_config(2).secret), isNot(id));
    await expectLater(node.idOf(Uint8List(31)), _refused);
    // Not up: nothing opens.
    await expectLater(node.open(id, 0), _refused);
    // Started, it is the node its key makes.
    await node.start(_config(1));
    expect(node.state.value, P2pState.up);
    expect(node.nodeId, id);
  }, skip: skip, timeout: patient);

  test('frames go both ways, whole and in order: an empty one, the longest, a burst', () async {
    final a = await _up(11), b = await _up(12);
    b.allow(a.nodeId!, {P2pChannel.packets});
    final coming = _next(b);
    final ours = await a.open(b.nodeId!, P2pChannel.packets, hint: await _here(b));
    final theirs = await coming;
    expect((ours.nodeId, ours.channel, ours.incoming), (b.nodeId, P2pChannel.packets, false));
    expect((theirs.nodeId, theirs.channel, theirs.incoming), (a.nodeId, P2pChannel.packets, true));
    final atA = _Heard(ours), atB = _Heard(theirs);

    final longest = Uint8List.fromList(List.generate(P2pNode.maxFrame, (i) => (i * 31) % 251));
    final sent = <Future<void>>[ours.add(Uint8List(0)), ours.add(longest)];
    for (var i = 0; i < 2000; i++) {
      sent.add(ours.add(Uint8List.fromList('small $i'.codeUnits)));
    }
    await Future.wait(sent);
    await _until(() => atB.frames.length == 2002, 'not everything arrived: ${atB.frames.length} of 2002');
    expect(atB.frames[0], isEmpty);
    expect(atB.frames[1], longest);
    for (var i = 0; i < 2000; i++) {
      expect(String.fromCharCodes(atB.frames[2 + i]), 'small $i');
    }
    // A frame is a list of its own: nothing of the library's bytes around it.
    expect(atB.frames[1].offsetInBytes, 0);
    expect(atB.frames[1].buffer.lengthInBytes, P2pNode.maxFrame);

    // The other way, on the same stream.
    await Future.wait([theirs.add(longest), theirs.add(Uint8List(0)), for (var i = 0; i < 500; i++) theirs.add(Uint8List.fromList([i >> 8, i & 255]))]);
    await _until(() => atA.frames.length == 502, 'not everything came back: ${atA.frames.length} of 502');
    expect(atA.frames[0], longest);
    expect(atA.frames[1], isEmpty);
    expect([for (final f in atA.frames.skip(2)) f[0] * 256 + f[1]], List.generate(500, (i) => i));

    // A frame past the longest is not sent at all, and the stream is none the worse.
    await expectLater(ours.add(Uint8List(P2pNode.maxFrame + 1)), _refused);

    // Closed by the one that opened it: what was sent just before still arrives, then the other end's frames are done.
    final last = ours.add(Uint8List.fromList('last'.codeUnits));
    await ours.close();
    await last;
    await ours.close();
    await _until(() => atB.done, 'the other end never saw the close');
    expect(String.fromCharCodes(atB.frames.last), 'last');
    expect(atB.frames.length, 2003);
    expect(atA.done, isTrue);
    await expectLater(ours.add(Uint8List(1)), _refused);
    await expectLater(theirs.add(Uint8List(1)), _refused);
    await theirs.close();
  }, skip: skip, timeout: patient);

  test('a node that was never allowed is turned away; one allowed a channel is refused another; a channel open to all takes anyone', () async {
    final a = await _up(21), b = await _up(22), stranger = await _up(23);
    final where = await _here(b);
    final taken = <P2pStream>[];
    b.opened.listen(taken.add);
    b.allow(a.nodeId!, {P2pChannel.packets});

    await expectLater(stranger.open(b.nodeId!, P2pChannel.packets, hint: where), _refused);
    await expectLater(a.open(b.nodeId!, P2pChannel.hub, hint: where), _refused);
    final ours = await a.open(b.nodeId!, P2pChannel.packets, hint: where);
    await _until(() => taken.length == 1, 'the allowed stream never came');
    expect((taken.single.nodeId, taken.single.channel), (a.nodeId, P2pChannel.packets));

    // A relay hosted here takes hub connections from devices it never heard of, and nothing else from them.
    b.openToAll({P2pChannel.hub});
    final hub = await stranger.open(b.nodeId!, P2pChannel.hub, hint: where);
    await _until(() => taken.length == 2, 'the stream on the open channel never came');
    expect((taken.last.nodeId, taken.last.channel), (stranger.nodeId, P2pChannel.hub));
    await expectLater(stranger.open(b.nodeId!, P2pChannel.packets, hint: where), _refused);
    await expectLater(stranger.open(b.nodeId!, P2pChannel.relays, hint: where), _refused);

    // Open to nobody again: the stranger's stream ends, the allowed node's does not.
    final atStranger = _Heard(hub), atA = _Heard(ours);
    b.openToAll({});
    await _until(() => atStranger.done, 'the stream on a channel that is no longer open was left open');
    await ours.add(Uint8List.fromList([1]));
    expect(atA.done, isFalse);
  }, skip: skip, timeout: patient);

  test('disallow closes everything with that node, and it is turned away after', () async {
    final a = await _up(31), b = await _up(32);
    final where = await _here(b);
    a.allow(b.nodeId!, {P2pChannel.packets});
    b.allow(a.nodeId!, {P2pChannel.packets});
    final pathsAtB = <P2pPath>[];
    b.paths.listen(pathsAtB.add);
    var coming = _next(b);
    final ours = await a.open(b.nodeId!, P2pChannel.packets, hint: where);
    final theirs = await coming;
    // And one the other way, over the link that is up: no hint needed.
    coming = _next(a);
    final back = await b.open(a.nodeId!, P2pChannel.packets);
    final backAtA = await coming;
    final heard = [_Heard(ours), _Heard(theirs), _Heard(back), _Heard(backAtA)];
    await _until(() => b.pathTo(a.nodeId!)?.kind == P2pPathKind.direct, 'the path never said straight');

    b.disallow(a.nodeId!);
    await _until(() => heard.every((h) => h.done), 'a stream was left open: ${[for (final h in heard) h.done]}');
    await _until(() => b.pathTo(a.nodeId!) == null && a.pathTo(b.nodeId!) == null, 'the link was left up');
    expect(pathsAtB.last.kind, P2pPathKind.none);
    expect(pathsAtB.last.nodeId, a.nodeId);
    await expectLater(a.open(b.nodeId!, P2pChannel.packets, hint: where), _refused);
    await expectLater(theirs.add(Uint8List(1)), _refused);
  }, skip: skip, timeout: patient);

  test('stop then start is the same node, and works again and again; who was allowed is still allowed', () async {
    final a = await _up(41), b = await _up(42);
    final id = b.nodeId;
    b.allow(a.nodeId!, {P2pChannel.packets});
    final states = <P2pState>[];
    b.state.addListener(() => states.add(b.state.value));
    for (var round = 0; round < 3; round++) {
      final where = await _here(b);
      final coming = _next(b);
      final ours = await a.open(b.nodeId!, P2pChannel.packets, hint: where);
      final theirs = await coming;
      final atA = _Heard(ours), atB = _Heard(theirs);
      await ours.add(Uint8List.fromList([round]));
      await _until(() => atB.frames.length == 1, 'round $round: the frame never came');
      expect(atB.frames.single, [round]);
      await _until(() => a.pathTo(b.nodeId!)?.kind == P2pPathKind.direct, 'round $round: the path never said straight');
      expect(a.pathTo(b.nodeId!)!.rttMs, lessThan(1000));

      await b.stop();
      // Everything is closed by the time stop is done: its streams, where it was, its links.
      expect(b.state.value, P2pState.off);
      expect(b.whereabouts.value, isNull);
      expect(atB.done, isTrue);
      expect(b.pathTo(a.nodeId!), isNull);
      await expectLater(theirs.add(Uint8List(1)), _refused);
      await expectLater(b.open(a.nodeId!, P2pChannel.packets), _refused);
      await _until(() => atA.done && a.pathTo(b.nodeId!) == null, 'round $round: the other end never saw it go');
      await expectLater(a.open(b.nodeId!, P2pChannel.packets, hint: where, timeout: const Duration(seconds: 1)), _refused);

      await b.start(_config(42));
      expect(b.state.value, P2pState.up);
      expect(b.nodeId, id);
    }
    expect(states, [for (var i = 0; i < 3; i++) ...[P2pState.off, P2pState.starting, P2pState.up]]);
    // Started with what it is up with already: nothing happens.
    await b.start(_config(42));
    expect(states.length, 9);
    // With another key it is stopped and started: another node.
    await b.start(_config(43));
    expect(b.state.value, P2pState.up);
    expect(b.nodeId, isNot(id));
    expect(states.sublist(9), [P2pState.off, P2pState.starting, P2pState.up]);
    b.networkChanged();
  }, skip: skip, timeout: patient);

  test('a listener that pauses holds the sender back, and nothing is lost when it goes on', () async {
    final a = await _up(51), b = await _up(52);
    b.allow(a.nodeId!, {P2pChannel.packets});
    final coming = _next(b);
    final ours = await a.open(b.nodeId!, P2pChannel.packets, hint: await _here(b));
    final theirs = await coming;
    final atB = _Heard(theirs);
    atB.sub.pause();
    // Three of the longest: the first is read and waits here for the listener; with it not taken there is no room for
    // the second, which is not read, and the sender is held where it is.
    final written = [false, false, false];
    final sent = [for (var i = 0; i < 3; i++) ours.add(Uint8List(P2pNode.maxFrame)..[0] = i).then((_) => written[i] = true)];
    await _until(() => written[0], 'the first frame was never sent');
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(atB.frames, isEmpty);
    expect(written.sublist(1), [false, false], reason: 'frames went on being read with nobody taking them');
    atB.sub.resume();
    await Future.wait(sent);
    await _until(() => atB.frames.length == 3, 'a frame was lost: ${atB.frames.length} of 3');
    expect([for (final f in atB.frames) f[0]], [0, 1, 2]);
    expect(atB.frames.every((f) => f.length == P2pNode.maxFrame), isTrue);
  }, skip: skip, timeout: patient);

  test('more than a stream holds waiting closes it, and a stream nobody takes is closed', () async {
    final a = await _up(61), b = await _up(62);
    b.allow(a.nodeId!, {P2pChannel.packets});
    final where = await _here(b);
    // Nobody at the far end listens for streams: the one that comes is closed there, and that is seen here.
    final unwanted = await a.open(b.nodeId!, P2pChannel.packets, hint: where);
    final atUnwanted = _Heard(unwanted);
    await _until(() => atUnwanted.done, 'a stream nobody took was left open');

    // Taken, but its frames never listened to: they are not read past the first, the sender's queue fills, and the
    // sender's stream is closed rather than its queue grown.
    final coming = _next(b);
    final ours = await a.open(b.nodeId!, P2pChannel.packets, hint: where);
    final theirs = await coming;
    final atA = _Heard(ours);
    Object? refusal;
    var queued = 0;
    for (; queued < 64 && refusal == null; queued++) {
      ours.add(Uint8List(P2pNode.maxFrame)).catchError((Object e) {
        refusal ??= e;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(refusal, isA<P2pError>(), reason: 'the queue took $queued frames of the longest and never filled');
    await _until(() => atA.done, 'the stream that overflowed was left open');
    await expectLater(ours.add(Uint8List(1)), _refused);
    // The far end, listening at last, is handed what had come before the end, and then the end.
    final atB = _Heard(theirs);
    await _until(() => atB.done, 'the far end never saw the end');
    expect(atB.frames.length, lessThanOrEqualTo(2));
  }, skip: skip, timeout: patient);

  test('a node that cannot be started says why, and can be started rightly after', () async {
    final node = _node();
    // Thrown, and the node is left down saying the same: by this side's own look at what it was given, and (the
    // last of these) by the library's.
    Matcher saying(String words) => throwsA(isA<P2pError>().having((e) => e.message, 'message', contains(words)));
    await expectLater(node.start(P2pConfig(secret: Uint8List(5))), saying('32 bytes'));
    expect(node.state.value, P2pState.down);
    expect(node.problem, contains('32 bytes'));
    await expectLater(node.start(P2pConfig(secret: _config(71).secret, helpers: const ['http://not-https.example'])), saying('http://not-https.example'));
    expect(node.state.value, P2pState.down);
    expect(node.problem, contains('http://not-https.example'));
    await expectLater(node.start(P2pConfig(secret: _config(71).secret, helpersOnly: true)), saying('link helper'));
    expect(node.state.value, P2pState.down);
    expect(node.problem, contains('link helper'));
    await expectLater(node.start(P2pConfig(secret: _config(71).secret, helpers: const ['https://not a name'])), saying('https://not a name'));
    expect(node.state.value, P2pState.down);
    expect(node.problem, contains('https://not a name'));
    expect(node.whereabouts.value, isNull);
    await expectLater(node.open(await node.idOf(_config(72).secret), 0), _refused);
    await node.start(_config(71));
    expect(node.state.value, P2pState.up);
    expect(node.problem, isNull);
    // Nothing is known of where the other is, and a hint that is no hint is none: said at once, not after the wait.
    final other = await node.idOf(_config(72).secret);
    final asked = Stopwatch()..start();
    await expectLater(node.open(other, 0, timeout: const Duration(seconds: 20)), _refused);
    await expectLater(node.open(other, 0, hint: const Whereabouts(helper: 'https://someone-elses.example', addresses: ['nowhere', '0.0.0.0:1']), timeout: const Duration(seconds: 20)), _refused);
    expect(asked.elapsed, lessThan(const Duration(seconds: 10)));
    expect(() => node.allow('not a node id', {0}), throwsArgumentError);
    expect(() => node.allow(other, {256}), throwsArgumentError);
    node.dispose();
    await expectLater(node.start(_config(71)), _refused);
  }, skip: skip, timeout: patient);
}
