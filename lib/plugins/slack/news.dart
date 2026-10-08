/// An organization's news, posted to the Slack channel the person chose for it (Matt's #5: "It pairs well with
/// organizations: a team's news could go to its channel too"). A port of `src/app/plugins/slack/news.ts`.
///
/// The news is what the organization's dashboard draws (`NEWS`, here lib/core/notifications.dart [orgKinds]):
/// someone joined, left, was removed, took or declined an invitation, a role changed, it was renamed. Each goes as
/// the sentence the bell reads it by ([sentenceOf]), and nothing else: no note, and nothing sealed.
///
/// When it goes is the phone's rule for its own notifications: after a pass of the feed, the rows above the cursor
/// the pass began at, oldest first, and nothing on a device's first look at the feed, which would post its whole
/// history. Three more rules make it once:
///
/// - **Once per row on this device.** A row is written again when it is read, so it can come above the cursor
///   twice; the ids posted are kept (`glyph-slack-posted`, the last 300), and an id is kept before its post goes, so
///   two passes close together cannot both send it. A post that fails is not tried again: the person is not there to
///   be told, and a retry that lands twice is worse than one that never lands.
/// - **Nothing from before the choice.** A row older than the moment its organization's channel was set is not
///   posted, so setting a channel today does not send last month's news when one of its rows is read on another
///   device.
/// - **Only an organization the person is a member of**, with a channel chosen for it on this device.
///
/// The choice is this device's, as the channels are: each device with a channel set for an organization posts its
/// news, so it is set on one device, and the pane says so.
///
/// What differs: the organizations are a seam. The page read `orgsState()` and `useOrgs()` from a module; here the
/// account's `Orgs` (lib/orgs/orgs.dart) is an object the app's root holds, so the root hands its list over as
/// [slackOrgs]. Until it does there are none: no news goes, and the pane draws no organizations.
library;

import 'package:flutter/foundation.dart';

import '../../core/notifications.dart' show FeedNotification, orgKinds, sentenceOf;
import '../../orgs/types.dart' show OrgRow;
import 'channels.dart';
import 'manifest.dart';

const String _newsKey = 'glyph-slack-news';
const String _postedKey = 'glyph-slack-posted';

/// How many posted ids are kept: far more than a pass ever brings.
const int _postedKept = 300;

/// The account's organizations, as this plugin reads them: the list the device keeps (`orgsState().list`), and what
/// says it has changed (`useOrgs`).
class SlackOrgs {
  const SlackOrgs({required this.list, this.changes});

  /// Every organization the account is in or invited to.
  final List<OrgRow> Function() list;

  /// Tells a page to read [list] again; null for a list that never changes.
  final Listenable? changes;

  static List<OrgRow> _none() => const [];

  /// No account, or none handed over yet.
  static const SlackOrgs none = SlackOrgs(list: _none);
}

/// Set by the app's root once the account is made: `SlackOrgs(list: () => orgs.orgsState().list, changes: orgs)`.
SlackOrgs slackOrgs = SlackOrgs.none;

/// Where one organization's news goes, and since when.
typedef _NewsChoice = ({String channel, int since});

Map<String, _NewsChoice> _choices() {
  final Object? kept = host.storage.get<Object?>(_newsKey, const <String, Object?>{});
  return {
    if (kept is Map)
      for (final MapEntry(:key, :value) in kept.entries)
        if (key is String && value is Map && value['channel'] is String) key: (channel: value['channel'] as String, since: value['since'] is num ? (value['since'] as num).toInt() : 0),
  };
}

/// The channel an organization's news goes to on this device, or null: none set, or the channel since forgotten
/// (`newsChannelFor`).
Channel? newsChannelFor(String orgId) => channelById(_choices()[orgId]?.channel);

/// Sends an organization's news to a channel from now on, or to nowhere with null (`setNewsChannel`).
void setNewsChannel(String orgId, String? channelId, [int? now]) {
  final next = _choices();
  if (channelId != null && channelId.isNotEmpty) {
    next[orgId] = (channel: channelId, since: now ?? DateTime.now().millisecondsSinceEpoch);
  } else {
    next.remove(orgId);
  }
  if (next.isNotEmpty) {
    host.storage.set(_newsKey, {for (final MapEntry(:key, :value) in next.entries) key: {'channel': value.channel, 'since': value.since}});
  } else {
    host.storage.remove(_newsKey);
  }
}

List<String> _postedIds() {
  final Object? kept = host.storage.get<Object?>(_postedKey, const <Object?>[]);
  return [
    if (kept is List)
      for (final id in kept)
        if (id is String) id,
  ];
}

/// Whether the account is a member of an organization now, by the list this device keeps.
bool _isMember(String orgId) => slackOrgs.list().any((row) => row.id == orgId && row.state == 'member');

/// The rows a pass brought, each new piece of an organization's news posted to its channel: those above [before],
/// of a kind that is news, about an organization with a channel set here, from no earlier than it was set, and not
/// posted from this device already. Answers how many went (`forwardNews`). [post] and [member] are the tests'.
Future<int> forwardNews(int before, List<FeedNotification> rows, {Future<void> Function(Channel channel, String text)? post, bool Function(String orgId)? member}) async {
  if (before <= 0) return 0;
  final chosen = _choices();
  if (chosen.isEmpty) return 0;
  final send = post ?? postToChannel;
  final isMember = member ?? _isMember;
  var posted = 0;
  // Oldest first, so the channel reads in the order it happened. Stable, as the page's sort is.
  final ordered = [for (final (at, n) in rows.indexed) (at, n)]
    ..sort((a, b) {
      final by = a.$2.rev.compareTo(b.$2.rev);
      return by != 0 ? by : a.$1.compareTo(b.$1);
    });
  for (final (_, n) in ordered) {
    if (n.rev <= before || !orgKinds.contains(n.kind)) continue;
    final orgId = n.org?.id;
    final choice = orgId == null ? null : chosen[orgId];
    if (orgId == null || orgId.isEmpty || choice == null || n.at < choice.since || !isMember(orgId)) continue;
    final channel = channelById(choice.channel);
    if (channel == null) continue;
    final done = _postedIds();
    if (done.contains(n.id)) continue;
    // Kept before it goes: at most once, never twice.
    final kept = [...done, n.id];
    host.storage.set(_postedKey, kept.length > _postedKept ? kept.sublist(kept.length - _postedKept) : kept);
    try {
      await send(channel, '${sentenceOf(n).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}.');
      posted += 1;
    } catch (_) {
      // Not said anywhere: this runs in the background, after a sync, with nobody looking at a note to tell.
    }
  }
  return posted;
}
