import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/details_cache.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/types.dart';

import 'support.dart';

/// The cache behind Notion's and GitHub's pills (lib/plugins/details_cache.dart), case for case from
/// `src/app/plugins/detailsCache.test.ts`, with the service stood in for by a `read` whose answers each test holds
/// and lets go of: how many are read at once, when an answer is fresh enough not to read again, when a failure is
/// tried again, and what is kept across a reload and how much.
///
/// What differs from the web's cases: the clock is the cache's own `now`, moved by the test, where the page faked
/// the system's. The last group is what the page had no case for.

final PluginManifest manifest = manifestOf('test', name: 'Test', standard: false, storage: ['glyph-test-details']);

MarkDetails details(String title, int readAt) => MarkDetails(url: 'https://x/$title', title: title, readAt: readAt);

/// A read per call, each answered when the test says.
class Service {
  final List<({String key, Completer<MarkDetails> answer})> calls = [];

  Future<MarkDetails> read(String key, String url) {
    final answer = Completer<MarkDetails>();
    calls.add((key: key, answer: answer));
    return answer.future;
  }
}

/// Lets the answered reads land, and the queue move on.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.value();
  }
}

void main() {
  late TestGround on;
  late PluginHost host;
  var now = 0;

  ({DetailsCache cache, Service service}) cache({int keep = 300, bool Function()? ready}) {
    final service = Service();
    return (cache: DetailsCache(host: host, storageKey: 'glyph-test-details', read: service.read, keep: keep, ready: ready, now: () => now), service: service);
  }

  setUp(() {
    on = TestGround();
    host = createHost(manifest, ground: on.ground);
    now = DateTime.utc(2026, 9, 25, 12).millisecondsSinceEpoch;
  });

  group('the details cache', () {
    test('reads two at a time and queues the rest, in the order they were wanted', () async {
      final (cache: c, :service) = cache();
      for (final key in ['a', 'b', 'c', 'd']) {
        c.want(key, 'https://x/$key');
      }
      expect([for (final call in service.calls) call.key], ['a', 'b']);
      expect(c.peek('c'), isA<MarkLoading>());
      service.calls[0].answer.complete(details('a', now));
      await settle();
      expect([for (final call in service.calls) call.key], ['a', 'b', 'c']);
      final a = c.peek('a');
      expect(a, isA<MarkReady>().having((r) => r.details.title, 'title', 'a').having((r) => r.loading, 'loading', isFalse));
    });

    test('does not read again while an answer is fresh, and does once it is 45 seconds old or asked by hand', () async {
      final (cache: c, :service) = cache();
      c.want('a', 'https://x/a');
      service.calls[0].answer.complete(details('a', now));
      await settle();
      c.want('a', 'https://x/a');
      expect(service.calls, hasLength(1));
      // A Refresh by hand reads whatever is kept, and the pill keeps its answer while it does.
      c.want('a', 'https://x/a', fresh: true);
      expect(service.calls, hasLength(2));
      expect(c.peek('a'), isA<MarkReady>().having((r) => r.loading, 'loading', isTrue));
      service.calls[1].answer.complete(details('a', now));
      await settle();
      now += 46000;
      c.want('a', 'https://x/a');
      expect(service.calls, hasLength(3));
    });

    test('says what a failed read said, and tries again only once the failure is as old as a stale answer', () async {
      final (cache: c, :service) = cache();
      c.want('a', 'https://x/a');
      service.calls[0].answer.completeError(Exception('The network is not back yet.'));
      await settle();
      expect(c.peek('a'), isA<MarkFailed>().having((f) => f.message, 'message', 'The network is not back yet.'));
      c.want('a', 'https://x/a');
      expect(service.calls, hasLength(1));
      now += 46000;
      c.want('a', 'https://x/a');
      expect(service.calls, hasLength(2));
    });

    test('keeps the answer it had over a read that fails', () async {
      final (cache: c, :service) = cache();
      c.want('a', 'https://x/a');
      service.calls[0].answer.complete(details('a', now));
      await settle();
      c.want('a', 'https://x/a', fresh: true);
      service.calls[1].answer.completeError(Exception('Rate limited.'));
      await settle();
      expect(c.peek('a'), isA<MarkReady>().having((r) => r.details.title, 'title', 'a').having((r) => r.loading, 'loading', isFalse));
    });

    test('reads a stale answer again at once after its re-read failed, rather than waiting out the failure', () async {
      final (cache: c, :service) = cache();
      c.want('a', 'https://x/a');
      service.calls[0].answer.complete(details('a', now));
      await settle();
      now += 46000;
      c.want('a', 'https://x/a');
      service.calls[1].answer.completeError(Exception('The network is not back yet.'));
      await settle();
      // The pill keeps the answer it had, not the failure,
      expect(c.peek('a'), isA<MarkReady>().having((r) => r.details.title, 'title', 'a').having((r) => r.loading, 'loading', isFalse));
      // and the answer is as stale as before, so the next time it is drawn it is read again.
      c.want('a', 'https://x/a');
      expect(service.calls, hasLength(3));
    });

    test('keeps the newest answers across a reload, and leaves out what another build kept in another shape', () async {
      final first = cache(keep: 2);
      first.cache.keep('old', details('old', now - 3000));
      first.cache.keep('mid', details('mid', now - 2000));
      first.cache.keep('new', details('new', now - 1000));
      final kept = (jsonDecode(on.kept.readText('glyph-test-details')!) as Map).cast<String, Object?>();
      expect(kept.keys, ['new', 'mid']);
      on.kept.writeText('glyph-test-details', jsonEncode({...kept, 'odd': {'title': 7}, 'gone': null}));
      final second = cache();
      expect(second.cache.peek('mid'), isA<MarkReady>().having((r) => r.details.title, 'title', 'mid'));
      expect(second.cache.peek('odd'), isNull);
      expect(second.cache.peek('old'), isNull);
    });

    test('asks nothing before it is ready, and tells the pills every time something changes', () async {
      var ready = false;
      var heard = 0;
      final stop = onMarkDetails(() => heard++);
      addTearDown(stop);
      final (cache: c, :service) = cache(ready: () => ready);
      c.want('a', 'https://x/a');
      expect(service.calls, isEmpty);
      ready = true;
      c.want('a', 'https://x/a');
      service.calls[0].answer.complete(details('a', now));
      await settle();
      expect(heard, 1);
      c.forget();
      expect(heard, 2);
      expect(c.peek('a'), isNull);
      expect(on.kept.readText('glyph-test-details'), isNull);
    });
  });

  // ---- not on the page ---------------------------------------------------------------------------------------------

  group('the details cache, further', () {
    test('reads one now, outside the queue, and answers what it kept', () async {
      final (cache: c, :service) = cache();
      expect(c.details('a'), isNull);
      final read = c.reread('a', 'https://x/a');
      service.calls[0].answer.complete(details('a', now));
      await read;
      expect(c.details('a')?.title, 'a');
      expect(on.kept.readText('glyph-test-details'), contains('"a"'));
    });

    test('keeps answers read in the same moment in the order they were known', () {
      final (cache: c, service: _) = cache();
      for (final key in ['one', 'two', 'three']) {
        c.keep(key, details(key, now));
      }
      expect((jsonDecode(on.kept.readText('glyph-test-details')!) as Map).keys, ['one', 'two', 'three']);
    });

    test('says a read that threw where it was asked as a failure, as one that failed later', () async {
      final c = DetailsCache(host: host, storageKey: 'glyph-test-details', read: (key, url) => throw StateError('No board is linked.'), now: () => now);
      c.want('a', 'https://x/a');
      await settle();
      expect(c.peek('a'), isA<MarkFailed>().having((f) => f.message, 'message', 'No board is linked.'));
    });

    test('must keep under a key its plugin owns', () {
      final c = DetailsCache(host: host, storageKey: 'glyph-notes', read: Service().read, now: () => now);
      expect(() => c.peek('a'), throwsA(isA<PluginPermissionError>()));
    });
  });

  group('a failure’s words', () {
    test('are its message when it carries one, and its own words without Dart’s label otherwise', () {
      expect(failureWords(Exception('Rate limited.')), 'Rate limited.');
      expect(failureWords(StateError('No board is linked.')), 'No board is linked.');
      expect(failureWords('Said as words.'), 'Said as words.');
      expect(failureWords(null), 'Something went wrong.');
      expect(failureWords(const FormatException('Not JSON')), 'Not JSON');
      expect(failureWords(PluginPermissionError(manifest, 'the host “x”')), "The Test plugin didn't declare the host “x”.");
      expect(failureWords(42), '42');
    });
  });
}
