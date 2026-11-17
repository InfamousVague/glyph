/// A made-up server, to try the ways servers could look (Matt, 2026-11-17: "I'd like to investigate deeper into making
/// our app have servers like discord ... no place for organizing multiple spaces and text groups under one location to
/// share and invite several users. I'd like you to propose 5 different layouts ... consider user lists, server
/// settings, moving channels and spaces around"). Nothing here reaches the network: it is the preview's own state,
/// kept while the preview is open, so what is changed in one layout shows in the others.
library;

import 'package:flutter/foundation.dart';

/// A text channel or a space (a voice room, as the app's spaces are).
enum ChannelKind { text, space }

class MockChannel {
  MockChannel(this.id, this.name, this.kind, {this.topic = '', this.unread = 0, this.inSpace = const [], this.locked = false});
  final String id;
  String name;
  final ChannelKind kind;
  String topic;
  int unread;

  /// Who is in a space now, by member id.
  List<String> inSpace;

  /// Only some roles see it.
  bool locked;
}

class MockCategory {
  MockCategory(this.id, this.name, this.channels, {this.folded = false});
  final String id;
  String name;
  final List<MockChannel> channels;
  bool folded;
}

/// Owner, admin, moderator, member: what each may do is [rolePowers].
enum MockRole { owner, admin, moderator, member }

const rolePowers = {
  MockRole.owner: 'Everything, and giving the server away',
  MockRole.admin: 'Settings, roles, channels and members',
  MockRole.moderator: 'Removing messages and people, muting in spaces',
  MockRole.member: 'Reading and writing where allowed, joining spaces',
};

class MockMember {
  MockMember(this.id, this.name, this.role, {this.online = false, this.status});
  final String id;
  final String name;
  MockRole role;
  bool online;

  /// What they are doing, where it is shown: "In Lounge".
  String? status;
}

class MockMessage {
  const MockMessage(this.from, this.text, this.minutesAgo);
  final String from;
  final String text;
  final int minutesAgo;
}

/// The preview's server, and every server in the rail beside it.
class MockServer extends ChangeNotifier {
  MockServer({required this.name, required this.hue, required this.categories, required this.members, this.description = '', this.invite = 'gogho.st/s/k7Qw2'});

  String name;
  String description;
  final String hue;
  final List<MockCategory> categories;
  final List<MockMember> members;
  String invite;

  /// Whether new members' messages wait for a moderator, and the server's notifications.
  bool approveJoins = false;
  String notifications = 'Mentions only';

  /// What each role may do, as switches: role → power → on.
  final Map<MockRole, Map<String, bool>> powers = {
    for (final r in MockRole.values)
      r: {
        'Manage channels': r.index <= MockRole.admin.index,
        'Invite people': r.index <= MockRole.moderator.index || true,
        'Remove messages': r.index <= MockRole.moderator.index,
        'Mute in spaces': r.index <= MockRole.moderator.index,
        'Mention everyone': r.index <= MockRole.admin.index,
      },
  };

  Iterable<MockChannel> get channels => categories.expand((c) => c.channels);
  MockChannel? channel(String id) => channels.where((c) => c.id == id).firstOrNull;
  MockMember? member(String id) => members.where((m) => m.id == id).firstOrNull;
  MockCategory categoryOf(MockChannel c) => categories.firstWhere((x) => x.channels.contains(c));
  int get online => members.where((m) => m.online).length;
  List<MockChannel> get liveSpaces => [for (final c in channels) if (c.kind == ChannelKind.space && c.inSpace.isNotEmpty) c];

  void changed() => notifyListeners();

  /// Moves [c] to [to] at [index] (its own category or another).
  void move(MockChannel c, MockCategory to, int index) {
    final from = categoryOf(c);
    final at = from.channels.indexOf(c);
    from.channels.removeAt(at);
    var i = index;
    if (identical(from, to) && at < index) i--;
    to.channels.insert(i.clamp(0, to.channels.length), c);
    notifyListeners();
  }

  /// Moves a category up (-1) or down (+1).
  void shiftCategory(MockCategory c, int by) {
    final i = categories.indexOf(c);
    final j = (i + by).clamp(0, categories.length - 1);
    if (i == j) return;
    categories
      ..removeAt(i)
      ..insert(j, c);
    notifyListeners();
  }

  void add(MockCategory to, String name, ChannelKind kind) {
    to.channels.add(MockChannel('c${DateTime.now().microsecondsSinceEpoch}', name, kind));
    notifyListeners();
  }

  void addCategory(String name) {
    categories.add(MockCategory('g${DateTime.now().microsecondsSinceEpoch}', name, []));
    notifyListeners();
  }

  void remove(MockChannel c) {
    categoryOf(c).channels.remove(c);
    notifyListeners();
  }

  void fold(MockCategory c) {
    c.folded = !c.folded;
    notifyListeners();
  }

  void setRole(MockMember m, MockRole r) {
    m.role = r;
    notifyListeners();
  }

  void kick(MockMember m) {
    members.remove(m);
    notifyListeners();
  }

  void read(MockChannel c) {
    if (c.unread == 0) return;
    c.unread = 0;
    notifyListeners();
  }

  void newInvite() {
    const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final n = DateTime.now().microsecondsSinceEpoch;
    invite = 'gogho.st/s/${List.generate(5, (i) => letters[(n >> (i * 5)) % letters.length]).join()}';
    notifyListeners();
  }

  /// A few made-up messages for a text channel.
  List<MockMessage> messagesOf(MockChannel c) => switch (c.name) {
        'announcements' => const [
            MockMessage('Maya', 'Welcome to the server! Read #rules and say hi in #general.', 2880),
            MockMessage('Maya', 'Game night moved to Friday at 8. The Lounge will be open from 7:30.', 95),
          ],
        'rules' => const [MockMessage('Maya', '1. Be kind. 2. No spam. 3. Spoilers in #spoilers only.', 10000)],
        _ => const [
            MockMessage('Jo', 'Anyone around tonight?', 41),
            MockMessage('Sam', 'I\'ll be in the Lounge after dinner', 38),
            MockMessage('Priya', 'Same. Bring the new map 😄', 22),
            MockMessage('Jo', 'Deal. I\'ll set it up', 3),
          ],
      };
}

/// The preview's made-up server, and the others in the rail.
MockServer sampleServer() => MockServer(
      name: 'Night Owls',
      hue: 'indigo',
      description: 'Game nights, late chats and the occasional movie.',
      categories: [
        MockCategory('info', 'Information', [
          MockChannel('ann', 'announcements', ChannelKind.text, topic: 'News from the admins', unread: 1),
          MockChannel('rules', 'rules', ChannelKind.text, topic: 'Read before posting', locked: true),
        ]),
        MockCategory('talk', 'Text channels', [
          MockChannel('gen', 'general', ChannelKind.text, topic: 'Anything goes', unread: 4),
          MockChannel('games', 'game-night', ChannelKind.text, topic: 'Plans for Friday'),
          MockChannel('pics', 'photos', ChannelKind.text, topic: 'Share what you made'),
        ]),
        MockCategory('voice', 'Spaces', [
          MockChannel('lounge', 'Lounge', ChannelKind.space, inSpace: const ['jo', 'sam', 'priya']),
          MockChannel('gaming', 'Gaming', ChannelKind.space, inSpace: const ['alex']),
          MockChannel('quiet', 'Quiet room', ChannelKind.space),
        ]),
      ],
      members: [
        MockMember('maya', 'Maya', MockRole.owner, online: true),
        MockMember('jo', 'Jo', MockRole.admin, online: true, status: 'In Lounge'),
        MockMember('sam', 'Sam', MockRole.moderator, online: true, status: 'In Lounge'),
        MockMember('priya', 'Priya', MockRole.member, online: true, status: 'In Lounge'),
        MockMember('alex', 'Alex', MockRole.member, online: true, status: 'In Gaming'),
        MockMember('lee', 'Lee', MockRole.member),
        MockMember('noor', 'Noor', MockRole.member),
        MockMember('riley', 'Riley', MockRole.member),
      ],
    );

/// The other servers the rail shows, by name and hue.
const otherServers = [('Book Club', 'green'), ('Family', 'coral'), ('Work', 'slate')];
