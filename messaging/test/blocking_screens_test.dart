import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/ui/blocking.dart';

import 'support/space_call_harness.dart';

/// The one Blocked list, numbers and Telegram and Signal people together (lib/ui/blocking.dart): drawn to
/// test/shots/blocked-* with --update-goldens.
void main() {
  testWidgets('the Blocked list', (tester) async {
    final h = await SpaceHarness.load(tester);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async => call.method == 'blockedNumbers'
        ? [
            {'address': '+15550100123', 'name': 'Unknown caller'},
            {'address': '+15550100456'},
          ]
        : null);
    final store = AppState();
    for (final n in Inbox.instance.networks) {
      n.listStore = store;
    }
    Inbox.instance.named('telegram')?.keepBlocked('7', name: 'Jo Park');
    Inbox.instance.named('signal')?.keepBlocked('aci-sam', name: 'Sam Rivera');
    for (final dark in [false, true]) {
      await h.shoot(tester, const BlockedScreen(), 'blocked', dark: dark);
    }
    expect(find.text('Jo Park'), findsOneWidget);
    expect(find.text('Sam Rivera'), findsOneWidget);
  });
}
