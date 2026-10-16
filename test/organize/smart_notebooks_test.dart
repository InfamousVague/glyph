import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/smart_notebooks.dart';
import 'package:ghost_md/sync/prefs.dart' show pickSynced, syncedPrefs;

/// Smart notebooks, searches kept by name in the preferences (lib/core/smart_notebooks.dart).
void main() {
  late PreferencesStore prefs;
  late SmartNotebookStore store;

  setUp(() {
    prefs = PreferencesStore()..startWithoutStorage();
    store = SmartNotebookStore(prefs: prefs, random: Random(1));
    addTearDown(store.dispose);
  });

  test('a search is kept by name, renamed, changed, moved and let go', () {
    final open = store.add('  Open   work ', 'tag:work is:todo')!;
    final week = store.add('This week', 'updated:<7d')!;
    final pics = store.add('Pictures', 'has:image')!;
    expect(open.name, 'Open work');
    expect(store.add('', 'tag:x'), isNull);
    expect(store.add('Empty', '   '), isNull);
    expect([for (final each in store.value) each.name], ['Open work', 'This week', 'Pictures']);

    store.rename(week.id, 'Lately');
    store.setQuery(week.id, 'updated:<3d');
    expect(store.byId(week.id), SmartNotebook(id: week.id, name: 'Lately', query: 'updated:<3d'));

    store.move(pics.id, 0);
    expect([for (final each in store.value) each.name], ['Pictures', 'Open work', 'Lately']);
    store.move(pics.id, 1);
    expect([for (final each in store.value) each.name], ['Open work', 'Pictures', 'Lately']);
    store.remove(open.id);
    expect([for (final each in store.value) each.name], ['Pictures', 'Lately']);
  });

  test('round-trips through the preferences as JSON, under its own key, and travels with the account', () {
    store.add('Open work', 'tag:work is:todo');
    store.add('Field guide', 'in:"Field guide" -is:done');
    final json = prefs.value.toJson();
    expect(json[smartNotebooksKey], [
      {'id': store.value[0].id, 'name': 'Open work', 'query': 'tag:work is:todo'},
      {'id': store.value[1].id, 'name': 'Field guide', 'query': 'in:"Field guide" -is:done'},
    ]);
    // Written out and read back, as the store keeps them and another device reads them.
    final again = Preferences.fromJson(jsonDecode(jsonEncode(json)));
    expect(smartNotebooksIn(again), store.value);
    expect(syncedPrefs, contains(smartNotebooksKey));
    expect(pickSynced(json)[smartNotebooksKey], json[smartNotebooksKey]);
  });

  test('hears them change on another device, and reads anything but the shape as none', () {
    var told = 0;
    store.addListener(() => told += 1);
    prefs.value = withSmartNotebooks(prefs.value, const [SmartNotebook(id: 's-1', name: 'From the phone', query: 'is:pinned')]);
    expect(told, 1);
    expect(store.value.single.name, 'From the phone');
    // Another setting changing leaves them alone.
    prefs.update((now) => now.copyWith(theme: 'light'));
    expect(told, 1);
    expect(smartNotebooksIn(Preferences.fromJson({smartNotebooksKey: 'rubbish'})), isEmpty);
    expect(smartNotebooksIn(Preferences.fromJson({smartNotebooksKey: [{'id': 1}, {'id': 'a', 'name': 'A', 'query': 'x'}, {'id': 'a', 'name': 'Twice', 'query': 'y'}]})).single.name, 'A');
  });
}
