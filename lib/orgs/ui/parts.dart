/// The small things the organization pages share: the words (`src/app/settings/orgWords.ts`), a round of a hue,
/// a role's chip (`.role`, settings/OrganizationsPane.module.css), and the pill a thing to do is
/// (`.action`, notes/OrganizationScreen.module.css and settings/InviteLinks.module.css, which are the same rule
/// written twice).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../home/home_organizations.dart' show OrgPresence;
import '../../notes/when.dart';
import '../../sheet/css.dart';
import '../types.dart';

/// A role, as a row reads it under an organization's name (`roleWords`).
String roleWords(String role) => role == 'owner' ? 'Owner' : (role == 'admin' ? 'Admin' : 'Member');

/// How many have joined, as a row reads it (`memberWords`).
String memberWords(int count) => count == 1 ? '1 member' : '$count members';

/// The sentence about the workspace, said on Members, on Workspace and on the dashboard (docs/TEAMS.md, D1;
/// `TEAMS_NOTES`).
const String teamsNotes = 'Notes filed here are the team’s: everyone in it reads and edits them, and edits made apart merge.';

/// When, mid-sentence: "yesterday" and "just now" lose their capital, a weekday or a month keeps its own (`since`).
String sinceWords(int ms, [int? now]) {
  final words = when(ms, now);
  return words == 'Yesterday' || words == 'Just now' ? words.toLowerCase() : words;
}

/// A member's line: since when they joined or were invited (`MemberRow`'s hint, `MemberLine`'s line).
String memberLine(Member member, {required bool self, int? now}) => member.state == 'member'
    ? '${self ? 'You, ' : ''}${member.role == 'owner' ? 'owner since' : 'joined'} ${sinceWords(member.since, now)}'
    : 'Invited${member.invitedBy != null && member.invitedBy!.isNotEmpty ? ' by ${member.invitedBy}' : ''} ${sinceWords(member.since, now)}';

/// An AI's line, in both lists (`AiLine`'s line, `AiRow`'s hint): whose connector it came through and when it was
/// last seen; "Through you" for the signed-in member's own.
String aiLine(OrgAi ai, {required String me, int? now}) => 'Through ${aiIsMine(ai, me) ? 'you' : ai.via} · last seen ${sinceWords(ai.lastSeen, now)}';

/// Whether an AI came through the signed-in member's own connector.
bool aiIsMine(OrgAi ai, String me) => ai.via.toLowerCase() == me.toLowerCase();

/// What the Members section says under itself once an AI is listed there: whose access it is, and what Remove
/// removes (`AI_NOTES`).
const String aiNotes = 'An AI reads and writes through its member’s own access, with their connector. Removing it takes it off this list, not out of the notes: it is listed again when it next reads them.';

/// A round of a hue (`data-hue` over `background: var(--app-space, var(--app-ink-3))`), [size] across: the
/// organization's colour as its hero's glyph, its title's dot, a pill's.
class HueRound extends StatelessWidget {
  const HueRound({super.key, required this.hue, required this.size});
  final String? hue;
  final double size;

  @override
  Widget build(BuildContext context) => GlacierScope(
        attrs: {'hue': hue ?? 'ink'},
        child: Builder(
          builder: (context) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: context.tokens.colorOf('var(--app-space, var(--app-ink-3))'), shape: BoxShape.circle),
          ),
        ),
      );
}

/// The chip after a handle: the role, or that they have not joined yet (`RoleChip`, `.role`). A small outlined
/// word: the owner's in ink, the others in the quiet ink, an invitation's outline dashed.
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required Member this.member});

  /// The chip after an AI's name, where a member has their role (`data-role="ai"`): the quiet chip, reading `AI`.
  const RoleChip.ai({super.key}) : member = null;

  /// Whose chip; null for an AI's.
  final Member? member;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    final member = this.member;
    final owner = member?.role == 'owner';
    final invited = member?.state == 'invited';
    final line = snapBorder(context, t.len('glacier-hairline'));
    final rule = owner ? t.color('app-ink-2') : t.color('app-rule');
    final words = Padding(
      // `padding: 0.1em 0.5em; line-height: 1.4`
      padding: EdgeInsets.symmetric(vertical: 0.1 * xs + line, horizontal: 0.5 * xs + line),
      child: Text(member == null ? 'AI' : (invited ? 'Invited' : roleWords(member.role)), style: pageText(t, xs, weight: 'medium', height: 1.4, color: owner ? t.color('app-ink') : t.color('app-ink-2')), softWrap: false),
    );
    return CustomPaint(painter: _Outline(color: rule, width: line, dashed: invited), child: words);
  }
}

/// A stadium's outline, solid or dashed (`border-style: dashed`).
class _Outline extends CustomPainter {
  const _Outline({required this.color, required this.width, required this.dashed});
  final Color color;
  final double width;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    final rect = (Offset.zero & size).deflate(width / 2);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    if (!dashed) return canvas.drawRRect(shape, paint);
    // A dash and a gap are each three times the line, as a browser draws a dashed border.
    final dash = width * 3;
    for (final metric in (Path()..addRRect(shape)).computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash * 2) {
        canvas.drawPath(metric.extractPath(at, (at + dash).clamp(0, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Outline old) => old.color != color || old.width != width || old.dashed != dashed;
}

/// A thing to do (`.action`; with [primary], InviteLinks.module.css `.primary`): a pill 2.25rem tall with the kit's
/// mark before its word, the app's ink on its faint wash, or the paper on the ink. Null [onPressed] is the disabled
/// button, dimmed to [dim] (0.5 on the dashboard, 0.6 on the links).
class OrgAction extends StatelessWidget {
  const OrgAction({super.key, required this.label, this.icon, required this.onPressed, this.primary = false, this.semanticLabel, this.dim = 0.5});

  final String label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final String? semanticLabel;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final line = snapBorder(context, t.len('glacier-hairline'));
    final ink = primary ? t.color('app-paper') : t.color('app-ink');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('full'),
        offset: 2,
        child: Opacity(
          opacity: state.disabled ? dim : 1,
          child: Container(
            constraints: BoxConstraints(minHeight: t.lenOf('2.25rem')),
            padding: EdgeInsets.symmetric(horizontal: sm),
            decoration: ShapeDecoration(
              color: primary ? t.color('app-ink') : t.colorOf('color-mix(in oklch, var(--app-ink) ${state.hovered ? 9 : 5}%, transparent)'),
              shape: StadiumBorder(side: BorderSide(color: primary ? const Color(0x00000000) : t.color('glacier-border-subtle'), width: line)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[IconTheme.merge(data: IconThemeData(color: ink), child: icon!), SizedBox(width: 0.45 * sm)],
                ExcludeSemantics(child: Text(label, style: pageText(t, sm, weight: 'medium', color: ink), softWrap: false)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The AI rows: each of the organization's AIs with the entry online that is it (its name, and whose connector
/// it came through where the entry says), and after them an entry online that is none of them, as a row made for it
/// (`last seen` now): Claude's first visit is online before the service has listed it.
List<(OrgAi, OrgPresence?)> aiLines(List<OrgAi> ais, List<OrgPresence> seen, {int? now}) {
  final online = [for (final s in seen) if (s.ai) s];
  bool same(OrgAi ai, OrgPresence s) => s.handle.toLowerCase() == ai.name.toLowerCase() && (s.via == null || s.via!.toLowerCase() == ai.via.toLowerCase());
  // Of one AI's entries, the one on a note.
  OrgPresence? best(Iterable<OrgPresence> of) {
    OrgPresence? held;
    for (final s in of) {
      if (held == null || (held.editingNote == null && s.editingNote != null)) held = s;
    }
    return held;
  }

  final lines = <(OrgAi, OrgPresence?)>[for (final ai in ais) (ai, best(online.where((s) => same(ai, s))))];
  final extra = <String, List<OrgPresence>>{};
  for (final s in online) {
    if (ais.any((ai) => same(ai, s))) continue;
    extra.putIfAbsent('${s.handle.toLowerCase()}|${s.via?.toLowerCase() ?? ''}', () => []).add(s);
  }
  for (final MapEntry(key: key, value: entries) in extra.entries) {
    final first = best(entries)!;
    lines.add((OrgAi(id: 'live:$key', name: first.handle, via: first.via ?? '', firstSeen: now ?? 0, lastSeen: now ?? 0), first));
  }
  return lines;
}
