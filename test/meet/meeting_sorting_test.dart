// One place for every meeting (Matt, 2026-10-26: "All meetings plugins should sort meetings to the same place on the
// recordings but have different settings"; lib/meet/ui/meeting_settings.dart). A Google Meet's take, a Zoom's and a
// Discord call's are filed by the one meeting step alike: a note in the Inbox, marked a meeting, written up, on the
// shelf, and sorted by the one switch into the same workspace's one Meetings folder. The switches every kind shares,
// Sync meeting recordings and Sort meetings into workspaces, are Settings › Recording's Meetings card, drawn once; a
// choice made on the old pages reads the same there, since each was always one synced preference and never one a
// kind, and an old link to them lands there. The Google Meet, Zoom and Discord pages draw neither, and each has Where
// meetings go, a row that opens the card, in Advanced and in Simple.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/enc_key.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/ai/meeting_sort.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/home/meeting_shelf.dart' show shelvedMeetings;
import 'package:ghost_md/meet/gmt.dart' show MeetService;
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/meet/meet_note.dart' show meetNoteId;
import 'package:ghost_md/meet/ui/meeting_settings.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart' show SettingsFindableMark;
import 'package:ghost_md/settings/panes/recording_pane.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:glacier/glacier.dart';

import '../account_ui/support.dart';
import 'support.dart';

/// What the device was asked: a tape kept, a write-up.
class _Phone implements MeetDevice {
  final List<String> writeUps = [];

  @override
  Future<int?> keepTape(String noteId, Uint8List audio, String mime) async => 90000;

  @override
  void writeUp(String noteId) => writeUps.add(noteId);
}

/// A signed-in device whose service has Ghost in meetings.
Future<({Device device, FakeMeet meet})> made() async {
  final meet = FakeMeet();
  final service = await FakeService.start(seed: seeded);
  final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher));
  await device.meetIn!.refresh();
  return (device: device, meet: meet);
}

/// A take of [kind] waiting on the service, sealed to the account.
Future<void> recorded(({Device device, FakeMeet meet}) d, String id, String kind) async {
  final kept = await ensureEncryptionKey(EncryptionKeyContext(token: d.device.account.session!.token, accountKey: (await d.device.account.accountKey())!, keys: d.device.keys, api: d.device.api, crypto: d.device.service.crypto));
  final sealed = await sealedTake(d.device.service.crypto, kept.pub, id, gmt1(title: 'Pricing review', meeting: 'm-$kind', kind: kind, captions: const [{'at': 1000, 'speaker': 'Sam Lee', 'text': 'Morning.'}]));
  d.meet.takes[id] = (meeting: 'm-$kind', at: 1792161900000, wrapped: sealed.wrapped, sealed: sealed.sealed);
}

/// The take ids, one a kind.
const Map<String, String> takes = {'meet': 'MeetTakeAAAAAAAAAAAAAA', 'zoom': 'ZoomTakeAAAAAAAAAAAAAA', 'discord': 'DiscordTakeAAAAAAAAAAA'};

/// The plugin pages, by their ids, and their kinds' names.
const List<(String, String)> pages = [('google-meet', 'Google Meet'), ('zoom', 'Zoom'), ('discord', 'Discord')];

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    // Each test from the defaults: the store is the app's own, and a test before may have turned a switch.
    preferences.startWithoutStorage();
    preferences.value = Preferences.defaults;
    final registry = createRegistry(builtIn, store: MemorySwitches());
    registry.setEnabled('discord', true);
    usePlugins(registry);
  });
  tearDown(() => usePlugins(createRegistry(const [])));

  group('one sorting for every kind', () {
    test('a Meet’s, a Zoom’s and a Discord call’s takes are filed, written up, shelved and sorted alike', () async {
      final d = await made();
      for (final MapEntry(:key, :value) in takes.entries) {
        await recorded(d, value, key);
      }
      final phone = _Phone();
      expect(
        await syncMeet(MeetPassContext(
          token: d.device.account.session!.token,
          api: d.device.api,
          crypto: d.device.service.crypto,
          pair: () async => (await d.device.keys.encryptionKey())!,
          notes: d.device.notes,
          prefs: preferences,
          kept: d.device.kept,
          now: () => 1792162000000,
          device: () => phone,
        )),
        3,
      );
      final ids = {for (final MapEntry(:key, :value) in takes.entries) key: meetNoteId(value)};
      // Each read as its own kind, and filed the same way: a note in the Inbox, marked a meeting, its write-up asked.
      for (final MapEntry(:key, :value) in ids.entries) {
        final note = d.device.notes.held[value]!;
        expect(note.body, contains('It is being written up on your device.'), reason: key);
        expect((note.recordingMs, note.source), (90000, NoteSource.capture), reason: key);
        expect(preferences.value.meetings, contains(value), reason: key);
        expect(d.device.workspaces.workspaceOf(value), isNull, reason: '$key: in the Inbox, as every kind is');
      }
      expect(phone.writeUps.toSet(), ids.values.toSet());
      expect(MeetService.of('discord'), MeetService.discord, reason: 'the kinds are told apart, and filed alike all the same');
      expect(MeetService.of('zoom'), MeetService.zoom);
      // On the home page's shelf, every kind.
      expect(shelvedMeetings(d.device.notes.held.values, preferences.value.meetings).map((n) => n.id).toSet(), ids.values.toSet());
      // The one switch: each is the sorting's while it is on, none once it is off.
      for (final id in ids.values) {
        expect(sortable(preferences.value, id, null), isTrue);
        expect(sortable(withSortMeetings(preferences.value, false), id, null), isFalse);
      }
      // And sorted into the same workspace's one Meetings folder, whichever plugin each came from.
      final ghost = d.device.workspaces.addWorkspace('Ghost.md')!;
      final sorter = MeetingSorter(
        workspaces: d.device.workspaces,
        preferences: () => preferences.value,
        setPreferences: preferences.update,
        getNote: (id) async => d.device.notes.held[id],
        ask: (_, _) async => jsonEncode({'workspace': ghost.id, 'confident': true}),
      );
      final folders = {for (final id in ids.values) (await sorter.meetingSummarized(id, d.device.notes.held[id]!.body))?.id};
      expect(folders, hasLength(1));
      final folder = d.device.workspaces.value.list.singleWhere((w) => w.id == folders.single);
      expect((folder.name, folder.parent), (meetingsFolderName, ghost.id));
      for (final id in ids.values) {
        expect(d.device.workspaces.workspaceOf(id)?.id, folder.id);
      }
    });
  });

  group('the preferences', () {
    test('a choice made on the old pages is the Meetings card’s: one key each, synced, never one a kind', () {
      final before = Preferences.defaults.copyWith(syncMeetingRecordings: false, syncMeetingRecordingsChosen: true, more: const {sortMeetingsKey: false});
      final read = Preferences.fromJson(jsonDecode(jsonEncode(before.toJson())) as Map<String, Object?>);
      expect((read.syncMeetingRecordings, sortsMeetings(read)), (false, false));
      expect(meetingsGoSaid(read), 'Inbox');
      expect(meetingsGoSaid(Preferences.defaults), 'Workspaces', reason: 'on unless turned off');
      // Nothing a kind's own to carry over.
      expect(read.more.keys.where((k) => RegExp('meet|zoom|discord', caseSensitive: false).hasMatch(k) && k != sortMeetingsKey && k != meetingSortsKey), isEmpty);
    });

    test('an old link to Recordings or Sorting, on a meeting plugin’s page or Meetings, lands on Recording’s row', () {
      (String, String?) land(String id, String setting) {
        final to = settingsLanding(SettingsTarget(id, setting: setting, nonce: 1));
        return (to.id, to.setting);
      }

      expect(land('plugin:google-meet', 'Sorting'), ('recording', 'Sort meetings into workspaces'));
      expect(land('plugin:zoom', 'Recordings'), ('recording', 'Sync meeting recordings'));
      expect(land('plugin:discord', 'Sort meetings into workspaces'), ('recording', 'Sort meetings into workspaces'));
      expect(land('meetings', 'Sync meeting recordings'), ('recording', 'Sync meeting recordings'));
      // What is a plugin's own stays on its page.
      expect(land('plugin:zoom', 'What the host must allow'), ('plugin:zoom', 'What the host must allow'));
      expect(land('account', 'Sorting'), ('account', 'Sorting'), reason: 'only from where the copies were');
    });
  });

  group('Settings › Recording’s Meetings card', () {
    testWidgets('has both switches once, each writing its one preference, with the sorting on by default', (tester) async {
      final d = await made();
      await d.device.pump(tester, RecordingPane(services: d.device.services));
      await settle(tester, 10);
      expect(find.text('MEETINGS'), findsOneWidget);
      Finder toggle(String name) => find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == name);
      expect(toggle('Sync meeting recordings'), findsOneWidget);
      expect(toggle('Sort meetings into workspaces'), findsOneWidget);
      expect(find.textContaining("A meeting is other people's voices: off, the words sync and the audio stays on the device it was made on."), findsOneWidget);
      expect((preferences.value.syncMeetingRecordings, preferences.value.syncMeetingRecordingsChosen), (true, false));
      expect(tester.widget<GlacierSwitch>(toggle('Sort meetings into workspaces')).checked, isTrue);
      await bringIntoView(tester, toggle('Sync meeting recordings'));
      await tester.tap(toggle('Sync meeting recordings'));
      await settle(tester);
      expect((preferences.value.syncMeetingRecordings, preferences.value.syncMeetingRecordingsChosen), (false, true));
      await bringIntoView(tester, toggle('Sort meetings into workspaces'));
      await tester.tap(toggle('Sort meetings into workspaces'));
      await settle(tester);
      expect(preferences.value.more[sortMeetingsKey], isFalse);
      expect(sortsMeetings(preferences.value), isFalse);
      await endSettings(tester);
    });

    testWidgets('reads a choice made before, off, as off', (tester) async {
      final d = await made();
      preferences.update((now) => withSortMeetings(now.copyWith(syncMeetingRecordings: false, syncMeetingRecordingsChosen: true), false));
      await d.device.pump(tester, RecordingPane(services: d.device.services));
      await settle(tester, 10);
      for (final name in ['Sync meeting recordings', 'Sort meetings into workspaces']) {
        expect(tester.widget<GlacierSwitch>(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == name)).checked, isFalse, reason: name);
      }
      await endSettings(tester);
    });

    testWidgets('counts the recordings that stayed on this phone: a meeting’s while those stay, and any over the service’s limit', (tester) async {
      final d = await made();
      Note taped(String id, String body, int ms) => d.device.notes.held[id] = Note(id: id, body: body, createdAt: 0, updatedAt: 0, source: NoteSource.capture, recordingMs: ms, segments: const []);
      taped('m', '# Meeting, 26 Sep 14:05', 60000);
      taped('big', '# Long', 150 * 60000);
      taped('ok', '# Short', 60000);
      preferences.update((now) => now.copyWith(meetings: const {'m': 1}, syncMeetingRecordings: false, syncMeetingRecordingsChosen: true));
      await d.device.pump(tester, RecordingPane(services: d.device.services));
      await settle(tester);
      expect(find.textContaining('2 recordings stayed on this phone: meetings, while their recordings stay'), findsOneWidget);
      preferences.update((now) => now.copyWith(syncMeetingRecordings: true));
      await settle(tester);
      expect(find.textContaining('1 recording stayed on this phone: longer than the account takes'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('in Simple is the page’s first card, the rest behind More, opened in place', (tester) async {
      final d = await made();
      preferences.update((now) => now.copyWith(experience: 'simple', experienceChosen: true));
      await d.device.pump(tester, RecordingPane(services: d.device.services));
      await settle(tester, 10);
      expect(titlesOf(tester), ['Meetings']);
      expect(find.text('WHILE RECORDING'), findsNothing);
      expect(find.byKey(const ValueKey('recording-more')), findsOneWidget);
      await press(tester, 'Show');
      expect(titlesOf(tester), containsAllInOrder(['Meetings', 'While recording', 'After recording', 'Summaries', 'Tapes', 'Voice log']));
      await endSettings(tester);
    });

    test('Recording is on Simple’s list wherever a meeting plugin’s page is, for the card', () async {
      final d = await made();
      SettingsFacts facts(AccountServices? services) => SettingsFacts(prefs: const Preferences(theme: 'light', experience: 'simple', experienceChosen: true), wide: false, haptics: true, android: true, ios: false, developer: false, services: services);
      bool listed(AccountServices? services) => settingsSections.singleWhere((s) => s.id == 'recording').where!(facts(services));
      expect(listed(d.device.services), isTrue);
      expect(listed(null), isFalse);
      expect(settingsSections.singleWhere((s) => s.id == 'recording').summary!(facts(d.device.services)), 'Meetings: Workspaces', reason: 'its row says where meetings go');
      plugins.setEnabled('google-meet', false);
      plugins.setEnabled('zoom', false);
      expect(listed(d.device.services), isFalse, reason: 'no meeting page in Simple, nothing to bring it');
      // Simple's search finds the card's rows there, and since the command search finds settings (f982a8dd, 2026-10-29)
      // the rest behind More too, each opening More in place (recordingBehindMore); until then it listed the card's alone.
      final names = settingsSections.singleWhere((s) => s.id == 'recording').settings!(facts(d.device.services)).map((f) => f.name);
      expect(names, containsAll(['Sync meeting recordings', 'Sort meetings into workspaces']));
      expect(names, contains('Stop when I go quiet'));
      expect(recordingBehindMore, contains('Stop when I go quiet'), reason: 'looked for in Simple, it opens More');
    });
  });

  group('the plugin pages', () {
    for (final (id, name) in pages) {
      for (final simple in [false, true]) {
        if (simple && id == 'discord') continue; // Discord's page waits behind Advanced.
        testWidgets('$name${simple ? ', in Simple,' : ''} draws no Sorting, and Where meetings go opens the Meetings card', (tester) async {
          final d = await made();
          await pumpApp(
            tester,
            size: const Size(390, 2400),
            prefs: Preferences(theme: 'light', experience: simple ? 'simple' : 'advanced', experienceChosen: true),
            home: BackScope(
              stack: BackStack(),
              child: AccountScope(services: d.device.services, child: SettingsSheet(open: true, onClose: () {}, onOpenNote: (_) {}, toPage: SettingsTarget('plugin:$id', nonce: 1))),
            ),
          );
          await settle(tester, 12);
          expect(find.byKey(const ValueKey('settings-display')).evaluate().map((e) => (e.widget as Text).data), [name]);
          for (final gone in ['Sync meeting recordings', 'Sort meetings into workspaces']) {
            expect(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == gone, skipOffstage: false), findsNothing, reason: '$name: $gone is Recording’s');
          }
          expect(titlesOf(tester), isNot(anyOf(contains('Recordings'), contains('Sorting'))));
          final row = find.byKey(const ValueKey('meetings-go'), skipOffstage: false);
          expect(row, findsOneWidget);
          expect(find.descendant(of: row, matching: find.text('Workspaces')), findsOneWidget);
          await bringIntoView(tester, row);
          await tester.tap(row);
          await settle(tester, 12);
          expect(find.byKey(const ValueKey('settings-display')).evaluate().map((e) => (e.widget as Text).data), ['Recording']);
          expect(find.text('MEETINGS'), findsOneWidget);
          final card = find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name == meetingsGoName);
          expect(card, findsOneWidget);
          await endSettings(tester);
        });
      }
    }
  });
}
