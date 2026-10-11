// An organization's audit log. A port of `src/app/notes/OrganizationLog.test.tsx`, case for case: every version of
// every note filed in its workspace with the team's news between them, newest first under the day; the filter and
// the pills; a change opened to what it changed. The versions are the real record over this device's memory, and the
// feed and the organizations are the device's own.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/versions_record.dart';
import 'package:ghost_md/core/versions_store.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/orgs/ui/organization_log.dart';
import 'package:ghost_md/sync/feed.dart';

import 'support.dart';

const String org = 'org-1';
const int day = 86400000;

/// Noon, so "a minute ago" and "yesterday" are never a midnight apart from what they say.
final int noon = DateTime(2026, 10, 7, 12).millisecondsSinceEpoch;

Note made(String id, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: 0);
final List<Note> notes = [made('a', '# Roadmap\n- ship'), made('b', '# Standup'), made('c', '# Groceries')];

/// A device signed in as matt, a member of Ghost with its workspace here, and where its versions are kept.
class Logged {
  Logged(this.device) : record = VersionsRecord(store: VersionsStore(null, kept: device.kept), preferences: preferences, workspaces: device.workspaces, keeper: () => 'matt') {
    device.orgs.saveOrgs(device.account.session!.accountId, const OrgState(list: [OrgRow(id: org, name: 'Ghost', hue: 'sea', role: 'owner', state: 'member', members: 2, createdAt: 1)], at: 1));
    device.workspaces.ensureOrgWorkspace(const OrgRow(id: org, name: 'Ghost', hue: 'sea', role: 'owner', state: 'member', members: 2, createdAt: 1));
  }
  final Device device;
  final VersionsRecord record;
  int _at = 1000000;

  /// Roadmap kept twice (two days ago, a minute ago) and Standup once (yesterday), all filed in the organization;
  /// Groceries kept once, filed nowhere (`kept`).
  Future<void> kept() async {
    await record.keepVersion('a', '# Roadmap', now: noon - 2 * day);
    await record.keepVersion('b', '# Standup', now: noon - day);
    await record.keepVersion('a', '# Roadmap\n- ship', now: noon - 60000);
    await record.keepVersion('c', '# Groceries', now: noon - 30000);
    device.workspaces.fileNote('a', orgWorkspaceId(org));
    device.workspaces.fileNote('b', orgWorkspaceId(org));
  }

  /// A row of the feed, as a pass would have fed it (`fed`).
  void fed({required String kind, String? from, NotificationOrg? org, Map<String, Object?>? body, int? at}) {
    _at += 60000;
    final item = FeedNotification(id: 'n$_at', rev: _at, kind: kind, at: at ?? _at, from: from, org: org, body: body);
    device.feed.updateFeed(device.account.session!.accountId, (state) => withFed(state, item, _at).copyWith(cursor: _at));
  }
}

class Asked {
  int back = 0;
  final List<String> opened = [];
}

Future<Asked> page(WidgetTester tester, Logged logged, {List<Note>? of}) async {
  final asked = Asked();
  await logged.device.pump(
    tester,
    OrganizationLog(services: logged.device.services, orgId: org, notes: of ?? notes, record: logged.record, wisp: false, now: () => noon, onBack: () => asked.back += 1, onOpenNote: asked.opened.add),
    scroll: false,
  );
  await settle(tester, 12);
  return asked;
}

String _words(WidgetTester tester, Finder within) => find.descendant(of: within, matching: find.byType(RichText)).evaluate().map((e) => (e.widget as RichText).text.toPlainText().replaceAll('￼', '')).join(' ');

/// Each line of the log as its words, in order; of one day when [day] is given.
List<String> rows(WidgetTester tester, [String? day]) => [
      for (final section in tester.widgetList<LogDay>(find.byType(LogDay)))
        if (day == null || section.day == day)
          for (final child in section.children) _words(tester, find.byKey(child.key!)),
    ];

List<String> days(WidgetTester tester) => [for (final section in tester.widgetList<LogDay>(find.byType(LogDay))) section.day];

String? figures(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('log-figures'))).data;

Future<void> filter(WidgetTester tester, String words) async {
  await tester.enterText(find.descendant(of: find.byKey(const ValueKey('log-filter')), matching: find.byType(EditableText)), words);
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  group('an organization’s audit log', () {
    testWidgets('is every change to the notes filed in the workspace, newest first under the day, with who, which note, how much and the first line', (tester) async {
      final logged = Logged(await Device.make(engine: false));
      await logged.kept();
      await page(tester, logged);
      expect(find.text('Ghost'), findsOneWidget);
      expect(find.textContaining('Audit log', findRichText: true), findsOneWidget);
      expect(tokensAt(tester, find.text('Ghost')).attrs['hue'], 'sea');
      expect(figures(tester), '3 changes across 2 notes · 1 person');
      expect(days(tester).take(2), ['Today', 'Yesterday']);
      expect(days(tester), hasLength(3));
      expect(rows(tester, 'Today'), hasLength(1));
      final today = rows(tester, 'Today').single;
      for (final words in ['matt', 'edited', 'Roadmap', '+1 −0', '+ - ship', 'v2']) {
        expect(today, contains(words));
      }
      final yesterday = rows(tester, 'Yesterday').first;
      for (final words in ['matt', 'created', 'Standup', 'First version']) {
        expect(yesterday, contains(words));
      }
      // Groceries is not filed here: its versions are not the organization's.
      expect(find.textContaining('Groceries'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('puts the team’s news between the changes, and shows the notes or the team alone', (tester) async {
      final logged = Logged(await Device.make(engine: false));
      await logged.kept();
      logged.fed(kind: 'member-joined', from: 'sam', org: (id: org, name: 'Ghost'), body: {'name': 'Ghost'}, at: noon - 45000);
      logged.fed(kind: 'member-joined', from: 'lee', org: (id: 'elsewhere', name: 'Elsewhere'), body: {'name': 'Elsewhere'}, at: noon - 40000);
      await page(tester, logged);
      expect(rows(tester, 'Today'), hasLength(2));
      expect(rows(tester, 'Today')[0], contains('sam joined Ghost'));
      expect(rows(tester, 'Today')[1], contains('Roadmap'));
      expect(find.textContaining('Elsewhere'), findsNothing);
      await tapKey(tester, 'log-kind-team');
      expect(rows(tester), hasLength(1));
      expect(rows(tester).single, contains('sam joined Ghost'));
      expect(figures(tester), '3 changes across 2 notes · 1 person · 1 line shown');
      await tapKey(tester, 'log-kind-notes');
      expect(rows(tester), hasLength(3));
      expect(rows(tester).any((row) => row.contains('sam joined')), isFalse);
      await tapKey(tester, 'log-kind-all');
      expect(rows(tester), hasLength(4));
      await endSettings(tester);
    });

    testWidgets('narrows to a note, a person or a version’s name by the filter', (tester) async {
      final logged = Logged(await Device.make(engine: false));
      await logged.kept();
      await page(tester, logged);
      expect(rows(tester), hasLength(3));
      await filter(tester, 'stand');
      expect(rows(tester), hasLength(1));
      expect(rows(tester).single, contains('Standup'));
      await filter(tester, 'MATT');
      expect(rows(tester), hasLength(3));
      await filter(tester, 'nothing like it');
      expect(rows(tester), isEmpty);
      expect(find.text('Nothing matches.'), findsOneWidget);
      await tapKey(tester, 'log-filter-clear');
      expect(rows(tester), hasLength(3));
      await endSettings(tester);
    });

    // Differs 24 (docs/PARITY.md): the phone's Back from an opened change left the log altogether, where the page's
    // closes the change first (notes/OrganizationLog.tsx `useBack(true, () => (opened ? setOpened(null) : onBack()))`).
    testWidgets('closes an opened change on the phone\'s Back, and only then is the log left', (tester) async {
      final logged = Logged(await Device.make(engine: false));
      await logged.kept();
      final asked = await page(tester, logged);
      final stack = BackScope.of(tester.element(find.byType(OrganizationLog)));
      final before = stack.depth;
      await tester.tap(find.byKey(const ValueKey('log:a:2')));
      await settle(tester, 10);
      expect(find.byKey(const ValueKey('version-change')), findsOneWidget);
      expect(stack.depth, before + 1, reason: 'the opened change answers Back while it is up');
      expect(stack.goBack(), isTrue);
      await settle(tester);
      expect(find.byKey(const ValueKey('version-change')), findsNothing);
      expect(rows(tester), hasLength(3));
      expect((asked.back, stack.depth), (0, before));
      await endSettings(tester);
    });

    testWidgets('opens a change to what that version changed, with the way to the note and to only that note', (tester) async {
      final logged = Logged(await Device.make(engine: false));
      await logged.kept();
      final asked = await page(tester, logged);
      expect(rows(tester, 'Today'), hasLength(1));
      await tester.tap(find.byKey(const ValueKey('log:a:2')));
      await settle(tester, 10);
      expect(find.textContaining('Roadmap · Version 2', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('version-change')), findsOneWidget);
      expect(VersionChange.rowsOf('# Roadmap', '# Roadmap\n- ship'), [(kind: 'same', text: '# Roadmap'), (kind: 'add', text: '- ship')]);
      expect(find.descendant(of: find.byKey(const ValueKey('version-change')), matching: find.text('- ship')), findsOneWidget);
      await tapKey(tester, 'log-open-note');
      expect(asked.opened, ['a']);
      await tapKey(tester, 'log-to-log');
      await settle(tester);
      expect(rows(tester), hasLength(3));
      // Only this note: Roadmap's two changes, under a pill that takes the narrowing off again.
      await tester.tap(find.byKey(const ValueKey('log:a:2')));
      await settle(tester, 10);
      await tapKey(tester, 'log-only-this');
      await settle(tester);
      expect(rows(tester), hasLength(2));
      expect(rows(tester).every((row) => row.contains('Roadmap')), isTrue);
      await tester.tap(find.bySemanticsLabel('Only Roadmap; press for every note'));
      await tester.pump();
      expect(rows(tester), hasLength(3));
      await endSettings(tester);
    });

    testWidgets('hears a version kept while it is open', (tester) async {
      final logged = Logged(await Device.make(engine: false));
      await logged.kept();
      await page(tester, logged);
      expect(rows(tester), hasLength(3));
      await logged.record.keepVersion('b', '# Standup\n- yesterday: shipped', label: 'After standup', now: noon - 1000);
      await settle(tester, 10);
      expect(rows(tester), hasLength(4));
      for (final words in ['Standup', 'After standup', '+1 −0']) {
        expect(rows(tester, 'Today').first, contains(words));
      }
      await endSettings(tester);
    });

    testWidgets('says so when nothing has changed yet, which notes keep no history, and goes back by its arrow', (tester) async {
      final logged = Logged(await Device.make(engine: false));
      logged.device.workspaces.fileNote('b', orgWorkspaceId(org));
      preferences.update((now) => now.copyWith(versions: const {'b': false}));
      final asked = await page(tester, logged);
      expect(figures(tester), '0 changes across 1 note');
      expect(find.text('Nothing has changed here yet.'), findsOneWidget);
      expect(find.text('History is off for Standup.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back to Ghost'));
      expect(asked.back, 1);
      await endSettings(tester);
    });
  });

  // This port's own: the words the page asked the device's language for, written out.
  group('the log’s words', () {
    test('a day is Today, Yesterday, or its date, with the year when it is another', () {
      expect(logDayOf(noon, now: noon), 'Today');
      expect(logDayOf(noon - day, now: noon), 'Yesterday');
      expect(logDayOf(noon - 2 * day, now: noon), 'Mon, Oct 5');
      expect(logDayOf(DateTime(2025, 12, 31, 9).millisecondsSinceEpoch, now: noon), 'Wed, Dec 31, 2025');
    });

    test('a clock is the hour and the minute, and a name is You for one kept without an account', () {
      expect(logClock(DateTime(2026, 10, 7, 18, 5).millisecondsSinceEpoch), '6:05 PM');
      expect(logClock(DateTime(2026, 10, 7, 0, 30).millisecondsSinceEpoch), '12:30 AM');
      expect(authorName('me'), 'You');
      expect(authorName('sam'), 'sam');
      expect(listWords(['Roadmap', 'Standup', 'Groceries']), 'Roadmap, Standup and Groceries');
      expect(logDateTime(DateTime(2026, 9, 28, 9, 7).millisecondsSinceEpoch), 'Sep 28, 2026, 9:07 AM');
    });

    group('in the phone’s own words (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);
      final lastYear = DateTime(2025, 12, 31, 9).millisecondsSinceEpoch;
      final morning = DateTime(2026, 9, 28, 9, 7).millisecondsSinceEpoch;
      final afternoon = DateTime(2026, 10, 9, 16, 5).millisecondsSinceEpoch;

      test('an American phone has the month first and a 12-hour clock', () {
        toldLocale = DateLocale.enUS;
        expect(logDayOf(noon, now: noon), 'Today');
        expect(logDayOf(noon - 2 * day, now: noon), 'Mon, Oct 5');
        expect(logDayOf(morning, now: noon), 'Mon, Sep 28');
        expect(logDayOf(lastYear, now: noon), 'Wed, Dec 31, 2025');
        expect((logClock(morning), logClock(afternoon)), ('9:07 AM', '4:05 PM'));
        expect((logDateTime(morning), logDateTime(afternoon)), ('Sep 28, 2026, 9:07 AM', 'Oct 9, 2026, 4:05 PM'));
      });

      test('a British phone has the day first and a 24-hour clock', () {
        toldLocale = DateLocale.enGB;
        expect(logDayOf(noon, now: noon), 'Today');
        expect(logDayOf(noon - 2 * day, now: noon), 'Mon, 5 Oct');
        expect(logDayOf(morning, now: noon), 'Mon, 28 Sept');
        expect(logDayOf(lastYear, now: noon), 'Wed, 31 Dec 2025');
        expect((logClock(morning), logClock(afternoon)), ('9:07', '16:05'));
        expect((logDateTime(morning), logDateTime(afternoon)), ('28 Sept 2026, 09:07', '9 Oct 2026, 16:05'));
      });
    });
  });
}
