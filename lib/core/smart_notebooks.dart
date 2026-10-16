/// Smart notebooks: searches kept by name (Matt, 2026-10-16: saved searches, after a look at what Evernote and
/// Obsidian keep). A smart notebook is a name and a query (lib/core/search_query.dart), and opens as the notes the
/// query finds now: nothing is filed in it, and a note that comes to hold to the query is in it at once.
///
/// **Where they are kept.** In the preferences, so they follow the account to every device as the workspaces do
/// (lib/sync/prefs.dart `syncedPrefs`), under the key [smartNotebooksKey]:
///
///     "smartNotebooks": [{"id": "s-k3f9x2", "name": "Open work", "query": "tag:work is:todo"}, …]
///
/// in the order the sidebar lists them. The typed [Preferences] has no field of its own for it: it is carried in
/// [Preferences.more], which reads and writes a key the class does not model as it was, so the shared class is
/// untouched and a build from before this keeps the list when it writes its settings back.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'preferences.dart';

/// The preference the smart notebooks are kept under.
const String smartNotebooksKey = 'smartNotebooks';

/// A search kept by name.
@immutable
class SmartNotebook {
  const SmartNotebook({required this.id, required this.name, required this.query});

  final String id;
  final String name;

  /// The search, as typed: its words and its operators.
  final String query;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'query': query};

  SmartNotebook copyWith({String? name, String? query}) => SmartNotebook(id: id, name: name ?? this.name, query: query ?? this.query);

  @override
  bool operator ==(Object other) => other is SmartNotebook && other.id == id && other.name == name && other.query == query;

  @override
  int get hashCode => Object.hash(id, name, query);

  @override
  String toString() => 'SmartNotebook($id, $name, $query)';
}

/// The smart notebooks a set of preferences keeps, in order; anything but the shape is none.
List<SmartNotebook> smartNotebooksIn(Preferences prefs) {
  final raw = prefs.more[smartNotebooksKey];
  if (raw is! List) return const [];
  final seen = <String>{};
  return List.unmodifiable([
    for (final each in raw)
      if (each is Map && each['id'] is String && each['name'] is String && each['query'] is String && seen.add(each['id'] as String))
        SmartNotebook(id: each['id'] as String, name: each['name'] as String, query: each['query'] as String),
  ]);
}

/// [prefs] keeping [list] as its smart notebooks.
Preferences withSmartNotebooks(Preferences prefs, List<SmartNotebook> list) => prefs.copyWith(more: {...prefs.more, smartNotebooksKey: [for (final each in list) each.toJson()]});

String _tidy(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The smart notebooks, and what is done to them, over the preferences. Listen to it: its value is the same list
/// until it changes, here or on another device.
class SmartNotebookStore extends ChangeNotifier implements ValueListenable<List<SmartNotebook>> {
  SmartNotebookStore({PreferencesStore? prefs, Random? random})
      : _prefs = prefs ?? preferences,
        _random = random ?? Random() {
    _value = smartNotebooksIn(_prefs.value);
    _prefs.addListener(_heard);
  }

  final PreferencesStore _prefs;
  final Random _random;
  late List<SmartNotebook> _value;

  @override
  List<SmartNotebook> get value => _value;

  void _heard() {
    final next = smartNotebooksIn(_prefs.value);
    if (listEquals(next, _value)) return;
    _value = next;
    notifyListeners();
  }

  void _write(List<SmartNotebook> next) {
    _value = List.unmodifiable(next);
    _prefs.update((now) => withSmartNotebooks(now, _value));
    notifyListeners();
  }

  /// The one by that id, or null.
  SmartNotebook? byId(String id) => _value.where((each) => each.id == id).firstOrNull;

  String _freshId() {
    const letters = '0123456789abcdefghijklmnopqrstuvwxyz';
    for (;;) {
      final id = 's-${List.generate(6, (_) => letters[_random.nextInt(letters.length)]).join()}';
      if (byId(id) == null) return id;
    }
  }

  /// A new one called [name], keeping [query]; null for an empty name or an empty search. Last in the list.
  SmartNotebook? add(String name, String query) {
    final clean = _tidy(name), search = query.trim();
    if (clean.isEmpty || search.isEmpty) return null;
    final made = SmartNotebook(id: _freshId(), name: clean, query: search);
    _write([..._value, made]);
    return made;
  }

  void rename(String id, String name) {
    final clean = _tidy(name);
    if (clean.isEmpty || byId(id) == null) return;
    _write([for (final each in _value) each.id == id ? each.copyWith(name: clean) : each]);
  }

  /// Its search changed.
  void setQuery(String id, String query) {
    final search = query.trim();
    if (search.isEmpty || byId(id) == null) return;
    _write([for (final each in _value) each.id == id ? each.copyWith(query: search) : each]);
  }

  /// Moves it to [to] in the list, counted as the list is before it moves; one step up or down is [to] its place
  /// less or more one.
  void move(String id, int to) {
    final from = _value.indexWhere((each) => each.id == id);
    if (from < 0) return;
    final next = [..._value];
    final moved = next.removeAt(from);
    next.insert(to.clamp(0, next.length), moved);
    if (listEquals(next, _value)) return;
    _write(next);
  }

  /// Gone from the list. No note is touched: a smart notebook holds none.
  void remove(String id) {
    if (byId(id) == null) return;
    _write([for (final each in _value) if (each.id != id) each]);
  }

  @override
  void dispose() {
    _prefs.removeListener(_heard);
    super.dispose();
  }
}
