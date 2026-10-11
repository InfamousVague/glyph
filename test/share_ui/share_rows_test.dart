// A note's sharing, and Settings' list of shared links, against the real shares over the service in memory. Ports
// of `src/app/share/ShareRows.test.tsx` and `src/app/settings/SharedLinks.test.tsx`, case for case: the web's tests
// stand a mock in for share.ts, where these seal and send a real share to the fake service.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/shared_links.dart';
import 'package:ghost_md/share/ui/share_rows.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:glacier/glacier.dart';

import '../account_ui/support.dart';

const String tag = '---\nlocation: 51.5074,-0.1278\n---\n';
const String cais = '[Cais do Sodré, Lisbon](geo:38.7061,-9.1443)';

Future<void> rows(WidgetTester tester, Device device, String noteId, {ShareKind kind = ShareKind.note, bool services = true}) async {
  await device.pump(tester, ShareRows(key: ValueKey('rows:$noteId:$kind:$services'), services: services ? device.services : null, noteId: noteId, kind: kind));
  await settle(tester, 10);
}

/// The row saying [label], or null.
SheetRow? row(WidgetTester tester, String label) {
  final found = find.widgetWithText(SheetRow, label);
  return found.evaluate().isEmpty ? null : tester.widget<SheetRow>(found.first);
}

/// A row's hint, as its words.
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
  final found = find.byKey(const ValueKey('share-said'));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

/// The note [id] shared already, as a device that shared it earlier holds it.
Future<String> shared(Device device, String id, String body) async {
  final note = device.keep(id, body);
  return device.shares!.shareNote(note, device.notes.held.values.toList());
}

void main() {
  setUpAll(loadAppFonts);

  group('a note’s sharing', () {
    testWidgets('signed out, says where to sign in and offers nothing to press', (tester) async {
      final device = await Device.make(signedIn: false);
      await rows(tester, device, 'a');
      expect(find.text('Sign in under Settings › Account first: a share is kept with your account.'), findsOneWidget);
      expect(find.byType(GlacierPressable), findsNothing);
      // With no services at all, the same line.
      await endSettings(tester);
      await rows(tester, device, 'a', services: false);
      expect(find.text('Sign in under Settings › Account first: a share is kept with your account.'), findsOneWidget);
      expect(find.byType(GlacierPressable), findsNothing);
      await endSettings(tester);
    });

    testWidgets('shares a saved note by a link, copies it, and offers the link from then on', (tester) async {
      final device = await Device.make();
      final copied = Clipped(tester);
      device.keep('a', '# Trip');
      await rows(tester, device, 'a');
      await pressRow(tester, 'Share a read-only link');
      final link = device.shares!.linkFor('a');
      expect(link, isNotNull);
      expect(device.service.shares, hasLength(1));
      // What the service holds opens with the link's key to the note's words, and to nobody without it.
      final read = await device.shares!.readShared(link!);
      expect(read.pages.single.body, '# Trip');
      expect(copied.text, link);
      expect(said(tester), 'The link is copied.');
      expect(row(tester, 'Copy the link'), isNotNull);
      await pressRow(tester, 'Stop sharing');
      expect(device.service.shares, isEmpty);
      expect(device.shares!.linkFor('a'), isNull);
      expect(row(tester, 'Share a read-only link'), isNotNull);
      await endSettings(tester);
    });

    testWidgets('says so when there is nothing saved to share yet, and what went wrong when sharing failed', (tester) async {
      final service = await FakeService.start(seed: seeded);
      var down = false;
      final device = await Device.make(service: service, fetcher: (request) async => down && request.url.path.contains('/shares') ? FetchResponse.json(500, {'error': 'The service is not answering.'}) : service.fetcher(request));
      await rows(tester, device, 'unsaved');
      await pressRow(tester, 'Share a read-only link');
      expect(said(tester), 'Save the note first: there is nothing to share yet.');
      await endSettings(tester);
      device.keep('a', '# Trip');
      down = true;
      await rows(tester, device, 'a');
      await pressRow(tester, 'Share a read-only link');
      expect(said(tester), 'The service is not answering.');
      expect(device.shares!.linkFor('a'), isNull);
      await endSettings(tester);
    });

    testWidgets('says a notebook’s pages go with it, and a note’s row says nothing of pages', (tester) async {
      final device = await Device.make();
      await rows(tester, device, 'a', kind: ShareKind.notebook);
      expect(hintOf(tester, 'Share a read-only link'), contains('Every page goes with it.'));
      await endSettings(tester);
      await rows(tester, device, 'b');
      expect(hintOf(tester, 'Share a read-only link'), isNot(contains('page')));
      await endSettings(tester);
    });

    testWidgets('says a journal is shared an entry at a time, with nothing to press, signed in or out, until it is shared', (tester) async {
      final device = await Device.make();
      await rows(tester, device, 'j', kind: ShareKind.journal);
      expect(find.text('A journal is shared an entry at a time. Open one to share it.'), findsOneWidget);
      expect(find.byType(GlacierPressable), findsNothing);
      await endSettings(tester);
      // A notebook shared before it was kept as a journal goes on as it was.
      await shared(device, 'k', '# Diary');
      await rows(tester, device, 'k', kind: ShareKind.journal);
      expect(row(tester, 'Copy the link'), isNotNull);
      expect(find.textContaining('an entry at a time'), findsNothing);
      await endSettings(tester);
      await device.services.signOut();
      await rows(tester, device, 'j', kind: ShareKind.journal);
      expect(find.textContaining('A journal is shared an entry at a time.'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('shows the link itself where the clipboard will not take it', (tester) async {
      final device = await Device.make();
      final link = await shared(device, 'a', '# Trip');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') throw PlatformException(code: 'no');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await rows(tester, device, 'a');
      await pressRow(tester, 'Copy the link');
      expect(said(tester), link);
      await endSettings(tester);
    });
  });

  group('where a shared note was written', () {
    testWidgets('offers to share it only where the note has a place, ticked once chosen, and says which way the link reads', (tester) async {
      final device = await Device.make();
      Clipped(tester);
      device.keep('a', '$tag# Trip');
      await rows(tester, device, 'a');
      await pressRow(tester, 'Share a read-only link');
      expect(hintOf(tester, 'Copy the link'), contains('Where it was written stays out of the link.'));
      expect(row(tester, 'Share where it was written')!.chosen, isFalse);
      // The share as sent leaves the place out.
      expect((await device.shares!.readShared(device.shares!.linkFor('a')!)).pages.single.body, isNot(contains('location:')));
      await pressRow(tester, 'Share where it was written');
      expect(device.shares!.sharingPlace('a'), isTrue);
      expect(row(tester, 'Share where it was written')!.chosen, isTrue);
      expect(hintOf(tester, 'Copy the link'), contains('The link carries where it was written.'));
      expect((await device.shares!.readShared(device.shares!.linkFor('a')!)).pages.single.body, contains('location: 51.5074,-0.1278'));
      await pressRow(tester, 'Share where it was written');
      expect(device.shares!.sharingPlace('a'), isFalse);
      await endSettings(tester);
    });

    testWidgets('has no such row for a note with nothing to carry', (tester) async {
      final device = await Device.make();
      Clipped(tester);
      device.keep('b', '# Plain');
      await rows(tester, device, 'b');
      await pressRow(tester, 'Share a read-only link');
      expect(row(tester, 'Share where it was written'), isNull);
      expect(row(tester, 'Share the places in it'), isNull);
      expect(hintOf(tester, 'Copy the link'), isNot(contains('stays out')));
      await endSettings(tester);
    });
  });

  group('the places written in a shared note', () {
    String carried(WidgetTester tester) => hintOf(tester, 'Copy the link').replaceFirst('Shared, read-only. Your edits reach readers a few seconds after you save.', '').trim();

    testWidgets('offers their own row only where the words hold one, and leaves the tag’s row word for word', (tester) async {
      final device = await Device.make();
      await shared(device, 'a', '$tag# Lisbon');
      await rows(tester, device, 'a');
      expect(hintOf(tester, 'Share where it was written'), 'The place and the map, on the shared page.');
      expect(row(tester, 'Share the places in it'), isNull);
      expect(carried(tester), 'Where it was written stays out of the link.');
      await endSettings(tester);
    });

    testWidgets('ticks the places apart from the tag', (tester) async {
      final device = await Device.make();
      await shared(device, 'b', '# Lisbon\n\n$cais');
      await rows(tester, device, 'b');
      expect(hintOf(tester, 'Share the places in it'), 'The places written in it, and their maps.');
      expect(row(tester, 'Share the places in it')!.chosen, isFalse);
      await pressRow(tester, 'Share the places in it');
      expect(device.shares!.sharingPlaces('b'), isTrue);
      expect(device.shares!.sharingPlace('b'), isFalse);
      expect(row(tester, 'Share the places in it')!.chosen, isTrue);
      await endSettings(tester);
    });

    test('says in the link’s hint exactly what the link carries, one sentence for what the pages hold', () {
      // tag held, places held, tag ticked, places ticked
      const cases = [
        (true, false, true, false, 'The link carries where it was written.'),
        (true, false, false, false, 'Where it was written stays out of the link.'),
        (false, true, false, true, 'The link carries the places in it.'),
        (false, true, false, false, 'The places in it stay out of the link.'),
        (true, true, true, true, 'The link carries where it was written and the places in it.'),
        (true, true, false, true, 'The link carries the places in it. Where it was written stays out.'),
        (true, true, true, false, 'The link carries where it was written. The places in it stay out.'),
        (true, true, false, false, 'Where it was written and the places in it stay out of the link.'),
        (false, false, true, true, ''),
      ];
      for (final (tag, places, withTag, withPlaces, words) in cases) {
        expect(linkCarries(tag: tag, places: places, withTag: withTag, withPlaces: withPlaces), words);
      }
    });

    testWidgets('and the row draws that sentence for a note that holds both, each tick moving it', (tester) async {
      final device = await Device.make();
      await shared(device, 'c', '$tag# Lisbon\n\n$cais');
      await rows(tester, device, 'c');
      expect(carried(tester), 'Where it was written and the places in it stay out of the link.');
      await pressRow(tester, 'Share the places in it');
      expect(carried(tester), 'The link carries the places in it. Where it was written stays out.');
      await pressRow(tester, 'Share where it was written');
      expect(carried(tester), 'The link carries where it was written and the places in it.');
      await endSettings(tester);
    });
  });

  group('the share sheet', () {
    testWidgets('is Share and the note’s title over its sharing rows', (tester) async {
      final device = await Device.make();
      device.keep('a', '# Trip');
      var closed = 0;
      await device.pump(tester, Stack(children: [ShareSheet(services: device.services, noteId: 'a', title: 'Trip', onClose: () => closed += 1)]), scroll: false);
      await settle(tester, 12);
      expect(find.byType(Sheet), findsOneWidget);
      // `<SheetTitle>Share {title || 'this note'}</SheetTitle>`
      expect(find.text('Share Trip'), findsOneWidget);
      expect(find.text('SHARING'), findsOneWidget);
      expect(row(tester, 'Share a read-only link'), isNotNull);
      await endSettings(tester);
    });
  });

  group('the list of shared links', () {
    testWidgets('lists each share by its note, and offers to take down only the ones no device lists that have settled', (tester) async {
      final device = await Device.make();
      final copied = Clipped(tester);
      final mine = await shared(device, 'mine', '# Cabin trip');
      // Shared from another device: in the synced settings, with no note here.
      preferences.update((now) => now.copyWith(shares: {...now.shares, 'elsewhere': const ShareEntry(id: 'EEEEEEEEEEEEEEEEEEEEEE', key: 'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK')}));
      // On the server and in no device's list: one long settled, one written a moment ago by another device.
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      device.service.shares['OOOOOOOOOOOOOOOOOOOOOO'] = (blob: 'x', updated: nowSeconds - 3600);
      device.service.shares['FFFFFFFFFFFFFFFFFFFFFF'] = (blob: 'x', updated: nowSeconds - 5);
      await device.pump(tester, SharedLinks(services: device.services));
      await settle(tester, 12);
      expect(find.text('Cabin trip'), findsOneWidget);
      expect(find.text('A note not on this device'), findsOneWidget);
      expect(find.text('A link no device lists'), findsOneWidget);
      expect(find.textContaining('Anyone with a link can read that note or notebook, and nobody else, the server included.'), findsOneWidget);
      await tester.tap(find.widgetWithText(RowAction, 'Copy').first);
      await settle(tester);
      expect(copied.text, mine);
      expect(find.text('The link is copied.'), findsOneWidget);
      await tester.tap(find.widgetWithText(RowAction, 'Take down'));
      await settle(tester, 12);
      expect(device.service.shares.containsKey('OOOOOOOOOOOOOOOOOOOOOO'), isFalse);
      expect(device.service.shares.containsKey('FFFFFFFFFFFFFFFFFFFFFF'), isTrue);
      expect(find.text('A link no device lists'), findsNothing);
      // Stop: the share comes down and leaves the list.
      await tester.tap(find.widgetWithText(RowAction, 'Stop').first);
      await settle(tester, 12);
      expect(device.shares!.linkFor('mine'), isNull);
      expect(find.text('Cabin trip'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('draws nothing while nothing is shared', (tester) async {
      final device = await Device.make();
      await device.pump(tester, SharedLinks(services: device.services));
      await settle(tester, 12);
      expect(find.byType(PaneSection), findsNothing);
      await endSettings(tester);
    });
  });
}
