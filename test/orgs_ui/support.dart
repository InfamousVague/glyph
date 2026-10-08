import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/orgs/ui/parts.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/organization_sheet.dart';

import '../account_ui/support.dart';

export '../account_ui/support.dart';

/// The organization made by matt, as the service holds it (`ghost()`).
Future<String> ghost(Device device, {String name = 'Ghost', String? hue = 'sea'}) async => (await device.orgs.createOrg(name, hue: hue)).id;

/// sam invited to [orgId] by the service's own rules, and joined when [joined]: the one account can only be matt
/// (`sam()`).
Future<void> sam(Device device, String orgId, {required bool joined}) async {
  await device.orgs.inviteByHandle(orgId, 'sam');
  if (joined) device.service.orgs[orgId]!.rows['sam']!.state = 'member';
}

/// An organization sam made, with matt in it as [role]: its row and workspace on the device, as a pass would have
/// brought them.
Future<String> boo(Device device, {bool member = true, String role = 'member'}) async {
  final id = device.service.invited('Boo', 'sam');
  if (member) {
    device.service.orgs[id]!.rows['matt']!
      ..state = 'member'
      ..role = role;
  }
  await listed(device);
  return id;
}

/// The organizations' list taken again, as a pass takes it (`syncOrgs` with `saveOrgs`).
Future<void> listed(Device device) async {
  final session = device.account.session!;
  await device.orgs.syncOrgs(OrgsContext(token: session.token, save: (state) => device.orgs.saveOrgs(session.accountId, state)));
}

/// The screen's sections, as its list names them (`.settingsScreen__rowLabel`).
List<String?> labels(WidgetTester tester) => [for (final text in tester.widgetList<Text>(find.byKey(const ValueKey('settings-row-label')))) text.data];

/// The page's name over its pane (`.settingsScreen__display`), or null on the list.
String? display(WidgetTester tester) {
  final found = find.byKey(const ValueKey('settings-display'));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

final Finder headWord = find.byKey(const ValueKey('settings-head-word'));

/// The head's word, without its arrow.
String headWords(WidgetTester tester) => find.descendant(of: headWord, matching: find.byType(RichText)).evaluate().map((e) => (e.widget as RichText).text.toPlainText().replaceAll('￼', '').trim()).join();

/// Opens the section called [label] from the list.
Future<void> openSection(WidgetTester tester, String label) async {
  final row = find.byWidgetPredicate((w) => w is Text && w.key == const ValueKey('settings-row-label') && w.data == label);
  expect(row, findsOneWidget, reason: 'the section called $label');
  await tester.tap(row);
  await settle(tester, 10);
}

/// The phone's back gesture.
Future<void> goBack(WidgetTester tester) async {
  testBack.goBack();
  await settle(tester, 10);
}

/// A member's row on Members, by handle, with its chip's words, its hint and the words under it (`member()`).
({Finder row, String? chip, String? hint, List<String> words})? member(WidgetTester tester, String handle) {
  final row = find.byKey(ValueKey('member:$handle'));
  if (row.evaluate().isEmpty) return null;
  final chip = find.descendant(of: row, matching: find.descendant(of: find.byType(RoleChip), matching: find.byType(Text)));
  final setting = tester.widget<SettingRow>(find.descendant(of: row, matching: find.byType(SettingRow)));
  return (
    row: row,
    chip: chip.evaluate().isEmpty ? null : tester.widget<Text>(chip.first).data,
    hint: (setting.hint as Text?)?.data,
    words: [for (final action in tester.widgetList<RowAction>(find.descendant(of: row, matching: find.byType(RowAction)))) (action.child as Text).data!],
  );
}

/// Presses the word [word] under [handle]'s row.
Future<void> pressOn(WidgetTester tester, String handle, String word) async {
  final target = find.descendant(of: find.byKey(ValueKey('member:$handle')), matching: find.text(word));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settle(tester, 10);
}

/// The hero's line under the organization's name (`.setk-hero__meta`).
String? heroMeta(WidgetTester tester) => (tester.widget<PaneHero>(find.byType(PaneHero)).meta as Text?)?.data;

/// The organization's own screen, drawn.
Future<void> pumpSheet(
  WidgetTester tester,
  Device device,
  String orgId, {
  OrganizationFrom? from,
  bool landOnMembers = true,
  VoidCallback? onClose,
  VoidCallback? onNotes,
  void Function(String url)? onOpenLink,
  Size size = phone,
}) async {
  await device.pump(
    tester,
    OrganizationSheet(services: device.services, orgId: orgId, from: from, landOnMembers: landOnMembers, onClose: onClose ?? () {}, onNotes: onNotes ?? () {}, onOpenLink: onOpenLink),
    size: size,
    scroll: false,
  );
  await settle(tester, 12);
}
