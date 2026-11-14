/// What a conversation's screen asks the plugins for, ready to put in place: the buttons for its header, the buttons
/// for its composer's row, and the lines for a message's menu. The three slots are defined in plugin.dart and
/// answered here; lib/ui/thread.dart does not ask yet (it is being worked on elsewhere), and each is one line when
/// it does:
///
///     actions: [...plugins.header(context, newest: _messages?.firstOrNull), IconTap(icon: Lucide.phone, …)],
///     ...plugins.composer(context, text: _text.text),            // beside Stickers
///     final choices = [..., ...plugins.message(context, m)];     // in _messageMenu
///
/// with `late final plugins = ConversationPlugins(thread: widget.thread, people: () => _people, write: …)`.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../sms.dart';
import '../ui/common.dart';
import 'list.dart' show PluginEffects, SmsEffects;
import 'plugin.dart';
import 'registry.dart';

class ConversationPlugins {
  ConversationPlugins({required this.thread, required this.people, this.write, this.open, PluginRegistry? registry, this.effects = const SmsEffects()}) : registry = registry ?? PluginRegistry.instance;

  final int thread;

  /// The conversation's other people, as the screen holds them now.
  final List<Person> Function() people;

  /// Writes into the message being written; null where the screen has no composer.
  final void Function(String text)? write;

  /// Opens another conversation by its number; null where the screen cannot.
  final void Function(int thread)? open;
  final PluginRegistry registry;
  final PluginEffects effects;

  MessageFacts _conversation(Message? newest) {
    final all = people();
    if (newest != null) {
      final facts = MessageFacts.message(newest, thread: thread, people: all);
      // The conversation's facts, with its newest message's words: everyone in it, not that message's sender alone.
      return MessageFacts(thread: thread, senders: [for (final p in all) p.address], text: facts.text, contact: all.any((p) => p.name != null && p.name!.isNotEmpty), group: all.length > 1, date: facts.date, outgoing: facts.outgoing);
    }
    return MessageFacts(thread: thread, senders: [for (final p in all) p.address], text: '', contact: all.any((p) => p.name != null && p.name!.isNotEmpty), group: all.length > 1);
  }

  /// The plugins' buttons for the header, to go before Call. [newest] is the conversation's newest message, where
  /// there is one: its words are what the conversation is known by.
  List<Widget> header(BuildContext context, {Message? newest}) {
    final store = AppStore(AppState.of(context));
    final facts = _conversation(newest);
    final tags = registry.classify(facts, store);
    final place = ConversationPlace(facts, tags, section: registry.sectionOf(facts, tags, store)?.id);
    return [
      for (final b in registry.actions(Slots.conversationHeader, place, store))
        IconTap(icon: b.action.icon, label: b.action.label, onPressed: () => b.action.run(_Host(this, b.plugin, context, facts, tags))),
    ];
  }

  /// The plugins' buttons for the composer's row, sized as Stickers and the microphone are. [text] is what is
  /// written so far.
  List<Widget> composer(BuildContext context, {String text = ''}) {
    final t = context.tokens;
    final store = AppStore(AppState.of(context));
    final facts = _conversation(null);
    return [
      for (final b in registry.actions(Slots.composer, ComposerPlace(thread: thread, senders: facts.senders, text: text), store))
        IconTap(icon: b.action.icon, label: b.action.label, size: 19, box: t.lenOf('2.25rem'), color: t.color('app-ink-2'), onPressed: () => b.action.run(_Host(this, b.plugin, context, facts, TagSet.none))),
    ];
  }

  /// The plugins' lines for the menu a message's long press brings up.
  List<Choice> message(BuildContext context, Message m) {
    final store = AppStore(AppState.of(context));
    final facts = MessageFacts.message(m, thread: thread, people: people());
    final tags = registry.classify(facts, store);
    return [
      for (final b in registry.actions(Slots.messageMenu, MessagePlace(facts, tags), store))
        Choice(b.action.label, b.action.icon, () => b.action.run(_Host(this, b.plugin, context, facts, tags)), danger: b.action.danger),
    ];
  }
}

/// A conversation's side of the contract, for one plugin's action.
class _Host implements PluginHost {
  _Host(this.owner, this.plugin, this.context, this.facts, this.tags);
  final ConversationPlugins owner;
  final GhostPlugin plugin;
  final BuildContext context;
  final MessageFacts facts;
  final TagSet tags;

  PluginStore get _store => AppStore(AppState.of(context));

  @override
  PluginPrefs get prefs => owner.registry.prefsOf(plugin, _store);

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
  void open(int thread) => owner.open?.call(thread);

  @override
  Future<void> markRead(int thread) => owner.effects.markRead(thread);

  /// Files this conversation; another's is the list's to file, which has its facts.
  @override
  void move(int thread, String? section) {
    if (thread == facts.thread && context.mounted) owner.registry.move(facts, tags, section, _store);
  }

  @override
  void write(String text) => owner.write?.call(text);
}
