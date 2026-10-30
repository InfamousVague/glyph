// A form's rows in its note's sharing (lib/forms/ui/form_rows.dart, docs/FORMS.md), against the real shares over the
// service in memory: a form not shared says what sharing it does; shared, its link is said to be a form at once and
// takes answers, paused and closed are each a row to choose, the count of answers filed and waiting is said, and the
// answers waiting can be deleted - behind More in simple mode. A note that is no form has no such rows.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/share/ui/share_rows.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../account_ui/support.dart';

const String formBody = '# Report a bug\n\nTell us.\n\n```form\nto: [[Bug reports]]\n- Summary: short, required\n```\n';

Future<void> rows(WidgetTester tester, Device device, String noteId) async {
  await device.pump(tester, ShareRows(key: ValueKey('rows:$noteId'), services: device.services, noteId: noteId));
  await settle(tester, 12);
}

SheetRow? row(WidgetTester tester, String label) {
  final found = find.widgetWithText(SheetRow, label);
  return found.evaluate().isEmpty ? null : tester.widget<SheetRow>(found.first);
}

Future<void> pressRow(WidgetTester tester, String label) async {
  await bringIntoView(tester, find.widgetWithText(SheetRow, label));
  await tester.tap(find.widgetWithText(SheetRow, label));
  await settle(tester, 12);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a form not shared says what sharing it does; a note that is no form has no form rows', (tester) async {
    final device = await Device.make();
    device.keep('book', '---\nbook: true\n---\n# Bug reports\n\n1. [[Report a bug]]\n');
    device.keep('form', formBody);
    device.keep('plain', '# Trip');
    await rows(tester, device, 'form');
    expect(find.byKey(const ValueKey('form-unshared')), findsOneWidget);
    expect(find.textContaining('Each answer becomes a ticket in Bug reports.'), findsOneWidget);
    await endSettings(tester);
    await rows(tester, device, 'plain');
    expect(find.byKey(const ValueKey('form-unshared')), findsNothing);
    expect(find.byKey(const ValueKey('form-open')), findsNothing);
    await endSettings(tester);
  });

  testWidgets('shared, its link is said to be a form at once, and is opened, paused or closed by a row', (tester) async {
    final device = await Device.make();
    device.keep('form', formBody);
    final link = await device.shares!.shareNote(device.notes.held['form']!, device.notes.held.values.toList());
    final id = link.substring(link.indexOf('#') + 1, link.lastIndexOf('.'));
    await rows(tester, device, 'form');
    final form = device.service.forms.forms[id]!;
    expect((form.note, form.state), ('form', 'open'));
    expect(row(tester, 'Taking answers')!.chosen, isTrue);
    expect(row(tester, 'Paused')!.chosen, isFalse);
    expect(find.text('No answers yet.'), findsOneWidget);
    await pressRow(tester, 'Paused');
    expect(form.state, 'paused');
    expect(row(tester, 'Paused')!.chosen, isTrue);
    await pressRow(tester, 'Closed');
    expect(form.state, 'closed');
    await pressRow(tester, 'Taking answers');
    expect(form.state, 'open');
    await endSettings(tester);
  });

  testWidgets('counts what came and was filed, and deletes what waits: behind More in simple mode', (tester) async {
    final device = await Device.make();
    device.keep('form', formBody);
    final link = await device.shares!.shareNote(device.notes.held['form']!, device.notes.held.values.toList());
    final id = link.substring(link.indexOf('#') + 1, link.lastIndexOf('.'));
    await rows(tester, device, 'form');
    final forms = device.service.forms;
    for (final n in [1, 2, 3]) {
      await forms.answer(device.service.crypto, form: id, id: 'answer-$n', keys: const [], payload: const {'v': 1, 'answers': []}, at: n);
    }
    forms.forms[id]!.filed = 2;
    forms.forms[id]!.received = 5;
    preferences.value = preferences.value.copyWith(experience: 'simple');
    await endSettings(tester);
    await rows(tester, device, 'form');
    expect(find.text('2 answers filed as tickets, 3 waiting for a device to file.'), findsOneWidget);
    expect(row(tester, 'Delete the answers waiting'), isNull);
    await pressRow(tester, 'More');
    await pressRow(tester, 'Delete the answers waiting');
    expect(forms.inbox, isEmpty);
    expect(find.text('3 answers deleted, unfiled.'), findsOneWidget);
    expect(row(tester, 'Delete the answers waiting'), isNull);
    await endSettings(tester);
  });
}
