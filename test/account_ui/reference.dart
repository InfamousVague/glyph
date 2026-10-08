import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/notifications.dart' show FeedNotification;
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/sync/feed.dart';

import '../orgs_ui/support.dart';

/// What the web page measured (tool/account_reference.mjs): for each named thing its rectangles and words.
class Reference {
  Reference(String name) : _json = jsonDecode(File('test/account_ui/fixtures/$name.json').readAsStringSync()) as Map<String, Object?>;
  final Map<String, Object?> _json;

  /// The moment the page's clock stood at.
  int get now => (_json['now']! as num).toInt();

  List<({Rect rect, String text})> of(String thing) => [
        for (final each in ((_json['things']! as Map)[thing] as List? ?? const []).cast<Map<String, Object?>>())
          (rect: Rect.fromLTWH((each['x']! as num).toDouble(), (each['y']! as num).toDouble(), (each['w']! as num).toDouble(), (each['h']! as num).toDouble()), text: each['text']! as String),
      ];
}

/// Holds a screen's rectangles to the page's, to half a pixel, and says every one that is off at once.
class Held {
  Held(this.reference, {this.by = 0.5});
  final Reference reference;
  final double by;
  Offset shift = Offset.zero;
  final List<String> off = [];
  int checked = 0;

  /// The page and the screen are laid over one another where [thing] is on each: a page drawn inside the app's
  /// shell starts lower than a screen drawn alone.
  void anchor(String thing, Rect here) => shift = reference.of(thing).first.rect.topLeft - here.topLeft;

  /// [got] against the page's [thing]: [dims] are the sides compared, `x`, `y`, `w` and `h`.
  void check(String thing, List<Rect> got, {String dims = 'xywh', int? only}) {
    final want = reference.of(thing);
    if (only == null && want.length < got.length) {
      off.add('$thing: the page has ${want.length}, the screen ${got.length}');
      return;
    }
    for (var i = 0; i < got.length; i++) {
      final at = only ?? i;
      if (at >= want.length) {
        off.add('$thing[$at]: not on the page');
        continue;
      }
      final page = want[at].rect, here = got[i].shift(shift);
      final misses = [
        if (dims.contains('x') && (page.left - here.left).abs() > by) 'x ${here.left.toStringAsFixed(2)} for ${page.left}',
        if (dims.contains('y') && (page.top - here.top).abs() > by) 'y ${here.top.toStringAsFixed(2)} for ${page.top}',
        if (dims.contains('w') && (page.width - here.width).abs() > by) 'w ${here.width.toStringAsFixed(2)} for ${page.width}',
        if (dims.contains('h') && (page.height - here.height).abs() > by) 'h ${here.height.toStringAsFixed(2)} for ${page.height}',
      ];
      checked += 1;
      if (misses.isNotEmpty) off.add('$thing[$at] "${want[at].text}": ${misses.join(', ')}');
    }
  }

  void done() => expect(off, isEmpty, reason: 'of $checked rectangles, off the page\'s by more than $by:\n${off.join('\n')}');
}

List<Rect> rectsOf(WidgetTester tester, Finder finder) => [for (final element in finder.evaluate()) tester.getRect(find.byElementPredicate((e) => identical(e, element)))];

const int day = 86400000;

/// The account the page was seeded with (tool/account_reference.mjs `seed`): matt, the owner of Ghost (sea) with
/// sam in it wearing rose and lee invited, a member of Studio (rose); two notes filed in Ghost; two pieces of its
/// news, one unread; and one invite link for a week. [now] is the page's clock.
Future<({Device device, String ghost, String studio})> seededDevice(int now) async {
  final device = await Device.make(peers: const ['sam', 'lee', 'ana'], now: () => now);
  device.service.clock = () => now - 3 * day;
  final id = await ghost(device);
  device.service.clock = () => now - 2 * day;
  await sam(device, id, joined: true);
  device.service.peerColour('sam', 'rose');
  device.service.clock = () => now - 3600000;
  await device.orgs.inviteByHandle(id, 'lee');
  device.service.clock = () => now;
  final studio = device.service.invited('Studio', 'sam');
  device.service.orgs[studio]!
    ..hue = 'rose'
    ..rows['matt']!.state = 'member'
    ..rows['ana'] = OrgRowKept(handle: 'ana', role: 'member', state: 'member', since: now, invitedBy: 'sam');
  await device.orgs.makeInviteLink(id, terms: const LinkTerms(expiresIn: 7 * 86400));
  await listed(device);
  device.notes.held['a'] = Note(id: 'a', body: '# Roadmap\n- ship', createdAt: now - day, updatedAt: now - 7200000);
  device.notes.held['b'] = Note(id: 'b', body: '# Standup\nyesterday: shipped', createdAt: now - day, updatedAt: now - 3600000);
  device.workspaces.fileNote('a', orgWorkspaceId(id));
  device.workspaces.fileNote('b', orgWorkspaceId(id));
  final account = device.account.session!.accountId;
  final org = (id: id, name: 'Ghost');
  device.feed.updateFeed(
    account,
    (state) => withFed(
      withFed(state, FeedNotification(id: 'n1', rev: 1, kind: 'member-joined', at: now - 2 * day, readAt: now, from: 'sam', org: org, body: const {'name': 'Ghost'}), now),
      FeedNotification(id: 'n2', rev: 2, kind: 'role-changed', at: now - 3600000, from: 'matt', org: org, body: const {'name': 'Ghost', 'role': 'admin'}),
      now,
    ).copyWith(cursor: 2),
  );
  return (device: device, ghost: id, studio: studio);
}
