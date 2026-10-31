/// Follow and Following on a team page's More sheet (docs/TEAMSPACES.md, "Follow a doc and Updates"; Matt,
/// 2026-10-31: "`watchers:` (the tickets' key) works on any page"): a row of its own under Following, which writes the
/// account into the page's `watchers:` or takes it off (lib/team/follow.dart [withFollowing]), through the open
/// editor so it is one step to undo and saves as typing does. Shown on a team's page, signed in; in simple mode too,
/// since following a page is not a fancy feature.
library;

import 'package:flutter/widgets.dart';

import '../art/art.dart';
import '../sheet/kit.dart';

/// The row's section: its heading and the one row. It flips as it is pressed, while the sheet stays up.
class FollowSection extends StatefulWidget {
  const FollowSection({super.key, required this.following, required this.onToggle});

  /// Whether the account follows the page as the sheet opens.
  final bool following;

  /// Follow ([on]) or stop.
  final ValueChanged<bool> onToggle;

  static const Key rowKey = ValueKey<String>('note-follow');

  @override
  State<FollowSection> createState() => _FollowSectionState();
}

class _FollowSectionState extends State<FollowSection> {
  late bool _following = widget.following;

  @override
  void didUpdateWidget(FollowSection old) {
    super.didUpdateWidget(old);
    if (old.following != widget.following) _following = widget.following;
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeading('Following'),
          SheetGroup(
            children: [
              SheetRow(
                key: FollowSection.rowKey,
                icon: AppIcon(_following ? Lucide.bell : Lucide.eye, size: 18, strokeWidth: 2.1),
                label: _following ? 'Following' : 'Follow',
                hint: _following ? 'Its changes reach your Updates. Press to stop.' : 'Its changes reach your Updates, under Docs.',
                on: _following,
                onPress: () {
                  setState(() => _following = !_following);
                  widget.onToggle(_following);
                },
              ),
            ],
          ),
        ],
      );
}
