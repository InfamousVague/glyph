/// Ghost Messaging's plugins: the contract (Matt, 2026-11-14: "prime the whole app to have plugin support for placing
/// UI elements and doing things like filtering out spam messages separating OTPs into their own section and more").
///
/// A plugin is a [GhostPlugin]: an id, a name, a line saying what it does and a switch (Settings › Plugins, kept
/// with the person's other choices). Switched off it adds nothing. Switched on it adds through four kinds of
/// extension point, each a plain value the app asks for and draws or acts on itself:
///
/// - [Classifier]: given a conversation or a message as [MessageFacts], the [Tag]s it deserves (`code`, `spam`).
/// - [ListSection]: a section of the list of conversations with a chip of its own, which takes the conversations
///   it wants out of the main list and says how its rows look ([RowLook]).
/// - [Slot]: a named place on a screen ([Slots]) for buttons and menu items ([PluginAction]) or widgets.
/// - [IncomingRule]: what to do with a message that has just come ([IncomingAction]).
///
/// A screen asks the registry (registry.dart) what its plugins have for a place and draws that; a plugin is handed
/// facts and a [PluginHost] to ask things of, never a screen or its state. All but the widget slots is data in and
/// data out ([MessageFacts.toJson] is the shape of the data in), so that a plugin loaded from outside the app one
/// day, a script or a package, could meet the same contract: the README says what that would still need.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../sms.dart';

// --- what a plugin is shown ------------------------------------------------------------------------------------------

/// A conversation by its last words, or one message, as a plugin is shown it: who it is from, what it says, and
/// whether the phone's contacts know them.
@immutable
class MessageFacts {
  const MessageFacts({required this.thread, required this.senders, required this.text, required this.contact, this.group = false, this.date, this.unread = false, this.muted = false, this.outgoing});

  /// The conversation it is, or is in.
  final int thread;

  /// The numbers (or email addresses) of the other people in the conversation; of the one who sent it, for a
  /// message.
  final List<String> senders;
  final String text;

  /// One of [senders] is in the phone's contacts.
  final bool contact;

  /// The conversation has more than one other person in it.
  final bool group;
  final DateTime? date;
  final bool unread;

  /// The conversation is muted: its messages arrive without a notification.
  final bool muted;

  /// Whether the words are the person's own. Null where that is not known: the list of conversations holds a
  /// conversation's last words, not whose they are.
  final bool? outgoing;

  /// A conversation as the list holds it: its people and its last words.
  factory MessageFacts.conversation(Conversation c) => MessageFacts(
        thread: c.id,
        senders: [for (final p in c.people) p.address],
        text: c.snippet,
        contact: c.people.any(_known),
        group: c.group,
        date: c.date,
        unread: c.unread,
        muted: c.muted,
      );

  /// One message of the conversation [thread], whose other people are [people].
  factory MessageFacts.message(Message m, {required int thread, required List<Person> people}) {
    final from = m.outgoing ? const <Person>[] : [for (final p in people) if (p.address == m.address) p];
    final sender = from.isNotEmpty ? from : (people.length == 1 ? people : const <Person>[]);
    return MessageFacts(
      thread: thread,
      senders: m.outgoing || m.address.isEmpty ? [for (final p in people) p.address] : [m.address],
      text: m.body,
      contact: sender.any(_known),
      group: people.length > 1,
      date: m.date,
      outgoing: m.outgoing,
    );
  }

  static bool _known(Person p) => p.name != null && p.name!.isNotEmpty;

  /// The same as plain values: what a plugin that is not compiled into the app would be handed.
  Map<String, Object?> toJson() => {
        'thread': thread,
        'senders': senders,
        'text': text,
        'contact': contact,
        'group': group,
        'date': date?.millisecondsSinceEpoch,
        'unread': unread,
        'muted': muted,
        'outgoing': outgoing,
      };
}

/// What a classifier found: a name (`code`, `spam`) and what it has to say with it (the code itself, why the text
/// reads as spam).
@immutable
class Tag {
  const Tag(this.name, [this.detail]);
  final String name;
  final String? detail;

  @override
  String toString() => detail == null ? name : '$name ($detail)';
}

/// The tags every classifier gave one conversation or message. Where two give the same name, the first is kept.
@immutable
class TagSet {
  const TagSet._(this._found);

  factory TagSet(Iterable<Tag> found) {
    final by = <String, String?>{};
    for (final tag in found) {
      by.putIfAbsent(tag.name, () => tag.detail);
    }
    return by.isEmpty ? none : TagSet._(by);
  }

  static const none = TagSet._({});

  final Map<String, String?> _found;

  bool has(String name) => _found.containsKey(name);
  String? detail(String name) => _found[name];
  Iterable<String> get names => _found.keys;
  bool get isEmpty => _found.isEmpty;

  /// The same names with the same details.
  bool same(TagSet other) {
    if (_found.length != other._found.length) return false;
    for (final e in _found.entries) {
      if (!other._found.containsKey(e.key) || other._found[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  String toString() => _found.isEmpty ? 'no tags' : [for (final e in _found.entries) Tag(e.key, e.value)].join(', ');
}

// --- (a) classifiers -------------------------------------------------------------------------------------------------

/// Says which tags a conversation or a message deserves. It is asked once for each and the answer is kept until the
/// words change (registry.dart, [TagStore]), so it must be cheap, must answer the same for the same facts, and is
/// given none of the person's choices: what depends on a choice belongs in [ListSection.takes], which is asked
/// every time.
typedef Classifier = List<Tag> Function(MessageFacts facts);

// --- what a plugin may ask of the app --------------------------------------------------------------------------------

/// A plugin's own choices, kept with the person's others under the plugin's name.
abstract interface class PluginPrefs {
  String? get(String key);
  void set(String key, String value);

  /// A switch: on unless it was switched off ([fallback] false: off unless switched on).
  bool flag(String key, {bool fallback = true});
  void setFlag(String key, bool on);
}

/// What a plugin's action is handed to do its work with: the app's side of the contract. A screen that draws a
/// slot or a section gives one; a plugin never sees the screen.
abstract interface class PluginHost {
  /// The choices of the plugin whose action this is.
  PluginPrefs get prefs;

  /// Says [words] to the person, briefly.
  void say(String words);

  /// Puts [text] on the clipboard, and says [say] where given.
  void copy(String text, {String? say});

  /// Opens the conversation [thread].
  void open(int thread);

  Future<void> markRead(int thread);

  /// Files the conversation [thread] in the section [section], or in the main list where that is null, and it
  /// stays there whatever the classifiers say of it afterwards.
  void move(int thread, String? section);

  /// Writes [text] into the message being written. Only a conversation's composer does anything with it.
  void write(String text);
}

/// Something a plugin offers to do: a button in a header or a composer, a line in a menu, a row's own button. The
/// app draws it as the place it is in draws such things, and calls [run] when it is chosen.
@immutable
class PluginAction {
  const PluginAction({required this.label, required this.icon, required this.run, this.danger = false});
  final String label;
  final LucideIcon icon;
  final FutureOr<void> Function(PluginHost host) run;

  /// Drawn in red: it deletes, or cannot be taken back.
  final bool danger;
}

// --- (b) sections of the list ----------------------------------------------------------------------------------------

/// How a section draws one of its conversations, where it is not as the main list does: said in words, and drawn by
/// the list (ui.dart, PluginRow).
@immutable
class RowLook {
  const RowLook({this.value, this.caption, this.end, this.word, this.tap});

  /// Drawn large where the last words would be, with the words small under it: a sign-in code.
  final String? value;

  /// A quiet line under the words: why the conversation is in this section.
  final String? caption;

  /// A button at the row's end.
  final PluginAction? end;

  /// A word to press after the caption.
  final PluginAction? word;

  /// What a tap on the row does, in place of opening the conversation (which its long press then offers).
  final PluginAction? tap;
}

/// A section of the list of conversations: a chip under the search field beside "Messages", and a list of its own
/// when the chip is chosen, the newest first. The chip is there only while the section has conversations.
@immutable
class ListSection {
  const ListSection({required this.id, required this.label, required this.icon, required this.takes, this.leavesMain = true, this.row});

  /// Its name among every plugin's sections, and what a conversation is filed under ([PluginHost.move]).
  final String id;

  /// What its chip says.
  final String label;
  final LucideIcon icon;

  /// Whether the conversation belongs here, by its facts, its tags and the plugin's choices. Asked of every
  /// conversation the classifiers have looked at, so it is a few comparisons and nothing more. A conversation the
  /// person filed somewhere themselves is not asked about. Where two sections would take one conversation, the
  /// first has it: sections are asked in the order their plugins are listed.
  final bool Function(MessageFacts facts, TagSet tags, PluginPrefs prefs) takes;

  /// Its conversations leave the main list. False: they are shown in both.
  final bool leavesMain;

  /// How its rows look; null (or answering null) draws them as the main list does.
  final RowLook? Function(MessageFacts facts, TagSet tags, PluginPrefs prefs)? row;
}

// --- (c) places on the screens ---------------------------------------------------------------------------------------

/// A named place on a screen where plugins can put something. [P] is what the screen says about the place.
sealed class Slot<P> {
  const Slot(this.name);
  final String name;
}

/// A place for things to press: the app draws each [PluginAction] as that place draws its own (an icon in a header,
/// a line in a menu).
final class ActionSlot<P> extends Slot<P> {
  const ActionSlot(super.name);

  /// What a plugin puts here: asked each time the place is drawn, with where it is and the plugin's choices.
  SlotFill fill(List<PluginAction> Function(P place, PluginPrefs prefs) actions) => ActionFill<P>._(this, actions);
}

/// A place for widgets of the plugin's own.
final class WidgetSlot<P> extends Slot<P> {
  const WidgetSlot(super.name);

  SlotFill fill(List<Widget> Function(BuildContext context, P place, PluginPrefs prefs) widgets) => WidgetFill<P>._(this, widgets);
}

/// One plugin's contribution to one slot ([ActionSlot.fill], [WidgetSlot.fill]).
sealed class SlotFill {
  const SlotFill();
  Slot<Object?> get slot;
}

final class ActionFill<P> extends SlotFill {
  const ActionFill._(this.slot, this.build);
  @override
  final ActionSlot<P> slot;
  final List<PluginAction> Function(P place, PluginPrefs prefs) build;
}

final class WidgetFill<P> extends SlotFill {
  const WidgetFill._(this.slot, this.build);
  @override
  final WidgetSlot<P> slot;
  final List<Widget> Function(BuildContext context, P place, PluginPrefs prefs) build;
}

/// The list of conversations: the section whose chip is chosen (null: the main list) and how many it shows.
@immutable
class ListPlace {
  const ListPlace({this.section, this.shown = 0});
  final String? section;
  final int shown;
}

/// One conversation: its facts, its tags, and the section it is in (null: the main list).
@immutable
class ConversationPlace {
  const ConversationPlace(this.facts, this.tags, {this.section});
  final MessageFacts facts;
  final TagSet tags;
  final String? section;
}

/// The composer of a conversation: who it writes to, and what is written so far.
@immutable
class ComposerPlace {
  const ComposerPlace({required this.thread, required this.senders, this.text = ''});
  final int thread;
  final List<String> senders;
  final String text;
}

/// One message in a conversation.
@immutable
class MessagePlace {
  const MessagePlace(this.facts, this.tags);
  final MessageFacts facts;
  final TagSet tags;
}

/// A plugin's own card on Settings › Plugins.
@immutable
class SettingsPlace {
  const SettingsPlace();
}

/// Every place there is. The ones in the list of conversations and in Settings are drawn (lib/ui/conversations.dart,
/// settings.dart here); the ones in a conversation are defined and wait for lib/ui/thread.dart to ask for them.
abstract final class Slots {
  /// Buttons in the list's header, before New message.
  static const listHeader = ActionSlot<ListPlace>('list.header');

  /// Between the search field and the list.
  static const aboveList = WidgetSlot<ListPlace>('list.above');

  /// Lines in the menu a conversation's long press brings up in the list.
  static const conversationMenu = ActionSlot<ConversationPlace>('list.conversation.menu');

  /// Buttons in a conversation's header, before Call.
  static const conversationHeader = ActionSlot<ConversationPlace>('conversation.header');

  /// Buttons in the composer's row, beside Stickers.
  static const composer = ActionSlot<ComposerPlace>('conversation.composer');

  /// Lines in the menu a message's long press brings up.
  static const messageMenu = ActionSlot<MessagePlace>('conversation.message.menu');

  /// Rows in the plugin's own card on Settings › Plugins, after its [GhostPlugin.settings].
  static const settings = WidgetSlot<SettingsPlace>('settings.plugin');

  static const List<Slot<Object?>> all = [listHeader, aboveList, conversationMenu, conversationHeader, composer, messageMenu, settings];
}

// --- (d) messages that have just come --------------------------------------------------------------------------------

/// What a plugin asks for when a message has just come.
sealed class IncomingAction {
  const IncomingAction();
}

/// The conversation is muted: what comes in it next arrives without a notification.
final class MuteNotification extends IncomingAction {
  const MuteNotification();
}

/// The conversation is marked as read, and its notification taken away.
final class MarkRead extends IncomingAction {
  const MarkRead();
}

/// The conversation is filed in [section], and stays there.
final class MoveToSection extends IncomingAction {
  const MoveToSection(this.section);
  final String section;
}

/// Asked once for each unread conversation as its newest message is first seen: its facts, its tags, the section it
/// is in (null: the main list) and the plugin's choices. It is decided here, in Dart, while the app is open: see
/// the README for what Android's side would have to do for it to hold while the app is closed.
typedef IncomingRule = List<IncomingAction> Function(MessageFacts facts, TagSet tags, String? section, PluginPrefs prefs);

// --- a plugin's own settings -----------------------------------------------------------------------------------------

/// One row of a plugin's card on Settings › Plugins, said in words: a switch kept in the plugin's choices, or a line
/// that explains. Anything else is a widget in [Slots.settings].
@immutable
class PluginSetting {
  /// A switch, kept under [key] in the plugin's choices.
  const PluginSetting.toggle({required String this.key, required this.label, this.hint, this.fallback = true, this.icon});

  /// A line that says something and changes nothing.
  const PluginSetting.note({required this.label, this.hint, this.icon})
      : key = null,
        fallback = false;

  final String? key;
  final String label;
  final String? hint;
  final bool fallback;
  final LucideIcon? icon;
}

// --- the plugin ------------------------------------------------------------------------------------------------------

/// A plugin. The ones the app ships with are compiled in and listed in registry.dart.
abstract class GhostPlugin {
  const GhostPlugin();

  /// Its name in the person's choices (`plugin_<id>`) and nowhere on the screen: lower-case letters and digits.
  String get id;

  /// What Settings › Plugins calls it.
  String get name;

  /// One line saying what it does.
  String get description;

  LucideIcon get icon => Lucide.puzzle;

  /// Whether it is on until the person says otherwise. One that hides messages should be chosen: off.
  bool get onByDefault => true;

  List<Classifier> get classifiers => const [];
  List<ListSection> get sections => const [];
  List<SlotFill> get slots => const [];
  List<IncomingRule> get incoming => const [];
  List<PluginSetting> get settings => const [];
}
