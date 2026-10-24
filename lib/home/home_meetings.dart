/// The meetings Ghost is going to, on the home page (Matt, 2026-10-23: "adding a home page section for upcoming
/// meetings"): a card among the page's notices, on the advanced page and Simple's alike, listing the meetings still to
/// come or going on now, the soonest first, with when each is and where it stands. Nothing at all when there are
/// none, or the account's service has no Ghost in meetings. Its foot opens Settings › Meetings, where a meeting is
/// skipped or Ghost sent to one (lib/settings/panes/meetings_pane.dart).
///
/// Drawn as the organization's card beside it is (home_org_events.dart): a tinted box, a heading, a line a meeting.
/// A booked occurrence of a recurring meeting has the repeat mark for its calendar, as on Settings › Meetings
/// (2026-10-24).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/ui_state.dart';
import '../app/widgets.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../meet/meet_api.dart';
import '../meet/meet_in.dart';
import '../meet/ui/meet_card.dart' show meetWhen;
import 'home_organizations.dart';
import 'home_text.dart';

/// How many meetings the card lists.
const int homeMeetingsMost = 4;

/// The meetings to show: still to come or going on (Ghost can be told not to join, or to leave), not yet over by
/// their end, the soonest first.
List<MeetBooking> upcomingMeetings(List<MeetBooking>? meetings, {required int now}) {
  final open = [for (final m in meetings ?? const <MeetBooking>[]) if (m.state.open && m.endsAt > now) m];
  open.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return open.take(homeMeetingsMost).toList();
}

class HomeMeetings extends StatelessWidget {
  const HomeMeetings({super.key, required this.services, this.onOpen});

  final AccountServices services;

  /// Opens Settings › Meetings; without it the card has no foot.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final meet = services.meetIn;
    if (meet == null) return const SizedBox.shrink();
    meet.readSoon();
    return ListenableBuilder(
      listenable: meet,
      builder: (context, _) {
        if (!meet.available) return const SizedBox.shrink();
        final now = services.now();
        final lines = upcomingMeetings(meet.meetings, now: now);
        if (lines.isEmpty) return const SizedBox.shrink();
        final t = context.tokens;
        final sm = t.fontSize('sm');
        final ink3 = t.color('app-ink-3');
        final hairline = t.len('glacier-hairline');
        return Semantics(
          container: true,
          label: 'Upcoming meetings',
          explicitChildNodes: true,
          child: Container(
            key: const ValueKey('home-meetings'),
            padding: EdgeInsets.all(t.space(4)),
            decoration: BoxDecoration(
              color: t.colorOf('color-mix(in oklch, var(--app-ink) 3%, transparent)'),
              border: Border.all(color: t.color('app-rule'), width: hairline),
              borderRadius: BorderRadius.circular(t.radius('lg')),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                HomeHeading(mark: AppIcon(Lucide.ghost, size: 15, color: t.color('app-ink-2')), words: 'Upcoming meetings'),
                SizedBox(height: t.space(2)),
                for (final (at, meeting) in lines.indexed)
                  Container(
                    key: ValueKey('home-meeting-${meeting.id}'),
                    padding: EdgeInsets.symmetric(vertical: t.space(2)),
                    decoration: BoxDecoration(border: at == lines.length - 1 ? null : Border(bottom: BorderSide(color: t.color('app-rule'), width: hairline))),
                    child: Row(
                      children: [
                        SizedBox(
                          width: t.lenOf('1.1rem'),
                          child: Center(
                            child: AppIcon(meeting.state != MeetState.booked ? Lucide.ghost : (meeting.series != null ? Lucide.repeat : Lucide.calendarDays), size: 15, color: meeting.state == MeetState.booked ? ink3 : t.color('app-ink')),
                          ),
                        ),
                        SizedBox(width: t.space(2)),
                        Expanded(
                          child: Text(
                            meeting.title ?? 'A meeting',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: pageText(t, sm, weight: meeting.state == MeetState.booked ? 'regular' : 'medium', color: meeting.state == MeetState.booked ? t.color('app-ink-2') : t.color('app-ink')),
                          ),
                        ),
                        SizedBox(width: t.space(2)),
                        Text(
                          meeting.state == MeetState.booked ? meetWhen(meeting.startsAt, now: now) : meetStateWords(meeting),
                          softWrap: false,
                          style: tabular(pageText(t, t.fontSize('xs'), color: ink3)),
                        ),
                      ],
                    ),
                  ),
                if (onOpen != null) ...[
                  SizedBox(height: t.space(2)),
                  Align(alignment: AlignmentDirectional.centerStart, child: AppWord(onPressed: onOpen!, child: const Text('Meetings'))),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
