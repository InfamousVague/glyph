// Rich embeds' links and what their services say of them (lib/editor/media/rich_embeds/providers.dart and
// oembed.dart; Matt: "Rich embeds: YouTube, Spotify and Figma links as playable or previewable cards, not just link
// cards"): which addresses are which, where a video starts, the oEmbed read with a fake GET and with a server on
// 127.0.0.1, and what is kept on the device, for how long, and only while asking is allowed. Nothing here leaves
// this machine.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/media/rich_embeds/oembed.dart';
import 'package:ghost_md/editor/media/rich_embeds/players.dart';
import 'package:ghost_md/editor/media/rich_embeds/providers.dart';

const String video = 'dQw4w9WgXcQ';
const String track = '4uLU6hMCjMI75M1A2tKUQC';
const String figmaKey = 'abcDEF1234567890ghijKL';

EmbedAnswer answer(int status, String body) => (status: status, body: Uint8List.fromList(utf8.encode(body)));

void main() {
  group('YouTube links', () {
    test('every way a video is written is the same video', () {
      for (final url in <String>[
        'https://www.youtube.com/watch?v=$video',
        'https://youtube.com/watch?v=$video&list=PL123&index=2',
        'http://www.youtube.com/watch?feature=share&v=$video',
        'https://m.youtube.com/watch?v=$video',
        'https://music.youtube.com/watch?v=$video&si=abc',
        'https://youtu.be/$video',
        'https://youtu.be/$video?si=Xy12',
        'https://www.youtube.com/embed/$video',
        'https://www.youtube-nocookie.com/embed/$video',
        'https://www.youtube.com/live/$video?feature=shared',
        'https://www.youtube.com/v/$video',
        'https://WWW.YouTube.com/watch?v=$video',
      ]) {
        final link = richLinkOf(url);
        expect(link, isNotNull, reason: url);
        expect((link!.service, link.id, link.kind), (EmbedService.youtube, video, 'video'), reason: url);
        expect(link.source, url);
      }
    });

    test('a short is a video of its own kind', () {
      final link = richLinkOf('https://www.youtube.com/shorts/$video?feature=share')!;
      expect((link.id, link.kind, link.kindName), (video, 'short', 'Short'));
    });

    test('reads the start time however it is written, and leaves none for the beginning', () {
      int? from(String url) => richLinkOf(url)!.start;
      expect(from('https://youtu.be/$video?t=90'), 90);
      expect(from('https://youtu.be/$video?t=90s'), 90);
      expect(from('https://www.youtube.com/watch?v=$video&t=1m30s'), 90);
      expect(from('https://www.youtube.com/watch?v=$video&t=1h2m3s'), 3723);
      expect(from('https://www.youtube.com/watch?v=$video&t=2m'), 120);
      expect(from('https://www.youtube.com/watch?v=$video#t=45'), 45);
      expect(from('https://www.youtube.com/embed/$video?start=30'), 30);
      expect(from('https://youtu.be/$video?t=0'), isNull);
      expect(from('https://youtu.be/$video?t=soon'), isNull);
      expect(from('https://youtu.be/$video'), isNull);
    });

    test('the player starts there, without YouTube’s cookies, and plays inline once tapped', () {
      final link = richLinkOf('https://youtu.be/$video?t=1m5s')!;
      expect(link.player.host, 'www.youtube-nocookie.com');
      expect(link.player.path, '/embed/$video');
      expect(link.player.queryParameters, <String, String>{'autoplay': '1', 'playsinline': '1', 'rel': '0', 'start': '65'});
      expect(richLinkOf('https://youtu.be/$video')!.player.queryParameters.containsKey('start'), isFalse);
      expect(link.oEmbed.toString(), 'https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D$video&format=json');
      expect(link.stillGuess, 'https://i.ytimg.com/vi/$video/hqdefault.jpg');
      expect(link.openUrl, 'https://youtu.be/$video?t=1m5s', reason: 'Open in YouTube opens the link as it was written');
      expect(link.playsInline, isTrue);
    });

    test('is not a channel, a playlist, a search, a bad id or another site', () {
      for (final url in <String>[
        'https://www.youtube.com/',
        'https://www.youtube.com/@somebody',
        'https://www.youtube.com/channel/UC1234567890',
        'https://www.youtube.com/playlist?list=PL1234567890',
        'https://www.youtube.com/results?search_query=cats',
        'https://www.youtube.com/watch',
        'https://www.youtube.com/watch?v=short',
        'https://www.youtube.com/watch?v=$video!',
        'https://youtu.be/',
        'https://notyoutube.com/watch?v=$video',
        'https://www.youtube.com.example.com/watch?v=$video',
        'ftp://www.youtube.com/watch?v=$video',
        'youtube.com/watch?v=$video',
      ]) {
        expect(richLinkOf(url), isNull, reason: url);
      }
    });
  });

  group('Spotify links', () {
    test('a track, an album, a playlist, an episode and a show, by address and by URI', () {
      for (final kind in <String>['track', 'album', 'playlist', 'episode', 'show']) {
        for (final url in <String>[
          'https://open.spotify.com/$kind/$track',
          'https://open.spotify.com/$kind/$track?si=0123abcd',
          'https://open.spotify.com/intl-de/$kind/$track',
          'https://open.spotify.com/intl-pt-BR/$kind/$track',
          'https://open.spotify.com/embed/$kind/$track',
          'spotify:$kind:$track',
        ]) {
          final link = richLinkOf(url);
          expect(link, isNotNull, reason: url);
          expect((link!.service, link.kind, link.id), (EmbedService.spotify, kind, track), reason: url);
          expect(link.openUrl, 'https://open.spotify.com/$kind/$track', reason: 'a URI opens as its page, which Spotify takes');
          expect(link.player.toString(), 'https://open.spotify.com/embed/$kind/$track?utm_source=oembed');
        }
      }
      expect(richLinkOf('spotify:user:spotify:playlist:$track')?.kind, 'playlist');
    });

    test('its player is compact for one song or episode and taller for the rest', () {
      expect(richLinkOf('https://open.spotify.com/track/$track')!.playerHeight, 152);
      expect(richLinkOf('https://open.spotify.com/episode/$track')!.playerHeight, 152);
      expect(richLinkOf('https://open.spotify.com/album/$track')!.playerHeight, 352);
      expect(richLinkOf('https://open.spotify.com/playlist/$track')!.playerHeight, 352);
      expect(richLinkOf('https://open.spotify.com/show/$track')!.kindName, 'Podcast');
      expect(richLinkOf('https://open.spotify.com/track/$track')!.oEmbed.toString(), 'https://open.spotify.com/oembed?url=https%3A%2F%2Fopen.spotify.com%2Ftrack%2F$track');
    });

    test('is not an artist, a user, a short id, another host or a bare word', () {
      for (final url in <String>[
        'https://open.spotify.com/artist/$track',
        'https://open.spotify.com/user/somebody',
        'https://open.spotify.com/track/abc',
        'https://open.spotify.com/track',
        'https://open.spotify.com/',
        'https://spotify.com/track/$track',
        'https://open.spotify.com.evil.dev/track/$track',
        'spotify:artist:$track',
        'spotify:track',
        'spotify:track:abc',
      ]) {
        expect(richLinkOf(url), isNull, reason: url);
      }
    });
  });

  group('Figma links', () {
    test('a community file is a Figma card, opened by Figma\'s embed though its oEmbed refuses it', () {
      final link = richLinkOf('https://www.figma.com/community/file/1035203688168086460/material-3-design-kit')!;
      expect((link.service, link.kind, link.id, link.kindName), (EmbedService.figma, 'community', '1035203688168086460', 'Community file'));
      expect(link.player.queryParameters['url'], 'https://www.figma.com/community/file/1035203688168086460/material-3-design-kit');
      expect(richLinkOf('https://www.figma.com/community/plugin/123456789012'), isNull, reason: 'a plugin has no file to show');
    });

    test('a file, a design, a prototype and a board, with their pages and nodes', () {
      for (final kind in <String>['file', 'design', 'proto', 'board']) {
        final url = 'https://www.figma.com/$kind/$figmaKey/Home-screen?node-id=1-2&t=xyz';
        final link = richLinkOf(url)!;
        expect((link.service, link.kind, link.id), (EmbedService.figma, kind, figmaKey));
        expect(link.playsInline, isFalse, reason: 'a file opens over the app');
        expect(link.player.toString(), 'https://www.figma.com/embed?embed_host=ghostmd&url=${Uri.encodeQueryComponent(url)}');
        expect(link.oEmbed.toString(), 'https://www.figma.com/api/oembed?url=${Uri.encodeQueryComponent(url)}');
      }
      expect(richLinkOf('https://figma.com/design/$figmaKey')!.source, 'https://figma.com/design/$figmaKey');
      expect(richLinkOf('http://www.figma.com/file/$figmaKey/x')!.source, 'https://www.figma.com/file/$figmaKey/x', reason: 'asked and opened over https');
      expect(richLinkOf('https://www.figma.com/proto/$figmaKey/x')!.kindName, 'Prototype');
    });

    test('is not a community page other than a file, a team, a short key or another site', () {
      for (final url in <String>[
        'https://www.figma.com/',
        'https://www.figma.com/community/plugin/1234567890',
        'https://www.figma.com/files/team/1234567890',
        'https://www.figma.com/design/short',
        'https://www.figma.com/design',
        'https://figma.example.com/design/$figmaKey',
        'https://www.notion.so/design/$figmaKey',
      ]) {
        expect(richLinkOf(url), isNull, reason: url);
      }
    });
  });

  group('start times', () {
    test('as YouTube writes them', () {
      expect(startSeconds('75'), 75);
      expect(startSeconds('1M15S'), 75);
      expect(startSeconds('1h'), 3600);
      expect(startSeconds(''), isNull);
      expect(startSeconds(null), isNull);
      expect(startSeconds('1:15'), isNull);
      expect(startSeconds('-5'), isNull);
    });
  });

  group('oEmbed answers', () {
    test('reads the title, the author and the picture with its size', () {
      final read = parseOEmbed(
        '{"title":"Never Gonna Give You Up","author_name":"Rick Astley","provider_name":"YouTube",'
        '"thumbnail_url":"https://i.ytimg.com/vi/$video/hqdefault.jpg","thumbnail_width":480,"thumbnail_height":360,"html":"<iframe></iframe>"}',
      );
      expect(read, const OEmbed(title: 'Never Gonna Give You Up', author: 'Rick Astley', thumbnail: 'https://i.ytimg.com/vi/$video/hqdefault.jpg', thumbnailWidth: 480, thumbnailHeight: 360));
    });

    test('takes Spotify’s answer, with no author, and Figma’s sizes written as text', () {
      expect(parseOEmbed('{"title":"Song","thumbnail_url":"https://i.scdn.co/image/ab67","type":"rich"}'), const OEmbed(title: 'Song', thumbnail: 'https://i.scdn.co/image/ab67'));
      expect(parseOEmbed('{"title":"Home","thumbnail_url":"https://s3.figma.com/t.png","thumbnail_width":"800","thumbnail_height":"450"}')?.thumbnailWidth, 800);
    });

    test('drops a picture that is not https, and an answer with nothing to show', () {
      expect(parseOEmbed('{"title":"T","thumbnail_url":"http://plain.dev/t.jpg"}'), const OEmbed(title: 'T'));
      expect(parseOEmbed('{"title":"  ","author_name":"A"}'), isNull);
      expect(parseOEmbed('{}'), isNull);
      expect(parseOEmbed('[1,2]'), isNull);
      expect(parseOEmbed('<html>Not found</html>'), isNull);
      expect(parseOEmbed(''), isNull);
    });

    test('the fetch asks the link’s own oEmbed address and reads a good answer', () async {
      final asked = <Uri>[];
      final fetch = oEmbedFetch(
        get: (address, {int maxBytes = oEmbedMaxBytes}) async {
          asked.add(address);
          expect(maxBytes, oEmbedMaxBytes);
          return answer(200, '{"title":"A song","author_name":"A band"}');
        },
      );
      final link = richLinkOf('spotify:track:$track')!;
      expect(await fetch(link), const OEmbed(title: 'A song', author: 'A band'));
      expect(asked, <Uri>[link.oEmbed]);
    });

    test('the fetch fails for an answer that is not 2xx, and for one with nothing in it', () async {
      final link = richLinkOf('https://youtu.be/$video')!;
      await expectLater(oEmbedFetch(get: (address, {int maxBytes = 0}) async => answer(404, 'Not Found'))(link), throwsA(isA<EmbedError>().having((e) => e.message, 'message', 'The service answered 404.')));
      await expectLater(oEmbedFetch(get: (address, {int maxBytes = 0}) async => answer(401, '{"title":"x"}'))(link), throwsA(isA<EmbedError>()));
      await expectLater(oEmbedFetch(get: (address, {int maxBytes = 0}) async => answer(200, 'Bad Request'))(link), throwsA(isA<EmbedError>().having((e) => e.message, 'message', 'The service said nothing to show.')));
      await expectLater(oEmbedFetch(get: (address, {int maxBytes = 0}) async => throw const EmbedError("The service couldn't be reached."))(link), throwsA(isA<EmbedError>()));
    });

    test('a picture is read over https only, and an empty or failed one is a failure', () async {
      final asked = <Uri>[];
      final read = pictureFetch(
        get: (address, {int maxBytes = 0}) async {
          asked.add(address);
          expect(maxBytes, pictureMaxBytes);
          return address.path == '/empty' ? answer(200, '') : answer(200, 'JPEG');
        },
      );
      expect(utf8.decode(await read('https://i.ytimg.com/vi/$video/hqdefault.jpg')), 'JPEG');
      await expectLater(read('http://i.ytimg.com/vi/$video/hqdefault.jpg'), throwsA(isA<EmbedError>()));
      await expectLater(read('file:///etc/hosts'), throwsA(isA<EmbedError>()));
      await expectLater(read('https://i.ytimg.com/empty'), throwsA(isA<EmbedError>()));
      expect(asked.map((uri) => uri.scheme), <String>['https', 'https']);
    });
  });

  group('the GET over dart:io, against a server on 127.0.0.1', () {
    late HttpServer server;
    late List<HttpRequest> asked;
    setUp(() async {
      asked = <HttpRequest>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        asked.add(request);
        if (request.uri.path == '/big') {
          request.response.add(List<int>.filled(4096, 65));
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"title":"From the server"}');
        }
        await request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('reads an answer, says who is asking, and refuses plain http unless allowed', () async {
      final at = Uri.parse('http://127.0.0.1:${server.port}/oembed');
      final got = await httpEmbedGet(allowHttp: true)(at);
      expect(got.status, 200);
      expect(parseOEmbed(utf8.decode(got.body)), const OEmbed(title: 'From the server'));
      expect(asked.single.headers.value(HttpHeaders.userAgentHeader), embedUserAgent);
      await expectLater(httpEmbedGet()(at), throwsA(isA<EmbedError>().having((e) => e.message, 'message', 'Only https is asked.')));
      expect(asked, hasLength(1), reason: 'the refused one never left');
    });

    test('stops reading past its most', () async {
      await expectLater(httpEmbedGet(allowHttp: true)(Uri.parse('http://127.0.0.1:${server.port}/big'), maxBytes: 1024), throwsA(isA<EmbedError>().having((e) => e.message, 'message', 'Too much came back.')));
    });

    test('a port nobody answers on is a failure', () async {
      final spare = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = spare.port;
      await spare.close();
      await expectLater(httpEmbedGet(allowHttp: true)(Uri.parse('http://127.0.0.1:$port/')), throwsA(isA<EmbedError>().having((e) => e.message, 'message', "The service couldn't be reached.")));
    });
  });

  group('what is kept on the device', () {
    const day = 24 * 60 * 60000;
    late MemoryStored stored;
    late List<RichLink> fetched;
    late List<String> pictured;
    late int now;
    late bool allowed;
    late Object? fails;
    final link = richLinkOf('https://youtu.be/$video')!;

    KeptEmbeds make({bool native = true}) => KeptEmbeds(
      stored,
      fetch: native
          ? (link) async {
              fetched.add(link);
              if (fails != null) throw fails!;
              return const OEmbed(title: 'The video', author: 'The channel', thumbnail: 'https://i.ytimg.com/vi/x/hq.jpg');
            }
          : null,
      pictures: (address) async {
        pictured.add(address);
        if (address.contains('bad')) throw const EmbedError('no');
        return Uint8List.fromList(<int>[1, 2, 3]);
      },
      allowed: () => allowed,
      now: () => now,
    );

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() {
      stored = MemoryStored();
      fetched = <RichLink>[];
      pictured = <String>[];
      now = 1000 * day;
      allowed = true;
      fails = null;
    });

    test('asks once, tells its listeners, and keeps the answer for a week', () async {
      final embeds = make();
      var told = 0;
      embeds.addListener(() => told += 1);
      expect(embeds.embedFor(link), isNull);
      embeds.wantEmbed(link);
      embeds.wantEmbed(link);
      await settle();
      expect(fetched, <RichLink>[link], reason: 'one ask while it is out');
      expect(told, 1);
      expect(embeds.embedFor(link)?.title, 'The video');
      now += 6 * day;
      embeds.wantEmbed(link);
      await settle();
      expect(fetched, hasLength(1));
      now += 2 * day;
      embeds.wantEmbed(link);
      await settle();
      expect(fetched, hasLength(2), reason: 'a week on, it is asked again');
    });

    test('is read back by the next launch', () async {
      make().wantEmbed(link);
      await settle();
      final again = make();
      expect(again.embedFor(link), const OEmbed(title: 'The video', author: 'The channel', thumbnail: 'https://i.ytimg.com/vi/x/hq.jpg'));
      again.wantEmbed(link);
      await settle();
      expect(fetched, hasLength(1));
    });

    test('a failure is kept for a day, and says so', () async {
      fails = const EmbedError('The service answered 404.');
      final embeds = make();
      embeds.wantEmbed(link);
      await settle();
      expect(embeds.failedFor(link), isTrue);
      expect(embeds.embedFor(link), isNull);
      now += day ~/ 2;
      embeds.wantEmbed(link);
      await settle();
      expect(fetched, hasLength(1));
      now += day;
      fails = null;
      embeds.wantEmbed(link);
      await settle();
      expect(fetched, hasLength(2));
      expect(embeds.failedFor(link), isFalse);
    });

    test('asks nothing, shows no picture and is not allowed with the switches shut, or with no fetch', () async {
      allowed = false;
      final embeds = make();
      expect(embeds.allowed, isFalse);
      embeds.wantEmbed(link);
      expect(await embeds.picture('https://i.ytimg.com/vi/$video/hqdefault.jpg'), isNull);
      await settle();
      expect(fetched, isEmpty);
      expect(pictured, isEmpty);
      allowed = true;
      expect(make(native: false).allowed, isFalse, reason: 'nothing can ask: an editor shows the plain card');
      expect(noEmbeds.allowed, isFalse);
    });

    test('a picture is read once and held, and a failed one is asked again', () async {
      final embeds = make();
      expect(await embeds.picture('https://a.dev/1.jpg'), <int>[1, 2, 3]);
      expect(await embeds.picture('https://a.dev/1.jpg'), <int>[1, 2, 3]);
      expect(pictured, <String>['https://a.dev/1.jpg']);
      expect(await embeds.picture('https://a.dev/bad.jpg'), isNull);
      expect(await embeds.picture('https://a.dev/bad.jpg'), isNull);
      expect(pictured.where((a) => a.contains('bad')), hasLength(2));
    });
  });

  group('the player’s page', () {
    test('is one frame of the player, sending the app’s site and no more, its address written safely', () {
      final link = richLinkOf('https://youtu.be/$video?t=5')!;
      final html = embedPageHtml(EmbedPage(player: link.player, title: 'A "quoted" <title> & more'));
      expect(html, contains('<iframe src="https://www.youtube-nocookie.com/embed/$video?autoplay=1&amp;playsinline=1&amp;rel=0&amp;start=5"'));
      expect(html, contains('title="A &quot;quoted&quot; &lt;title> &amp; more"'));
      expect(html, contains('referrerpolicy="strict-origin-when-cross-origin"'));
      expect(html, contains('allow="autoplay; encrypted-media; picture-in-picture; fullscreen; clipboard-write"'));
      expect(html, contains('background:#000000'));
      expect(embedBase, 'https://ghostmarkdown.com/');
    });

    test('no web view in a test: the app’s players say so, and a tap opens the link', () {
      expect(webViewEmbedPlayers.available, isFalse);
    });
  });
}
