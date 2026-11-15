import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/plugins/embeds.dart';
import 'package:ghost_messaging/plugins/registry.dart';

import 'support/list_harness.dart';

/// Smart embeds (lib/plugins/embeds.dart; Matt, 2026-11-14: "I also want smart embeds added to expand spotify
/// links, youtube, etc").
void main() {
  late List<Uri> asked;
  setUp(() {
    asked = [];
    Embeds.forget();
    Embeds.fetch = (url) async {
      asked.add(url);
      if (url.host == 'www.youtube.com' && url.path == '/oembed') {
        return (status: 200, body: jsonEncode({'title': 'Never Gonna Give You Up', 'author_name': 'Rick Astley', 'thumbnail_url': 'https://i.ytimg.com/vi/x/hq.jpg'}));
      }
      if (url.host == 'open.spotify.com' && url.path == '/oembed') {
        return (status: 200, body: jsonEncode({'title': 'Blinding Lights', 'thumbnail_url': 'https://i.scdn.co/image/abc'}));
      }
      if (url.host == 'publish.twitter.com') {
        return (status: 200, body: jsonEncode({'author_name': 'Ghost', 'html': '<blockquote><p lang="en">Hello &amp; welcome</p>&mdash; Ghost</blockquote>'}));
      }
      if (url.host == 'music.apple.com' || url.host == 'news.example') {
        return (
          status: 200,
          body: '<html><head><title>Fallback</title><meta property="og:title" content="Midnights &amp; more"><meta property="og:site_name" content="Apple Music">'
              '<meta property="og:image" content="/art.jpg"></head></html>'
        );
      }
      return (status: 404, body: '');
    };
  });

  test('a link is known by its service, else it is any site', () {
    expect(EmbedService.of('https://www.youtube.com/watch?v=dQw4w9WgXcQ')?.id, 'youtube');
    expect(EmbedService.of('https://youtu.be/dQw4w9WgXcQ')?.id, 'youtube');
    expect(EmbedService.of('https://music.youtube.com/watch?v=1')?.id, 'youtubemusic');
    expect(EmbedService.of('https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b')?.id, 'spotify');
    expect(EmbedService.of('https://music.apple.com/us/album/x/1')?.id, 'applemusic');
    expect(EmbedService.of('https://m.tiktok.com/@a/video/1')?.id, 'tiktok');
    expect(EmbedService.of('https://twitter.com/a/status/1')?.id, 'x');
    expect(EmbedService.of('https://news.example/story'), isNull);
  });

  test('YouTube and Spotify say what a link is by oEmbed; X by its post\'s words', () async {
    final yt = (await Embeds.of('https://youtu.be/dQw4w9WgXcQ'))!;
    expect(yt.title, 'Never Gonna Give You Up');
    expect(yt.author, 'Rick Astley');
    expect(yt.image, 'https://i.ytimg.com/vi/x/hq.jpg');
    expect(yt.source, 'YouTube');
    expect(asked.single.queryParameters['url'], 'https://youtu.be/dQw4w9WgXcQ');
    expect((await Embeds.of('https://open.spotify.com/track/1'))!.title, 'Blinding Lights');
    expect((await Embeds.of('https://x.com/ghost/status/1'))!.title, 'Hello & welcome');
    // Asked once: kept while the app is open.
    await Embeds.of('https://youtu.be/dQw4w9WgXcQ');
    expect(asked.where((u) => u.host == 'www.youtube.com'), hasLength(1));
  });

  test('any other page by its Open Graph lines; nothing asked of it where only known services are wanted', () async {
    final apple = (await Embeds.of('https://music.apple.com/us/album/midnights/1'))!;
    expect(apple.title, 'Midnights & more');
    expect(apple.image, 'https://music.apple.com/art.jpg', reason: 'a picture given from the site\'s root');
    expect(apple.source, 'Apple Music');
    expect((await Embeds.of('https://news.example/story'))!.site, 'Apple Music');
    asked.clear();
    expect(await Embeds.of('https://other.example/page', others: false), isNull);
    expect(asked, isEmpty);
    expect(await Embeds.of('https://gone.example/404'), isNull, reason: 'a site that did not answer gets no card');
  });

  testWidgets('the card: the service\'s name, the title, who made it', (tester) async {
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const Center(child: EmbedCard(url: 'https://youtu.be/dQw4w9WgXcQ')), AppState());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Never Gonna Give You Up'), findsOneWidget);
    expect(find.text('Rick Astley'), findsOneWidget);
    expect(shippedPlugins.whereType<EmbedsPlugin>(), hasLength(1));
  });
}
