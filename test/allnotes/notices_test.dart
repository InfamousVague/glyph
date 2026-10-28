import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/notes/notices.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'support.dart';

/// What is waiting on the person, in the words it is said in (lib/notes/notices.dart), after the web's
/// `notes/Notices.test.tsx`: each stage of an update, the voice model coming down or failing to, and the Academy's
/// invitation. Each says nothing at all when there is nothing to say.
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

  group('the update card', () {
    testWidgets('says nothing with nothing newer', (tester) async {
      await show(tester, const UpdateNotice(updates: AppUpdates()));
      expect(key('update-notice'), findsNothing);
      expect(tester.getSize(find.byType(UpdateNotice)).height, 0);
      await away(tester);
    });

    testWidgets('offers a new version to install, with the ghost and its parcel, and installs it', (tester) async {
      var installs = 0;
      await show(tester, UpdateNotice(updates: AppUpdates(apk: const ApkAvailable('1.9.0'), onInstall: () => installs += 1)));
      expect(said(tester, 'Ghost.md 1.9.0 is out.'), isTrue);
      expect(tester.widget<Ghost>(find.byType(Ghost)).scene, GhostScene.update);
      await tester.tap(find.text('Install'));
      expect(installs, 1);
      await away(tester);
    });

    testWidgets('counts a download in whole megabytes, with its bar and its cogs, and offers nothing to press meanwhile', (tester) async {
      await show(tester, const UpdateNotice(updates: AppUpdates(apk: ApkDownloading('1.9.0', received: 12400000, total: 48000000))));
      expect(said(tester, 'Downloading Ghost.md 1.9.0, 12 of 48 MB.'), isTrue);
      expect(key('update-action'), findsNothing);
      expect(find.byType(WorkingGears), findsOneWidget);
      expect(find.byType(Ghost), findsNothing);
      // `inline-size: 26%`: a whole percent of the card, 3px tall along its foot.
      final card = tester.getRect(key('update-notice')), bar = tester.getRect(key('update-progress'));
      final t = GlacierTheme.of(tester.element(key('update-notice')));
      expect(bar.width / card.width, closeTo(0.26, 0.002));
      expect([bar.height, bar.left - card.left], [3, 0]);
      expect(bar.bottom, closeTo(card.bottom - t.space(5), 0.01), reason: 'the bar is on the card’s foot, above its margin');
      await tester.pump(const Duration(seconds: 1));
      await away(tester);
    });

    testWidgets('takes the same room in every state, its words where they were, from the first word to the restart', (tester) async {
      // Matt, 2026-10-24: "the ghost update banner shifts when updating pleaase make sure it always takes up the same
      // space".
      for (final width in [390.0, 1000.0]) {
        final states = <String, AppUpdates>{
          'available': AppUpdates(apk: const ApkAvailable('2.3.23'), onInstall: () {}),
          'downloading': const AppUpdates(apk: ApkDownloading('2.3.23', received: 12400000, total: 57000000)),
          'ready': AppUpdates(apk: const ApkReady('2.3.23'), onRestart: () {}),
          'restarting': const AppUpdates(apk: ApkRestarting('2.3.23')),
          'failed': AppUpdates(apk: const ApkFailed('2.3.23', 'The download was cut short. Check the connection and try again.'), onInstall: () {}),
          'waiting': AppUpdates(apk: const ApkInstalling('2.3.23'), onInstall: () {}),
        };
        final heights = <String, double>{}, starts = <String, double>{};
        for (final MapEntry(key: name, value: updates) in states.entries) {
          await show(tester, UpdateNotice(updates: updates), width: width);
          heights[name] = tester.getSize(key('update-notice')).height;
          starts[name] = tester.getTopLeft(find.descendant(of: key('update-body'), matching: find.byType(Text)).first).dx;
          await tester.pump(const Duration(seconds: 1));
        }
        expect(heights.values.toSet(), hasLength(1), reason: 'at $width: $heights');
        expect(starts.values.toSet(), hasLength(1), reason: 'the words start in one place at $width: $starts');
      }
      await away(tester);
    });

    testWidgets('says why an install did not happen, and offers it again', (tester) async {
      await show(tester, UpdateNotice(updates: AppUpdates(apk: const ApkFailed('1.9.0', 'The file was damaged.'), onInstall: () {})));
      expect(said(tester, 'Ghost.md 1.9.0 didn’t install. The file was damaged.'), isTrue);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(Ghost), findsNothing);
      await away(tester);
    });

    testWidgets('asks to be let install, and waits on Android once it has asked', (tester) async {
      await show(tester, UpdateNotice(updates: AppUpdates(apk: const ApkNeedsPermission(), onInstall: () {})));
      expect(said(tester, 'Let Ghost.md install apps, then come back.'), isTrue);
      expect(find.text('Install'), findsOneWidget);
      await away(tester);
      await show(tester, UpdateNotice(updates: AppUpdates(apk: const ApkInstalling('1.9.0'), onInstall: () {})));
      expect(said(tester, 'Ghost.md 1.9.0 is waiting on Android.'), isTrue);
      expect(find.text('Open'), findsOneWidget);
      await away(tester);
    });

    testWidgets('offers a reload for a new version of the page already downloaded', (tester) async {
      var reloads = 0;
      await show(tester, UpdateNotice(updates: AppUpdates(ready: true, onReload: () => reloads += 1)));
      expect(said(tester, 'A new version of Ghost.md is ready.'), isTrue);
      await tester.tap(find.text('Reload'));
      expect(reloads, 1);
      await away(tester);
    });

    testWidgets('is the stylesheet’s card: a space of margin under it, its pill a space-10 tall, white in the dark too', (tester) async {
      await show(tester, UpdateNotice(updates: AppUpdates(ready: true, onReload: () {})));
      final t = GlacierTheme.of(tester.element(key('update-notice')));
      final card = tester.getRect(key('update-notice')), pill = tester.getRect(key('update-action'));
      // `padding: space-3 space-3 space-3 space-4` round the ghost, 3rem tall and taller than the pill of
      // `min-block-size: space-10` beside it, and `margin: 0 0 space-5`.
      expect(card.height, closeTo(t.space(3) * 2 + t.lenOf('3rem') + t.space(5), 0.01));
      expect(tester.getSize(find.byType(Image)).height, closeTo(t.lenOf('3rem'), 0.01));
      expect(pill.height, closeTo(t.space(10), 0.01));
      expect(card.right - pill.right, closeTo(t.space(3), 0.01));
      expect(card.width, closeTo(390 - t.len('app-gutter-start') - t.len('app-gutter-end'), 0.01));
      await loadPictures(tester);
      await shot(tester, 'notice-update-dark');
    });
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
            UpdateNotice(updates: AppUpdates(apk: const ApkAvailable('1.15.0'), onInstall: () {})),
            const UpdateNotice(updates: AppUpdates(apk: ApkDownloading('1.15.0', received: 12400000, total: 48000000))),
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
