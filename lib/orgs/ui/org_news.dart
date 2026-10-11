/// An organization's own news, as its dashboard (organization_screen.dart) and its audit log
/// (organization_log.dart) both draw it from the feed. A port of `src/app/notes/orgNews.tsx`.
///
/// The kinds that are the organization's news (`NEWS`) are [orgKinds] in lib/core/notifications.dart: an invitation
/// is the invitee's, and is answered on its own row.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/notifications.dart';
import '../../home/home_org_events.dart' show OrgNews;
import '../../home/home_organizations.dart' show HomeOrg, OrgPresence;

export '../../core/notifications.dart' show orgKinds;

/// Each kind of news's mark at the start of its row, from the kit, as the notifications drawer draws it (`MARKS`).
const Map<String, LucideIcon> orgNewsMarks = {
  'invite-accepted': Lucide.userCheck,
  'invite-declined': Lucide.userX,
  'member-joined': Lucide.userPlus,
  'member-left': Lucide.userMinus,
  'member-removed': Lucide.userMinus,
  'role-changed': Lucide.crown,
  'org-renamed': Lucide.pencil,
  'org-deleted': Lucide.trash2,
};

/// A kind's mark in its colour (`<span data-hue={KIND_HUES[kind]}>{MARKS[kind]}</span>`): the hue's own where the
/// kind has one, else [fallback].
class OrgNewsMark extends StatelessWidget {
  const OrgNewsMark({super.key, required this.kind, required this.fallback, this.size = 17});
  final String kind;
  final Color fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mark = orgNewsMarks[kind];
    if (mark == null) return SizedBox.square(dimension: size);
    final hue = kindHues[kind];
    if (hue == null) return AppIcon(mark, size: size, color: fallback);
    return GlacierScope(
      attrs: {'hue': hue},
      child: Builder(builder: (context) => AppIcon(mark, size: size, color: context.tokens.colorOf('var(--app-space)', current: fallback))),
    );
  }
}

// --- what the home page is handed ------------------------------------------------------------------------------------

/// The organizations the home page draws (`home/HomeOrganizations.tsx` reads `useOrgs()`): the ones joined, as the
/// service last listed them. [here] is who is in each now, by organization, from the live service where there is
/// one.
List<HomeOrg> homeOrganizations(AccountServices? services, {Map<String, List<OrgPresence>> here = const {}}) => [
      if (services != null && services.signedIn)
        for (final row in services.joined) HomeOrg(id: row.id, name: row.name, hue: row.hue, members: row.members, here: here[row.id] ?? const []),
    ];

/// An organization's news as the home page's card says it (`home/HomeOrgEvents.tsx`): each row's sentence, when,
/// and its kind's colour. What Settings › Notifications switched off is the drawer's to leave out, not this card's:
/// the page lists the feed's rows as they are.
List<OrgNews> homeOrgNews(AccountServices? services, String? orgId) => [
      if (services != null && orgId != null)
        for (final n in services.newsOf(orgId)) OrgNews(id: n.id, at: n.at, words: sentenceOf(n), hue: kindHues[n.kind]),
    ];
