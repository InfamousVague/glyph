import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';

import 'support.dart';

/// The Notion account as Settings > Notion reads it (client.dart [NotionAccountWatch], the page's
/// `useNotionAccount`): asked of the secure store when the page is drawn, and again each time Ghost.md comes back
/// to the front, which is how a sign-in finished in the phone's browser, or a disconnect made elsewhere, shows
/// without leaving the page. The web app's `account.test.tsx`.

/// The page's reading of the account: the workspace, or that there is none.
class Account extends StatefulWidget {
  const Account({super.key});

  @override
  State<Account> createState() => _AccountState();
}

class _AccountState extends State<Account> {
  late final NotionAccountWatch watch = NotionAccountWatch()..addListener(() => setState(() {}));

  @override
  void dispose() {
    watch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = watch.account;
    return Directionality(textDirection: TextDirection.ltr, child: Text(shown == null ? 'asking' : (shown.connected ? shown.workspaceName! : 'signed out')));
  }
}

/// Until what was asked has answered and been drawn: the store and the recorded network answer in microtasks.
Future<void> answered(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  late Phone phone;

  setUp(() => phone = Phone(account: accountJson(workspace: 'Glyph HQ'))..use());
  tearDown(() {
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  group('useNotionAccount', () {
    testWidgets('reads the account when drawn, and again when Ghost.md comes back to the front, not when it goes', (tester) async {
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.pumpWidget(const Account());
      expect(find.text('asking'), findsOneWidget);
      await tester.pump();
      expect(find.text('Glyph HQ'), findsOneWidget);
      expect(phone.secrets.reads, 1);
      // Disconnected elsewhere while the app was away.
      phone.secrets.held.remove(accountSecret);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(phone.secrets.reads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(phone.secrets.reads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await answered(tester);
      expect(find.text('signed out'), findsOneWidget);
      expect(phone.secrets.reads, 2);
    });

    // Not in the web's file, which stood the binary in for: coming back from Notion's page with the sign-in done.
    testWidgets('collects a sign-in in flight when Ghost.md comes back, and says why one was refused', (tester) async {
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      phone.secrets.held.clear();
      late NotionAccountWatch watch;
      await tester.pumpWidget(const Account());
      watch = tester.state<_AccountState>(find.byType(Account)).watch;
      await tester.pump();
      expect(find.text('signed out'), findsOneWidget);

      await tester.runAsync(startNotionSignIn);
      phone.answer = (request) async => json(202, {'pending': true});
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await answered(tester);
      expect(find.text('signed out'), findsOneWidget, reason: 'still on Notion’s page');
      expect(watch.problem, isNull);

      phone.answer = (request) async => json(200, {'accessToken': 'secret', 'workspaceName': 'Studio'});
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await answered(tester);
      expect(find.text('Studio'), findsOneWidget);
      expect([for (final r in phone.requests) r.url.path], ['/api/notion/claim', '/api/notion/claim']);

      await tester.runAsync(() async {
        await disconnectNotion();
        await startNotionSignIn();
      });
      phone.answer = (request) async => json(400, {'error': 'You cancelled the sign-in.'});
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await answered(tester);
      expect(find.text('signed out'), findsOneWidget);
      expect(watch.problem, 'You cancelled the sign-in.');
    });
  });
}
