// The proof that settings survive this app unharmed (lib/sync/prefs.dart, `PrefsBridge`).
//
// The page's preferences are a plain object, so whatever a newer build put in the account's settings rides through a
// pass on an older one. The Dart preferences are TYPED: reading the account's blob into them drops every field the
// type does not model, reads a value it cannot draw as its default, and the next push would then erase all of that
// from every device the person owns. So the pass works on JSON and the bridge puts back what the type left out. Here
// "another device" is a newer Ghost.md that writes the blob by hand, and the device under test is the typed
// `PreferencesStore` behind its bridge, on the fake service.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/sync/prefs.dart';

import 'support.dart';

/// What a newer build keeps in the account's settings: every synced key, with fields this build's types do not
/// model (marked `new…`), values it cannot draw, and a setting it does not sync at all.
Map<String, Object?> newerBlob() => {
      ...pickSynced(Preferences.defaults.toJson()),
      // A theme from a later build: this one reads it as its default.
      'theme': 'aurora',
      'density': 'cosy',
      'homeLayout': 'mosaic',
      'homeLayoutChosen': true,
      'codeLight': 'paper',
      'codeChosen': true,
      'motionSpeed': 'glacial',
      'openNotes': ['n1', 'n2'],
      'tabGroups': {
        'list': [
          {'id': 'g1', 'name': 'Work', 'hue': 'sea', 'newPinned': true},
        ],
        'of': {'n1': 'g1'},
        'newOrder': ['g1'],
      },
      'workspaces': {
        'list': [
          {'id': 'w1', 'name': 'Home', 'hue': 'sea', 'newIcon': 'house'},
          {'id': 'org-o1', 'name': 'Ghost', 'org': 'o1'},
          {'id': 'w2', 'name': 'Odd', 'hue': 'ultraviolet'},
        ],
        'notes': {'n1': 'w1', 'n9': 'org-o1'},
        'newSort': 'manual',
      },
      'trash': {'t1': 7, 't2': 'not a time'},
      'meetings': {'m1': 40},
      'shares': {
        'n1': {'id': 'i' * 22, 'key': 'k' * 43, 'sent': 'p2:1', 'lacked': ['a.jpg'], 'place': true, 'newExpires': 99},
      },
      'notifications': {
        'team': true,
        'claude': false,
        'summaries': true,
        'conflicts': true,
        'mutedOrgs': ['o1'],
        'newDigest': 'weekly',
      },
      // A setting a newer build syncs and this one has never heard of.
      'newFromTheFuture': {'a': 1},
    };

/// A device of this app: the typed store behind its bridge.
class TypedDevice {
  TypedDevice(this.service) {
    store.startWithoutStorage();
    bridge = PrefsBridge(store: store, kept: kept, key: 'glyph-sync-7-prefs-held');
  }
  final FakeService service;
  final PreferencesStore store = PreferencesStore();
  final MemoryStored kept = MemoryStored();
  late PrefsBridge bridge;
  PrefsState state = const PrefsState();

  /// The app closed and opened again: the store as it was, and the bridge read back from this device's memory.
  void relaunch() {
    bridge.dispose();
    bridge = PrefsBridge(store: store, kept: kept, key: 'glyph-sync-7-prefs-held');
  }

  Future<bool> sync() async {
    bridge.applying = true;
    try {
      return await syncPrefs(PrefsContext(
        token: service.signedIn(),
        key: service.accountKey,
        read: bridge.read,
        write: bridge.write,
        state: state,
        save: (next) {
          state = next;
          bridge.saved(next);
        },
        api: apiOf(service),
        crypto: service.crypto,
        carried: bridge.carried,
        carry: bridge.carry,
      ));
    } finally {
      bridge.applying = false;
    }
  }
}

Future<void> writeAs(FakeService service, Map<String, Object?> blob) async {
  final sealed = await service.crypto.seal(service.accountKey, blob, 'prefs');
  await apiOf(service).call('PUT', 'prefs', token: service.signedIn(), body: {'base': service.prefs?.rev ?? 0, 'blob': sealed});
}

Future<Map<String, Object?>> held(FakeService service) async => (await service.crypto.open(service.accountKey, service.prefs!.blob, 'prefs') as Map).cast<String, Object?>();

void main() {
  test('the typed preferences alone would lose it: this is what the bridge is for', () {
    final blob = newerBlob();
    final through = Preferences.fromJson(blob).toJson();
    expect(through['theme'], 'dark');
    expect(((through['workspaces'] as Map)['list'] as List).first, isNot(containsPair('newIcon', 'house')));
    expect(through['notifications'], isNot(containsPair('newDigest', 'weekly')));
  });

  test('settings taken from the account and sent back are the account’s, to the letter, with nothing this build does not model dropped', () async {
    final service = await FakeService.start(seed: testAccount);
    final blob = newerBlob();
    await writeAs(service, blob);
    final device = TypedDevice(service);
    // A setting that stays on the device, and one this build's store kept without knowing it.
    device.store.value = Preferences.fromJson({...Preferences.defaults.toJson(), 'formatModel': 'qwen3.5-2b', 'uiScale': 1.1, 'newDeviceOnly': 'kept'});

    expect(await device.sync(), isTrue);
    // What this build can draw, it draws; what it cannot, it reads as its own default, on this device only.
    expect(device.store.value.theme, 'dark');
    expect(device.store.value.openNotes, ['n1', 'n2']);
    expect(device.store.value.workspaces.list.map((w) => w.id), ['w1', 'org-o1', 'w2']);
    expect(device.store.value.notifications.claude, isFalse);
    // What stays with the device stayed, and so did the store's own unknown key.
    expect((device.store.value.formatModel, device.store.value.uiScale), ('qwen3.5-2b', 1.1));
    expect(device.store.value.more, {'newDeviceOnly': 'kept'});

    // Nothing changed here: nothing is sent, on this run or after the app is opened again.
    service.calls.clear();
    expect(await device.sync(), isFalse);
    device.relaunch();
    expect(await device.sync(), isFalse);
    expect(service.calls, ['GET prefs', 'GET prefs']);

    // One setting changed here, of a kind that has nothing to do with the rest: the whole blob goes again.
    device.store.update((now) => now.copyWith(assist: false));
    expect(await device.sync(), isFalse);
    expect(service.calls.last, 'PUT prefs');
    final sent = await held(service);
    // Every key the account held is there, in the account's own words, but for the one this device changed.
    expect(jsonEncode(sent), jsonEncode({...blob, 'assist': false}));
  });

  test('a setting changed here keeps the fields beside it that this build does not model', () async {
    final service = await FakeService.start(seed: testAccount);
    final blob = newerBlob();
    await writeAs(service, blob);
    final device = TypedDevice(service);
    await device.sync();

    // The person renames a workspace, files a note, takes one out of the trash, mutes an organization, folds a tab
    // group and stops carrying a share's place: each inside a structure a newer build has added to.
    device.store.update((now) => now.copyWith(
          workspaces: KeptWorkspaces(
            list: [
              const KeptWorkspace(id: 'w1', name: 'House', hue: 'sea'),
              ...now.workspaces.list.skip(1),
              const KeptWorkspace(id: 'w3', name: 'New'),
            ],
            notes: {...now.workspaces.notes, 'n2': 'w3'},
          ),
          trash: const {},
          notifications: now.notifications.copyWith(mutedOrgs: ['o1', 'o2']),
          tabGroups: TabGroups(list: [now.tabGroups.list.first.copyWith(collapsed: true)], of: now.tabGroups.of),
          shares: {'n1': ShareEntry(id: 'i' * 22, key: 'k' * 43, sent: 'p2:2', lacked: const ['a.jpg'])},
        ));
    await device.sync();
    final sent = await held(service);

    final spaces = sent['workspaces'] as Map;
    expect(spaces['newSort'], 'manual');
    expect(spaces['list'], [
      // Renamed here, and still wearing what the newer build gave it.
      {'id': 'w1', 'name': 'House', 'hue': 'sea', 'newIcon': 'house'},
      // Untouched here: as the account had them, the marker and the hue this build cannot draw included.
      {'id': 'org-o1', 'name': 'Ghost', 'org': 'o1'},
      {'id': 'w2', 'name': 'Odd', 'hue': 'ultraviolet'},
      {'id': 'w3', 'name': 'New'},
    ]);
    expect(spaces['notes'], {'n1': 'w1', 'n9': 'org-o1', 'n2': 'w3'});
    // The trash emptied here is empty; the entry this build could never read is not this build's to drop.
    expect(sent['trash'], {'t2': 'not a time'});
    expect(sent['notifications'], {'team': true, 'claude': false, 'summaries': true, 'conflicts': true, 'mutedOrgs': ['o1', 'o2'], 'newDigest': 'weekly'});
    expect(sent['tabGroups'], {
      'list': [
        {'id': 'g1', 'name': 'Work', 'hue': 'sea', 'collapsed': true, 'newPinned': true},
      ],
      'of': {'n1': 'g1'},
      'newOrder': ['g1'],
    });
    // The place was unticked here, so it is gone; the newer build's field on the same share is not.
    expect(sent['shares'], {
      'n1': {'id': 'i' * 22, 'key': 'k' * 43, 'sent': 'p2:2', 'lacked': ['a.jpg'], 'newExpires': 99},
    });
    // And everything this device did not touch is the account's own, the values it cannot draw included.
    for (final key in ['theme', 'density', 'homeLayout', 'codeLight', 'motionSpeed', 'openNotes', 'meetings', 'newFromTheFuture']) {
      expect(jsonEncode(sent[key]), jsonEncode(blob[key]), reason: key);
    }
  });

  test('a value this build could not draw gives way once the person chooses here', () async {
    final service = await FakeService.start(seed: testAccount);
    await writeAs(service, newerBlob());
    final device = TypedDevice(service);
    await device.sync();
    expect(device.store.value.theme, 'dark');
    // Chosen here, and chosen back to the very default the unknown theme was read as: still a choice.
    device.store.update((now) => now.copyWith(theme: 'light'));
    device.store.update((now) => now.copyWith(theme: 'dark'));
    await device.sync();
    expect((await held(service))['theme'], 'dark');
  });

  test('two devices of this app and a newer one keep one another’s settings whole through a merge', () async {
    final service = await FakeService.start(seed: testAccount);
    final blob = newerBlob();
    await writeAs(service, blob);
    final phone = TypedDevice(service);
    final fold = TypedDevice(service);
    await phone.sync();
    await fold.sync();
    // The newer device files a note and adds to a field only it knows; the phone, meanwhile, opens a tab.
    final theirs = (jsonDecode(jsonEncode(await held(service))) as Map).cast<String, Object?>();
    ((theirs['workspaces'] as Map)['notes'] as Map)['n7'] = 'w1';
    (theirs['notifications'] as Map)['newDigest'] = 'daily';
    theirs['newFromTheFuture'] = {'a': 2};
    await writeAs(service, theirs);
    phone.store.update((now) => now.copyWith(openNotes: ['n1', 'n2', 'n3'], density: 'compact'));
    expect(await phone.sync(), isTrue);
    final merged = await held(service);
    expect(merged['openNotes'], ['n1', 'n2', 'n3']);
    expect(merged['density'], 'compact');
    expect(((merged['workspaces'] as Map)['notes'] as Map)['n7'], 'w1');
    expect((merged['notifications'] as Map)['newDigest'], 'daily');
    expect(merged['newFromTheFuture'], {'a': 2});
    expect(merged['theme'], 'aurora');
    expect(((merged['workspaces'] as Map)['list'] as List).first, {'id': 'w1', 'name': 'Home', 'hue': 'sea', 'newIcon': 'house'});
    // The other device of this app takes the lot, changes nothing, and has nothing to say.
    expect(await fold.sync(), isTrue);
    expect(fold.store.value.openNotes, ['n1', 'n2', 'n3']);
    service.calls.clear();
    await fold.sync();
    await phone.sync();
    expect(service.calls, ['GET prefs', 'GET prefs']);
    expect(jsonEncode(await held(service)), jsonEncode(merged));
  });

  test('signing out forgets what the account held, and a second account starts from nothing', () async {
    final service = await FakeService.start(seed: testAccount);
    await writeAs(service, newerBlob());
    final device = TypedDevice(service);
    await device.sync();
    expect(device.kept.getItem('glyph-sync-7-prefs-held'), isNotNull);
    device.bridge.forget();
    expect(device.kept.getItem('glyph-sync-7-prefs-held'), isNull);
    expect(device.bridge.read()['theme'], 'dark');
  });
}
