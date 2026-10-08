// How each field looks as a chip (lib/editor/items/field_chips.dart): `src/app/editor/fieldChips.test.ts`, case for
// case. Counted from Thursday 1 October 2026, in British.
//
// What is asked differently: a look's `menu` is the `FieldMenu` enum; and `chipElement` is the `FieldChip` widget,
// so the last case draws three chips and reads what a reader and a screen reader get of each - the initial and the
// words in order, a mark with an icon and no words, a named field's key before its value - where the page's read
// tag names, `data-` attributes and class names. A chip made a `button` on the page is one given a tap here.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/core/task_fields.dart';
import 'package:ghost_md/editor/items/field_chips.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

const String today = '2026-10-01';

ChipLook? look(String text, [bool done = false]) {
  final spans = fieldsIn(text);
  return spans.isEmpty ? null : chipLook(spans.first, today: today, done: done, locale: 'en-GB');
}

void main() {
  setUpAll(loadAppFonts);

  group('a day, named from today', () {
    test('says today, tomorrow and yesterday, and the weekday and date otherwise', () {
      expect(dayLabel('2026-10-01', today), 'Today');
      expect(dayLabel('2026-10-02', today), 'Tomorrow');
      expect(dayLabel('2026-09-30', today), 'Yesterday');
      expect(dayLabel('2026-10-03', today, 'en-GB'), 'Sat 3 Oct');
      expect(dayLabel('2026-09-29', today, 'en-GB'), 'Tue 29 Sept');
    });

    test('adds the year only when it is not this one', () {
      expect(dayLabel('2027-01-15', today, 'en-GB'), 'Fri, 15 Jan 2027');
      expect(daySaid('2026-10-03', today, 'en-GB'), 'Saturday 3 October');
      expect(daySaid('2025-12-24', today, 'en-GB'), 'Wednesday, 24 December 2025');
    });

    test('leaves words that are not a day as they are', () {
      expect(dayLabel('2026-02-30', today), '2026-02-30');
    });

    test('stands overdue once it has passed, today on the day, and done once the box is ticked', () {
      expect(dueTone('2026-09-29', today, false), 'overdue');
      expect(dueTone('2026-10-01', today, false), 'today');
      expect(dueTone('2026-10-02', today, false), 'plain');
      expect(dueTone('2026-09-29', today, true), 'done');
    });
  });

  group('each field’s chip', () {
    test('draws the due day with its calendar, and says when it is', () {
      var chip = look('📅 2026-09-29')!;
      expect((chip.text, chip.tone, chip.label, chip.menu, chip.key), ('Tue 29 Sept', 'overdue', 'Due Tuesday 29 September, overdue', FieldMenu.date, 'due'));
      chip = look('📅 2026-10-01')!;
      expect((chip.text, chip.tone, chip.label), ('Today', 'today', 'Due Thursday 1 October, today'));
      chip = look('📅 2026-10-03')!;
      expect((chip.text, chip.tone), ('Sat 3 Oct', 'plain'));
      chip = look('📅 2026-09-29', true)!;
      expect((chip.tone, chip.label), ('done', 'Due Tuesday 29 September'));
    });

    test('draws the other days quieter, each with its word', () {
      var chip = look('🛫 2026-10-02')!;
      expect((chip.text, chip.tone, chip.menu, chip.key), ('Starts tomorrow', 'quiet', FieldMenu.date, 'start'));
      chip = look('⏳ 2026-10-05')!;
      expect((chip.text, chip.menu, chip.key), ('Scheduled Mon 5 Oct', FieldMenu.date, 'scheduled'));
      chip = look('✅ 2026-09-30')!;
      expect((chip.text, chip.menu), ('Done yesterday', null));
      chip = look('➕ 2026-09-28')!;
      expect((chip.text, chip.menu), ('Added Mon 28 Sept', null));
      chip = look('❌ 2026-09-28')!;
      expect((chip.text, chip.menu), ('Cancelled Mon 28 Sept', null));
    });

    test('draws a priority as its mark, with its name for a screen reader', () {
      var chip = look('⏫')!;
      expect((chip.text, chip.tone, chip.label, chip.menu), ('', 'high', 'High priority', FieldMenu.priority));
      chip = look('🔺')!;
      expect((chip.tone, chip.label), ('highest', 'Highest priority'));
      chip = look('⏬', true)!;
      expect((chip.tone, chip.label), ('done', 'Lowest priority'));
    });

    test('draws a person with their initial, a recurrence with its words, and a named field with its key', () {
      var chip = look('@sam-ortiz')!;
      expect((chip.text, chip.initial, chip.label, chip.menu, chip.key), ('sam ortiz', 'S', 'Assigned to sam ortiz', FieldMenu.person, 'sam-ortiz'));
      chip = look('🔁 every week')!;
      expect((chip.text, chip.label, chip.menu), ('every week', 'Repeats every week', null));
      chip = look('[effort:: 3]')!;
      expect((chip.text, chip.name, chip.label, chip.menu), ('3', 'effort', 'effort: 3', null));
    });

    test('draws Dataview’s own days and priority as the emoji’s are', () {
      var chip = look('[due:: 2026-10-02]')!;
      expect((chip.text, chip.menu, chip.key), ('Tomorrow', FieldMenu.date, 'due'));
      chip = look('[completion:: 2026-09-30]')!;
      expect(chip.text, 'Done yesterday');
      chip = look('[priority:: high]')!;
      expect((chip.tone, chip.menu), ('high', FieldMenu.priority));
    });

    test('draws nothing it cannot read as what it says, and nothing for Tasks’ ids', () {
      expect(look('📅 2026-02-30'), isNull);
      expect(look('[priority:: soon]'), isNull);
      expect(look('🆔 abc123'), isNull);
      expect(look('⛔ abc123'), isNull);
    });

    test('names the day in the device’s language', () {
      final span = fieldsIn('📅 2026-10-03').first;
      expect(chipLook(span, today: today, done: false, locale: 'en-US')?.text, 'Sat, Oct 3');
    });

    test('knows one look from another', () {
      expect(sameLook(look('⏫')!, look('⏫')!), isTrue);
      expect(sameLook(look('⏫')!, look('🔺')!), isFalse);
      expect(personShown('Sam_Ortiz'), 'Sam Ortiz');
    });
  });

  group('a chip’s element', () {
    testWidgets('carries its tone and its label, and its words, initial and key in order', (tester) async {
      final semantics = tester.ensureSemantics();
      const person = Key('person'), priority = Key('priority'), named = Key('named');
      final taps = <Rect>[];
      await pumpApp(
        tester,
        prefs: const AppPreferences(theme: 'light'),
        home: Builder(
          builder: (context) => ColoredBox(
            color: context.tokens.color('glacier-bg'),
            child: Align(
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldChip(look('@sam')!, key: person),
                  FieldChip(look('⏫')!, key: priority, onTap: taps.add),
                  FieldChip(look('[effort:: 3]')!, key: named),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      Finder inside(Key chip, Finder what) => find.descendant(of: find.byKey(chip), matching: what);
      List<String> words(Key chip) {
        final texts = tester.widgetList<Text>(inside(chip, find.byType(Text))).toList();
        final found = <(double, String)>[for (final text in texts) (tester.getTopLeft(find.byWidget(text)).dx, text.data!)]..sort((a, b) => a.$1.compareTo(b.$1));
        return <String>[for (final one in found) one.$2];
      }

      expect(look('@sam')!.tone, 'plain');
      expect(find.bySemanticsLabel('Assigned to sam'), findsOneWidget);
      // The initial, then the words.
      expect(words(person), <String>['S', 'sam']);
      expect(tester.getSemantics(find.bySemanticsLabel('Assigned to sam')).flagsCollection.isButton, isFalse);

      // A priority is its mark alone, and a chip with a tap is a button.
      expect(words(priority), isEmpty);
      expect(inside(priority, find.byType(AppIcon)), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('High priority')).flagsCollection.isButton, isTrue);
      await tester.tap(find.byKey(priority));
      expect(taps, hasLength(1));
      expect(taps.single, tester.getRect(find.byKey(priority)));

      // A named field: its key, then its value.
      expect(words(named), <String>['effort', '3']);
      expect(inside(named, find.byType(AppIcon)), findsNothing);
      semantics.dispose();
      debugDisableShadows = true;
    });
  });
}
