// A person's chip and card once Settings › Contacts matches them (lib/editor/items/field_chips.dart,
// lib/integrations/contacts/contact_card.dart): the chip wears the contact's picture or initials, and the card's
// Call, Text, Email and Open in Contacts hand the right address to the device, the chip's own actions after them.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/task_fields.dart';
import 'package:ghost_md/editor/items/field_chips.dart';
import 'package:ghost_md/integrations/contacts/contact_book.dart';
import 'package:ghost_md/integrations/contacts/contact_card.dart';
import 'package:ghost_md/integrations/contacts/contacts.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

ChipLook personLook(String written) => chipLook(fieldsIn(written).single, today: '2026-10-17', done: false)!;

/// The words drawn inside [finder].
List<String> textsIn(WidgetTester tester, Finder finder) => <String>[for (final text in tester.widgetList<Text>(find.descendant(of: finder, matching: find.byType(Text)))) text.data ?? ''];

void main() {
  setUpAll(loadAppFonts);

  late FakeContactBook book;
  late ContactsStore contacts;

  setUp(() {
    book = FakeContactBook();
    contacts = ContactsStore(book: book, kept: MemoryStored());
    useContacts(contacts);
  });

  tearDown(() => useContacts(null));

  Future<void> pumpChip(WidgetTester tester, String written) async {
    await pumpApp(tester, prefs: const AppPreferences(theme: 'light'), home: Center(child: FieldChip(personLook(written), onTap: (_) {})));
    await tester.pump();
  }

  Future<void> end(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  group('the chip', () {
    testWidgets('with Contacts off is the initial in its ring, as before', (tester) async {
      await pumpChip(tester, '@sam');
      expect(textsIn(tester, find.byType(FieldChip)), <String>['S', 'sam']);
      expect(find.descendant(of: find.byType(FieldChip), matching: find.byType(Image)), findsNothing);
      await end(tester);
    });

    testWidgets('with no contact by the name is the initial too', (tester) async {
      await contacts.turnOn();
      await pumpChip(tester, '@matt');
      expect(textsIn(tester, find.byType(FieldChip)), <String>['M', 'matt']);
      await end(tester);
    });

    testWidgets('matched, wears the contact’s initials, and takes the same room as an initial', (tester) async {
      await pumpChip(tester, '@sam');
      final before = tester.getSize(find.byType(FieldChip));
      await tester.runAsync(contacts.turnOn);
      await tester.pump();
      expect(textsIn(tester, find.byType(FieldChip)), <String>['SO', 'sam']);
      expect(tester.getSize(find.byType(FieldChip)), before);
      await end(tester);
    });

    testWidgets('matched to a contact with a picture, wears the picture', (tester) async {
      book.photos['c-sam'] = onePixel;
      await tester.runAsync(contacts.turnOn);
      await pumpChip(tester, '@sam-ortiz');
      await tester.runAsync(() async => pumpEventQueue());
      await tester.pump();
      expect(find.descendant(of: find.byType(FieldChip), matching: find.byType(Image)), findsOneWidget);
      expect(textsIn(tester, find.byType(FieldChip)), <String>['sam ortiz']);
      await end(tester);
    });
  });

  group('the card', () {
    late List<Uri> launched;
    late int removed;

    setUp(() {
      launched = <Uri>[];
      removed = 0;
    });

    Future<bool> launch(Uri uri) async {
      launched.add(uri);
      return true;
    }

    Future<void> pumpCard(WidgetTester tester, PhoneContact contact, {List<PersonCardAction>? actions}) async {
      await pumpApp(
        tester,
        prefs: const AppPreferences(theme: 'light'),
        home: Center(
          child: SizedBox(
            width: 360,
            child: PersonCard(
              contact: contact,
              name: 'sam',
              launch: launch,
              openInContacts: () => book.open(contact.id),
              actions: actions ?? <PersonCardAction>[PersonCardAction(icon: Lucide.userMinus, label: 'Remove', onPress: () => removed += 1)],
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('says who they are, and offers Call, Text, Email, Open in Contacts, then the chip’s Remove', (tester) async {
      await pumpCard(tester, sam);
      for (final words in <String>['Sam Ortiz', '@sam', 'Call', 'Text', 'Email', 'Open in Contacts', 'Remove', 'sam@example.com']) {
        expect(find.text(words), findsOneWidget, reason: words);
      }
      // The primary number, as the phone lists it first.
      expect(find.text('+1 (555) 010-0100'), findsNWidgets(2));
      await end(tester);
    });

    testWidgets('hands the number to the dialler and to messages, and the address to mail', (tester) async {
      await pumpCard(tester, sam);
      await tester.tap(find.text('Call'));
      await tester.tap(find.text('Text'));
      await tester.tap(find.text('Email'));
      await tester.pump();
      expect(<String>[for (final uri in launched) '$uri'], <String>['tel:+15550100100', 'sms:+15550100100', 'mailto:sam@example.com']);
      await end(tester);
    });

    testWidgets('opens the address book at them, and keeps the chip’s own action', (tester) async {
      await pumpCard(tester, sam);
      await tester.tap(find.text('Open in Contacts'));
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(book.opened, <String>['c-sam']);
      expect(removed, 1);
      expect(launched, isEmpty);
      await end(tester);
    });

    testWidgets('offers only the ways a contact can be reached', (tester) async {
      await pumpCard(tester, ana, actions: const <PersonCardAction>[]);
      expect(find.text('Call'), findsNothing);
      expect(find.text('Text'), findsNothing);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Open in Contacts'), findsOneWidget);
      await pumpCard(tester, robin, actions: const <PersonCardAction>[]);
      expect(find.text('Email'), findsNothing);
      expect(find.text('Open in Contacts'), findsOneWidget);
      await end(tester);
    });

    testWidgets('is a sheet on a phone and a popover on a desktop, and a press closes it first', (tester) async {
      await pumpApp(tester, prefs: const AppPreferences(theme: 'light'), home: const Center(child: Text('note', key: ValueKey<String>('note'))));
      final at = tester.getRect(find.byKey(const ValueKey<String>('note')));
      showPersonCard(tester.element(find.byKey(const ValueKey<String>('note'))), contact: sam, name: 'sam', at: at, store: contacts, launch: launch, coarse: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Sheet), findsOneWidget);
      await tester.tap(find.text('Call'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Sheet), findsNothing);
      expect(launched.single.toString(), 'tel:+15550100100');
      showPersonCard(tester.element(find.byKey(const ValueKey<String>('note'))), contact: sam, name: 'sam', at: at, store: contacts, launch: launch, coarse: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Sheet), findsNothing);
      expect(find.byType(GlacierPopover), findsOneWidget);
      expect(find.text('Open in Contacts'), findsOneWidget);
      await tester.tap(find.text('Email'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GlacierPopover), findsNothing);
      expect(launched.last.toString(), 'mailto:sam@example.com');
      await end(tester);
    });
  });

  test('the addresses are the device’s own forms', () {
    expect('${callUri('+44 (0)20 7946 0018')}', 'tel:+4402079460018');
    expect('${textUri('555-0100')}', 'sms:5550100');
    expect('${mailUri(' sam@example.com ')}', 'mailto:sam@example.com');
  });
}
