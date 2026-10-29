// Every plugin's setup (lib/plugins/onboarding/; Matt, 2026-10-29: "add the voiceover onboarding for the rest of the
// plugins"): which built-in plugins have one and which have nothing to set up; every step's words said by a clip of
// its own and no clip left over; the step done by a button (a sign-in started, a permission asked) in the sheet, its
// problem under it, on by itself where it is a permission, and the check's way back to it. Then the setups this file
// holds by themselves: Google Calendar's sign-in, the Contacts and Place reminders permissions, and those with nothing
// to keep, seen once (Google Meet, Zoom, Todoist). Google, the address book and the phone's location are the test's
// own (test/calendar/fake_google.dart, test/integrations/contacts/support.dart, test/support/fake_places.dart): nothing
// is asked of a network or a device. Notion's, GitHub's, Slack's, Discord's and ElevenLabs' are each in their plugin's
// folder (setup_test.dart).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/calendar/calendar.dart';
import 'package:ghost_md/calendar/setup.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/integrations/contacts/contact_book.dart';
import 'package:ghost_md/integrations/contacts/contacts.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/calendar/calendar.dart';
import 'package:ghost_md/plugins/contacts/contacts.dart';
import 'package:ghost_md/plugins/meetings/meetings.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:ghost_md/plugins/onboarding/setup_voice.dart';
import 'package:ghost_md/plugins/places/places.dart';
import 'package:ghost_md/plugins/todoist/todoist.dart';
import 'package:ghost_md/reminders/place_host.dart';

import '../../calendar/fake_google.dart';
import '../../integrations/contacts/support.dart';
import '../../settings/support.dart';
import '../../support/fake_places.dart';

List<String> ids(PluginSetup setup) => [for (final step in setup.steps) step.id];

/// A setup of the test's own with a sign-in: [answer] is what its button says went wrong, [signedIn] whether it is
/// ready, and [passes] what its check finds (as [signedIn] where null).
class FakeSignIn {
  String? answer;
  bool signedIn = false;
  bool? passes;
  int started = 0;
  bool onward = false;

  PluginSetup get setup => PluginSetup(
        id: 'fake',
        name: 'Fake',
        hues: const ['indigo'],
        ready: () => signedIn,
        watch: setupWatchesNothing,
        steps: [
          const SetupIntro(id: 'intro', title: 'What it is', icon: Lucide.sparkles),
          SetupAct(
            id: 'signin',
            title: 'Sign in',
            icon: Lucide.link,
            label: 'Sign in with Fake',
            again: 'Sign in again',
            onward: onward,
            run: () async {
              started += 1;
              return answer;
            },
          ),
          SetupCheck(id: 'check', title: 'Check it', icon: Lucide.shieldCheck, run: () async => (passes ?? signedIn) ? const SetupResult.ok('Signed in.') : const SetupResult.failed('Not signed in yet.', pasteAgain: true)),
          const SetupDone(id: 'done', title: 'Done', icon: Lucide.wandSparkles),
        ],
      );
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));

  group('which plugins', () {
    test('every built-in plugin a person sets up has a setup, by its own id; Marks, Rich embeds, Things, Webhooks and Keyboard modes have nothing to set up', () {
      final withOne = {for (final plugin in builtIn) if (plugin.setup != null) plugin.manifest.id};
      expect(withOne, {'notion', 'github', 'claude', 'slack', 'place-reminders', 'calendar', 'contacts', 'todoist', 'lovart', 'discord', 'google-meet', 'zoom', 'elevenlabs', 'openai', 'gemini', 'custom-ai', 'aster'});
      expect({for (final plugin in builtIn) if (plugin.setup == null) plugin.manifest.id}, {'marks', 'rich-embeds', 'things', 'webhooks', 'keyboard-modes'});
      for (final plugin in builtIn) {
        if (plugin.setup case final make?) expect(make().id, plugin.manifest.id, reason: 'its words and its memory are by the plugin’s id');
      }
    });

    test('every step of every setup is said: its words, Simple’s too, each a clip of the voice, and no clip left over', () {
      final said = <String>{};
      for (final plugin in builtIn) {
        final setup = plugin.setup?.call();
        if (setup == null) continue;
        expect({for (final step in setup.steps) step.id}, hasLength(setup.steps.length), reason: '${setup.id}: each step’s id once');
        for (final step in setup.steps) {
          final name = '${setup.id}-${step.id}';
          for (final simple in [false, true]) {
            expect(setup.wordsOf(step, simple: simple), isNotEmpty, reason: name);
          }
          expect(setupVoice.containsKey(name), isTrue, reason: '$name has no words to say');
          said
            ..add(name)
            ..add('$name-simple');
        }
      }
      expect([for (final name in setupVoice.keys) if (!said.contains(name)) name], isEmpty, reason: 'words for no step');
      // One line each, in single quotes, with no straight apostrophe: what tool/plugin_setup_voice.py reads.
      expect(setupVoice.values.where((words) => words.contains('\n') || words.contains("'")), isEmpty);
    });

    test('the addresses no one opened are said to be unverified', () {
      final links = {
        for (final plugin in builtIn)
          if (plugin.setup?.call() case final setup?)
            for (final step in setup.steps.whereType<SetupOpen>())
              for (final link in step.links) link.url: link.verified,
      };
      expect([for (final MapEntry(:key, :value) in links.entries) if (value) key], ['https://console.anthropic.com/', 'https://console.anthropic.com/settings/billing', 'https://console.anthropic.com/settings/keys', 'https://www.lovart.ai/', 'https://www.lovart.ai/home']);
    });
  });

  group('a step done by a button', () {
    late FakeSignIn fake;
    late SetupMemory memory;

    setUp(() {
      fake = FakeSignIn();
      memory = SetupMemory(MemoryStored());
    });

    Future<void> pumpSheet(WidgetTester tester) => pumpSettings(tester, PluginSetupSheet(key: UniqueKey(), setup: fake.setup, memory: memory, onClose: () {}));
    String title(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('setup-title'))).data!;

    testWidgets('runs the plugin’s own sign-in, says under it what went wrong, and waits for Next', (tester) async {
      memory.at('fake', 'signin');
      fake.answer = 'Notion needs the newest Ghost.md.';
      await pumpSheet(tester);
      expect(title(tester), 'Sign in');
      expect(find.text('Sign in with Fake'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setup-act')));
      await settleSettings(tester);
      expect(fake.started, 1);
      expect(find.text('Notion needs the newest Ghost.md.'), findsOneWidget);
      expect(title(tester), 'Sign in');
      fake.answer = null;
      await tester.tap(find.byKey(const ValueKey('setup-act')));
      await settleSettings(tester);
      expect(find.byKey(const ValueKey('setup-act-problem')), findsNothing);
      // A sign-in is finished in the browser: the step stays until Next.
      expect(title(tester), 'Sign in');
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      expect(title(tester), 'Check it');
      await endSettings(tester);
    });

    testWidgets('a permission answered goes on to the check by itself', (tester) async {
      fake.onward = true;
      memory.at('fake', 'signin');
      await pumpSheet(tester);
      fake.signedIn = true;
      await tester.tap(find.byKey(const ValueKey('setup-act')));
      await settleSettings(tester);
      expect(title(tester), 'Check it');
      expect(find.text('Signed in.'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('a check that fails offers Sign in again, which goes back to the button', (tester) async {
      memory.at('fake', 'check');
      await pumpSheet(tester);
      // Left at its check with nothing signed in: the sign-in again, as a paste would be.
      expect(title(tester), 'Sign in');
      fake
        ..signedIn = true
        ..passes = false;
      memory.at('fake', 'check');
      await pumpSheet(tester);
      expect(title(tester), 'Check it');
      expect(find.text('Not signed in yet.'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setup-paste-again')));
      await settleSettings(tester);
      expect(title(tester), 'Sign in');
      await endSettings(tester);
    });
  });

  group('Google Calendar', () {
    late FakeGoogle google;
    late PreferencesStore prefs;
    late List<String> opened;

    setUp(() {
      google = FakeGoogle();
      prefs = PreferencesStore()..startWithoutStorage();
      opened = [];
    });

    CalendarService service({String? base = fakeBase}) {
      final kept = MemoryStored();
      return CalendarService(fetch: google.fetch, prefs: prefs, kept: () => kept, googleBase: () => base, open: (url) async => opened.add(url));
    }

    test('an intro, the sign-in, the check and a first thing to try; the plugin’s own', () {
      final setup = calendarSetup(service: service());
      expect(ids(setup), ['intro', 'signin', 'check', 'done']);
      expect([for (final step in setup.steps) step.runtimeType.toString()], ['SetupIntro', 'SetupAct', 'SetupCheck', 'SetupDone']);
      expect(setup.name, 'Google Calendar');
      expect(calendarPlugin.setup, isNotNull);
    });

    test('connects through the service’s own sign-in, says Google is still waiting, then connected with its calendars', () async {
      final calendar = service();
      final setup = calendarSetup(service: calendar);
      expect(setup.ready(), isFalse);
      final signIn = setup.steps.whereType<SetupAct>().single;
      expect(await signIn.run(), isNull);
      expect(opened.single, startsWith('$fakeBase/start?state='));
      final check = setup.steps.whereType<SetupCheck>().single;
      // The fake answers its first claim 202, as Google's page still open.
      final waiting = await check.run();
      expect((waiting.kind, waiting.words, waiting.pasteAgain), (SetupCheckKind.failed, 'Google hasn’t said yet. Allow Ghost.md on Google’s page, then check again.', true));
      final done = await check.run();
      expect((done.kind, done.words), (SetupCheckKind.ok, 'Google Calendar is connected, with 2 calendars. Your own is shown.'));
      expect(setup.ready(), isTrue);
      await calendar.syncGoogle();
      calendar.dispose();
    });

    test('says why it can’t start: Local only on, or no Google sign-in in this build; nothing opened', () async {
      prefs.update((p) => p.copyWith(localOnly: true));
      expect(await calendarConnect(service()), 'Local only is on, so no calendar is read. Turn it off in Settings › Account first.');
      prefs.update((p) => p.copyWith(localOnly: false));
      expect(await calendarConnect(service(base: null)), 'Google Calendar can’t be connected from here. Paste a calendar’s iCal address on Calendar’s page instead.');
      google.configured = false;
      expect(await calendarConnect(service()), startsWith('Google Calendar can’t be connected'));
      expect(opened, isEmpty);
    });

    test('a sign-in refused is said in the service’s words, with the way back to it', () async {
      // A claim for a sign-in the service no longer has.
      final kept = MemoryStored();
      final refused = CalendarService(
        fetch: (request) async => request.url.path.endsWith('/claim') ? FetchResponse.json(404, {'error': 'no sign-in with that state, or it expired'}) : google.fetch(request),
        prefs: prefs,
        kept: () => kept,
        googleBase: () => fakeBase,
        open: (url) async => opened.add(url),
      );
      await refused.connectGoogle();
      final result = await calendarSetupResult(refused);
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
      expect(result.words, refused.problem);
      expect(result.words, isNotEmpty);
      refused.dispose();
    });

    test('an iCal address is as good as Google: nothing more is needed', () {
      final calendar = service();
      prefs.update((p) => withCalendarSetup(p, calendarSetupOf(p).copyWith(addresses: [const CalendarAddress(id: 'w', url: 'https://cal.test/work.ics')])));
      expect(calendarSetup(service: calendar).ready(), isTrue);
      calendar.dispose();
    });
  });

  group('Contacts', () {
    test('an intro, the permission, the check and a first thing to try', () {
      expect(ids(contactsSetup(store: ContactsStore(book: FakeContactBook(), kept: MemoryStored()))), ['intro', 'allow', 'check', 'done']);
      expect(contactsPlugin.setup, isNotNull);
    });

    test('allowed: the phone asked once, the setup goes on by itself, and the check counts the contacts', () async {
      final book = FakeContactBook();
      final store = ContactsStore(book: book, kept: MemoryStored());
      final setup = contactsSetup(store: store);
      expect(setup.ready(), isFalse);
      final allow = setup.steps.whereType<SetupAct>().single;
      expect(allow.onward, isTrue);
      expect(await allow.run(), isNull);
      expect(book.asked, 1);
      expect(setup.ready(), isTrue);
      final result = await setup.steps.whereType<SetupCheck>().single.run();
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Allowed: 5 contacts, read on this device only.'));
    });

    test('refused, says so and asks again; refused for good, opens the phone’s settings; the check sends it back', () async {
      final book = FakeContactBook(answer: ContactsAccess.denied);
      final store = ContactsStore(book: book, kept: MemoryStored());
      final setup = contactsSetup(store: store);
      expect(await contactsAllow(store), 'Ghost.md was not allowed to read your contacts. Press again to be asked again.');
      final check = await contactsSetupResult(store);
      expect((check.kind, check.pasteAgain), (SetupCheckKind.failed, true));
      book.answer = ContactsAccess.blocked;
      expect(await contactsAllow(store), startsWith('Ghost.md is not allowed to read your contacts.'));
      expect(await contactsAllow(store), 'Allow contacts for Ghost.md in your device’s settings, then come back here and check.');
      expect(book.settingsOpened, 1);
      expect(setup.ready(), isFalse);
    });

    test('a device with no address book has nothing to set up', () async {
      final store = ContactsStore(book: FakeContactBook(answer: ContactsAccess.unavailable), kept: MemoryStored());
      expect(await contactsAllow(store), 'This device has no contacts Ghost.md can read.');
      expect(contactsSetup(store: store).ready(), isTrue);
    });
  });

  group('Place reminders', () {
    late FakePlaces phone;

    setUp(() {
      phone = FakePlaces()..now = PlaceAccess.ask;
      placesSetupAccess.value = null;
    });

    test('an intro, the location, the check and a first thing to try', () {
      expect(ids(placesSetup(places: () => phone)), ['intro', 'allow', 'check', 'done']);
      expect(placesPlugin.setup, isNotNull);
    });

    test('asks Android’s prompts in their order, then the check says it is allowed all the time', () async {
      final setup = placesSetup(places: () => phone);
      await setup.prepare!();
      expect(setup.ready(), isFalse);
      final allow = setup.steps.whereType<SetupAct>().single;
      expect(allow.onward, isTrue);
      expect(await allow.run(), isNull);
      expect(phone.asked, ['foreground', 'background']);
      final result = await setup.steps.whereType<SetupCheck>().single.run();
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Allowed all the time. Your phone tells Ghost.md when it arrives at a place on one of your to-dos.'));
      expect(setup.ready(), isTrue);
    });

    test('only while in use: the check says so in the page’s words, and sends it back', () async {
      phone.afterBackground = PlaceAccess.whileUsing;
      final setup = placesSetup(places: () => phone);
      await setup.steps.whereType<SetupAct>().single.run();
      final result = await setup.steps.whereType<SetupCheck>().single.run();
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
      expect(result.words, startsWith('Android only lets Ghost.md know where you are while it is open'));
    });

    test('refused for good: the phone’s settings, and what to choose there', () async {
      phone.now = PlaceAccess.blocked;
      expect(await placesAllow(phone), 'In the phone’s settings, open Permissions › Location and choose Allow all the time, then come back and check.');
      expect(phone.asked, ['settings']);
    });

    test('a device with no geofences has nothing to set up', () async {
      final setup = placesSetup(places: () => null);
      expect(setup.ready(), isTrue);
      expect((await setup.steps.whereType<SetupCheck>().single.run()).kind, SetupCheckKind.ok);
    });
  });

  group('seen once: Google Meet, Zoom and Todoist', () {
    test('Google Meet: what Ghost does, then how to invite it; Zoom: what the host must allow between', () {
      expect(ids(googleMeetSetup()), ['intro', 'done']);
      expect(ids(zoomSetup()), ['intro', 'host', 'done']);
      final host = zoomSetup().steps[1] as SetupIntro;
      expect(host.points.map((p) => p.$2), [for (final (label, hint) in zoomHostRules) '$label: $hint']);
      expect(googleMeetPlugin.setup, isNotNull);
      expect(zoomPlugin.setup, isNotNull);
    });

    test('Todoist: where the token is and where it goes, with no paste and no check, since the plugin keeps no token', () {
      final setup = todoistSetup();
      expect(ids(setup), ['intro', 'key', 'done']);
      expect(setup.steps.whereType<SetupPaste>(), isEmpty);
      final link = setup.steps.whereType<SetupOpen>().single.links.single;
      expect((link.url, link.verified), (todoistTokenUrl, false));
      expect(todoistPlugin.setup, isNotNull);
    });

    test('each is needed until it has been done or skipped on this device, and then not', () {
      final memory = SetupMemory(MemoryStored());
      for (final setup in [googleMeetSetup(memory: memory), zoomSetup(memory: memory), todoistSetup(memory: memory)]) {
        expect(setup.ready(), isFalse, reason: setup.id);
        memory.at(setup.id, setup.steps.first.id);
        expect(setup.ready(), isFalse, reason: '${setup.id}: put away half way');
      }
      memory.end('google-meet', 'done', SetupEnd.done);
      memory.end('zoom', 'intro', SetupEnd.skipped);
      expect([googleMeetSetup(memory: memory).ready(), zoomSetup(memory: memory).ready(), todoistSetup(memory: memory).ready()], [true, true, false]);
    });
  });
}
