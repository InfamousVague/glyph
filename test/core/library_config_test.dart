import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/library_config.dart';
import 'package:ghost_md/core/library_folder.dart' show LibraryStatus;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/smart_notebooks.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/daily_notes.dart';

/// The committed library config (lib/core/library_config.dart; docs/MARKDOWN_FIRST.md §6): written from the
/// preferences, read back into them on a restore or when newer, additive, never a secret, and reconciled between two
/// devices sharing a folder by last writer per section with the synced preferences as the tie-break.
void main() {
  /// A device: its preferences in memory, its own storage, and a keeper over [file].
  ({PreferencesStore prefs, MemoryStored stored, LibraryConfigKeeper keeper}) device(ConfigFile file, {DateTime Function()? clock}) {
    final prefs = PreferencesStore()..startWithoutStorage();
    final stored = MemoryStored();
    final keeper = LibraryConfigKeeper(file: file, preferences: prefs, stored: stored, writeAfter: Duration.zero, clock: clock, log: (_) {});
    return (prefs: prefs, stored: stored, keeper: keeper);
  }

  /// The preferences of a device that made Work (moss), Work/Clients and Home, chose a daily-notes folder and a
  /// smart notebook, and is in Acme.
  Preferences described() {
    final store = WorkspaceStore();
    final work = store.addWorkspace('Work', 'moss')!;
    store.addWorkspace('Clients', 'ink', work.id);
    final home = store.addWorkspace('Home')!;
    store.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Acme Corp', hue: 'sea'));
    var prefs = Preferences.defaults.copyWith(
      workspaces: KeptWorkspaces(list: [for (final w in store.value.list) KeptWorkspace(id: w.id, name: w.name, hue: w.hue, parent: w.parent)], notes: {'n1': work.id}),
      mapTiles: false,
    );
    prefs = withDailyNotes(prefs, DailyNotesSetup(folder: home.id, template: 'A day'));
    return withSmartNotebooks(prefs, const [SmartNotebook(id: 's-1', name: 'Open work', query: 'is:todo')]);
  }

  group('the file', () {
    test('is version 1, keyed by path, carries no filings and no secrets, and keeps keys it does not know', () {
      final stored = MemoryStored()
        ..write(slackChannelsKey, [{'id': 'c1', 'name': '#eng'}])
        ..write(slackMeetingsKey, {'channel': 'c1', 'on': true, 'share': false})
        ..write('glyph-slack-webhook:c1', 'https://hooks.slack.com/x');
      final config = LibraryConfig.of(described(), stored: stored);
      final json = config.toJson();
      expect(json['version'], 1);
      expect(json['workspaces'], {'Work': {'hue': 'moss', 'order': 0}, 'Work/Clients': {'order': 0}, 'Home': {'order': 1}});
      expect(json['orgs'], {'orgs/Acme Corp': {'org': 'o1', 'name': 'Acme Corp', 'hue': 'sea'}});
      expect(json['dailyNotes'], {'folder': 'Home', 'template': 'A day'});
      expect(json['smartNotebooks'], [{'id': 's-1', 'name': 'Open work', 'query': 'is:todo'}]);
      expect(json['defaults'], {'geotag': true, 'mapTiles': false, 'placeNames': true});
      expect(json['slack'], {'channels': [{'id': 'c1', 'name': '#eng'}], 'meetings': {'channel': 'c1', 'share': false}});
      expect(json.containsKey('discord'), isFalse);
      expect(config.encode(), isNot(contains('hooks.slack.com')));
      expect(config.encode(), isNot(contains('n1')), reason: 'filings are the paths');
      expect(looksSecret(json), isFalse);

      final back = LibraryConfig.parse('${jsonEncode({...json, 'later': {'x': 1}, 'written': {'workspaces': '2026-10-31T10:00:00.000Z'}})}\n');
      expect(back.workspaces['Work']?.hue, 'moss');
      expect(back.orgs['orgs/Acme Corp']?.org, 'o1');
      expect(back.written, {'workspaces': '2026-10-31T10:00:00.000Z'});
      expect(back.toJson()['later'], {'x': 1}, reason: 'a newer build’s key rides through');
      expect(LibraryConfig.parse('not json'), LibraryConfig.empty);
      expect(LibraryConfig.parse(null).toJson(), {'version': 1});
    });

    test('writes a folder’s id only where it is not the one its place gives it', () {
      final old = Preferences.defaults.copyWith(workspaces: const KeptWorkspaces(list: [KeptWorkspace(id: 'w-old123', name: 'Work')]));
      expect(LibraryConfig.of(old).toJson()['workspaces'], {'Work': {'id': 'w-old123', 'order': 0}});
    });

    test('refuses anything that looks like a secret', () {
      expect(looksSecret({'slack': {'channels': [{'id': 'c1', 'name': '#eng'}]}}), isFalse);
      expect(looksSecret({'slack': {'channels': [{'id': 'c1', 'url': 'https://hooks.slack.com/x'}]}}), isTrue, reason: 'a URL under slack is a webhook');
      expect(looksSecret({'calendars': ['https://calendar.google.com/ical']}), isTrue);
      expect(looksSecret({'github': {'token': 'ghp_x'}}), isTrue);
      expect(looksSecret({'google': {'refreshToken': 'x'}}), isTrue);
      expect(looksSecret({'webhookUrl': 'x'}), isTrue);
      expect(looksSecret({'defaults': {'geotag': true}, 'me': 'matt'}), isFalse);
      expect(looksSecret({'dailyNotes': {'folder': 'https://not-a-url-section'}}), isFalse, reason: 'a URL elsewhere is words');
    });

    test('is where the library is: the app’s folder, a chosen folder, and nowhere for a SAF tree', () {
      expect((configFileFor(const LibraryStatus(kind: 'app', own: '/data/Library')) as FileConfigFile).path, '/data/Library/.glyph/config.json');
      expect((configFileFor(const LibraryStatus(kind: 'folder', path: '/Users/m/Notes', own: '/data/Library')) as FileConfigFile).path, '/Users/m/Notes/.glyph/config.json');
      expect((configFileFor(const LibraryStatus(kind: 'folder', path: '/Volumes/gone', reachable: false, own: '/data/Library')) as FileConfigFile).path, '/data/Library/.glyph/config.json');
      expect(configFileFor(const LibraryStatus(kind: 'tree', name: 'Notes')), isNull);
      expect(configFileFor(const LibraryStatus(kind: 'app')), isNull);
    });
  });

  group('a restore', () {
    test('reads the whole file into empty preferences: folders with their ids and hues, the daily notes, the smart notebooks, the defaults, the channels', () async {
      final file = MemoryConfigFile();
      final writer = device(file);
      writer.prefs.value = described();
      writer.stored.write(slackChannelsKey, [{'id': 'c1', 'name': '#eng'}]);
      await writer.keeper.open();
      await writer.keeper.flush();
      expect(file.writes, 1);

      final fresh = device(file);
      expect(await fresh.keeper.open(), ['workspaces', 'orgs', 'dailyNotes', 'smartNotebooks', 'defaults', 'slack']);
      final prefs = fresh.prefs.value;
      final list = prefs.workspaces.list;
      final work = list.singleWhere((w) => w.name == 'Work'), clients = list.singleWhere((w) => w.name == 'Clients'), home = list.singleWhere((w) => w.name == 'Home');
      final theirs = described().workspaces.list;
      expect((work.id, work.hue, clients.id, clients.parent, home.id), (theirs[0].id, 'moss', theirs[1].id, theirs[0].id, theirs[2].id));
      expect(list.singleWhere((w) => w.id == orgWorkspaceId('o1')).name, 'Acme Corp');
      expect(prefs.workspaces.notes, isEmpty, reason: 'the filings come from the paths (lib/core/folder_adopter.dart)');
      expect(dailyNotesIn(prefs), DailyNotesSetup(folder: home.id, template: 'A day'));
      expect(smartNotebooksIn(prefs).map((s) => s.name), ['Open work']);
      expect(prefs.mapTiles, isFalse);
      expect(fresh.stored.read<Object?>(slackChannelsKey, null), [{'id': 'c1', 'name': '#eng'}]);
      // Read once: the next open takes nothing again, and the restored device writes nothing it did not change.
      expect(await fresh.keeper.reread(), isEmpty);
      await fresh.keeper.flush();
      expect(file.writes, 1);
    });

    test('takes an older file’s id for a folder, else the one its place gives it', () async {
      final file = MemoryConfigFile(jsonEncode({'version': 1, 'workspaces': {'Work': {'id': 'w-old123'}, 'Work/Clients': {}, '..': {}}, 'written': {'workspaces': '2026-10-31T10:00:00.000Z'}}));
      final fresh = device(file);
      await fresh.keeper.open();
      final list = fresh.prefs.value.workspaces.list;
      expect(list.map((w) => w.name), ['Work', 'Clients'], reason: 'a name that cleans away makes no folder');
      expect(list[0].id, 'w-old123');
      expect(list[1].id, folderIdFor([for (final w in list) Workspace(id: w.id, name: w.name, parent: w.parent)], 'Clients', 'w-old123'));
    });
  });

  group('two devices sharing a folder', () {
    test('take each other’s folders additively, and the later writer’s hue wins per section', () async {
      var now = DateTime.utc(2026, 10, 31, 10);
      final file = MemoryConfigFile();
      final a = device(file, clock: () => now), b = device(file, clock: () => now);
      await a.keeper.open();
      await b.keeper.open();

      // A makes Work in moss and writes; B, with a folder of its own, opens the file and takes Work beside it.
      a.prefs.update((p) => p.copyWith(workspaces: const KeptWorkspaces(list: [KeptWorkspace(id: 'w-work00', name: 'Work', hue: 'moss')])));
      await a.keeper.flush();
      b.prefs.update((p) => p.copyWith(workspaces: const KeptWorkspaces(list: [KeptWorkspace(id: 'w-home00', name: 'Home')])));
      // The defaults too: A's write is the first word on them, and B never saw the section.
      expect(await b.keeper.reread(), ['workspaces', 'defaults']);
      expect(b.prefs.value.workspaces.list.map((w) => '${w.name}:${w.hue}'), ['Home:null', 'Work:moss']);

      // B recolours Work later and writes; A, which last wrote at 10:00, takes the newer file.
      now = DateTime.utc(2026, 10, 31, 11);
      b.prefs.update((p) => p.copyWith(workspaces: KeptWorkspaces(list: [for (final w in p.workspaces.list) w.id == 'w-work00' ? KeptWorkspace(id: w.id, name: w.name, hue: 'sea') : w])));
      await b.keeper.flush();
      expect(await a.keeper.reread(), ['workspaces']);
      // B's order too (Home first, as B made them): the section is taken whole.
      expect(a.prefs.value.workspaces.list.map((w) => '${w.name}:${w.hue}'), ['Home:null', 'Work:sea']);

      // Nothing newer: the preferences stand, and a reread changes nothing (the synced settings are the tie-break).
      expect(await a.keeper.reread(), isEmpty);
      expect(await b.keeper.reread(), isEmpty);
      expect(file.writes, 2);
    });

    test('does not overwrite a section it has not taken yet', () async {
      var now = DateTime.utc(2026, 10, 31, 10);
      final file = MemoryConfigFile();
      final a = device(file, clock: () => now), b = device(file, clock: () => now);
      await a.keeper.open();
      await b.keeper.open();
      a.prefs.update((p) => p.copyWith(mapTiles: false));
      await a.keeper.flush();
      // B changes the same section without rereading: its write leaves A's newer stamp alone, and the next reread
      // takes A's.
      now = DateTime.utc(2026, 10, 31, 9);
      b.prefs.update((p) => p.copyWith(placeNames: false));
      await b.keeper.flush();
      expect(file.writes, 1);
      expect(await b.keeper.reread(), ['defaults']);
      expect(b.prefs.value.mapTiles, isFalse);
    });

    test('merges channels by id into the plugin’s own item, and never the on switch', () async {
      final stored = MemoryStored()
        ..write(slackChannelsKey, [{'id': 'c1', 'name': '#old', 'extra': 1}])
        ..write(slackMeetingsKey, {'channel': 'c9', 'on': true, 'share': true});
      applyConfigSection(Preferences.defaults, LibraryConfig.parse(jsonEncode({'slack': {'channels': [{'id': 'c1', 'name': '#eng'}, {'id': 'c2', 'name': '#ops'}], 'meetings': {'channel': 'c2', 'share': false}}})), 'slack', stored: stored);
      expect(stored.read<Object?>(slackChannelsKey, null), [{'id': 'c1', 'name': '#eng', 'extra': 1}, {'id': 'c2', 'name': '#ops'}]);
      expect(stored.read<Object?>(slackMeetingsKey, null), {'channel': 'c2', 'on': true, 'share': false});
    });
  });

  group('the keeper', () {
    test('writes a moment after a change, once, and refuses a secret', () async {
      final file = MemoryConfigFile();
      final a = device(file);
      await a.keeper.open();
      a.prefs.update((p) => p.copyWith(placeNames: false));
      a.prefs.update((p) => p.copyWith(mapTiles: false));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(file.writes, 1);
      final written = LibraryConfig.parse(file.text);
      expect(written.defaults, {'geotag': true, 'mapTiles': false, 'placeNames': false});
      expect(written.written.keys, ['defaults']);

      a.stored.write(slackChannelsKey, [{'id': 'c1', 'name': 'https://hooks.slack.com/leak'}]);
      a.keeper.touch();
      await a.keeper.flush();
      expect(file.writes, 1, reason: 'a value that looks like a secret is never written');
      a.keeper.dispose();
    });
  });
}
