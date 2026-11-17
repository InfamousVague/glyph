import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../kept_lists.dart';
import 'bluesky.dart';
import 'google_chat.dart';
import 'mastodon.dart';
import 'matrix.dart';
import 'signal.dart';
import 'teams.dart';
import 'whatsapp.dart';
import 'telegram.dart';

/// Direct messages from other networks, read and answered in Ghost (Matt, 2026-11-15: "Let's build in telegram and
/// bluesky for now, since we can't send outbound messages anything without the ability to back and forth is
/// useless"). docs/other-apps-dms.md says why these two: each offers a real client API, read and write, that a
/// third-party app may use. Every network runs on this device and talks to its own servers: nothing about it goes
/// through ghost-sms.com.
///
/// A network is one of [InboxNetwork]; the list shows each signed-in one as a tab of its own (lib/ui/conversations.dart)
/// and its chats open in lib/ui/inbox_ui.dart.

/// Where a network stands.
enum InboxState {
  /// This build cannot run it (Telegram without its app id, or without its library on this computer).
  unavailable,

  /// Not signed in.
  signedOut,

  /// Partway through signing in: [InboxNetwork.step] says what it waits for.
  signingIn,

  /// Signed in, and its chats arriving.
  ready,
}

/// What a sign-in waits for next.
/// [elsewhere]: waiting for another device signed in to the account to approve this one (Telegram's login link).
enum InboxStep { none, phone, code, password, credentials, elsewhere }

/// A conversation on another network.
@immutable
class InboxChat {
  const InboxChat({
    required this.network,
    required this.id,
    required this.title,
    required this.date,
    this.snippet = '',
    this.unread = 0,
    this.group = false,
    this.avatar,
    this.lastFromMe = false,
    this.pinned = false,
    this.service = false,
    this.stranger = false,
    this.cold = false,
    this.flag,
    this.muted = false,
  });

  /// [InboxNetwork.id] of the network it is on.
  final String network;

  /// The network's own name for it.
  final String id;
  final String title;
  final DateTime date;
  final String snippet;
  final int unread;
  final bool group;

  /// The address of its picture, where the network gives one.
  final String? avatar;

  /// The last message was this account's.
  final bool lastFromMe;

  /// Pinned at the top of the network's own list.
  final bool pinned;

  /// The network's own account or a bot, not a person: where sign-in codes come from (Telegram's 777000).
  final bool service;

  /// Someone not in this account's contacts wrote first (Telegram's "Report spam" bar): spam is looked for (scams.dart).
  final bool stranger;

  /// A stranger wrote and this account never answered: Telegram still offers to report them (its action bar).
  final bool cold;

  /// What the network itself says of the account, where it marks it ("Telegram marks this account as a scam").
  final String? flag;

  /// Muted on the network itself (Telegram's own mute): no notification from Ghost either (lib/inbox/alerts.dart).
  final bool muted;

  InboxChat copyWith({String? title, DateTime? date, String? snippet, int? unread, String? avatar, bool? lastFromMe}) => InboxChat(
        network: network,
        id: id,
        title: title ?? this.title,
        date: date ?? this.date,
        snippet: snippet ?? this.snippet,
        unread: unread ?? this.unread,
        group: group,
        avatar: avatar ?? this.avatar,
        lastFromMe: lastFromMe ?? this.lastFromMe,
        pinned: pinned,
        service: service,
        stranger: stranger,
        cold: cold,
        flag: flag,
        muted: muted,
      );
}

/// A message in an [InboxChat].
/// A picture, video, sound or file in an [InboxMessage] (Matt, 2026-11-15: "Is it possible to send and receive
/// attachments through telegram too?"). [path] is the file on this device once the network has brought it down
/// ([InboxNetwork.fileOf]); [thumbPath] a small picture of a video, where it has one.
@immutable
class InboxMedia {
  const InboxMedia({required this.kind, required this.fileId, this.path, this.name, this.size = 0, this.width = 0, this.height = 0, this.duration = 0, this.thumbId, this.thumbPath});

  /// "photo", "video", "audio" or "file".
  final String kind;
  final int fileId;
  final String? path;
  final String? name;
  final int size, width, height;

  /// Seconds, for a video or a sound.
  final int duration;
  final int? thumbId;
  final String? thumbPath;

  InboxMedia withPath(int file, String path) => InboxMedia(
        kind: kind, fileId: fileId, path: file == fileId ? path : this.path, name: name, size: size, width: width, height: height,
        duration: duration, thumbId: thumbId, thumbPath: file == thumbId ? path : thumbPath);
}

/// One kind of reaction on a message: the emoji, how many gave it, and whether you are one of them.
@immutable
class InboxReaction {
  const InboxReaction({required this.emoji, this.count = 1, this.mine = false});
  final String emoji;
  final int count;
  final bool mine;
}

@immutable
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.text,
    required this.date,
    required this.mine,
    this.sender = '',
    this.state = 'sent',
    this.media = const [],
    this.reactions = const [],
    this.replyTo,
    this.replyText,
    this.replySender,
    this.event = false,
    this.edited = false,
    this.versions = const [],
  });
  final String id;

  /// Changed by whoever wrote it since it was sent (Matt, 2026-11-17: "Add support for edited messages on telegram and
  /// signal and the ability to see the original message"), and what it said before, the first first: [original] is
  /// what was sent. Empty where it was edited before this device saw it: the network keeps no earlier words.
  final bool edited;
  final List<String> versions;
  String? get original => versions.isEmpty ? null : versions.first;

  /// Something that happened in the chat rather than something someone said ("Esther joined the group", a pin, a new
  /// name): drawn as a small line across the middle, not a bubble, as the network's own app does.
  final bool event;

  /// Its reactions, a kind each (Matt, 2026-11-17: "Id like to be able to reply to messages as well as react to
  /// telegram and signal messages").
  final List<InboxReaction> reactions;

  /// The message it answers, by [id], and what that one said and who said it, where the network tells.
  final String? replyTo;
  final String? replyText;
  final String? replySender;
  final String text;
  final DateTime date;
  final bool mine;

  /// Its pictures, videos, sounds and files, where it has any.
  final List<InboxMedia> media;

  /// Who wrote it, where that is someone else in a group.
  final String sender;

  /// "sending", "sent" or "failed", for this account's own.
  final String state;
}

/// A network's client: signing in, its chats, a chat's messages, and sending.
/// Someone in a network's own contacts (Matt, 2026-11-16: "Show telegram and signal contacts when linked with icons to
/// show which each is and filters, where contacts can be messages on multiple platforms as which you like to use when
/// stating a conversation"). lib/inbox/people.dart puts them together with the phone's contacts, by number or name.
@immutable
class InboxContact {
  const InboxContact({required this.network, required this.id, required this.name, this.number, this.avatar, this.handle});

  /// [InboxNetwork.id] of the network they are on.
  final String network;

  /// The network's own name for them: Telegram's user id, Signal's ACI.
  final String id;
  final String name;

  /// Their phone number as the network has it (+1…), where it shares one.
  final String? number;

  /// Their picture on this device, once brought down.
  final String? avatar;

  /// A username, where they have one (Telegram's @name).
  final String? handle;
}

// --- a group's details, and changing them (Matt, 2026-11-16: "Add them to a drawer when pressing and holding on the
// group name add support for all supported featues") ----------------------------------------------------------------

/// What a network lets a group's details be changed in, at all. Whether this person may, in this group, is
/// [GroupDetails]'s to say.
enum GroupFeature { title, description, photo, timer, addPeople, removePeople, admins, announcementsOnly, editInfoRule, addPeopleRule, inviteLink, leave }

/// Someone in a group, or invited to it, or asking to join.
@immutable
class GroupPerson {
  const GroupPerson({required this.id, required this.name, this.number, this.admin = false, this.me = false, this.owner = false});

  /// The network's own name for them (Signal's ACI, Telegram's user id).
  final String id;
  final String name;
  final String? number;
  final bool admin;

  /// Who made the group, where the network says (Telegram's creator): no one can take their admin away.
  final bool owner;
  final bool me;
}

/// A group as its drawer shows it: what it is, who is in it, its rules, and what this person may change.
@immutable
class GroupDetails {
  const GroupDetails({
    required this.title,
    this.description = '',
    this.photo,
    this.timer = 0,
    this.people = const [],
    this.pending = const [],
    this.requesting = const [],
    this.admin = false,
    this.editInfoAdminsOnly = false,
    this.addPeopleAdminsOnly = false,
    this.announcementsOnly = false,
    this.inviteLink,
    required this.supports,
    this.canEditInfo = false,
    this.canAddPeople = false,
    this.canRemovePeople = false,
    this.canSetAdmins = false,
    this.canChangeRules = false,
  });

  final String title;
  final String description;

  /// The group's picture on this device, where there is one.
  final String? photo;

  /// Messages disappear after this many seconds; 0, never.
  final int timer;
  final List<GroupPerson> people;

  /// Invited, not yet joined; and asking to join.
  final List<GroupPerson> pending, requesting;

  /// This person is an admin.
  final bool admin;

  /// Only admins may change its name, picture, description and timer; only admins may add people; only admins may
  /// write.
  final bool editInfoAdminsOnly, addPeopleAdminsOnly, announcementsOnly;
  final String? inviteLink;
  final Set<GroupFeature> supports;

  /// What this person may do here, by the group's rules and their role.
  final bool canEditInfo, canAddPeople, canRemovePeople, canSetAdmins, canChangeRules;

  bool can(GroupFeature f) => supports.contains(f);
}

/// A change to a group: each field left null is left as it is.
@immutable
class GroupChange {
  const GroupChange({
    this.title,
    this.description,
    this.photo,
    this.timer,
    this.add = const [],
    this.remove = const [],
    this.admin = const [],
    this.unadmin = const [],
    this.announcementsOnly,
    this.editInfoAdminsOnly,
    this.addPeopleAdminsOnly,
    this.leave = false,
  });
  final String? title;
  final String? description;

  /// A picture's path for the group's new one; '' takes it away.
  final String? photo;

  /// Seconds; 0 turns disappearing messages off.
  final int? timer;
  final List<String> add, remove, admin, unadmin;
  final bool? announcementsOnly, editInfoAdminsOnly, addPeopleAdminsOnly;
  final bool leave;

  bool get isEmpty =>
      title == null && description == null && photo == null && timer == null && add.isEmpty && remove.isEmpty && admin.isEmpty && unadmin.isEmpty && announcementsOnly == null && editInfoAdminsOnly == null && addPeopleAdminsOnly == null && !leave;
}

/// The timers disappearing messages offer, as Signal's and Telegram's apps do: seconds and their words.
const disappearingTimers = <(int, String)>[(0, 'Off'), (30, '30 seconds'), (300, '5 minutes'), (3600, '1 hour'), (28800, '8 hours'), (86400, '1 day'), (604800, '1 week'), (2419200, '4 weeks')];

/// Whether someone is on a network now, or when they last were (Matt, 2026-11-17: "activity presence sensing for friends
/// and conacts on telegram and signal to be able to tell if a friend is online on a given plaform anywhere the users
/// avatar is shown"). Telegram says so; Signal keeps no such thing.
@immutable
class InboxPresence {
  const InboxPresence({required this.network, this.online = false, this.lastSeen, this.rough});

  /// What the network calls itself: "Telegram".
  final String network;
  final bool online;

  /// When they were last on, where the network says.
  final DateTime? lastSeen;

  /// Where they keep the time to themselves: "recently", "within a week", "within a month".
  final String? rough;

  /// "online", "last seen 5 min ago", "last seen recently"; null where nothing is known.
  String? words({DateTime? now}) {
    if (online) return 'online';
    final seen = lastSeen;
    if (seen != null) {
      final ago = (now ?? DateTime.now()).difference(seen);
      if (ago.inMinutes < 1) return 'last seen just now';
      if (ago.inMinutes < 60) return 'last seen ${ago.inMinutes} min ago';
      if (ago.inHours < 24) return 'last seen ${ago.inHours} h ago';
      if (ago.inDays < 7) return 'last seen ${ago.inDays} d ago';
      return 'last seen a long time ago';
    }
    return rough == null ? null : 'last seen $rough';
  }
}

/// Told when someone's presence changes, apart from a network's other changes: an avatar listens to this alone.
class PresenceChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

abstract class InboxNetwork extends ChangeNotifier {
  String get id;
  String get name;

  InboxState get state;
  InboxStep get step => InboxStep.none;

  /// Why the last thing asked of it failed, to show; null once something works.
  String? get error;

  /// Who is signed in (a handle or a name), once signed in.
  String? get account;

  /// The chats, the newest first.
  List<InboxChat> get chats;

  /// The messages of [chatId] that are held, the oldest first. [load] fetches them.
  List<InboxMessage> messagesOf(String chatId);

  /// Brings [chatId]'s recent messages (and, with [older], the ones before those held).
  Future<void> load(String chatId, {bool older = false});

  /// Sends [text] to [chatId]. It shows at once as "sending".
  Future<void> send(String chatId, String text);

  /// Marks [chatId] read, there as here.
  Future<void> markRead(String chatId);

  // --- archiving and deleting (Matt, 2026-11-15: "if possible proxy the archive and delete messages too, if we can't
  // actually delete telegram messages add them to a ignore or archive list") -------------------------------------------
  // A network that can do these itself does them there (Telegram's archive, its Delete); one that can't keeps them
  // in a list of Ghost's own on this device, so they are gone from here all the same.

  /// The chats the list shows: [chats] without those in Ghost's own lists (archived, deleted or blocked here).
  List<InboxChat> get shownChats {
    final gone = {...localList('archived'), ...localList('deleted'), ...localList('blocked')};
    return gone.isEmpty ? chats : [for (final c in chats) if (!gone.contains(c.id)) c];
  }

  /// The chats archived: the network's own archive, or Ghost's list for it.
  List<InboxChat> get archivedChats {
    final kept = localList('archived');
    return kept.isEmpty ? const [] : [for (final c in chats) if (kept.contains(c.id)) c];
  }

  /// Moves [chatId] into the archive, or out of it.
  Future<void> archive(String chatId, bool archived) async {
    setLocal('archived', chatId, archived);
    notifyListeners();
  }

  /// Deletes [chatId] for this account: there where the network allows it, else left out of Ghost from now on.
  Future<void> deleteChat(String chatId) async {
    setLocal('deleted', chatId, true);
    notifyListeners();
  }

  // --- blocking (Matt, 2026-11-17: "I'd like to be able to block signal and telegram users"; "add the signal helper
  // and do your recommendation. Make sure the UIs are unified across SMS Telegram and Signal") -------------------------
  // Blocked on the network itself where it can ([canBlock]: Telegram's own block, Signal's through the helper), and
  // always in Ghost's own list too, so they are gone from here at once and stay gone while the network is away.

  /// Whether this network blocks people itself (else Ghost's list is the whole of it).
  bool get canBlock => false;

  /// Whether the one-to-one chat [chatId] is with someone blocked.
  bool isBlocked(String chatId) => localList('blocked').contains(chatId);

  /// Everyone blocked, as Ghost knows them: [chatId] of the chat with them, and their name as it was.
  List<({String id, String name})> get blockedPeople {
    final names = _blockedNames;
    return [for (final id in localList('blocked')) (id: id, name: names[id] ?? id)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Map<String, String> get _blockedNames {
    try {
      return (jsonDecode(listStore?.choice('inbox_${id}_blocked_names', '{}') ?? '{}') as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  /// Blocks the person [chatId] is with, or unblocks them ([on] false): on the network where it can, then in Ghost's
  /// list. Throws with the network's reason where it refuses; Ghost's list is left as it was then.
  Future<void> block(String chatId, {required String name, bool on = true}) async {
    keepBlocked(chatId, name: name, on: on);
    notifyListeners();
  }

  /// Ghost's list alone: [chatId] in it or out, with the name to show.
  void keepBlocked(String chatId, {String? name, bool on = true}) {
    final names = _blockedNames;
    if (on && name != null && name.isNotEmpty) names[chatId] = name;
    if (!on) names.remove(chatId);
    listStore?.set('inbox_${id}_blocked_names', jsonEncode(names));
    setLocal('blocked', chatId, on);
  }

  /// Brings the network's own blocked list into Ghost's (someone blocked in the network's app shows here too). Nothing
  /// where the network keeps none.
  Future<void> refreshBlocked() async {}

  /// This account's own contacts on the network, once signed in; none where it keeps none.
  List<InboxContact> get contacts => const [];

  /// The chat with [contact], made where there is none yet; its id, or null where it can't be.
  Future<String?> chatWith(InboxContact contact) async => null;

  /// Whether files can be sent here: pictures, videos, voice messages and other files.
  bool get canSendFiles => false;

  /// Sends the files at [paths] to [chatId], [caption] with the last; [voice] for a recorded voice message.
  Future<void> sendFiles(String chatId, List<String> paths, {String caption = '', bool voice = false}) async =>
      throw UnsupportedError('$name can\'t send files here yet');

  /// The file [fileId] on this device, brought down first where it is not yet; null where it can't be.
  Future<String?> fileOf(int fileId) async => null;

  /// Asks for [fileId] to be brought down without waiting: a picture as its bubble is first drawn.
  void wantFile(int fileId) {}

  /// Pins [chatId] at the top, or unpins it: the network's own pin where it has one, else Ghost's list.
  Future<void> pin(String chatId, bool pinned) async {
    setLocal('pinned', chatId, pinned);
    notifyListeners();
  }

  /// Whether [chat] is pinned, by the network or in Ghost's list.
  bool isPinned(InboxChat chat) => chat.pinned || localList('pinned').contains(chat.id);

  /// Whether [message] can be deleted for everyone in the chat, not only for this account.
  bool canDeleteForEveryone(String chatId, InboxMessage message) => false;

  /// Deletes [messageId] in [chatId]: for this account, or for everyone where [forEveryone] and allowed.
  Future<void> deleteMessage(String chatId, String messageId, {bool forEveryone = false}) async {
    setLocal('deleted_msg_$chatId', messageId, true);
    notifyListeners();
  }

  /// [chatId]'s messages without those Ghost's own list leaves out.
  List<InboxMessage> shownMessages(String chatId) {
    final gone = localList('deleted_msg_$chatId');
    final all = messagesOf(chatId);
    return gone.isEmpty ? all : [for (final m in all) if (!gone.contains(m.id)) m];
  }

  /// Where Ghost's own lists are kept: the app's preferences on this device, given as the network starts.
  AppState? listStore;

  /// One of Ghost's own lists for this network ("archived", "deleted", "deleted_msg_<chat>").
  Set<String> localList(String what) => (listStore?.choice('inbox_${id}_$what', '') ?? '').split('\u001f').where((x) => x.isNotEmpty).toSet();

  void setLocal(String what, String item, bool on) {
    final s = localList(what);
    on ? s.add(item) : s.remove(item);
    listStore?.set('inbox_${id}_$what', s.join('\u001f'));
    KeptLists.instance.changed();
  }

  /// The chat opened in the app: kept fresh more often while it is shown. Null when none is.
  set watching(String? chatId);

  /// Starts what was signed in before, if anything.
  Future<void> start(AppState app);

  /// Signs out and forgets everything kept for it on this device.
  Future<void> signOut();

  /// Shown in Settings as "Coming soon", and never started: not offered yet.
  bool get soon => false;

  /// Reactions can be put on its messages ([react]), and which: the first few are offered in a row.
  bool get canReact => false;
  List<String> get reactionChoices => const ['❤️', '👍', '👎', '😂', '😮', '😢', '🙏', '🔥', '🎉'];

  /// Puts [emoji] on the message [messageId] of [chatId], or takes it off ([remove]). Throws with the network's reason.
  Future<void> react(String chatId, String messageId, String emoji, {bool remove = false}) => Future.error(UnsupportedError('$name reactions can\'t be sent from here'));

  /// A message can be answered with a reply that quotes it ([reply]).
  bool get canReply => false;

  /// Sends [text] to [chatId] as a reply to the message [messageId].
  Future<void> reply(String chatId, String messageId, String text) => send(chatId, text);

  /// Someone's presence on this network, by the network's id for them or for a chat with them alone; null where it
  /// keeps none, or knows none of them.
  InboxPresence? presenceOf(String id) => null;

  /// Someone's presence by their phone number (digits only), for a conversation of texts with them; null as above.
  InboxPresence? presenceOfNumber(String digits) => null;

  /// Told whenever someone's presence changes.
  final PresenceChanges presenceChanges = PresenceChanges();

  /// The group [chatId] in full, for its drawer; null where the network has no such thing or it is not a group.
  Future<GroupDetails?> groupDetails(String chatId) async => null;

  /// Makes [change] to the group [chatId] on the network itself, where everyone in it sees it, and answers with the
  /// group as it then is (null once you have left). Throws with the network's reason where it refuses.
  Future<GroupDetails?> changeGroup(String chatId, GroupChange change) => Future.error(UnsupportedError('$name groups can\'t be changed from here'));

  /// Unread chats.
  int get unreadChats => chats.where((c) => c.unread > 0).length;
}

/// The networks, as the app holds them.
class Inbox {
  Inbox._(this.networks);

  static Inbox? _instance;
  // Bluesky is built and tested, and offered later (Matt, 2026-11-15: "I don't have bluesky setup yet, set that to
  // "coming soon"").
  // Mastodon is built and tested, and offered later too (Matt, 2026-11-15: "Wire up mastadon and bluesky and have them
  // set as coming soon until we get the API keys setup").
  // Signal through mautrix-signal (Matt, 2026-11-15: "Lets wire it up for signal through the mautrix"), offered from
  // 0.7.40 (2026-11-16: "Add it to a release it's okay as long as our app bundle stays under 200mb").
  // Matrix through mautrix-go, encryption included (Matt, 2026-11-17: "Let's add support for matrix").
  // WhatsApp through whatsmeow, linked as WhatsApp Web is (Matt, 2026-11-17: "enable whatsapp but warn the user that
  // it's unsupported by whatsapp"): its sign-in and Settings say WhatsApp may ban accounts on unofficial apps.
  // Microsoft Teams over Microsoft Graph (Matt, 2026-11-17: "Let's add support for matrix, microsoft teams and google
  // chat"): "Not in this build" until it is built with a Microsoft app id (GHOST_TEAMS_CLIENT_ID). Google Chat the same, until
  // built with a Google app id (GHOST_GCHAT_CLIENT_ID and _SECRET).
  static Inbox get instance => _instance ??= Inbox._([Telegram(), Bluesky(soon: true), Mastodon(soon: true), Signal(), WhatsApp(), Matrix(), Teams(), GoogleChat()]);

  /// Stand-ins for a test of a screen; null puts the app's own back.
  @visibleForTesting
  static set instance(Inbox? i) => _instance = i;

  @visibleForTesting
  static Inbox of(List<InboxNetwork> networks) => Inbox._(networks);

  final List<InboxNetwork> networks;

  InboxNetwork? named(String id) {
    for (final n in networks) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Told whenever anyone's presence changes on any network.
  Listenable get presenceChanges => Listenable.merge([for (final n in networks) n.presenceChanges]);

  /// The presence of whoever [address] names: `<network>:<id>` (a chat or person on that network), or a phone number,
  /// looked for on every network signed in. Online anywhere wins; else the latest seen.
  InboxPresence? presenceOfAddress(String address) {
    final colon = address.indexOf(':');
    if (colon > 0) {
      final n = named(address.substring(0, colon));
      if (n != null) return n.state == InboxState.ready ? n.presenceOf(address.substring(colon + 1)) : null;
    }
    final digits = address.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return null;
    InboxPresence? best;
    for (final n in ready) {
      final p = n.presenceOfNumber(digits);
      if (p == null) continue;
      if (p.online) return p;
      if (best == null || (p.lastSeen != null && (best.lastSeen == null || p.lastSeen!.isAfter(best.lastSeen!)))) best = p;
    }
    return best;
  }

  /// The networks signed in, whose chats the list shows.
  List<InboxNetwork> get ready => [for (final n in networks) if (!n.soon && n.state == InboxState.ready) n];

  Listenable get changes => Listenable.merge(networks);

  Future<void> start(AppState app) async {
    for (final n in networks) {
      if (n.soon) continue;
      n.listStore = app;
      try {
        await n.start(app);
      } catch (e) {
        debugPrint('inbox: ${n.id} did not start: $e');
      }
    }
  }
}
