// Where Wrapped shows (lib/plugins/wrapped/story.dart, home_card.dart, page.dart, review.dart, pane.dart; docs/WRAPPED.md,
// "Where it lives"; Matt, 2026-11-05: "Have this plugin add a card to the home page to view the wrapped section or in
// the sidebar dock"): the story in light, dark and Simple; the home card's three ways (not made, making, ready) and its
// View opening the story; the sidebar's row and the bar's command there with the plugin on and gone with it off, the
// row opening the page and the page the story; the review's buttons going through the note; the Settings page.
// Pictures into build/feature-shots/wrapped/ under --update-goldens.
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/art.dart' show Lucide;
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/wrapped/wrapped.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:glacier/glacier.dart';

import '../../support/feature_shot.dart';
import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  late WrappedWorld world;
  late WrappedService service;
  setUp(() {
    world = WrappedWorld();
    useActivity(Activity());
    service = world.service();
    WrappedService.current = service;
  });
  tearDown(() {
    WrappedService.current = null;
    wrappedOpenNote = null;
  });

  /// A Wrapped as the pass leaves it, with no AI asked in the test: the gists, the themes, a suggestion, the soup a gem.
  void made() {
    service.store.set(service.state.copyWith(
      finished: () => wrappedNow.subtract(const Duration(hours: 1)),
      themes: const ['Travel plans', 'Work releases'],
      reads: {
        for (final note in service.passNotes) note.id: WrappedRead(hash: note.hash, gist: 'About ${note.title}', gem: note.id == 'recipe', stale: note.id == 'draft', staleWhy: 'An empty draft'),
      },
      suggestions: const [WrappedSuggestion(kind: SuggestionKind.move, notes: ['meeting'], folderId: 'work', why: 'A work meeting')],
    ));
  }

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Widget paper(Widget child) => Builder(
        builder: (context) => Material(
          type: MaterialType.transparency,
          child: ColoredBox(color: context.tokens.color('app-paper'), child: BackScope(child: child)),
        ),
      );

  group('the story', () {
    for (final (theme, simple) in [('light', false), ('dark', false), ('light', true)]) {
      testWidgets('renders its cards in $theme${simple ? ', Simple' : ''}, swiped through to the summary', (tester) async {
        made();
        var closed = false;
        await pumpApp(tester, prefs: AppPreferences(theme: theme, experience: simple ? 'simple' : 'advanced'), home: paper(WrappedStory(service: service, onClose: () => closed = true, onReview: () {})));
        await settle(tester);
        expect(find.byKey(const ValueKey('wrapped-story')), findsOneWidget);
        expect(find.text('Your 2026 in notes'), findsOneWidget);
        await featureShot(tester, 'wrapped', 'story-hello-$theme${simple ? '-simple' : ''}');
        // Tap through every card: the right two-thirds of the screen goes on.
        final seen = <String>[];
        for (var i = 0; i < 12 && find.byKey(const ValueKey('wrapped-card-summary')).evaluate().isEmpty; i++) {
          await tester.tapAt(const Offset(350, 400));
          await settle(tester, 5);
          seen.addAll([for (final id in ['notes', 'words', 'busiest', 'streak', 'themes', 'linked', 'todos', 'spoken', 'forgot']) if (find.byKey(ValueKey('wrapped-card-$id')).evaluate().isNotEmpty) id]);
        }
        expect(seen.toSet(), containsAll(['notes', 'busiest', 'streak', 'themes', 'linked', 'todos', 'forgot']));
        expect(find.text('7 notes'), findsWidgets);
        expect(find.byKey(const ValueKey('wrapped-share')), findsOneWidget);
        expect(find.byKey(const ValueKey('wrapped-review')), findsOneWidget);
        // The summary's picture holds the numbers alone until the themes are chosen.
        expect(find.textContaining('Into Travel plans'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('wrapped-share-themes')));
        await tester.pump();
        expect(find.textContaining('Into Travel plans'), findsOneWidget);
        await featureShot(tester, 'wrapped', 'story-summary-$theme${simple ? '-simple' : ''}');
        await tester.tap(find.byKey(const ValueKey('wrapped-story-close')));
        expect(closed, isTrue);
        await away(tester);
      });
    }

    test('its cards for a library with nothing in it: the hello and the summary', () {
      final cards = storyCards(wrappedStats(const [], WrappedPeriod.year, now: wrappedNow), now: wrappedNow);
      expect([for (final c in cards) c.id], ['hello', 'notes', 'summary']);
    });

    testWidgets('still where the device asks for less motion', (tester) async {
      made();
      await pumpApp(tester, home: paper(MediaQuery(data: const MediaQueryData(disableAnimations: true), child: WrappedStory(service: service, onClose: () {}))));
      await tester.pump();
      expect(find.byType(AnimatedSlide), findsNothing);
      await away(tester);
    });
  });

  group('the home card', () {
    Widget card() => paper(Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.all(16), child: WrappedHomeCard(service: service))));

    testWidgets('not made: Make my Wrapped', (tester) async {
      await pumpApp(tester, home: card());
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('wrapped-home-card-notMade')), findsOneWidget);
      expect(find.text('Make my Wrapped'), findsOneWidget);
      await featureShot(tester, 'wrapped', 'home-not-made');
      await away(tester);
    });

    testWidgets('making: how far, with Open', (tester) async {
      service.store.set(service.state.copyWith(wanted: true));
      await pumpApp(tester, home: card());
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('wrapped-home-card-making')), findsOneWidget);
      expect(find.textContaining('Making your Wrapped…'), findsOneWidget);
      expect(find.byKey(const ValueKey('wrapped-card-open')), findsOneWidget);
      await away(tester);
    });

    testWidgets('ready: the period, the headline and the ghost; View opens the story', (tester) async {
      made();
      await pumpApp(tester, prefs: const AppPreferences(theme: 'light', experience: 'simple'), home: card());
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('wrapped-home-card-ready')), findsOneWidget);
      expect(find.text('New · Your Wrapped · This year'), findsOneWidget);
      expect(find.text('7 notes this year'), findsOneWidget);
      await featureShot(tester, 'wrapped', 'home-ready-simple');
      await tester.tap(find.byKey(const ValueKey('wrapped-card-view')));
      await settle(tester);
      expect(find.byKey(const ValueKey('wrapped-story')), findsOneWidget);
      expect(service.state.fresh, isFalse, reason: 'seen');
      await away(tester);
    });
  });

  group('the plugin’s places', () {
    test('the sidebar’s row, the bar’s command and the home card only while it is on', () {
      final off = createRegistry(builtIn, store: MemorySwitches());
      expect(off.places().where((p) => p.id == 'wrapped'), isEmpty);
      expect(off.homeCards().where((c) => c.id == 'wrapped'), isEmpty);
      final on = createRegistry(builtIn, store: MemorySwitches({'wrapped': true}));
      expect(on.places().single.command, 'Open my Wrapped');
      expect(on.places(simple: true).single.id, 'wrapped', reason: 'in Simple too, as My tickets is');
      expect(on.homeCards().single.id, 'wrapped');
    });

    test('the bar lists Open my Wrapped from the places it is handed', () {
      final place = createRegistry(builtIn, store: MemorySwitches({'wrapped': true})).places().single;
      final commands = paletteCommands(
        const PaletteWorld(),
        PaletteDoing(
          openNote: (_) {},
          newNote: () {},
          closeTab: (_) {},
          showList: () {},
          browseNotes: () {},
          back: () {},
          forward: () {},
          settings: () {},
          chooseWorkspace: (_) {},
          fileNote: (_, _) {},
          setView: (_) {},
          setTheme: (_) {},
          pin: (_, _) {},
          archive: (_) {},
          remove: (_) {},
          groupTab: (_) {},
          joinTabGroup: (_, _) {},
          leaveTabGroup: (_) {},
          setFocusMode: (_) {},
          places: [(key: place.id, title: place.command, words: place.words, run: () {})],
        ),
        'wrapped',
      );
      expect(commands.map((c) => c.descriptor.label), contains('Open my Wrapped'));
    });

    for (final on in [true, false]) {
      testWidgets('the sidebar ${on ? 'has its Wrapped row, which opens the page and the story' : 'has no Wrapped row with the plugin off'}', (tester) async {
        made();
        final registry = createRegistry(builtIn, store: MemorySwitches({'wrapped': on}));
        final places = <ShelfPlace>[];
        late BuildContext at;
        for (final place in registry.places()) {
          places.add((id: place.id, name: place.name, icon: Lucide.all[place.icon]!, onPressed: () => place.open(at)));
        }
        await pumpApp(
          tester,
          home: paper(Builder(builder: (context) {
            at = context;
            return Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: NoteTree(notes: world.library.value, activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: world.workspaces, stored: MemoryStored(), places: places)));
          })),
        );
        await settle(tester, 3);
        final row = find.byKey(const ValueKey('plugin-place-wrapped'));
        if (!on) {
          expect(row, findsNothing);
          await away(tester);
          return;
        }
        expect(row, findsOneWidget);
        expect(find.descendant(of: row, matching: find.text('Wrapped')), findsOneWidget);
        await tester.tap(find.descendant(of: row, matching: find.text('Wrapped')));
        await settle(tester);
        expect(find.byKey(const ValueKey('wrapped-page')), findsOneWidget);
        await featureShot(tester, 'wrapped', 'page');
        await tester.tap(find.byKey(const ValueKey('wrapped-story-open')));
        await settle(tester);
        expect(find.byKey(const ValueKey('wrapped-story')), findsOneWidget);
        await away(tester);
      });
    }
  });

  group('the review', () {
    Widget review({bool? simple}) => paper(SettingsPaneScope(finder: SettingsFinder(), child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: WrappedReview(service: service, simple: simple))));

    testWidgets('Check off on a to-do writes the note, and Undo takes it back', (tester) async {
      made();
      await pumpApp(tester, size: const Size(430, 1600), home: review(simple: false));
      await settle(tester);
      final ferry = find.ancestor(of: find.text('Book the ferry'), matching: find.byType(SettingRow)).first;
      expect(find.descendant(of: ferry, matching: find.textContaining('- [ ] Book the ferry')), findsOneWidget, reason: 'the line as written');
      await tester.runAsync(() async {
        await tester.tap(find.descendant(of: ferry, matching: find.byKey(const ValueKey('todo-check'))));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);
      expect(world.library.noteOf('trip')!.body, contains('- [x] Book the ferry'));
      expect(find.text('Book the ferry'), findsNothing);
      await featureShot(tester, 'wrapped', 'review-after-check');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('wrapped-undo')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);
      expect(world.library.noteOf('trip')!.body, contains('- [ ] Book the ferry'));
      await away(tester);
    });

    testWidgets('in Simple the to-dos and stale notes show; the rest behind More, opened in place', (tester) async {
      made();
      await pumpApp(tester, size: const Size(430, 1600), home: review(simple: true));
      await settle(tester);
      expect(find.byKey(const ValueKey('wrapped-todos')), findsOneWidget);
      expect(find.byKey(const ValueKey('wrapped-stale')), findsOneWidget);
      expect(find.byKey(const ValueKey('wrapped-tidy')), findsNothing);
      expect(find.byKey(const ValueKey('todo-keep')), findsNothing);
      await featureShot(tester, 'wrapped', 'review-simple');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-more')), matching: find.text('Show')));
      await settle(tester);
      expect(find.byKey(const ValueKey('wrapped-tidy')), findsOneWidget);
      expect(find.textContaining('Move “Weekly sync” to Work'), findsOneWidget);
      await away(tester);
    });
  });

  testWidgets('its page in Settings: the period, View the story, Make my Wrapped, the review and what is sent', (tester) async {
    await pumpApp(tester, size: const Size(430, 1400), home: paper(SettingsPaneScope(finder: SettingsFinder(), child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: WrappedPane(service: service)))));
    await settle(tester);
    expect(find.byKey(const ValueKey('wrapped-period-year')), findsOneWidget);
    expect(find.byKey(const ValueKey('wrapped-make')), findsOneWidget);
    expect(find.text('Make my Wrapped'), findsOneWidget);
    expect(find.textContaining('made of counts alone'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-period-last12')), matching: find.byType(Pick)));
    await tester.pump();
    expect(service.state.period, WrappedPeriod.last12);
    await featureShot(tester, 'wrapped', 'settings-page');
    await away(tester);
  });
}
