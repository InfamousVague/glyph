// The Figma plugin (lib/plugins/figma/; Matt, 2026-11-02: "Also add a figma plugin"): a link's file and frame read
// from its address, the node-id's hyphen made the API's colon; Figma's API asked through the plugin's host with the
// token, a frame's name, size and picture and a file's thumbnail read, and its refusals; what was learnt kept and
// asked again when stale or after a refusal's wait; the cards' source, which is Rich embeds' own while the plugin is
// off, not connected, Link previews off or Local only on, and falls back to the oEmbed when Figma will not say; a card
// drawn as the frame; and the page, which keeps only a token Figma accepts and forgets twice. Figma is the test's own:
// nothing is asked of the network.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/media/link_cards.dart';
import 'package:ghost_md/editor/media/rich_embeds/cards.dart';
import 'package:ghost_md/editor/media/rich_embeds/oembed.dart';
import 'package:ghost_md/editor/media/rich_embeds/providers.dart';
import 'package:ghost_md/plugins/figma/figma.dart';
import 'package:ghost_md/plugins/figma/manifest.dart' as figma;
import 'package:ghost_md/plugins/github/plain_field.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/rich_embeds/rich_embeds.dart';
import 'package:ghost_md/sync/connections.dart' show syncedSwitches;

import '../../editor/media/support.dart' show pumpNote;
import '../github/support.dart';

const String fileKey = 'abcDEF1234567890ghijKL';
const String frameUrl = 'https://www.figma.com/design/$fileKey/Mobile-app?node-id=12-34&t=xyz';
const String fileUrl = 'https://www.figma.com/file/$fileKey/Mobile-app';
const String framePicture = 'https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/frame.png';
const String fileThumb = 'https://s3-alpha.figma.com/thumbnails/file.png';

RichLink rich(String url) => richLinkOf(url)!;

/// Figma as the test has it: a file with one frame, unless told to refuse.
FetchResponse figmaAnswers(FetchRequest request, {int? refuse, Map<String, String> headers = const {}}) {
  if (refuse != null) return FetchResponse(refuse, headers: {'content-type': 'application/json', ...headers}, bytes: Uint8List.fromList('{"status":$refuse,"err":"${refuse == 403 ? 'Invalid token' : 'Not found'}"}'.codeUnits));
  final path = request.url.path;
  if (path == '/v1/me') return FetchResponse.json(200, {'id': '1', 'handle': 'Matt', 'email': 'matt@example.com'});
  if (path == '/v1/files/$fileKey/nodes') {
    return FetchResponse.json(200, {
      'name': 'Mobile app',
      'thumbnailUrl': fileThumb,
      'nodes': {
        '12:34': {
          'document': {
            'id': '12:34',
            'name': 'Login',
            'type': 'FRAME',
            'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 390, 'height': 844},
          },
        },
      },
    });
  }
  if (path == '/v1/images/$fileKey') return FetchResponse.json(200, {'err': null, 'images': {'12:34': framePicture}});
  if (path == '/v1/files/$fileKey') return FetchResponse.json(200, {'name': 'Mobile app', 'thumbnailUrl': fileThumb, 'document': {'children': []}});
  return FetchResponse.json(404, {'status': 404, 'err': 'Not found'});
}

/// Rich embeds' own oEmbed, as the test has it.
class Embeds {
  final List<RichLink> asked = [];
  final Map<String, Completer<OEmbed>> out = {};

  Future<OEmbed> fetch(RichLink link) {
    asked.add(link);
    return (out[link.key] = Completer<OEmbed>()).future;
  }

  final List<String> pictures = [];
  Future<Uint8List> picture(String address) async {
    pictures.add(address);
    return Uint8List(0);
  }
}

void main() {
  group('a link’s file and frame', () {
    test('the node-id’s hyphen is the API’s colon, and a link without one is the file', () {
      expect(figmaLinkOfUrl(frameUrl), const FigmaLink(fileKey: fileKey, nodeId: '12:34'));
      expect(figmaLinkOfUrl(fileUrl), const FigmaLink(fileKey: fileKey));
      expect(figmaLinkOfUrl('https://figma.com/proto/$fileKey/Flow?node-id=1-2&starting-point-node-id=1%3A2'), const FigmaLink(fileKey: fileKey, nodeId: '1:2'));
      expect(figmaLinkOfUrl('https://www.figma.com/board/$fileKey/Jam?node-id=0-1'), const FigmaLink(fileKey: fileKey, nodeId: '0:1'));
      // An older link wrote the colon itself, escaped.
      expect(figmaLinkOfUrl('https://www.figma.com/file/$fileKey/Old?node-id=12%3A34'), const FigmaLink(fileKey: fileKey, nodeId: '12:34'));
      // An instance's layer.
      expect(figmaLinkOfUrl('https://www.figma.com/design/$fileKey/X?node-id=I5-6%3B7-8')?.nodeId, 'I5:6;7:8');
      expect(figmaLinkOfUrl(frameUrl)!.key, '$fileKey/12:34');
    });

    test('a branch is its own file; a community file, another service and nonsense are not the plugin’s', () {
      expect(figmaLinkOfUrl('https://www.figma.com/design/$fileKey/branch/zyxWVU0987654321/Mobile?node-id=1-2'), const FigmaLink(fileKey: 'zyxWVU0987654321', nodeId: '1:2'));
      expect(figmaLinkOfUrl('https://www.figma.com/community/file/1234567890123/Kit'), isNull);
      expect(figmaLinkOfUrl('https://youtu.be/dQw4w9WgXcQ'), isNull);
      expect(figmaLinkOfUrl('https://www.figma.com/design/$fileKey/X?node-id=<script>')?.nodeId, isNull);
    });

    test('a frame’s picture is asked about a card wide, never past 2', () {
      expect(pictureScale(390, 844), '2');
      expect(pictureScale(1440, 900), '1.11');
      expect(pictureScale(1440, 9000), '0.27');
      expect(pictureScale(null, null), '2');
      expect(pictureScale(800, 0), '2');
    });
  });

  group('Figma’s API', () {
    late TestGround ground;
    setUp(() => ground = useGround((request) async => figmaAnswers(request)));

    test('a frame: its node with the API’s colon, its picture at its scale, with the token, from api.figma.com', () async {
      final frame = await FigmaClient(token: 'figd_test').frame(figmaLinkOfUrl(frameUrl)!);
      expect(frame, const FigmaFrame(file: 'Mobile app', frame: 'Login', picture: framePicture, width: 390, height: 844));
      expect([for (final asked in ground.asked) asked.url.path], ['/v1/files/$fileKey/nodes', '/v1/images/$fileKey']);
      expect(ground.asked.first.url.queryParameters, {'ids': '12:34', 'depth': '1'});
      expect(ground.asked.last.url.queryParameters, {'ids': '12:34', 'format': 'png', 'scale': '2'});
      for (final asked in ground.asked) {
        expect(asked.url.host, 'api.figma.com');
        expect(header(asked, 'X-Figma-Token'), 'figd_test');
      }
    });

    test('a file: its name and thumbnail, from one call', () async {
      final frame = await FigmaClient(token: 'figd_test').frame(figmaLinkOfUrl(fileUrl)!);
      expect(frame, const FigmaFrame(file: 'Mobile app', picture: fileThumb));
      expect(ground.asked.single.url.path, '/v1/files/$fileKey');
      expect(ground.asked.single.url.queryParameters, {'depth': '1'});
    });

    test('a frame the file no longer has, or one Figma draws nothing of, is the file’s thumbnail', () async {
      useGround((request) async => request.url.path.endsWith('/nodes') ? FetchResponse.json(200, {'name': 'Mobile app', 'thumbnailUrl': fileThumb, 'nodes': {'12:34': null}}) : figmaAnswers(request));
      expect(await FigmaClient(token: 't').frame(figmaLinkOfUrl(frameUrl)!), const FigmaFrame(file: 'Mobile app', picture: fileThumb));
      useGround((request) async => request.url.path.startsWith('/v1/images') ? FetchResponse.json(200, {'err': null, 'images': {'12:34': null}}) : figmaAnswers(request));
      expect(await FigmaClient(token: 't').frame(figmaLinkOfUrl(frameUrl)!), const FigmaFrame(file: 'Mobile app', frame: 'Login', picture: fileThumb));
    });

    test('whose the token is', () async {
      final account = await FigmaClient(token: 't').me();
      expect(account.words, 'Matt · matt@example.com');
      expect(ground.asked.single.url.toString(), 'https://api.figma.com/v1/me');
    });

    test('refusals are failures: a token Figma does not know, a scope it lacks, a file not there, too many asks, no answer', () async {
      Future<FigmaFailure> failing(FetchResponse Function(FetchRequest request) answer) async {
        useGround((request) async => answer(request));
        try {
          await FigmaClient(token: 't').frame(figmaLinkOfUrl(frameUrl)!);
        } on FigmaFailure catch (failure) {
          return failure;
        }
        fail('it answered');
      }

      final bad = await failing((r) => figmaAnswers(r, refuse: 403));
      expect((bad.status, bad.badToken, bad.scope), (403, true, false));
      final scope = await failing((r) => FetchResponse.json(403, {'status': 403, 'err': 'Invalid scope(s): current_user:read'}));
      expect((scope.badToken, scope.scope), (false, true));
      final missing = await failing((r) => figmaAnswers(r, refuse: 404));
      expect((missing.status, missing.badToken), (404, false));
      final busy = await failing((r) => figmaAnswers(r, refuse: 429, headers: {'Retry-After': '90'}));
      expect((busy.busy, busy.retryAfter), (true, const Duration(seconds: 90)));
      final none = await failing((r) => throw const SocketLike());
      expect((none.status, none.message), (null, figmaUnreachable));
    });
  });

  group('what was learnt, kept', () {
    late TestGround ground;
    late int now;
    late FigmaFrames frames;
    late List<FetchRequest> asked;
    FetchResponse Function(FetchRequest request) answer = figmaAnswers;

    setUp(() {
      now = 1000000;
      answer = figmaAnswers;
      ground = useGround((request) async => answer(request));
      asked = ground.asked;
      frames = FigmaFrames(client: () => FigmaClient(token: 'figd_test'), now: () => now);
    });

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('asked once, kept in the plugin’s storage, and asked again only once it is stale', () async {
      final link = figmaLinkOfUrl(frameUrl)!;
      var told = 0;
      frames.addListener(() => told++);
      frames.want(link);
      frames.want(link);
      await settle();
      expect(asked, hasLength(2), reason: 'the node and its picture, once');
      expect(told, 1);
      expect(frames.frameFor(link)?.frame, 'Login');
      // Another reader of the same storage (the app again, after a restart) knows it without asking.
      expect(FigmaFrames(client: () => fail('asked'), now: () => now).frameFor(link)?.picture, framePicture);
      expect(ground.kept.read<Object?>(figma.framesKey, null, (v) => v), isA<Map>());
      now += const Duration(days: 4).inMilliseconds;
      frames.want(link);
      await settle();
      expect(asked, hasLength(2), reason: 'still fresh');
      now += const Duration(days: 2).inMilliseconds;
      frames.want(link);
      await settle();
      expect(asked, hasLength(4), reason: 'stale: Figma’s picture addresses do not last for ever');
    });

    test('a refusal is kept a day, a 429 as long as Figma said, and no answer ten minutes; a new token forgets them', () async {
      final link = figmaLinkOfUrl(frameUrl)!;
      var failed = 0;
      answer = (r) => figmaAnswers(r, refuse: 404);
      frames.want(link, failed: () => failed++);
      await settle();
      expect((frames.failedFor(link), frames.frameFor(link), failed), (true, null, 1));
      now += const Duration(hours: 23).inMilliseconds;
      frames.want(link);
      await settle();
      expect(asked, hasLength(1));
      now += const Duration(hours: 2).inMilliseconds;
      answer = (r) => figmaAnswers(r, refuse: 429, headers: {'Retry-After': '120'});
      frames.want(link);
      await settle();
      expect(asked, hasLength(2));
      now += 100000;
      frames.want(link);
      await settle();
      expect(asked, hasLength(2), reason: 'Figma asked for two minutes');
      now += 30000;
      answer = (r) => throw const SocketLike();
      frames.want(link);
      await settle();
      expect(asked, hasLength(3));
      now += const Duration(minutes: 9).inMilliseconds;
      frames.want(link);
      await settle();
      expect(asked, hasLength(3));
      answer = figmaAnswers;
      frames.forgetFailures();
      frames.want(link);
      await settle();
      expect(frames.frameFor(link)?.frame, 'Login');
      frames.forgetAll();
      expect(frames.frameFor(link), isNull);
    });
  });

  group('the cards’ source', () {
    late Registry before;
    late Registry registry;
    late TestGround ground;
    late Embeds service;
    late bool previews, localOnly;
    late KeptEmbeds base;
    late FigmaFrames frames;
    late FigmaEmbeds embeds;

    setUp(() async {
      before = plugins;
      previews = true;
      localOnly = false;
      registry = createRegistry([richEmbedsPlugin, figmaPlugin], store: MemorySwitches(), localOnly: () => localOnly);
      usePlugins(registry);
      ground = useGround((request) async => figmaAnswers(request));
      service = Embeds();
      base = KeptEmbeds(MemoryStored(), fetch: service.fetch, pictures: service.picture, allowed: () => previews && !localOnly);
      frames = FigmaFrames();
      embeds = FigmaEmbeds(base, frames: frames);
    });
    tearDown(() {
      embeds.dispose();
      usePlugins(before);
    });

    Future<void> connect() async {
      registry.setEnabled('figma', true);
      await figma.host.secrets.write(figma.tokenSecret, 'figd_test');
    }

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('ships off, its switch follows the account, and off or not connected the card is Rich embeds’ and Figma’s API is asked nothing', () async {
      expect(figma.manifest.standard, isFalse);
      expect(syncedSwitches, contains('figma'));
      expect(figmaFramesOn(), isFalse);
      embeds.wantEmbed(rich(frameUrl));
      await settle();
      expect(service.asked.single.source, frameUrl);
      expect(ground.asked, isEmpty);
      // On, but no token yet: the same.
      registry.setEnabled('figma', true);
      expect(figmaFramesOn(), isFalse);
      embeds.wantEmbed(rich(fileUrl));
      await settle();
      expect(ground.asked, isEmpty);
      expect(service.asked, hasLength(2));
    });

    test('connected, a frame’s card is the frame: its name, its file’s, its picture in its shape, and the oEmbed is not asked', () async {
      await connect();
      expect(figmaFramesOn(), isTrue);
      var told = 0;
      embeds.addListener(() => told++);
      final link = rich(frameUrl);
      embeds.wantEmbed(link);
      expect(embeds.embedFor(link), isNull, reason: 'waiting for Figma');
      expect(embeds.failedFor(link), isFalse);
      await settle();
      expect(embeds.embedFor(link), const OEmbed(title: 'Login', author: 'Mobile app', thumbnail: framePicture, thumbnailWidth: 390, thumbnailHeight: 844));
      expect(service.asked, isEmpty);
      expect(told, greaterThan(0));
      // Another service's link is the embeds' own.
      embeds.wantEmbed(rich('https://youtu.be/dQw4w9WgXcQ'));
      expect(service.asked.single.service, EmbedService.youtube);
    });

    test('connected while a card is on screen, the card is asked of Figma at once; disconnected, of the oEmbed', () async {
      var told = 0;
      embeds.addListener(() => told++);
      final link = rich(frameUrl);
      embeds.wantEmbed(link);
      await settle();
      expect((service.asked.length, ground.asked.length), (1, 0));
      await connect();
      await settle();
      expect(ground.asked, isNotEmpty, reason: 'asked as the token was kept');
      expect(embeds.embedFor(link)?.title, 'Login');
      expect(told, greaterThan(0));
      await figma.host.secrets.write(figma.tokenSecret, null);
      await settle();
      expect(embeds.embedFor(link), isNull, reason: 'the oEmbed, still out: Rich embeds’ card again');
    });

    test('Figma refusing falls back to the oEmbed quietly: its answer, or the plain card where it has none', () async {
      await connect();
      useGround((request) async => figmaAnswers(request, refuse: 404));
      await figma.host.secrets.write(figma.tokenSecret, 'figd_test');
      final link = rich(frameUrl);
      embeds.wantEmbed(link);
      await settle();
      expect(service.asked.single.source, frameUrl, reason: 'asked as Rich embeds asks it, once Figma said no');
      expect(embeds.failedFor(link), isFalse, reason: 'the oEmbed is still out');
      service.out[link.key]!.complete(const OEmbed(title: 'Mobile app', author: 'Matt', thumbnail: fileThumb));
      await settle();
      expect(embeds.embedFor(link)?.title, 'Mobile app');
      final other = rich(fileUrl);
      embeds.wantEmbed(other);
      await settle();
      service.out[other.key]!.completeError(const EmbedError('The service answered 404.'));
      await settle();
      expect(embeds.failedFor(other), isTrue, reason: 'neither would say: the plain card');
    });

    test('Link previews off or Local only on: nothing is asked of Figma, and under Local only the plugin is off', () async {
      await connect();
      previews = false;
      expect(embeds.allowed, isFalse);
      embeds.wantEmbed(rich(frameUrl));
      await settle();
      expect(ground.asked, isEmpty);
      expect(service.asked, isEmpty);
      previews = true;
      localOnly = true;
      expect(figmaFramesOn(), isFalse);
      expect(embeds.allowed, isFalse);
      embeds.wantEmbed(rich(frameUrl));
      await settle();
      expect(ground.asked, isEmpty);
    });

    testWidgets('a frame’s link alone on its line is drawn as the frame, with Rich embeds off too', (tester) async {
      await connect();
      registry.setEnabled(richEmbedsManifest.id, false);
      await tester.runAsync(() async {
        frames.want(figmaLinkOfUrl(frameUrl)!);
        await settle();
      });
      await pumpNote(tester, 'Designs\n- $frameUrl\nafter', more: [linkCards(enabled: () => previews, embeds: embeds)]);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('cm-embedCard-figma')), findsOneWidget);
      expect(tester.state<RichEmbedCardState>(find.byType(RichEmbedCard)).phase, EmbedCardPhase.preview);
      String said(String key) => tester.widgetList<InlineWords>(find.byKey(ValueKey<String>(key))).map((w) => w.text).join();
      expect(said('cm-embed-title'), 'Login');
      expect(said('cm-embed-about'), 'Mobile app · Figma design');
      expect(service.pictures, [framePicture]);
      // Disconnected, and Rich embeds off: a plain link card again.
      await tester.runAsync(() => figma.host.secrets.write(figma.tokenSecret, null));
      registry.setEnabled('figma', false);
      await tester.pump();
      await tester.pump();
      expect(find.byType(RichEmbedCard), findsNothing);
    });
  });

  group('the page', () {
    late TestGround ground;
    late FigmaFrames frames;
    FetchResponse Function(FetchRequest request) answer = figmaAnswers;

    setUp(() {
      answer = figmaAnswers;
      ground = useGround((request) async => answer(request));
      frames = FigmaFrames();
    });

    Future<void> type(WidgetTester tester, String token) async {
      await tester.enterText(find.descendant(of: find.byType(PlainField), matching: find.byType(EditableText)), token);
      await tester.pump();
    }

    testWidgets('keeps a token Figma accepts and says whose it is; refuses one it does not; Disconnect asks twice and forgets', (tester) async {
      await pumpPane(tester, FigmaPane(frames: frames));
      expect(figmaPlugin.settings!.summary(), 'Not connected');
      expect(find.byKey(const ValueKey('figma-token-new')), findsOneWidget);
      expect(actionEnabled(tester, 'Connect'), isFalse);
      answer = (r) => figmaAnswers(r, refuse: 403);
      await type(tester, '  figd_not_a_real_token_at_all  ');
      await press(tester, action('Connect'));
      expect(ground.asked.single.url.path, '/v1/me');
      expect(ground.secrets.held, isEmpty);
      expect(textOf(tester), contains('Figma didn’t accept that token'));
      answer = figmaAnswers;
      await press(tester, action('Connect'));
      expect(ground.secrets.held, {figma.tokenSecret: 'figd_not_a_real_token_at_all'});
      expect(header(ground.asked.last, 'X-Figma-Token'), 'figd_not_a_real_token_at_all');
      expect(textOf(tester), contains('The token works. It is Matt · matt@example.com’s.'));
      expect(textOf(tester), contains('Connected as Matt · matt@example.com'));
      expect(textOf(tester), isNot(contains('figd_not_a_real_token_at_all')));
      expect(figmaPlugin.settings!.summary(), 'Connected');
      frames.want(figmaLinkOfUrl(frameUrl)!);
      await settle(tester);
      expect(frames.frameFor(figmaLinkOfUrl(frameUrl)!), isNotNull);
      await press(tester, action('Disconnect'));
      expect(ground.secrets.held, isNotEmpty, reason: 'asked twice');
      await press(tester, action('Tap again'));
      expect(ground.secrets.held, isEmpty);
      expect(frames.frameFor(figmaLinkOfUrl(frameUrl)!), isNull, reason: 'what the cards learnt, forgotten');
      expect(find.byKey(const ValueKey('figma-token-new')), findsOneWidget);
      await away(tester);
    });

    testWidgets('in Simple the token is all of it, and More shows the rest in place', (tester) async {
      await pumpPane(tester, FigmaPane(frames: frames));
      expect(find.byKey(const ValueKey('figma-more'), skipOffstage: false), findsNothing, reason: 'Advanced has it all');
      final shows = find.byKey(const ValueKey('figma-shows-frame'), skipOffstage: false);
      expect(shows, findsOneWidget);
      preferences.value = preferences.value.copyWith(experience: 'simple');
      await tester.pump();
      expect(shows, findsNothing);
      await press(tester, action('Show'));
      expect(shows, findsOneWidget);
      expect(find.byKey(const ValueKey('figma-more'), skipOffstage: false), findsNothing);
      await away(tester);
    });
  });
}

/// Nothing answered.
class SocketLike implements Exception {
  const SocketLike();
}
