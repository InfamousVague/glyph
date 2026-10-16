// A note's site, in its sharing (lib/share/ui/site_rows.dart): publish it, copy its link, publish it again at the
// same address, unpublish it; a journal and a build that offers no sites draw none; signed out it says where to sign
// in. Against the real sites over the service in memory.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/share/ui/share_rows.dart';
import 'package:ghost_md/share/ui/site_rows.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../account_ui/support.dart';

Future<void> rows(WidgetTester tester, Device device, String noteId, {ShareKind kind = ShareKind.note}) async {
  await device.pump(tester, ShareRows(key: ValueKey('rows:$noteId:$kind'), services: device.services, noteId: noteId, kind: kind));
  await settle(tester, 10);
}

String hintOf(WidgetTester tester, String label) {
  final texts = tester.widgetList<Text>(find.descendant(of: find.widgetWithText(SheetRow, label), matching: find.byType(Text))).toList();
  return texts.length > 1 ? texts[1].data! : '';
}

Future<void> pressRow(WidgetTester tester, String label) async {
  await bringIntoView(tester, find.widgetWithText(SheetRow, label));
  await tester.tap(find.widgetWithText(SheetRow, label));
  await settle(tester, 12);
}

String? said(WidgetTester tester) {
  final found = find.byKey(const ValueKey('site-said'));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('publishes a notebook as a site, copies its link, publishes it again at the same address and unpublishes it', (tester) async {
    final device = await Device.make(publishing: true);
    final copied = Clipped(tester);
    device.keep('book', '---\nbook: true\n---\n# Field guide\n\n1. [[Trees]]\n');
    device.keep('t', '# Trees\n\nOaks.');
    await rows(tester, device, 'book', kind: ShareKind.notebook);
    expect(find.text('SITE'), findsOneWidget);
    expect(hintOf(tester, 'Publish as a site'), 'A small website of this notebook, its pages in order. Anyone with the link can read it. The server can’t read your words, though a page’s name is in its address. Search engines can’t list it.');
    await pressRow(tester, 'Publish as a site');
    final site = device.sites!.siteFor('book')!;
    expect(copied.text, site.link);
    expect(said(tester), 'Published. The link is copied.');
    expect(device.service.sites.keys, [site.id]);
    expect(hintOf(tester, 'Copy the site’s link'), startsWith('Published just now.'));
    device.keep('t', '# Trees\n\nOaks and ash.');
    await pressRow(tester, 'Publish again');
    expect(said(tester), 'Published again, at the same address.');
    expect(device.service.sites.keys, [site.id]);
    expect((await device.sites!.readSite(site.id, site.key)).pages.last.body, contains('ash'));
    await pressRow(tester, 'Unpublish');
    expect(device.service.sites, isEmpty);
    expect(find.widgetWithText(SheetRow, 'Publish as a site'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('a site published on another device shows here as published', (tester) async {
    final service = await FakeService.start(seed: seeded);
    final phone = await Device.make(service: service, publishing: true);
    await phone.sites!.publish(phone.keep('n', '# Walk'), phone.notes.held.values.toList());
    final mac = await Device.make(service: service, publishing: true);
    mac.keep('n', '# Walk');
    await rows(tester, mac, 'n');
    expect(find.widgetWithText(SheetRow, 'Copy the site’s link'), findsOneWidget);
    expect(hintOf(tester, 'Publish as a site'), isEmpty);
    await endSettings(tester);
  });

  testWidgets('signed out it says where to sign in; a journal and a build with no sites draw none', (tester) async {
    final out = await Device.make(publishing: true, signedIn: false);
    await rows(tester, out, 'a');
    expect(hintOf(tester, 'Publish as a site'), 'Sign in under Settings › Account first: a site is kept with your account.');
    await endSettings(tester);
    final device = await Device.make(publishing: true);
    await rows(tester, device, 'j', kind: ShareKind.journal);
    expect(find.byType(SiteRows), findsNothing);
    await endSettings(tester);
    final none = await Device.make();
    await rows(tester, none, 'a');
    expect(find.text('SITE'), findsNothing);
    expect(find.widgetWithText(SheetRow, 'Share a read-only link'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('says so when there is nothing saved to publish yet', (tester) async {
    final device = await Device.make(publishing: true);
    await rows(tester, device, 'unsaved');
    await pressRow(tester, 'Publish as a site');
    expect(said(tester), 'Save the note first: there is nothing to publish yet.');
    expect(device.service.sites, isEmpty);
    await endSettings(tester);
  });
}
