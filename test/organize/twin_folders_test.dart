// Folders made twice (Matt, 2026-10-23: "When creating multiple folders it seems like it's syncing then duplicating
// the folder I created a meetings folder and got one with no notes but the color i chose and then one with no color
// but the note i placed inside, fix the duplicate folders").
//
// How his were made: the Mac made Meetings in HelloTrade, in a colour, and filed a note in it. The note's row reached
// the phone in a team pass, which syncs no settings, so the phone had no Meetings and the team's channel made one
// for the note's path (lib/team/folders.dart `fileAt`), with an id of its own and no colour. The settings then merged
// both lists by id (lib/sync/prefs.dart `merged`): both folders stood, and the note's filing went to the phone's,
// which sent last. Here two devices of one account do exactly that, through the real settings pass against the
// service in memory, each with its own [WorkspaceStore] over its settings. Then the heal (`mergeTwinFolders`) on
// the twins his account holds now, Meetings and Agents, and on twins inside twins, personal twins, and two devices
// healing at once.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/sync/prefs.dart';
import 'package:ghost_md/team/folders.dart';

import '../sync/support.dart';

/// A device's workspaces kept in its settings map, as the app keeps them in the preferences
/// (lib/core/kept_workspaces.dart), and the filter on the device.
class _MapStorage implements WorkspaceStorage {
  _MapStorage(this.device);
  final _Device device;
  String? _current;

  @override
  WorkspaceSheet read() {
    final held = KeptWorkspaces.fromJson(device.prefs['workspaces']);
    return WorkspaceSheet(list: [for (final w in held.list) Workspace.kept(id: w.id, name: w.name, hue: w.hue, parent: w.parent)], notes: held.notes, current: _current);
  }

  @override
  void write(WorkspaceSheet sheet) {
    device.prefs = {
      ...device.prefs,
      'workspaces': KeptWorkspaces(list: [for (final w in sheet.list) KeptWorkspace(id: w.id, name: w.name, hue: w.hue, parent: w.parent)], notes: sheet.notes).toJson(),
    };
    _current = sheet.current;
  }
}

/// A device of the account: its settings, as the settings pass reads and writes them, and its workspaces over them.
class _Device {
  _Device(this.service) : api = apiOf(service) {
    store = WorkspaceStore(storage: _MapStorage(this), onFiled: (ids, w) => filed.add('${ids.join(',')} to ${folderFor(w, store.value.list)}'));
  }

  final FakeService service;
  final Api api;
  Map<String, Object?> prefs = Preferences.defaults.toJson();
  PrefsState state = const PrefsState();
  late final WorkspaceStore store;
  final List<String> filed = [];

  /// One pass of the settings, and the workspaces read again from what it left, as the app's storage tells its store.
  Future<void> sync() async {
    await syncPrefs(PrefsContext(
      token: service.signedIn(),
      key: service.accountKey,
      read: () => prefs,
      write: (next) => prefs = {...prefs, ...next},
      state: state,
      save: (next) => state = next,
      api: api,
      crypto: service.crypto,
    ));
    store.reloadWorkspaces();
  }

  /// The folders inside [parent], as "name (hue): notes".
  List<String> inside(String parent) => [
        for (final w in store.childrenOf(parent)) '${w.name}${w.hue == null ? '' : ' (${w.hue})'}: ${store.notesInWorkspace(w.id).join(',')}',
      ];
}

void main() {
  const hello = OrgLike(id: 'org1', name: 'HelloTrade');
  final root = orgWorkspaceId(hello.id);

  group('a folder made by hand on one device and by a note’s path on another', () {
    late FakeService service;
    late _Device mac, phone;

    setUp(() async {
      service = await FakeService.start(seed: testAccount);
      mac = _Device(service);
      phone = _Device(service);
      mac.store.ensureOrgWorkspace(hello);
      await mac.sync();
      await phone.sync();
      expect(phone.store.value.list.map((w) => w.id), [root]);
    });

    test('is one folder on both, in the colour chosen, with the note in it (the Mac sends first)', () async {
      final meetings = mac.store.addWorkspace('Meetings', 'sea', root)!;
      mac.store.fileNote('n1', meetings.id);
      await mac.sync();
      // The phone's team pass, before its settings pass: the note's path names a folder it has not got.
      OrgFolders(phone.store, hello.id).fileAt('n1', ['Meetings']);
      await phone.sync();
      await mac.sync();
      for (final device in [mac, phone]) {
        expect(device.inside(root), ['Meetings (sea): n1']);
      }
      expect(phone.store.workspaceOf('n1')!.id, meetings.id);
    });

    test('is one folder on both, in the colour chosen, with the note in it (the phone sends first)', () async {
      final meetings = mac.store.addWorkspace('Meetings', 'sea', root)!;
      mac.store.fileNote('n1', meetings.id);
      OrgFolders(phone.store, hello.id).fileAt('n1', ['Meetings']);
      await phone.sync();
      await mac.sync();
      await phone.sync();
      for (final device in [mac, phone]) {
        expect(device.inside(root), ['Meetings (sea): n1']);
      }
    });

    test('folders inside folders, made by a path on the phone, are the Mac’s own', () async {
      final clients = mac.store.addWorkspace('Clients', 'moss', root)!;
      final acme = mac.store.addWorkspace('Acme', 'rose', clients.id)!;
      mac.store.fileNote('n1', acme.id);
      await mac.sync();
      OrgFolders(phone.store, hello.id).fileAt('n1', ['Clients', 'Acme']);
      await phone.sync();
      await mac.sync();
      for (final device in [mac, phone]) {
        expect(device.inside(root), ['Clients (moss): ']);
        expect(device.inside(clients.id), ['Acme (rose): n1']);
      }
    });

    test('a personal folder made on two devices before either synced is one', () async {
      final mine = mac.store.addWorkspace('Daily', 'amber')!;
      mac.store.fileNote('d1', mine.id);
      final theirs = phone.store.addWorkspace('daily')!;
      phone.store.fileNote('d2', theirs.id);
      expect(theirs.id, mine.id);
      await mac.sync();
      await phone.sync();
      await mac.sync();
      for (final device in [mac, phone]) {
        final top = [for (final w in device.store.value.list) if (w.parent == null && !isOrgWorkspace(w.id)) w];
        expect(top.map((w) => (w.id, w.hue)), [(mine.id, 'amber')]);
        expect(device.store.notesInWorkspace(mine.id)..sort(), ['d1', 'd2']);
      }
    });
  });

  group('twins already made are made one again', () {
    /// Matt's HelloTrade as the connector listed it on 2026-10-23: the empty twin in his colour, the other holding
    /// the note.
    WorkspaceSheet matts() => WorkspaceSheet(
          list: [
            Workspace(id: root, name: 'HelloTrade'),
            Workspace(id: 'w-i6k7sk', name: 'Meetings', hue: 'sea', parent: root),
            Workspace(id: 'w-m6jy58', name: 'Meetings', parent: root),
            Workspace(id: 'w-s8w81r', name: 'Agents', parent: root),
            Workspace(id: 'w-j842m7', name: 'Agents', hue: 'violet', parent: root),
            const Workspace(id: 'w-mine01', name: 'Meetings'),
          ],
          notes: {'standup': 'w-m6jy58', 'agent-plan': 'w-s8w81r', 'own': 'w-mine01', 'lead': root},
          current: 'w-m6jy58',
        );

    test('Meetings and Agents: the coloured one kept, the note filed in it, nothing deleted or taken out', () {
      final filed = <String>[];
      final trash = MemoryTrash();
      late final WorkspaceStore store;
      store = WorkspaceStore(storage: MemoryWorkspaceStorage(matts()), trash: trash, onFiled: (ids, w) => filed.add('${ids.join(',')} to ${folderFor(w, store.value.list)}'));
      expect(store.mergeTwinFolders(), 2);
      expect([for (final w in store.childrenOf(root)) (w.id, w.name, w.hue)], [('w-i6k7sk', 'Meetings', 'sea'), ('w-j842m7', 'Agents', 'violet')]);
      expect(store.value.of, {'standup': 'w-i6k7sk', 'agent-plan': 'w-j842m7', 'own': 'w-mine01', 'lead': root});
      // Still the organization's, at the same path, so no team note's row is put again and none is deleted.
      expect(store.orgOf(store.workspaceOf('standup')!.id), hello.id);
      expect(filed, containsAll(['standup to orgs/HelloTrade/Meetings', 'agent-plan to orgs/HelloTrade/Agents']));
      expect(filed.where((line) => line.endsWith(' to Inbox')), isEmpty);
      expect(trash.value, isEmpty);
      // The personal Meetings is not the organization's twin; the filter follows the folder kept.
      expect(store.value.list.where((w) => w.id == 'w-mine01'), hasLength(1));
      expect(store.value.current?.id, 'w-i6k7sk');
      // Once is enough.
      filed.clear();
      expect(store.mergeTwinFolders(), 0);
      expect(filed, isEmpty);
    });

    test('two devices healing at once, their lists in other orders, meet with nothing to argue over', () async {
      final service = await FakeService.start(seed: testAccount);
      final mac = _Device(service), phone = _Device(service);
      for (final device in [mac, phone]) {
        final sheet = matts();
        final list = device == phone ? sheet.list.reversed : sheet.list;
        device.prefs = {
          ...device.prefs,
          'workspaces': KeptWorkspaces(list: [for (final w in list) KeptWorkspace(id: w.id, name: w.name, hue: w.hue, parent: w.parent)], notes: sheet.notes).toJson(),
        };
        device.store.reloadWorkspaces();
      }
      await mac.sync();
      await phone.sync();
      expect(mac.store.mergeTwinFolders(), 2);
      expect(phone.store.mergeTwinFolders(), 2);
      await mac.sync();
      await phone.sync();
      await mac.sync();
      for (final device in [mac, phone]) {
        expect([for (final w in device.store.childrenOf(root)) (w.id, w.hue)]..sort((a, b) => a.$1.compareTo(b.$1)), [('w-i6k7sk', 'sea'), ('w-j842m7', 'violet')]);
        expect(device.store.workspaceOf('standup')!.id, 'w-i6k7sk');
        expect(device.store.workspaceOf('agent-plan')!.id, 'w-j842m7');
      }
    });

    test('twins inside twins: the folders inside them are put in the one kept, and are made one in turn', () {
      final store = WorkspaceStore(
        storage: MemoryWorkspaceStorage(const WorkspaceSheet(
          list: [
            Workspace(id: 'w-a', name: 'Clients'),
            Workspace(id: 'w-b', name: 'clients', hue: 'moss'),
            Workspace(id: 'w-a1', name: 'Acme', parent: 'w-a'),
            Workspace(id: 'w-b1', name: 'Acme', parent: 'w-b'),
            Workspace(id: 'w-a2', name: 'Initech', parent: 'w-a'),
          ],
          notes: {'n1': 'w-a1', 'n2': 'w-b1', 'n3': 'w-a2', 'n4': 'w-a'},
        )),
      );
      expect(store.mergeTwinFolders(), 2);
      expect(store.value.list.map((w) => '${w.id} in ${w.parent}'), ['w-b in null', 'w-a1 in w-b', 'w-a2 in w-b']);
      expect(store.value.of, {'n1': 'w-a1', 'n2': 'w-a1', 'n3': 'w-a2', 'n4': 'w-b'});
    });

    test('folders of the same name in different places are not twins', () {
      final store = WorkspaceStore(
        storage: MemoryWorkspaceStorage(const WorkspaceSheet(
          list: [
            Workspace(id: 'w-a', name: 'Work'),
            Workspace(id: 'w-b', name: 'Home'),
            Workspace(id: 'w-a1', name: 'Notes', parent: 'w-a'),
            Workspace(id: 'w-b1', name: 'Notes', parent: 'w-b'),
          ],
          notes: {'n1': 'w-a1', 'n2': 'w-b1'},
        )),
      );
      expect(store.mergeTwinFolders(), 0);
      expect(store.value.list, hasLength(4));
    });
  });

  test('a folder’s id is its place’s: the same for the same place, another for another, the old shape', () {
    final list = [Workspace(id: root, name: 'HelloTrade'), const Workspace(id: 'w-x', name: 'Work')];
    final a = folderIdFor(list, 'Meetings', root);
    expect(a, matches(RegExp(r'^w-[a-z0-9]{6}$')));
    expect(folderIdFor(list, ' meetings ', root), a);
    expect(folderIdFor([Workspace(id: root, name: 'Renamed'), ...list.skip(1)], 'Meetings', root), a, reason: 'the organization by its id, not its name');
    expect(folderIdFor(list, 'Meetings', null), isNot(a));
    expect(folderIdFor(list, 'Meetings', 'w-x'), isNot(a));
    expect(folderIdFor(list, 'Meetings', 'w-gone'), isNull);
    expect(folderIdFor(list, '///', root), isNull);
  });
}
