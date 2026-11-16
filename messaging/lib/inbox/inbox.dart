import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../kept_lists.dart';
import 'bluesky.dart';
import 'mastodon.dart';
import 'signal.dart';
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
enum InboxStep { none, phone, code, password, credentials }

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

@immutable
class InboxMessage {
  const InboxMessage({required this.id, required this.text, required this.date, required this.mine, this.sender = '', this.state = 'sent', this.media = const []});
  final String id;
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

  /// The chats the list shows: [chats] without those in Ghost's own lists (archived or deleted here).
  List<InboxChat> get shownChats {
    final gone = {...localList('archived'), ...localList('deleted')};
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
  // Signal through mautrix-signal, built and Coming soon until it is proven (Matt, 2026-11-15: "Lets wire it up for
  // signal through the mautrix").
  static Inbox get instance => _instance ??= Inbox._([Telegram(), Bluesky(soon: true), Mastodon(soon: true), Signal(soon: true)]);

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
