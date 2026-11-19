import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../changelog.dart';
import '../kit/settings_type.dart';
import '../sms.dart' show Sms;
import 'circles/members_drawer.dart' show showMembersDrawer;
import 'common.dart' show GhostLogo;
import 'drawer_head.dart' show DrawerHead, DrawerHeading;
import 'settings_panes.dart' show appVersion;

/// What's new: the release notes (lib/changelog.dart) in the app's drawer, once after each update and again from
/// Settings › About (Matt, 2026-11-19: "Implement a changelog that pops up ever time a new update is released with
/// release notes").

/// The version whose notes were last shown (or that was first installed), kept with the device's choices.
const changelogSeenKey = 'changelog_seen';

/// Shows what came since this device last saw the notes, where anything did: called once the app's frame is up. A new
/// install shows nothing (its walkthrough says what the app does) and starts from the version it is. Notes are marked
/// seen as they are shown, so they come up once.
Future<void> showWhatsNewIfUpdated(BuildContext context, {String current = appVersion}) async {
  final app = AppState.of(context);
  final seen = app.choice(changelogSeenKey, '');
  if (seen == current) return;
  app.set(changelogSeenKey, current);
  // From before the notes were kept: a phone that has been set up has been used, so it has updated into them; a
  // phone still to be set up is new. A computer or an iPhone can't tell a new install from an update, so it starts
  // from the version it is and is shown the notes from its next update on.
  if (seen.isEmpty && (Sms.remote || !app.flag('onboarded', fallback: false))) return;
  final notes = seen.isEmpty ? notesSince('', current, most: 1) : notesSince(seen, current);
  if (notes.isEmpty || !context.mounted) return;
  await showWhatsNew(context, notes);
}

/// [notes] in the drawer, newest first; the newest release's when none are given.
Future<void> showWhatsNew(BuildContext context, [List<ReleaseNotes>? notes]) {
  final shown = notes ?? changelog.take(1).toList();
  return showMembersDrawer(
    context,
    title: 'What\'s new',
    subtitle: shown.length == 1 ? 'Ghost Messaging ${shown.single.version}' : 'Since you last looked',
    face: const GhostLogo(size: 40),
    list: (_) => WhatsNewList(notes: shown),
  );
}

/// The notes of each release, as a list of lines under its version.
class WhatsNewList extends StatelessWidget {
  const WhatsNewList({super.key, required this.notes});
  final List<ReleaseNotes> notes;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gutter = DrawerHead.gutter(t);
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(gutter, t.space(3), gutter, t.space(4)),
      children: [
        for (final r in notes) ...[
          if (notes.length > 1) DrawerHeading(r.version),
          for (final line in r.notes)
            Padding(
              padding: EdgeInsets.only(bottom: t.space(3)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: EdgeInsets.only(top: t.lenOf('0.5rem'), right: t.space(3)),
                  child: Container(width: 6, height: 6, decoration: BoxDecoration(color: t.color('app-accent'), shape: BoxShape.circle)),
                ),
                Expanded(child: Text(line, style: pageText(t, t.fontSize('md'), color: t.color('app-ink'), height: 1.4))),
              ]),
            ),
          SizedBox(height: t.space(2)),
        ],
      ],
    );
  }
}
