
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/account.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/keystore.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/mail/mail_in.dart';
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/orgs/org_keys.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/share/share.dart';
import 'package:ghost_md/share/sites.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/feed.dart';
import 'package:glacier/glacier.dart';

import '../settings/support.dart';
import '../support/fake_service.dart';
import '../support/sync_device.dart';

export 'package:ghost_md/account/api.dart' show ApiError, FetchRequest, FetchResponse, Fetcher;

export '../settings/support.dart';
export '../support/fake_service.dart';

/// The account the service is seeded with (`src/test/fakeService.ts`).
const ({String handle, String password}) seeded = (handle: 'matt', password: 'correct horse');

/// This device's pictures, for a share: none.
class NoPictures implements SharePictures {
  @override
  Future<Uint8List?> read(String name) async => null;
  @override
  Future<Uint8List> smaller(Uint8List bytes) async => bytes;
  @override
  Future<void> keep(String name, Uint8List bytes) async {}
}

/// A device with the real account objects over the service in memory (test/support/fake_service.dart) and the fake
/// crypto: [Account], [SyncEngine], [Orgs], [OrgKeys], [NotificationFeed] and [Shares], bundled as the screens take
/// them ([AccountServices]). Nothing here can reach a real service: the [Api]'s fetcher is the fake's own.
///
/// The preferences are the app's own store, which `pumpApp` resets: make the device first, and pump with [pump],
/// which hands the test's page the preferences as they stand.
class Device {
  Device._(this.service, {Fetcher? fetcher, bool engine = true, bool shares = true, bool publishing = false, bool meeting = false, int Function()? now}) {
    preferences.startWithoutStorage();
    preferences.value = const Preferences(theme: 'light');
    api = Api(base: 'http://service.test/api', fetcher: fetcher ?? service.fetcher);
    account = Account(keys: keys, api: api, crypto: service.crypto, iterations: fastRounds, label: 'Test phone');
    feed = NotificationFeed(account: account, crypto: service.crypto, kept: kept);
    workspaces = WorkspaceStore(storage: KeptWorkspaceStorage(prefs: preferences, stored: kept));
    orgs = Orgs(account: account, api: api, workspaces: workspaces, kept: kept);
    orgKeys = OrgKeys(crypto: service.crypto, api: api);
    this.engine = engine
        ? SyncEngine(account: AccountDoor(account), api: api, crypto: service.crypto, keys: keys, prefs: preferences, notes: notes, files: files, feed: feed, orgs: orgs, orgKeys: orgKeys, kept: kept, mailIn: publishing ? syncMail : null)
        : null;
    // A published site and email to a note (docs/SITES.md, docs/MAIL.md), for the tests of those.
    sites = publishing ? Sites(account: account, api: api, crypto: service.crypto, pictures: NoPictures(), listNotes: () async => notes.held.values.toList()) : null;
    mailIn = publishing ? MailIn(account: account, keys: keys, api: api, crypto: service.crypto) : null;
    // Ghost in meetings (docs/MEET.md), for its own tests: a fake service of its routes in front of this one.
    meetIn = meeting ? MeetIn(account: account, keys: keys, api: api, crypto: service.crypto) : null;
    this.shares = shares ? Shares(account: account, api: api, crypto: service.crypto, prefs: preferences, pictures: NoPictures(), listNotes: () async => notes.held.values.toList()) : null;
    services = AccountServices(
      account: account,
      engine: this.engine,
      orgs: orgs,
      orgKeys: orgKeys,
      feed: feed,
      shares: this.shares,
      sites: sites,
      mailIn: mailIn,
      meetIn: meetIn,
      listNotes: () async => notes.held.values.toList(),
      prefs: preferences,
      workspaces: workspaces,
      kept: kept,
      now: now,
    );
  }

  /// A device of [service], or of a new one seeded with [seeded]. [signedIn] signs it in with the password, as a
  /// person would. [fetcher] stands between the device and the service.
  static Future<Device> make({FakeService? service, bool signedIn = true, Fetcher? fetcher, bool engine = true, bool shares = true, bool publishing = false, bool meeting = false, List<String> peers = const ['sam'], int Function()? now}) async {
    final device = Device._(service ?? await FakeService.start(seed: seeded, peers: peers), fetcher: fetcher, engine: engine, shares: shares, publishing: publishing, meeting: meeting, now: now);
    if (signedIn) await device.account.signIn(seeded.handle, seeded.password);
    return device;
  }

  final FakeService service;
  final MemoryStored kept = MemoryStored();
  final MemoryKeyStore keys = MemoryKeyStore();
  final DeviceNotes notes = DeviceNotes();
  final DeviceFiles files = DeviceFiles();
  late final Api api;
  late final Account account;
  late final NotificationFeed feed;
  late final WorkspaceStore workspaces;
  late final Orgs orgs;
  late final OrgKeys orgKeys;
  late final SyncEngine? engine;
  late final Shares? shares;
  late final Sites? sites;
  late final MailIn? mailIn;
  late final MeetIn? meetIn;
  late final AccountServices services;

  /// A note on this device.
  Note keep(String id, String body, {int at = 0}) => notes.held[id] = Note(id: id, body: body, createdAt: at, updatedAt: at);

  /// Draws [child] under the app's theme with the [AccountScope] over it, the preferences as they stand.
  Future<void> pump(WidgetTester tester, Widget child, {Size size = phone, bool scroll = true, bool dark = false}) async {
    final page = AccountScope(services: services, child: scroll ? SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child)) : child);
    await pumpSettings(tester, page, size: size, prefs: preferences.value.copyWith(theme: dark ? 'dark' : 'light'));
  }
}

/// Lets what a press started finish: the service's answers are futures that settle between frames.
Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Types [text] into the field called [label] (its `aria-label`).
Future<void> typeInto(WidgetTester tester, String label, String text) async {
  final field = find.byWidgetPredicate((widget) => widget is GlacierInput && widget.ariaLabel == label);
  expect(field, findsOneWidget, reason: 'the field called $label');
  await tester.enterText(find.descendant(of: field, matching: find.byType(EditableText)), text);
  await tester.pump();
}

/// The cards' titles on the page, in its order (`.setk__title`).
List<String> titlesOf(WidgetTester tester) => [
      for (final section in tester.widgetList<PaneSection>(find.byType(PaneSection)))
        if (section.title != null) section.title!,
    ];

/// Presses the row, or the word, saying [words].
Future<void> press(WidgetTester tester, String words) async {
  final target = find.text(words);
  expect(target, findsWidgets, reason: 'something saying "$words"');
  await bringIntoView(tester, target.first);
  await tester.tap(target.first, warnIfMissed: false);
  await settle(tester);
}

/// The word saying [words], as the kit's pressable: for whether it can be pressed.
GlacierPressable pressableOf(WidgetTester tester, String words) => tester.widget<GlacierPressable>(find.ancestor(of: find.text(words), matching: find.byType(GlacierPressable)).first);

/// What the clipboard was last given, by a test that listens for it.
class Clipped {
  Clipped(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') text = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  }
  String? text;
}

/// Presses what is keyed [key], brought into view first.
Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  expect(target, findsOneWidget, reason: 'something keyed $key');
  await bringIntoView(tester, target);
  await tester.tap(target);
  await tester.pump();
}

/// Scrolls [target] to the middle of its page, clear of a bar over the page's top.
Future<void> bringIntoView(WidgetTester tester, Finder target) async {
  final element = tester.element(target);
  if (Scrollable.maybeOf(element) != null) await Scrollable.ensureVisible(element, alignment: 0.5);
  await tester.pump();
}
