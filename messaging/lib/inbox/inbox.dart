import 'package:flutter/foundation.dart';

import '../app_state.dart';
import 'bluesky.dart';
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
      );
}

/// A message in an [InboxChat].
@immutable
class InboxMessage {
  const InboxMessage({required this.id, required this.text, required this.date, required this.mine, this.sender = '', this.state = 'sent'});
  final String id;
  final String text;
  final DateTime date;
  final bool mine;

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

  /// The chat opened in the app: kept fresh more often while it is shown. Null when none is.
  set watching(String? chatId);

  /// Starts what was signed in before, if anything.
  Future<void> start(AppState app);

  /// Signs out and forgets everything kept for it on this device.
  Future<void> signOut();

  /// Unread chats.
  int get unreadChats => chats.where((c) => c.unread > 0).length;
}

/// The networks, as the app holds them.
class Inbox {
  Inbox._(this.networks);

  static Inbox? _instance;
  static Inbox get instance => _instance ??= Inbox._([Telegram(), Bluesky()]);

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
  List<InboxNetwork> get ready => [for (final n in networks) if (n.state == InboxState.ready) n];

  Listenable get changes => Listenable.merge(networks);

  Future<void> start(AppState app) async {
    for (final n in networks) {
      try {
        await n.start(app);
      } catch (e) {
        debugPrint('inbox: ${n.id} did not start: $e');
      }
    }
  }
}
