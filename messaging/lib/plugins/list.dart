/// What the list of conversations (lib/ui/conversations.dart) keeps of the plugins, so that the screen has a few
/// lines of them and no more: the conversations' tags (tag_store.dart), which section each is in, the chips, a
/// section's rows, what fills the list's slots, and the rules run on a message that has just come.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../sms.dart';
import '../ui/common.dart';
import 'plugin.dart';
import 'registry.dart';
import 'tag_store.dart';
import 'ui.dart';

export 'plugin.dart' show ListPlace;
export 'ui.dart' show PluginRow;

/// What the plugins' side does to the phone's messages: asked of Android in the app, counted in a test.
abstract interface class PluginEffects {
  Future<void> markRead(int thread);
  Future<void> mute(int thread, bool muted);
}

class SmsEffects implements PluginEffects {
  const SmsEffects();

  @override
  Future<void> markRead(int thread) => Sms.instance.markRead(thread);

  @override
  Future<void> mute(int thread, bool muted) => Sms.instance.threadFlag('muted', thread, muted);
}

/// The conversations that are not archived, by section: which section each one is in, the sections that have any
/// (in the order they are asked), how many each has, and which have something unread.
@immutable
class Sorted {
  const Sorted(this.at, this.sections, this.counts, this.unread);
  static const none = Sorted({}, [], {}, {});

  final Map<int, PluginSection> at;
  final List<PluginSection> sections;
  final Map<String, int> counts;
  final Set<String> unread;

  bool has(String? section) => section != null && counts.containsKey(section);
}

class ListPlugins {
  ListPlugins({required this.changed, required this.open, required this.refresh, PluginRegistry? registry, this.effects = const SmsEffects()}) : registry = registry ?? PluginRegistry.instance {
    tags = TagStore(this.registry, onTagged: _arrived)..addListener(changed);
    this.registry.onError ??= (plugin, error) => Sms.instance.devLog('plugin', '${plugin.id}: ${'$error'.split('\n').first}');
  }

  /// TagSet worked out between frames have changed which section some conversation is in: the list is drawn again.
  final VoidCallback changed;

  /// Opens a conversation of the list by its number.
  final void Function(int thread) open;

  /// Reads the list again: something was marked as read or muted.
  final Future<void> Function() refresh;
  final PluginRegistry registry;
  final PluginEffects effects;
  late final TagStore tags;

  PluginStore? _store;
  bool _gone = false;

  /// The person's choices, given each time the list is built.
  void bind(AppState app) {
    if (registry.isEmpty) return;
    final store = AppStore(app);
    _store = store;
    tags.bind(store);
  }

  /// Conversations that have just been read, the newest first, before they are drawn.
  void take(Iterable<Conversation> fresh) {
    if (!registry.isEmpty) tags.take(fresh);
  }

  void dispose() {
    _gone = true;
    tags.dispose();
  }

  // --- which section each conversation is in ------------------------------------------------------------------------

  List<Conversation>? _sortedOf;
  int _sortedTags = -1;
  int _sortedStamp = -1;
  Sorted _sorted = Sorted.none;

  /// Sorts [all] into sections. Worked out again only when the list, some conversation's tags or a plugin's choices
  /// have changed.
  Sorted sort(List<Conversation>? all) {
    final store = _store;
    if (store == null || all == null) return _sorted = Sorted.none;
    if (identical(all, _sortedOf) && _sortedTags == tags.version && _sortedStamp == store.stamp) return _sorted;
    _sortedOf = all;
    _sortedTags = tags.version;
    _sortedStamp = store.stamp;
    final sections = registry.sections(store);
    // With no section there is nothing to sort, unless a plugin that is now off left conversations muted.
    if (sections.isEmpty && store.read(mutedKey) == null) return _sorted = Sorted.none;
    final at = <int, PluginSection>{};
    final counts = <String, int>{};
    final unread = <String>{};
    final listed = <int>{};
    for (final c in all) {
      if (c.archived) continue;
      final facts = tags.facts(c.id);
      if (facts == null) continue;
      listed.add(c.id);
      final s = registry.sectionOf(facts, tags.of(c.id), store, among: sections);
      if (s == null) continue;
      at[c.id] = s;
      counts[s.id] = (counts[s.id] ?? 0) + 1;
      if (c.unread) unread.add(s.id);
    }
    _settle(at, listed);
    return _sorted = Sorted(at, [for (final s in sections) if (counts.containsKey(s.id)) s], counts, unread);
  }

  /// The conversations of [all] that the chosen tab shows: a section's own, or the main list without the ones a
  /// section has taken out of it. A search from the main list looks through all of them.
  List<Conversation> pick(List<Conversation> all, String? section, {required bool searching}) {
    final at = _sorted.at;
    if (at.isEmpty) return all;
    if (section != null) return [for (final c in all) if (at[c.id]?.id == section) c];
    if (searching) return all;
    return [for (final c in all) if (at[c.id]?.section.leavesMain != true) c];
  }

  // --- what the screen draws ----------------------------------------------------------------------------------------

  /// The chips under the search field, or null while no section has a conversation in it.
  Widget? chips(String? chosen, ValueChanged<String?> onPick) {
    final s = _sorted;
    if (s.sections.isEmpty) return null;
    return SectionChips(sections: s.sections, counts: s.counts, unread: s.unread, chosen: chosen, onPick: onPick);
  }

  ConversationPlace _place(Conversation c) => ConversationPlace(MessageFacts.conversation(c), tags.of(c.id), section: _sorted.at[c.id]?.id);

  /// How [c]'s section draws it, with the host its actions are run with; null where it is drawn as the main list
  /// draws it.
  (RowLook, PluginHost)? look(BuildContext context, Conversation c) {
    final store = _store;
    final s = _sorted.at[c.id];
    if (store == null || s == null) return null;
    final look = registry.look(s, MessageFacts.conversation(c), tags.of(c.id), store);
    return look == null ? null : (look, _Host(this, s.plugin, context));
  }

  /// The lines the plugins add to the menu a conversation's long press brings up.
  List<Choice> menu(BuildContext context, Conversation c) {
    final store = _store;
    if (store == null) return const [];
    return [
      for (final b in registry.actions(Slots.conversationMenu, _place(c), store))
        Choice(b.action.label, b.action.icon, () => b.action.run(_Host(this, b.plugin, context)), danger: b.action.danger),
    ];
  }

  /// The buttons the plugins add to the list's header.
  List<Widget> header(BuildContext context, ListPlace place) {
    final store = _store;
    if (store == null) return const [];
    return [
      for (final b in registry.actions(Slots.listHeader, place, store))
        IconTap(icon: b.action.icon, label: b.action.label, onPressed: () => b.action.run(_Host(this, b.plugin, context))),
    ];
  }

  /// What the plugins put between the search field and the list.
  List<Widget> above(BuildContext context, ListPlace place) {
    final store = _store;
    return store == null ? const [] : registry.widgets(Slots.aboveList, context, place, store);
  }

  // --- a message that has just come ---------------------------------------------------------------------------------

  /// The conversations a plugin's rule has muted, kept in one choice as `thread:plugin:section`: a mute a plugin
  /// asked for lasts while the plugin is on and the conversation is in the section it was muted in.
  static const mutedKey = 'plugins_muted';

  Future<void> _queue = Future<void>.value();

  /// A conversation has been classified. Where it is unread, its newest message has just come (or came while the app
  /// was closed): the plugins' rules are asked what to do with it. On a computer the phone decides.
  void _arrived(MessageFacts facts, TagSet tags) {
    final store = _store;
    if (!facts.unread || store == null || Sms.remote) return;
    final asked = registry.incoming(facts, tags, store);
    if (asked.isEmpty) return;
    // After the frame that is being built, one conversation at a time.
    _queue = _queue.then((_) => _apply(facts, tags, asked, store)).catchError((_) {});
  }

  Future<void> _apply(MessageFacts facts, TagSet tags, List<BoundIncoming> asked, PluginStore store) async {
    if (_gone) return;
    var reread = false;
    for (final b in asked) {
      switch (b.action) {
        case MarkRead():
          await effects.markRead(facts.thread);
          reread = true;
        case MuteNotification():
          if (facts.muted || _muted(store).any((m) => m.$1 == facts.thread)) break;
          await effects.mute(facts.thread, true);
          final section = registry.sectionOf(facts, tags, store)?.id ?? Filing.main;
          _setMuted(store, [..._muted(store), (facts.thread, b.plugin.id, section)]);
          reread = true;
        case MoveToSection(:final section):
          registry.move(facts, tags, section, store);
      }
    }
    if (reread && !_gone) await refresh();
  }

  List<(int, String, String)> _muted(PluginStore store) {
    final raw = store.read(mutedKey);
    if (raw == null) return const [];
    final out = <(int, String, String)>[];
    for (final part in raw.split(',')) {
      final bits = part.split(':');
      final thread = int.tryParse(bits.first);
      if (thread != null && bits.length == 3) out.add((thread, bits[1], bits[2]));
    }
    return out;
  }

  void _setMuted(PluginStore store, List<(int, String, String)> muted) => store.write(mutedKey, [for (final m in muted) '${m.$1}:${m.$2}:${m.$3}'].join(','));

  /// A conversation a plugin muted is given its notifications back once that plugin is off or the conversation has
  /// left the section it was muted in ("Not spam"). [listed] are the conversations the list holds that are not
  /// archived: one that is archived, or not read yet (an older one, on a phone with thousands), is left as it is.
  void _settle(Map<int, PluginSection> at, Set<int> listed) {
    final store = _store;
    if (store == null || Sms.remote) return;
    final muted = _muted(store);
    if (muted.isEmpty) return;
    final on = {for (final p in registry.plugins) if (registry.isOn(p, store)) p.id};
    final undo = [
      for (final m in muted)
        if (listed.contains(m.$1) && (!on.contains(m.$2) || (at[m.$1]?.id ?? Filing.main) != m.$3)) m,
    ];
    if (undo.isEmpty) return;
    _queue = _queue.then((_) async {
      if (_gone) return;
      _setMuted(store, [for (final m in _muted(store)) if (!undo.contains(m)) m]);
      for (final m in undo) {
        await effects.mute(m.$1, false);
      }
      if (!_gone) await refresh();
    }).catchError((_) {});
  }
}

/// The list's side of the contract, for one plugin's action.
class _Host implements PluginHost {
  _Host(this.list, this.plugin, this.context);
  final ListPlugins list;
  final GhostPlugin plugin;
  final BuildContext context;

  @override
  PluginPrefs get prefs => list.registry.prefsOf(plugin, list._store!);

  @override
  void say(String words) {
    if (context.mounted) toast(context, words);
  }

  @override
  void copy(String text, {String? say}) {
    Clipboard.setData(ClipboardData(text: text));
    if (say != null) this.say(say);
  }

  @override
  void open(int thread) => list.open(thread);

  @override
  Future<void> markRead(int thread) async {
    await list.effects.markRead(thread);
    if (!list._gone) await list.refresh();
  }

  @override
  void move(int thread, String? section) {
    final facts = list.tags.facts(thread);
    if (facts != null) list.registry.move(facts, list.tags.of(thread), section, list._store!);
  }

  /// The list has nothing being written.
  @override
  void write(String text) {}
}
