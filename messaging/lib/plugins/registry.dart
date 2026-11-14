/// The plugins the app has and what the ones that are switched on add (the contract is plugin.dart). A screen asks
/// here: which tags a conversation has, which section it is in, what there is for a slot, what to do with a message
/// that has just come. A plugin that is off is never asked, and one that throws is left out and said in the
/// Developer log, so a bad plugin costs its own part and not the list.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import 'plugin.dart';

/// The plugins the app ships with, in the order Settings › Plugins lists them and their sections are asked.
const List<GhostPlugin> shippedPlugins = [];

/// The person's choices as the plugins' side reads and writes them: the app's own ([AppStore]), or a map in a test.
abstract interface class PluginStore {
  String? read(String key);
  void write(String key, String value);

  /// Goes up whenever a plugin's switch or one of its choices changes: what was worked out from them is worked out
  /// again.
  int get stamp;
}

/// The plugins' choices in the app's own ([AppState]), which keeps them in Android's preferences with the rest.
class AppStore implements PluginStore {
  const AppStore(this.app);
  final AppState app;

  @override
  String? read(String key) {
    final value = app.choice(key, '');
    return value.isEmpty ? null : value;
  }

  @override
  void write(String key, String value) => app.set(key, value);

  @override
  int get stamp => app.pluginsStamp;
}

/// Choices kept in memory: a test's, or a page drawn with no app round it.
class MemoryStore implements PluginStore {
  MemoryStore([Map<String, String>? values]) : values = {...?values};
  final Map<String, String> values;

  @override
  int stamp = 0;

  @override
  String? read(String key) {
    final value = values[key];
    return value == null || value.isEmpty ? null : value;
  }

  @override
  void write(String key, String value) {
    values[key] = value;
    stamp++;
  }
}

class _Prefs implements PluginPrefs {
  const _Prefs(this.store, this.prefix);
  final PluginStore store;
  final String prefix;

  @override
  String? get(String key) => store.read('$prefix$key');

  @override
  void set(String key, String value) => store.write('$prefix$key', value);

  @override
  bool flag(String key, {bool fallback = true}) {
    final value = get(key);
    return value == null ? fallback : value == 'on';
  }

  @override
  void setFlag(String key, bool on) => set(key, on ? 'on' : 'off');
}

/// Where the person (or a plugin's rule) has filed conversations by hand, which holds whatever the classifiers say:
/// a conversation's number to a section's id, or to [main] for one kept in the main list. Kept in one choice,
/// `plugins_filed`, as `12:codes,40:,77:spam`.
@immutable
class Filing {
  const Filing._(this._by);

  factory Filing.parse(String? raw) {
    if (raw == null || raw.isEmpty) return none;
    final by = <int, String>{};
    for (final part in raw.split(',')) {
      final at = part.indexOf(':');
      final thread = at < 0 ? null : int.tryParse(part.substring(0, at));
      if (thread != null) by[thread] = part.substring(at + 1);
    }
    return by.isEmpty ? none : Filing._(by);
  }

  static const key = 'plugins_filed';
  static const none = Filing._({});

  /// Filed in the main list: no section takes it.
  static const main = '';

  final Map<int, String> _by;

  /// The section [thread] is filed in, [main] for the main list, or null where it was never filed.
  String? of(int thread) => _by[thread];

  Filing _with(int thread, String? section) {
    final by = {..._by};
    section == null ? by.remove(thread) : by[thread] = section;
    return Filing._(by);
  }

  String _encode() => [for (final e in _by.entries) '${e.key}:${e.value}'].join(',');
}

/// A section, and the plugin whose it is.
@immutable
class PluginSection {
  const PluginSection(this.plugin, this.section);
  final GhostPlugin plugin;
  final ListSection section;
  String get id => section.id;
}

/// Something to press, and the plugin whose it is: the host it is run with has that plugin's choices.
@immutable
class BoundAction {
  const BoundAction(this.plugin, this.action);
  final GhostPlugin plugin;
  final PluginAction action;
}

/// What one plugin asks for of a message that has just come.
@immutable
class BoundIncoming {
  const BoundIncoming(this.plugin, this.action);
  final GhostPlugin plugin;
  final IncomingAction action;
}

/// What a plugin adds, read once when the registry is made: a plugin's lists are not asked for again.
class _Entry {
  _Entry(this.plugin)
      : classifiers = List.of(plugin.classifiers),
        sections = [for (final s in plugin.sections) PluginSection(plugin, s)],
        slots = List.of(plugin.slots),
        incoming = List.of(plugin.incoming),
        settings = List.of(plugin.settings);
  final GhostPlugin plugin;
  final List<Classifier> classifiers;
  final List<PluginSection> sections;
  final List<SlotFill> slots;
  final List<IncomingRule> incoming;
  final List<PluginSetting> settings;
}

class PluginRegistry {
  PluginRegistry(Iterable<GhostPlugin> plugins, {this.onError}) : _entries = [for (final p in plugins) _Entry(p)] {
    final ids = <String>{};
    final sections = <String>{};
    for (final e in _entries) {
      if (!_name.hasMatch(e.plugin.id)) throw ArgumentError('A plugin\'s id is lower-case letters and digits: "${e.plugin.id}"');
      if (!ids.add(e.plugin.id)) throw ArgumentError('Two plugins are called "${e.plugin.id}"');
      for (final s in e.sections) {
        if (!_name.hasMatch(s.id)) throw ArgumentError('A section\'s id is lower-case letters and digits: "${s.id}"');
        if (!sections.add(s.id)) throw ArgumentError('Two sections are called "${s.id}"');
      }
    }
  }

  /// The app's own: the plugins it ships with. A test puts its own here.
  static PluginRegistry instance = PluginRegistry(shippedPlugins);

  static final _name = RegExp(r'^[a-z0-9]+$');

  final List<_Entry> _entries;

  /// Told when a plugin throws while being asked something: which one, and what it threw.
  void Function(GhostPlugin plugin, Object error)? onError;

  List<GhostPlugin> get plugins => [for (final e in _entries) e.plugin];

  /// There are no plugins at all: nothing is worked out for anyone.
  bool get isEmpty => _entries.isEmpty;

  // --- the switch ---------------------------------------------------------------------------------------------------

  /// The choice a plugin's switch is kept under.
  static String switchKey(GhostPlugin plugin) => 'plugin_${plugin.id}';

  bool isOn(GhostPlugin plugin, PluginStore store) {
    final value = store.read(switchKey(plugin));
    return value == null ? plugin.onByDefault : value == 'on';
  }

  void setOn(GhostPlugin plugin, PluginStore store, bool on) => store.write(switchKey(plugin), on ? 'on' : 'off');

  /// The plugin's own choices, kept under its name (`plugin_<id>_<key>`).
  PluginPrefs prefsOf(GhostPlugin plugin, PluginStore store) => _Prefs(store, 'plugin_${plugin.id}_');

  /// The rows a plugin gives its card on Settings › Plugins.
  List<PluginSetting> settingsOf(GhostPlugin plugin) => [for (final e in _entries) if (identical(e.plugin, plugin)) ...e.settings];

  Iterable<_Entry> _on(PluginStore store) => _entries.where((e) => isOn(e.plugin, store));

  T _ask<T>(GhostPlugin plugin, T otherwise, T Function() ask) {
    try {
      return ask();
    } catch (error) {
      onError?.call(plugin, error);
      return otherwise;
    }
  }

  // --- (a) tags -----------------------------------------------------------------------------------------------------

  /// What every classifier of the plugins that are on says of [facts]. Not kept: [TagStore] keeps it for the list.
  TagSet classify(MessageFacts facts, PluginStore store) {
    List<Tag>? found;
    for (final e in _on(store)) {
      for (final classifier in e.classifiers) {
        final tags = _ask(e.plugin, const <Tag>[], () => classifier(facts));
        if (tags.isNotEmpty) (found ??= []).addAll(tags);
      }
    }
    return found == null ? TagSet.none : TagSet(found);
  }

  // --- (b) sections -------------------------------------------------------------------------------------------------

  /// The sections of the plugins that are on, in the order they are asked.
  List<PluginSection> sections(PluginStore store) => [for (final e in _on(store)) ...e.sections];

  String? _filedRaw;
  Filing _filed = Filing.none;

  /// Where conversations have been filed by hand.
  Filing filing(PluginStore store) {
    final raw = store.read(Filing.key);
    if (raw != _filedRaw) {
      _filedRaw = raw;
      _filed = Filing.parse(raw);
    }
    return _filed;
  }

  PluginSection? _taker(MessageFacts facts, TagSet tags, PluginStore store, List<PluginSection> sections) {
    for (final s in sections) {
      if (_ask(s.plugin, false, () => s.section.takes(facts, tags, prefsOf(s.plugin, store)))) return s;
    }
    return null;
  }

  /// The section a conversation is in, or null for the main list: where it was filed by hand if it was (and that
  /// section's plugin is still on), else the first section that takes it. [among] is [sections], where the caller
  /// has them already.
  PluginSection? sectionOf(MessageFacts facts, TagSet tags, PluginStore store, {List<PluginSection>? among}) {
    final sections = among ?? this.sections(store);
    if (sections.isEmpty) return null;
    final filed = filing(store).of(facts.thread);
    if (filed != null) {
      if (filed == Filing.main) return null;
      for (final s in sections) {
        if (s.id == filed) return s;
      }
    }
    return _taker(facts, tags, store, sections);
  }

  /// Files a conversation in [section] (null: the main list), to stay there. Where that is where the sections would
  /// put it anyway, what was filed is forgotten and they decide again from then on.
  void move(MessageFacts facts, TagSet tags, String? section, PluginStore store) {
    final byRules = _taker(facts, tags, store, sections(store))?.id;
    final filed = filing(store);
    final next = filed._with(facts.thread, byRules == section ? null : (section ?? Filing.main));
    store.write(Filing.key, next._encode());
  }

  /// How a section draws a conversation of its own, or null for the main list's row.
  RowLook? look(PluginSection s, MessageFacts facts, TagSet tags, PluginStore store) {
    final row = s.section.row;
    return row == null ? null : _ask(s.plugin, null, () => row(facts, tags, prefsOf(s.plugin, store)));
  }

  // --- (c) slots ----------------------------------------------------------------------------------------------------

  /// What the plugins that are on have to press at [slot], each with the plugin whose it is.
  List<BoundAction> actions<P>(ActionSlot<P> slot, P place, PluginStore store) {
    final out = <BoundAction>[];
    for (final e in _on(store)) {
      for (final fill in e.slots) {
        if (fill is! ActionFill<P> || fill.slot.name != slot.name) continue;
        for (final action in _ask(e.plugin, const <PluginAction>[], () => fill.build(place, prefsOf(e.plugin, store)))) {
          out.add(BoundAction(e.plugin, action));
        }
      }
    }
    return out;
  }

  /// The widgets the plugins that are on put at [slot]; those of [only] alone, where given.
  List<Widget> widgets<P>(WidgetSlot<P> slot, BuildContext context, P place, PluginStore store, {GhostPlugin? only}) {
    final out = <Widget>[];
    for (final e in _on(store)) {
      if (only != null && !identical(only, e.plugin)) continue;
      for (final fill in e.slots) {
        if (fill is! WidgetFill<P> || fill.slot.name != slot.name) continue;
        out.addAll(_ask(e.plugin, const <Widget>[], () => fill.build(context, place, prefsOf(e.plugin, store))));
      }
    }
    return out;
  }

  // --- (d) messages that have just come -----------------------------------------------------------------------------

  /// What the plugins that are on ask for of a conversation whose newest message has just come.
  List<BoundIncoming> incoming(MessageFacts facts, TagSet tags, PluginStore store) {
    final out = <BoundIncoming>[];
    String? section;
    var placed = false;
    for (final e in _on(store)) {
      if (e.incoming.isEmpty) continue;
      if (!placed) {
        section = sectionOf(facts, tags, store)?.id;
        placed = true;
      }
      for (final rule in e.incoming) {
        for (final action in _ask(e.plugin, const <IncomingAction>[], () => rule(facts, tags, section, prefsOf(e.plugin, store)))) {
          out.add(BoundIncoming(e.plugin, action));
        }
      }
    }
    return out;
  }
}
