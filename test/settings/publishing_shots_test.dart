// Pictures of what publishing and email to a note look like, for the eye (docs/FEATURES_2_1.md, publish-email):
// written only by `flutter test --update-goldens test/settings/publishing_shots_test.dart`, into
// build/feature-shots/publish-email/ (not committed), dark, at the phone's size and the Fold's inner one.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/mail/ui/mail_card.dart';
import 'package:ghost_md/settings/panes/account_pane.dart';
import 'package:ghost_md/settings/published_sites.dart';
import 'package:ghost_md/share/ui/share_rows.dart';

import '../account_ui/support.dart';

const Size fold = Size(900, 1000);
const Size phoneShot = Size(430, 932);

Future<void> draw(WidgetTester tester, Device device, Widget child, Size size) async {
  await pumpApp(tester, size: size, ratio: 3, prefs: const Preferences(theme: 'dark'), home: BackScope(stack: BackStack(), child: AccountScope(services: device.services, child: child)));
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await settle(tester, 12);
}

Future<void> picture(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/publish-email/$name.png'));
}

/// A device with two sites published and an address on, the account as a person's would be after a week of it.
Future<Device> busy() async {
  var clock = DateTime(2026, 10, 14, 9, 30).millisecondsSinceEpoch;
  final service = await FakeService.start(seed: seeded)..clock = () => clock;
  final device = await Device.make(service: service, publishing: true, now: () => DateTime(2026, 10, 16, 14, 5).millisecondsSinceEpoch);
  await device.sites!.publish(device.keep('b', '---\nbook: true\n---\n# Field guide\n\n1. [[Trees]]\n'), device.notes.held.values.toList());
  clock = DateTime(2026, 10, 16, 11, 12).millisecondsSinceEpoch;
  await device.sites!.publish(device.keep('n', '# The long road'), device.notes.held.values.toList());
  await device.mailIn!.newAddress();
  return device;
}

Widget cards(Device device) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AccountPane(services: device.services),
      ),
    );

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the Account page\'s two cards, phone and Fold', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    final device = await busy();
    device.sites!.forget();
    for (final (size, name) in [(phoneShot, 'phone'), (fold, 'fold')]) {
      await draw(tester, device, cards(device), size);
      await Scrollable.ensureVisible(tester.element(find.byType(PublishedSites)), alignment: 0.1);
      await tester.pump();
      await picture(tester, 'account-cards-$name-dark');
      await endSettings(tester);
    }
  });

  testWidgets('email to a note, off', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    final device = await Device.make(publishing: true);
    await draw(tester, device, cards(device), phoneShot);
    await Scrollable.ensureVisible(tester.element(find.byType(MailCard)), alignment: 0.2);
    await tester.pump();
    await picture(tester, 'mail-off-phone-dark');
    await endSettings(tester);
  });

  testWidgets('a notebook\'s sharing with its site, before and after publishing, phone and Fold', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    final fresh = await Device.make(publishing: true);
    fresh.keep('b', '---\nbook: true\n---\n# Field guide\n');
    await draw(tester, fresh, ShareSheet(services: fresh.services, noteId: 'b', title: 'Field guide', kind: ShareKind.notebook, onClose: () {}), phoneShot);
    await picture(tester, 'site-rows-unpublished-phone-dark');
    await endSettings(tester);
    final device = await busy();
    for (final (size, name) in [(phoneShot, 'phone'), (fold, 'fold')]) {
      await draw(tester, device, ShareSheet(services: device.services, noteId: 'b', title: 'Field guide', kind: ShareKind.notebook, onClose: () {}), size);
      await picture(tester, 'site-rows-published-$name-dark');
      await endSettings(tester);
    }
  });
}
