import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/notes/notices.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'support.dart';

/// What is waiting on the person, in the words it is said in (lib/notes/notices.dart), after the web's
/// `notes/Notices.test.tsx`: the voice model coming down or failing to, and the Academy's invitation (the update's card
/// is gone: the activity tray says the app's updates). Each says nothing at all when there is nothing to say.
///
/// Not measured on the page: none of these can be brought up in the dev server without an update or a model to wait
/// for. The sizes asserted are the stylesheet's own (Notices.module.css), through the tokens.
void main() {
  setUpAll(loadAppFonts);

  Future<void> show(WidgetTester tester, Widget notice, {String theme = 'dark', double width = 390}) async {
    await pumpApp(
      tester,
      size: Size(width, 844),
      prefs: AppPreferences(theme: theme),
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Padding(padding: EdgeInsets.fromLTRB(context.tokens.len('app-gutter-start'), 60, context.tokens.len('app-gutter-end'), 0), child: Align(alignment: Alignment.topCenter, child: notice)),
        ),
      ),
    );
    await settle(tester);
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  bool said(WidgetTester tester, String words) => find.textContaining(words, findRichText: true).evaluate().isNotEmpty;

  test('there is no update card: the app’s own updates are the activity tray’s (lib/activity/activity_tray.dart)', () {
    // Matt, 2026-10-30: "show the updates stuff in the activity drawer only now with a badge". The card, its words and
    // its foil went with it; test/activity/activity_updates_test.dart holds the tray's section.
    expect(File('lib/notes/notices.dart').readAsStringSync(), isNot(contains('class UpdateNotice')));
  });

  group('the voice model’s line', () {
    testWidgets('is there only while voice notes cannot work yet', (tester) async {
      await show(tester, VoiceModelStatus(state: const VoiceModelQuiet(), onRetry: () {}));
      expect(key('voice-model-notice'), findsNothing);
      await away(tester);
    });

    testWidgets('counts its download, and offers another go when it failed', (tester) async {
      await show(tester, VoiceModelStatus(state: const VoiceModelDownloading(received: 30600000, total: 148000000), onRetry: () {}));
      expect(said(tester, 'Downloading the voice model, 31 of 148 MB. Keep Ghost.md open.'), isTrue);
      await away(tester);
      var retries = 0;
      await show(tester, VoiceModelStatus(state: const VoiceModelFailed('offline'), onRetry: () => retries += 1));
      expect(said(tester, 'The voice model didn’t download.'), isTrue);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
      await away(tester);
    });

    testWidgets('and the better model’s, only while it is coming down', (tester) async {
      await show(tester, const RefiningNotice());
      expect(key('refining-notice'), findsNothing);
      await away(tester);
      await show(tester, const RefiningNotice(received: 5400000, total: 20000000));
      expect(said(tester, 'Getting the better voice model, 5 of 20 MB.'), isTrue);
      await away(tester);
    });
  });

  group('the Academy’s invitation', () {
    testWidgets('starts the Academy, and can be put away when there is a way to', (tester) async {
      var opened = 0, hidden = 0;
      await show(tester, AcademyCard(onOpen: () => opened += 1, onHide: () => hidden += 1));
      expect(find.text('Ghost Academy'), findsOneWidget);
      expect(find.text('Learn the marks, one at a time.'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.tap(find.bySemanticsLabel('Not now'));
      expect([opened, hidden], [1, 1]);
      await away(tester);
      await show(tester, AcademyCard(onOpen: () {}));
      expect(find.bySemanticsLabel('Not now'), findsNothing);
      await away(tester);
    });

    testWidgets('keeps Start and the cross beside its words, and drops them under the words where the card is narrow', (tester) async {
      await show(tester, AcademyCard(onOpen: () {}, onHide: () {}));
      final beside = tester.getRect(find.text('Start')), words = tester.getRect(find.text('Ghost Academy'));
      expect(beside.top, lessThan(tester.getRect(find.text('Learn the marks, one at a time.')).bottom), reason: 'on the words’ own line');
      expect(beside.left, greaterThan(words.right));
      await away(tester);
      // The docked sidebar's list: too narrow for nine rems of words beside the two buttons.
      await show(tester, SizedBox(width: 230, child: AcademyCard(onOpen: () {}, onHide: () {})));
      final under = tester.getRect(find.text('Start')), line = tester.getRect(find.text('Learn the marks, one at a time.'));
      expect(under.top, greaterThan(line.bottom));
      final card = tester.getRect(key('academy-card')), cross = tester.getRect(find.bySemanticsLabel('Not now'));
      final t = GlacierTheme.of(tester.element(key('academy-card')));
      expect(card.right - cross.right, closeTo(t.space(3) + t.len('glacier-hairline'), 0.01), reason: 'at the line’s end');
      await away(tester);
    });
  });

  group('an invitation to an organization', () {
    testWidgets('says who asked, in the Academy’s card, with the buttons it is handed', (tester) async {
      await show(tester, const InviteNotice(sentence: 'Sam invited you to Acme', actions: Text('Accept')));
      expect(find.text('Sam invited you to Acme'), findsOneWidget);
      expect(find.text('Accept to join; its workspace is made for you.'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      await away(tester);
    });
  });

  for (final theme in ['dark', 'light']) {
    testWidgets('all of them, one under another, $theme', (tester) async {
      await show(
        tester,
        theme: theme,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InviteNotice(sentence: 'Sam invited you to Acme', actions: Builder(builder: (context) => Text('Accept · Decline', style: context.tokens.text('sm')))),
            AcademyCard(onOpen: () {}, onHide: () {}),
            VoiceModelStatus(state: const VoiceModelDownloading(received: 30600000, total: 148000000), onRetry: () {}),
            VoiceModelStatus(state: const VoiceModelFailed(), onRetry: () {}),
            const RefiningNotice(received: 5400000, total: 20000000),
          ],
        ),
      );
      await loadPictures(tester);
      await shot(tester, 'notices-$theme');
    });
  }
}
