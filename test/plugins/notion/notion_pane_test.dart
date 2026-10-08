import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../../settings/support.dart';
import 'support.dart';

/// Notion's two faces in the app: its page in Settings (signing in and out, the boards shared) and its picker on a
/// note's cog (a board to send the note's list to). The web app's `NotionPane.test.tsx`, case for case. The page's
/// test stood the client in for; here the client is the real one, on a phone whose secure store and whose recorded
/// answers each test sets (the sign-in and the calls themselves are client_test.dart).
Map<String, Object?> boards(List<Map<String, Object?>> results) => {'results': results};
final Map<String, Object?> road = database('b1', 'Roadmap', properties: const {'Task': {'type': 'title'}});
final Map<String, Object?> home = database('b2', 'Home');

void main() {
  setUpAll(loadAppFonts);
  late Phone phone;
  final finder = SettingsFinder();

  setUp(() {
    phone = Phone()..use();
    phone.answer = (request) async => json(200, boards([road, home]));
  });
  tearDown(() {
    resetNotionDetails();
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  Future<void> pane(WidgetTester tester) => pumpSettings(tester, SettingsPaneScope(finder: finder, child: const SingleChildScrollView(child: NotionPane())));
  Future<void> picker(WidgetTester tester, VoidCallback onDone, {bool settle = true}) =>
      pumpSettings(tester, Align(alignment: Alignment.topLeft, child: SizedBox(width: 290, child: BoardPicker(noteId: 'n1', onDone: onDone))), settle: settle);
  String calloutWords(WidgetTester tester) => tester.widget<Text>(find.descendant(of: find.byType(SettingsCallout), matching: find.byType(Text))).data!;

  group('Settings > Notion', () {
    // The page's first half, "in a browser, says Notion works in the app", has no counterpart: this is the app.
    testWidgets('on an old binary, says that it needs the newest', (tester) async {
      phone.generation = 11;
      await pane(tester);
      expect(find.text('Notion needs the newest Ghost.md.'), findsOneWidget);
      expect(find.text('Install the latest version from Settings > Updates, then come back here to sign in.'), findsOneWidget);
      expect(find.byType(SettingRow), findsNothing);
      await endSettings(tester);
    });

    testWidgets('signed out, opens the sign-in and then says to finish it on Notion', (tester) async {
      await pane(tester);
      expect(find.text('Not signed in'), findsOneWidget);
      await tester.tap(find.text('Sign in'));
      await settleSettings(tester);
      expect(phone.opened, hasLength(1));
      expect(phone.opened.single, startsWith('https://ghostmarkdown.com/api/notion/start?state='));
      expect(find.text('Finish signing in on Notion'), findsOneWidget);
      expect(find.text('Pick the boards Ghost.md can use, then come back here.'), findsOneWidget);
      expect(find.descendant(of: find.byType(RowAction), matching: find.text('Open again')), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('says why the sign-in would not start', (tester) async {
      phone.cannotOpen = 'Notion needs the newest Ghost.md. Install it from Settings > Updates.';
      await pane(tester);
      await tester.tap(find.text('Sign in'));
      await settleSettings(tester);
      expect(calloutWords(tester), 'Notion needs the newest Ghost.md. Install it from Settings > Updates.');
      expect(find.text('Not signed in'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('signed in, names the workspace, lists the boards shared, and signs out', (tester) async {
      phone.secrets.held[accountSecret] = accountJson(workspace: 'Studio');
      await pane(tester);
      expect(find.text('Signed in to Studio'), findsOneWidget);
      expect(find.text('Tasks are named by “Task”.'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(phone.asked.single['path'], 'search');
      await tester.tap(find.text('Sign out'));
      await settleSettings(tester);
      expect(phone.secrets.held.containsKey(accountSecret), isFalse);
      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('BOARDS'), findsNothing);
      await endSettings(tester);
    });

    // Settings' contract, in the one state that draws the whole page: each name the search lists for it is a card
    // on it, so a hit lights something (docs/DESIGN.md §138).
    testWidgets('signed in, draws every card the search lists for the page', (tester) async {
      phone.secrets.held[accountSecret] = accountJson(workspace: 'Studio');
      await pane(tester);
      expect(find.text('Home'), findsOneWidget);
      final names = [for (final setting in notionPlugin.settings!.settings) setting.name];
      expect(names, ['Account', 'Boards']);
      expect(names.where((name) => finder.find(name) == null), isEmpty);
      await endSettings(tester);
    });

    testWidgets('says when no boards were shared, and why they could not be read', (tester) async {
      phone.secrets.held[accountSecret] = accountJson(workspace: null);
      phone.answer = (request) async => json(200, boards(const []));
      await pane(tester);
      expect(find.text('Signed in to Notion'), findsOneWidget);
      expect(find.text('No boards shared yet'), findsOneWidget);
      await endSettings(tester);

      phone.answer = (request) async => json(401, {'message': 'API token is invalid.'});
      await pane(tester);
      expect(calloutWords(tester), 'Notion signed Ghost.md out. Sign in again in Settings › Plugins › Notion.');
      await endSettings(tester);
    });

    testWidgets('is the page the plugin hands Settings', (tester) async {
      await pumpSettings(tester, SingleChildScrollView(child: Builder(builder: notionPlugin.settings!.pane)));
      expect(find.byType(NotionPane), findsOneWidget);
      await endSettings(tester);
    });
  });

  group('the board picker on a note', () {
    testWidgets('offers the sign-in while signed out', (tester) async {
      await picker(tester, () {});
      expect(find.text('Sign in to Notion'), findsOneWidget);
      await tester.tap(find.text('Sign in with Notion'));
      await settleSettings(tester);
      expect(phone.opened, hasLength(1));
      await endSettings(tester);
    });

    testWidgets('says it is checking before the account has answered', (tester) async {
      final answered = Completer<void>();
      phone.secrets.hold = answered.future;
      await picker(tester, () {}, settle: false);
      expect([for (final text in tester.widgetList<Text>(find.byType(Text))) text.data], ['Checking Notion…']);
      answered.complete();
      await settleSettings(tester);
      expect(find.text('Checking Notion…'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('links the board chosen, ticks it, and takes the note off Notion again', (tester) async {
      phone.secrets.held[accountSecret] = accountJson(workspace: 'Studio');
      var done = 0;
      await picker(tester, () => done += 1);
      expect(find.text('Boards in Studio that Ghost.md can see.'), findsOneWidget);
      SheetRow row(String label) => tester.widget<SheetRow>(find.ancestor(of: find.text(label), matching: find.byType(SheetRow)));
      expect(row('Roadmap').chosen, isFalse);
      expect(find.text('Don’t send this note to Notion'), findsNothing);
      await tester.tap(find.text('Roadmap'));
      await settleSettings(tester);
      expect(boardFor('n1')?.id, 'b1');
      expect(boardFor('n1')?.titleProperty, 'Task');
      expect(done, 1);
      expect(row('Roadmap').chosen, isTrue);
      expect(row('Home').chosen, isFalse);
      await tester.tap(find.text('Don’t send this note to Notion'));
      await settleSettings(tester);
      expect(boardFor('n1'), isNull);
      expect(done, 2);
      await endSettings(tester);
    });

    testWidgets('says there are no boards yet, and why they could not be read', (tester) async {
      phone.secrets.held[accountSecret] = accountJson(workspace: null);
      phone.answer = (request) async => json(200, boards(const []));
      await picker(tester, () {});
      expect(find.text('Boards in Notion that Ghost.md can see.'), findsOneWidget);
      expect(find.text('No boards yet'), findsOneWidget);
      expect(find.text('Sign in again from Settings › Plugins › Notion and tick the boards you want.'), findsOneWidget);
      await endSettings(tester);

      phone.answer = (request) async => json(404);
      await picker(tester, () {});
      expect(find.text('Notion can’t see that board. Share it with Ghost.md in Notion.'), findsOneWidget);
      expect(find.text('Looking for boards…'), findsOneWidget);
      await endSettings(tester);
    });
  });
}
