// editor/videos.test.ts, case for case where a case is about the card. The page's `<video>` is the phone's player
// here (`FilmSeams.films`, lib/core/films.dart), and a player made for the test stands for it: what the card does
// is held: when the disc is drawn, what the words say for each reader, a press playing and pausing with the film
// over the poster and its line along the foot, full screen as a layer that plays the card's own film and pauses it
// as it closes, a film that would not open or failed as it played asked about again, and one let go with its card.
// One film pausing another is the device's (test/core/phone_films_test.dart).
import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/films.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/images.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/media/videos.dart';

import '../../support/render.dart';
import 'support.dart';

const String film = '[![video 0:12](image/poster.png)](video/0a1b2c3d.mp4)';
const Key card = ValueKey<String>('cm-videoCard'), disc = ValueKey<String>('disc'), full = ValueKey<String>('full'), words = ValueKey<String>('words');

/// A film open on a player that plays nothing: what it was told, in order.
class FakeFilm implements FilmPlaying {
  final ValueNotifier<bool> on = ValueNotifier<bool>(false), broke = ValueNotifier<bool>(false);
  final ValueNotifier<int> at = ValueNotifier<int>(0);
  final List<String> told = <String>[];

  @override
  Widget surface() => const SizedBox(key: ValueKey<String>('frames'));
  @override
  ValueListenable<bool> get playing => on;
  @override
  ValueListenable<int> get position => at;
  @override
  int get durationMs => 12000;
  @override
  ValueListenable<bool> get failed => broke;
  @override
  void play() {
    told.add('play');
    on.value = true;
  }

  @override
  void pause() {
    told.add('pause');
    on.value = false;
  }

  @override
  void seek(int ms) => at.value = ms;
  @override
  void close() => told.add('close');
}

/// A phone with the film on it, unless told otherwise.
class FakeDevice implements FilmDevice {
  FakeDevice({this.present = true, this.opens = true});

  bool present, opens;
  final List<FakeFilm> opened = <FakeFilm>[];

  @override
  bool get plays => true;
  @override
  Future<bool> here(String video) async => present;
  @override
  Future<FilmPlaying> open(String video) async {
    if (!opens) throw StateError('no');
    final film = FakeFilm();
    opened.add(film);
    return film;
  }
}

String? said(WidgetTester tester) => tester.widgetList<InlineWords>(find.byKey(words)).map((w) => w.text).firstOrNull;

void main() {
  setUpAll(loadAppFonts);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  group('a film’s card', () {
    testWidgets('is drawn under a film’s line, in any lead, and its poster is not drawn again as a picture', (tester) async {
      await pumpNote(tester, 'Film\n$film\n- $film\n> $film\nsee $film here', more: <Extension>[inlineImages(store: MemoryPictureStore()), videoCards(VideoMode.still)]);
      expect(find.byKey(card), findsNWidgets(3));
      expect(find.byKey(const ValueKey<String>('figure-waiting')), findsOneWidget);
    });

    testWidgets('is not drawn in fenced code', (tester) async {
      await pumpNote(tester, '```\n$film\n```', more: <Extension>[videoCards(VideoMode.play)]);
      expect(find.byKey(card), findsNothing);
    });

    testWidgets('plays where the film is here: a disc and Full screen, drawn only once the phone has said so', (tester) async {
      final asked = <String>[];
      final answer = Completer<FilmHere>();
      await pumpNote(tester, film, more: <Extension>[
        videoCards(VideoMode.play, seams: FilmSeams(filmHere: (video) {
          asked.add(video);
          return answer.future;
        })),
      ]);
      expect(find.byKey(disc), findsNothing);
      answer.complete(FilmHere.here);
      await settle(tester);
      expect(asked, <String>['0a1b2c3d.mp4']);
      expect(find.byKey(disc), findsOneWidget);
      expect(find.byKey(full), findsOneWidget);
      expect(find.bySemanticsLabel('Play the video, 0:12'), findsOneWidget);
      expect(find.bySemanticsLabel('Full screen'), findsOneWidget);
      expect(said(tester), isNull);
    });

    testWidgets('says the film is not on this phone, with no disc, before anyone taps', (tester) async {
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.play, seams: FilmSeams(filmHere: (_) async => FilmHere.missing))]);
      await settle(tester);
      expect(find.byKey(disc), findsNothing);
      expect(said(tester), 'This video isn’t on this phone.');
    });

    testWidgets('says to update on an older binary, and where the film stays on any other device', (tester) async {
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.play, seams: FilmSeams(filmHere: (_) async => FilmHere.update))]);
      await settle(tester);
      expect(said(tester), 'Update Ghost.md to play this video.');
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.play, seams: FilmSeams(filmHere: (_) async => FilmHere.elsewhere))]);
      await settle(tester);
      expect(said(tester), 'A video of 0:12. It stays on the phone it was added on.');
      expect(find.byKey(disc), findsNothing);
    });

    testWidgets('on a shared page says only a still is shared, and asks nothing', (tester) async {
      var asked = 0;
      Future<FilmHere> here(String _) async {
        asked += 1;
        return FilmHere.here;
      }

      Future<FilmsPlay> plays() async {
        asked += 1;
        return FilmsPlay.phone;
      }

      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.shared, seams: FilmSeams(filmHere: here, filmsPlay: plays))]);
      await settle(tester);
      expect(said(tester), 'A video of 0:12. Only a still from it is shared.');
      expect(asked, 0);
      expect(find.byKey(disc), findsNothing);
    });

    testWidgets('as a still asks nothing of the film, and says only what the device says', (tester) async {
      var asked = 0;
      Future<FilmHere> here(String _) async {
        asked += 1;
        return FilmHere.here;
      }

      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.still, seams: FilmSeams(filmHere: here, filmsPlay: () async => FilmsPlay.phone))]);
      await settle(tester);
      expect(said(tester), isNull);
      expect(find.byKey(disc), findsNothing);
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.still, seams: FilmSeams(filmHere: here, filmsPlay: () async => FilmsPlay.update))]);
      await settle(tester);
      expect(said(tester), 'Update Ghost.md to play this video.');
      expect(asked, 0);
    });

    test('has words for each reader, which say the length where the line does', () {
      expect(videoWords(VideoMode.shared, CardState.shared, 12000), 'A video of 0:12. Only a still from it is shared.');
      expect(videoWords(VideoMode.shared, CardState.quiet, null), 'A video. Only a still from it is shared.');
      expect(videoWords(VideoMode.play, CardState.missing, 12000), 'This video isn’t on this phone.');
      expect(videoWords(VideoMode.play, CardState.unplayable, 12000), 'This video can’t be played on this phone.');
      expect(videoWords(VideoMode.still, CardState.update, 12000), 'Update Ghost.md to play this video.');
      expect(videoWords(VideoMode.still, CardState.elsewhere, null), 'A video. It stays on the phone it was added on.');
      expect(videoWords(VideoMode.play, CardState.quiet, 12000), '');
    });
  });

  group('playing', () {
    const Key frames = ValueKey<String>('film'), progress = ValueKey<String>('progress');

    testWidgets('plays and pauses on a press of the frame, the film over its poster and its line along the foot', (tester) async {
      final device = FakeDevice();
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.play, seams: FilmSeams(films: Films(device: device)))]);
      await settle(tester);
      // Asked of the device: here, so the disc; nothing opened until it is wanted.
      expect(find.byKey(disc), findsOneWidget);
      expect(device.opened, isEmpty);
      expect(find.byKey(frames), findsNothing);
      expect(find.byKey(progress), findsNothing);
      expect(find.bySemanticsLabel('Play the video, 0:12'), findsOneWidget);

      await tester.tap(find.byKey(disc));
      await settle(tester);
      final playing = device.opened.single;
      expect(playing.told, <String>['play']);
      expect(find.byKey(frames), findsOneWidget);
      expect(find.byKey(progress), findsOneWidget);
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(find.ancestor(of: find.byKey(disc), matching: find.byType(AnimatedOpacity))).opacity, 0);

      // Half way: the line is half the frame.
      playing.at.value = 6000;
      await tester.pump();
      final line = find.descendant(of: find.byKey(progress), matching: find.byType(FractionallySizedBox));
      expect(tester.widget<FractionallySizedBox>(line).widthFactor, 0.5);

      await tester.tap(find.byKey(disc), warnIfMissed: false);
      await settle(tester);
      expect(playing.told, <String>['play', 'pause']);
      expect(device.opened, hasLength(1), reason: 'the same film, not another');
      expect(find.byKey(frames), findsOneWidget, reason: 'paused where it stopped, not back to the poster');
      expect(find.bySemanticsLabel('Play the video, 0:12'), findsOneWidget);

      // Its card gone, the film is let go.
      await tester.pumpWidget(const SizedBox());
      expect(playing.told.last, 'close');
    });

    testWidgets('goes full screen as a layer that plays the card’s own film, and pauses it as it closes or on back', (tester) async {
      final device = FakeDevice();
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.play, seams: FilmSeams(films: Films(device: device)))]);
      await settle(tester);
      await tester.tap(find.byKey(full));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final playing = device.opened.single;
      expect(playing.told, <String>['play']);
      expect(find.bySemanticsLabel('The video, 0:12, full screen'), findsOneWidget);
      // A tap on the film pauses and plays it.
      await tester.tap(find.byKey(const ValueKey<String>('layer-film')));
      expect(playing.told, <String>['play', 'pause']);
      await tester.tap(find.byKey(const ValueKey<String>('layer-film')));
      expect(playing.told, <String>['play', 'pause', 'play']);
      await tester.tap(find.byKey(const ValueKey<String>('layer-close')));
      await settle(tester);
      expect(playing.told.last, 'pause');
      expect(find.byKey(const ValueKey<String>('layer-film')), findsNothing);
      expect(find.byKey(frames), findsOneWidget, reason: 'the card is where the layer left it');
      expect(device.opened, hasLength(1));

      // Again, and the back gesture closes it.
      await tester.tap(find.byKey(full));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('layer-film')), findsOneWidget);
      expect(backStack.goBack(), isTrue);
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('layer-film')), findsNothing);
      expect(playing.told.last, 'pause');
    });

    testWidgets('asks again about a film that would not open, or failed as it played, and says which', (tester) async {
      final device = FakeDevice(opens: false);
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.play, seams: FilmSeams(films: Films(device: device)))]);
      await settle(tester);
      await tester.tap(find.byKey(disc));
      await settle(tester);
      await tester.pump();
      expect(said(tester), 'This video can’t be played on this phone.');
      expect(find.byKey(disc), findsNothing);

      final other = FakeDevice();
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.play, seams: FilmSeams(films: Films(device: other)))]);
      await settle(tester);
      await tester.tap(find.byKey(disc));
      await settle(tester);
      // Gone from the phone as it played.
      other.present = false;
      other.opened.single.broke.value = true;
      await settle(tester);
      await tester.pump();
      expect(said(tester), 'This video isn’t on this phone.');
      expect(find.byKey(disc), findsNothing);
      expect(find.byKey(frames), findsNothing);
      expect(other.opened.single.told.last, 'close');
    });

    testWidgets('says the film is gone, or cannot be played here, when the player says it would not play after all', (tester) async {
      final failed = ValueNotifier<Map<String, CardState>>(const <String, CardState>{});
      await pumpNote(tester, film, more: <Extension>[videoCards(VideoMode.play, seams: FilmSeams(filmHere: (_) async => FilmHere.here, failed: failed))]);
      await settle(tester);
      expect(find.byKey(disc), findsOneWidget);
      // Still here (a kind the player cannot play, or a read that failed): never that it is missing.
      failed.value = const <String, CardState>{'0a1b2c3d.mp4': CardState.unplayable};
      await tester.pump();
      expect(said(tester), 'This video can’t be played on this phone.');
      expect(find.byKey(disc), findsNothing);
      expect(find.byKey(full), findsNothing);
      failed.value = const <String, CardState>{'0a1b2c3d.mp4': CardState.missing};
      await tester.pump();
      expect(said(tester), 'This video isn’t on this phone.');
    });
  });

  group('a film just added', () {
    Future<List<Transaction>> added(WidgetTester tester, {required int caretLine, bool again = false}) async {
      final store = MemoryPictureStore();
      final seen = <Transaction>[];
      const doc = 'Film\n$film\n\nfar below';
      filmAdded('poster.png', 640, 360);
      final view = await pumpNote(tester, doc, more: <Extension>[
        inlineImages(store: store),
        videoCards(VideoMode.play),
        EditorViewLike.updateListener.of((update) => seen.addAll(update.transactions)),
      ]);
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.line(caretLine).from)));
      await tester.pump();
      seen.clear();
      store.lend(<String, Uint8List>{'poster.png': Uint8List.fromList(MediaFixture.picture('poster.png'))});
      await settlePictures(tester);
      if (again) {
        // The card is drawn again (the note changed above it): its poster arrives again, and the page stays put.
        seen.clear();
        view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x')));
        await settlePictures(tester);
      }
      return seen;
    }

    bool scrolled(List<Transaction> trs) => trs.any((tr) => tr.effects.any((e) => e.isOf(EditorViewLike.scrollIntoViewEffect)));

    testWidgets('keeps the caret under its card in sight as the poster arrives, while the note has the focus', (tester) async {
      expect(scrolled(await added(tester, caretLine: 3)), isTrue);
    });

    testWidgets('keeps it in sight once: a card drawn again never pulls the page back to the caret', (tester) async {
      expect(scrolled(await added(tester, caretLine: 3, again: true)), isFalse);
    });

    testWidgets('leaves the caret anywhere else to the person', (tester) async {
      expect(scrolled(await added(tester, caretLine: 4)), isFalse);
    });
  });

  group('the film’s line', () {
    testWidgets('in fenced code is the code as written, with no card and no fold', (tester) async {
      await pumpNote(tester, 'Film\n```\n$film\n```', more: <Extension>[videoCards(VideoMode.play)]);
      expect(find.byKey(card), findsNothing);
      expect(shownOf(tester, 2), film);
    });

    testWidgets('reads as its words off the caret’s line, and as written on it while the note is being written', (tester) async {
      final view = await pumpNote(tester, 'Film\n$film', more: <Extension>[videoCards(VideoMode.play)]);
      expect(shownOf(tester, 1), 'video 0:12');
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length)));
      await tester.pump();
      expect(shownOf(tester, 1), film);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      expect(shownOf(tester, 1), 'video 0:12');
    });
  });
}
