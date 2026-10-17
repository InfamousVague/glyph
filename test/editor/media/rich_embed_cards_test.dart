// Rich embeds drawn in a note (lib/editor/media/rich_embeds/cards.dart; Matt: "Rich embeds: YouTube, Spotify and
// Figma links as playable or previewable cards, not just link cards"): the card in the plain one's place, waiting
// for the service, with its answer, playing once tapped and never before, quiet with Link previews off or Local
// only on, the plain card where the service would not answer, a Figma file full screen and closed by its close,
// Escape and the back, and a video moved full screen and back playing on. The players are a fake: a test has no
// web view.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/link_preview.dart' show LinkOpener;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/media/link_cards.dart';
import 'package:ghost_md/editor/media/rich_embeds/cards.dart';
import 'package:ghost_md/editor/media/rich_embeds/oembed.dart';
import 'package:ghost_md/editor/media/rich_embeds/players.dart';
import 'package:ghost_md/editor/media/rich_embeds/providers.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/rich_embeds/rich_embeds.dart';

import '../../support/render.dart';
import 'support.dart';

const String video = 'dQw4w9WgXcQ';
const String track = '4uLU6hMCjMI75M1A2tKUQC';
const String figmaKey = 'abcDEF1234567890ghijKL';
const String youtube = 'https://youtu.be/$video?t=42';
const String song = 'https://open.spotify.com/track/$track';
const String album = 'spotify:album:$track';
const String figma = 'https://www.figma.com/design/$figmaKey/Home?node-id=1-2';

/// A player that is only a box: what it was asked to play, and whether it was let go.
class FakePlayback implements EmbedPlayback {
  FakePlayback(this.page);

  final EmbedPage page;
  bool disposed = false;
  final List<bool> drawn = <bool>[];

  @override
  Widget view({required bool whole}) {
    drawn.add(whole);
    return SizedBox.expand(key: ValueKey<String>(whole ? 'fake-player-whole' : 'fake-player'));
  }

  @override
  void dispose() => disposed = true;
}

class FakePlayers extends EmbedPlayers {
  FakePlayers({this.available = true});

  @override
  final bool available;
  final List<FakePlayback> opened = <FakePlayback>[];

  @override
  EmbedPlayback open(EmbedPage page, {LinkOpener? open}) {
    final made = FakePlayback(page);
    opened.add(made);
    return made;
  }
}

/// A service that answers when told to.
class Service {
  final List<RichLink> asked = <RichLink>[];
  final List<String> pictures = <String>[];
  final Map<String, Completer<OEmbed>> _out = <String, Completer<OEmbed>>{};

  Future<OEmbed> fetch(RichLink link) {
    asked.add(link);
    return (_out[link.key] = Completer<OEmbed>()).future;
  }

  Future<Uint8List> picture(String address) async {
    pictures.add(address);
    return Uint8List(0);
  }

  void answer(RichLink link, OEmbed embed) => _out[link.key]!.complete(embed);
  void fail(RichLink link) => _out[link.key]!.completeError(const EmbedError('The service answered 404.'));
}

const Key card = ValueKey<String>('cm-embedCard-youtube'), play = ValueKey<String>('cm-embed-play'), openIn = ValueKey<String>('cm-embed-open');
const Key plain = ValueKey<String>('cm-linkCard'), layer = ValueKey<String>('cm-embed-layer');

List<String> said(WidgetTester tester, Key key) => tester.widgetList<InlineWords>(find.byKey(key)).map((w) => w.text).toList();

void main() {
  setUpAll(loadAppFonts);

  late Service service;
  late FakePlayers players;
  late List<String> opened;
  late bool previews, localOnly;
  late ValueNotifier<int> switches;
  late KeptEmbeds embeds;

  setUp(() {
    service = Service();
    players = FakePlayers();
    opened = <String>[];
    previews = true;
    localOnly = false;
    switches = ValueNotifier<int>(0);
    embeds = KeptEmbeds(MemoryStored(), fetch: service.fetch, pictures: service.picture, allowed: () => previews && !localOnly);
  });

  Future<EditorView> pump(WidgetTester tester, String doc, {bool readOnly = false, EmbedPlayers? using}) => pumpNote(
    tester,
    doc,
    readOnly: readOnly,
    more: <Extension>[
      linkCards(open: (url) async => opened.add(url), enabled: () => previews, switches: switches, embeds: embeds, players: using ?? players),
    ],
  );

  RichEmbedCardState cardState(WidgetTester tester) => tester.state<RichEmbedCardState>(find.byType(RichEmbedCard));

  // The cards are the Rich embeds plugin's (lib/plugins/rich_embeds): on by default, and off a plain link card.
  group('the Rich embeds plugin', () {
    late Registry before;
    late Registry registry;
    setUp(() {
      before = plugins;
      registry = createRegistry([richEmbedsPlugin], store: MemorySwitches());
      usePlugins(registry);
    });
    tearDown(() => usePlugins(before));

    testWidgets('ships on: a YouTube link is its rich card', (tester) async {
      expect(richEmbedsManifest.standard, isTrue);
      expect(richEmbedsOn(), isTrue);
      await pump(tester, youtube);
      expect(find.byKey(card), findsOneWidget);
      expect(find.byKey(plain), findsNothing);
    });

    testWidgets('switched off, every such link is a plain link card and nothing is asked of its service; on again, rich', (tester) async {
      registry.setEnabled(richEmbedsManifest.id, false);
      await pump(tester, 'Watch\n$youtube\n$album');
      expect(find.byKey(card), findsNothing);
      expect(find.byType(RichEmbedCard), findsNothing);
      // The video's line has the plain card any link has; a spotify: address, with no page, has none.
      expect(find.byKey(plain), findsOneWidget);
      expect(service.asked, isEmpty);
      registry.setEnabled(richEmbedsManifest.id, true);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(card), findsOneWidget);
      expect(find.byType(RichEmbedCard), findsNWidgets(2));
    });
  });

  group('a YouTube video', () {
    testWidgets('waits for YouTube with the video’s own still and the link’s words, and plays nothing', (tester) async {
      await pump(tester, 'Watch this\n- [The talk]($youtube)\nafter');
      expect(find.byKey(card), findsOneWidget);
      expect(find.byKey(plain), findsNothing, reason: 'the rich card is in the plain one’s place');
      expect(cardState(tester).phase, EmbedCardPhase.loading);
      expect(said(tester, const ValueKey<String>('cm-embed-title')), <String>['The talk']);
      expect(service.asked.single.id, video);
      expect(service.pictures, <String>['https://i.ytimg.com/vi/$video/hqdefault.jpg']);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(players.opened, isEmpty, reason: 'nothing plays before a tap');
      expect(find.byKey(const ValueKey<String>('fake-player')), findsNothing);
    });

    testWidgets('says the title and the channel once YouTube answers, and asks for the picture it names', (tester) async {
      await pump(tester, youtube);
      service.answer(service.asked.single, const OEmbed(title: 'Never Gonna Give You Up', author: 'Rick Astley', thumbnail: 'https://i.ytimg.com/vi/$video/maxres.jpg'));
      await tester.pump();
      await tester.pump();
      expect(cardState(tester).phase, EmbedCardPhase.preview);
      expect(said(tester, const ValueKey<String>('cm-embed-title')), <String>['Never Gonna Give You Up']);
      expect(said(tester, const ValueKey<String>('cm-embed-about')), <String>['Rick Astley · YouTube video']);
      expect(service.pictures.last, 'https://i.ytimg.com/vi/$video/maxres.jpg');
      expect(find.bySemanticsLabel('Play Never Gonna Give You Up'), findsOneWidget);
      expect(find.bySemanticsLabel('Open in YouTube'), findsOneWidget);
      expect(players.opened, isEmpty);
    });

    testWidgets('plays in the card once tapped, from the link’s start, and the note’s words stay as they were', (tester) async {
      final view = await pump(tester, 'Before\n$youtube\nAfter');
      await tester.tap(find.byKey(play));
      await tester.pump();
      expect(players.opened, hasLength(1));
      final page = players.opened.single.page;
      expect(page.player.path, '/embed/$video');
      expect(page.player.queryParameters['start'], '42');
      expect(page.player.queryParameters['autoplay'], '1');
      expect(cardState(tester).phase, EmbedCardPhase.playing);
      expect(find.byKey(const ValueKey<String>('fake-player')), findsOneWidget);
      // 16:9 in the card.
      final box = tester.getSize(find.byKey(const ValueKey<String>('fake-player')));
      expect(box.width / box.height, closeTo(16 / 9, 0.01));
      expect(view.state.doc.toString(), 'Before\n$youtube\nAfter');
      expect(opened, isEmpty);
    });

    testWidgets('Open in YouTube hands the link to the phone and plays nothing here', (tester) async {
      await pump(tester, youtube);
      await tester.tap(find.byKey(openIn));
      await tester.pump();
      expect(opened, <String>[youtube]);
      expect(players.opened, isEmpty);
    });

    testWidgets('Full screen moves the same player into a layer, and the close brings it back playing', (tester) async {
      await pump(tester, youtube);
      await tester.tap(find.byKey(play));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('cm-embed-full')));
      await tester.pump();
      expect(find.byKey(layer), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fake-player-whole')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fake-player')), findsNothing);
      expect(find.byWidgetPredicate((w) => w is InlineWords && w.text == 'Playing full screen'), findsOneWidget, reason: 'the card holds its place');
      await tester.tap(find.byKey(const ValueKey<String>('cm-embed-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(layer), findsNothing);
      expect(find.byKey(const ValueKey<String>('fake-player')), findsOneWidget);
      expect(players.opened, hasLength(1), reason: 'the same player, never made again');
      expect(players.opened.single.disposed, isFalse);
      expect(players.opened.single.drawn, containsAllInOrder(<bool>[false, true, false]));
    });

    testWidgets('the player is let go when its line goes', (tester) async {
      final view = await pump(tester, 'Before\n$youtube\nAfter');
      await tester.tap(find.byKey(play));
      await tester.pump();
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 7, to: 7 + youtube.length + 1)));
      await tester.pump();
      expect(find.byType(RichEmbedCard), findsNothing);
      expect(players.opened.single.disposed, isTrue);
    });

    testWidgets('where no player can be made, a tap opens the link', (tester) async {
      final none = FakePlayers(available: false);
      await pump(tester, youtube, using: none);
      await tester.tap(find.byKey(play));
      await tester.pump();
      expect(none.opened, isEmpty);
      expect(opened, <String>[youtube]);
    });

    testWidgets('is drawn in a view that cannot be edited too, a notebook’s words', (tester) async {
      await pump(tester, 'Read only\n$youtube', readOnly: true);
      expect(find.byKey(card), findsOneWidget);
      await tester.tap(find.byKey(play));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('fake-player')), findsOneWidget);
    });
  });

  group('with the switches shut', () {
    testWidgets('Link previews off: the plain card with the service’s name and the link, nothing asked, a tap opens it', (tester) async {
      previews = false;
      await pump(tester, 'https://www.airbnb.com/rooms/1234\n$youtube');
      expect(find.byKey(plain), findsOneWidget, reason: 'the airbnb link has no card at all; the video has its quiet one');
      expect(find.byType(RichEmbedCard), findsOneWidget);
      expect(cardState(tester).phase, EmbedCardPhase.quiet);
      expect(said(tester, const ValueKey<String>('cm-linkCard-title')), <String>['YouTube video']);
      expect(said(tester, const ValueKey<String>('cm-linkCard-where')), <String>['youtu.be/$video?t=42']);
      await tester.tap(find.byKey(plain));
      await tester.pump();
      expect(opened, <String>[youtube]);
      expect(service.asked, isEmpty);
      expect(service.pictures, isEmpty);
      expect(players.opened, isEmpty);
    });

    testWidgets('Local only on: the same, though Link previews is on', (tester) async {
      localOnly = true;
      await pump(tester, '[Our song]($song)');
      expect(cardState(tester).phase, EmbedCardPhase.quiet);
      expect(said(tester, const ValueKey<String>('cm-linkCard-title')), <String>['Our song']);
      await tester.tap(find.byKey(plain));
      await tester.pump();
      expect(opened, <String>[song]);
      expect(service.asked, isEmpty);
      expect(players.opened, isEmpty);
    });

    testWidgets('turned off while it plays, the player stops and the card goes quiet', (tester) async {
      await pump(tester, youtube);
      await tester.tap(find.byKey(play));
      await tester.pump();
      previews = false;
      switches.value += 1;
      await tester.pump();
      await tester.pump();
      expect(cardState(tester).phase, EmbedCardPhase.quiet);
      expect(players.opened.single.disposed, isTrue);
    });

    testWidgets('Local only turned on while it plays: the same', (tester) async {
      await pump(tester, youtube);
      await tester.tap(find.byKey(play));
      await tester.pump();
      localOnly = true;
      switches.value += 1;
      await tester.pump();
      await tester.pump();
      expect(cardState(tester).phase, EmbedCardPhase.quiet);
      expect(players.opened.single.disposed, isTrue);
    });

    testWidgets('an editor told nothing of the device asks nothing and plays nothing', (tester) async {
      await pumpNote(tester, youtube, more: <Extension>[linkCards(open: (url) async => opened.add(url), players: players)]);
      expect(cardState(tester).phase, EmbedCardPhase.quiet);
      await tester.tap(find.byKey(plain));
      await tester.pump();
      expect(opened, <String>[youtube]);
      expect(players.opened, isEmpty);
    });
  });

  testWidgets('a service that would not answer leaves the plain link card', (tester) async {
    await pump(tester, youtube);
    service.fail(service.asked.single);
    await tester.pump();
    await tester.pump();
    expect(cardState(tester).phase, EmbedCardPhase.failed);
    expect(find.byKey(card), findsNothing);
    expect(find.byKey(plain), findsOneWidget);
    await tester.tap(find.byKey(plain));
    await tester.pump();
    expect(opened, <String>[youtube]);
    expect(players.opened, isEmpty);
  });

  group('Spotify', () {
    testWidgets('a track: its artwork and title, and its compact player in the card once tapped', (tester) async {
      await pump(tester, song);
      expect(find.byKey(const ValueKey<String>('cm-embedCard-spotify')), findsOneWidget);
      expect(service.pictures, isEmpty, reason: 'Spotify’s artwork is named by its answer');
      service.answer(service.asked.single, const OEmbed(title: 'Bohemian Rhapsody', thumbnail: 'https://i.scdn.co/image/ab67'));
      await tester.pump();
      await tester.pump();
      expect(said(tester, const ValueKey<String>('cm-embed-title')), <String>['Bohemian Rhapsody']);
      expect(said(tester, const ValueKey<String>('cm-embed-about')), <String>['Spotify track']);
      expect(service.pictures, <String>['https://i.scdn.co/image/ab67']);
      expect(players.opened, isEmpty);
      await tester.tap(find.byKey(play));
      await tester.pump();
      expect(players.opened.single.page.player.toString(), 'https://open.spotify.com/embed/track/$track?utm_source=oembed');
      expect(tester.getSize(find.byKey(const ValueKey<String>('cm-embed-player'))).height, 152);
      await tester.tap(find.byKey(openIn));
      await tester.pump();
      expect(opened, <String>[song]);
    });

    testWidgets('an album by its URI: the taller player, and Open in Spotify opens its page', (tester) async {
      await pump(tester, '- $album');
      await tester.tap(find.byKey(play));
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey<String>('cm-embed-player'))).height, 352);
      await tester.tap(find.byKey(openIn));
      await tester.pump();
      expect(opened, <String>['https://open.spotify.com/album/$track']);
    });
  });

  group('Figma', () {
    Future<void> openIt(WidgetTester tester) async {
      await tester.tap(find.byKey(play));
      await tester.pump();
    }

    testWidgets('its picture and title; a tap opens the interactive embed full screen, not in the card', (tester) async {
      await pump(tester, figma);
      expect(find.byKey(const ValueKey<String>('cm-embedCard-figma')), findsOneWidget);
      service.answer(service.asked.single, const OEmbed(title: 'Home screen', author: 'Matt', thumbnail: 'https://s3.figma.com/t.png', thumbnailWidth: 800, thumbnailHeight: 400));
      await tester.pump();
      await tester.pump();
      expect(said(tester, const ValueKey<String>('cm-embed-about')), <String>['Matt · Figma design']);
      expect(find.bySemanticsLabel('Open Home screen'), findsOneWidget);
      expect(players.opened, isEmpty);
      await openIt(tester);
      expect(find.byKey(layer), findsOneWidget);
      // Faded in, as a film's layer is: its name is read once it is there.
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Figma, Home screen, full screen'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fake-player-whole')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fake-player')), findsNothing, reason: 'nothing plays in the card');
      expect(players.opened.single.page.player.toString(), 'https://www.figma.com/embed?embed_host=ghostmd&url=${Uri.encodeQueryComponent(figma)}');
    });

    testWidgets('closes on its close, on Escape and on the phone’s back, and lets each player go', (tester) async {
      await pump(tester, figma);
      await openIt(tester);
      await tester.tap(find.byKey(const ValueKey<String>('cm-embed-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(layer), findsNothing);
      expect(players.opened[0].disposed, isTrue);

      await openIt(tester);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(layer), findsNothing);
      expect(players.opened[1].disposed, isTrue);

      await openIt(tester);
      await tester.pumpAndSettle();
      final depth = backStack.depth;
      expect(backStack.goBack(), isTrue, reason: 'the layer takes the back before the note does');
      await tester.pumpAndSettle();
      expect(find.byKey(layer), findsNothing);
      expect(backStack.depth, depth - 1);
      expect(players.opened[2].disposed, isTrue);
      expect(players.opened, hasLength(3));
    });

    testWidgets('the layer goes with its card', (tester) async {
      final view = await pump(tester, 'A\n$figma');
      await openIt(tester);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 1, to: view.state.doc.length)));
      await tester.pumpAndSettle();
      expect(find.byKey(layer), findsNothing);
      expect(players.opened.single.disposed, isTrue);
    });
  });

  testWidgets('a link a plugin reads keeps its own row, rich or not', (tester) async {
    await pumpNote(tester, youtube, more: <Extension>[linkCards(embeds: embeds, players: players, reads: (text, url) => true)]);
    expect(find.byType(RichEmbedCard), findsNothing);
    expect(service.asked, isEmpty);
  });

  testWidgets('a link in code, or among words, has no card', (tester) async {
    await pump(tester, '```\n$youtube\n```\nsee $youtube here\nspotify:artist:$track');
    expect(find.byType(RichEmbedCard), findsNothing);
    expect(find.byKey(plain), findsNothing);
  });

  test('a spotify: URI alone on its line is a link line, and only where it is an embed', () {
    expect(linkLine('spotify:track:$track'), const LinkLine('spotify:track:$track', null));
    expect(linkLine('- [Our song](spotify:track:$track)'), const LinkLine('spotify:track:$track', 'Our song'));
    expect(linkLine('spotify:artist:$track'), isNull);
    expect(linkLine('spotify:track:short'), isNull);
  });
}
