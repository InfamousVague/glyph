/// A member's page (docs/TEAMSPACES.md, "Members"; Matt, 2026-10-31: "A member's page is drawn, not stored: their
/// tickets, the docs they own (`owner:` or verified `by:`), their recent edits (from versions), their colour. Reached
/// from the members strip, `@mentions` and the presence avatars"). A page under the organization's dashboard, as its
/// audit log is (organization_log.dart), whose arrow goes back to it.
///
/// On it: their round in the colour they wear in the organization, their handle and role, whether they are in the app
/// now (and the page they are editing, opened by a press), then their open tickets in the organization (the soonest
/// due first), the pages they own, and their newest changes to its pages, one line a page, read from the versions as
/// the audit log reads them. What it says is lib/team/members.dart's ([memberFacts]); nothing is written or kept.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/note.dart';
import '../../core/note_facts.dart';
import '../../core/versions_log.dart';
import '../../core/versions_record.dart';
import '../../home/home_organizations.dart' show OrgPresence;
import '../../mentions/mention_syntax.dart' show handleKey;
import '../../notes/when.dart' as when;
import '../../sheet/css.dart';
import '../../shell/header_pane.dart';
import '../../team/members.dart';
import '../orgs.dart';
import 'parts.dart';

/// A member's page in an organization.
class MemberPage extends StatefulWidget {
  const MemberPage({super.key, required this.services, required this.orgId, required this.handle, required this.notes, required this.onBack, required this.onOpenNote, this.record, this.seen = const [], this.wisp = true, this.now});

  final AccountServices? services;
  final String orgId;

  /// Whose page: their handle, in any case.
  final String handle;

  /// The notes this device holds (not the trash), of which the organization's are read.
  final List<Note> notes;

  /// The dashboard.
  final VoidCallback onBack;
  final ValueChanged<String> onOpenNote;

  /// Where the notes' versions are kept; null, and the page has no recent edits.
  final VersionsRecord? record;

  /// Who is in the organization's notes now, by device.
  final List<OrgPresence> seen;
  final bool wisp;
  final int Function()? now;

  static const Key barKey = ValueKey<String>('member-page-bar'), backKey = ValueKey<String>('member-page-back'), statusKey = ValueKey<String>('member-page-status');
  static const Key ticketsKey = ValueKey<String>('member-page-tickets'), ownedKey = ValueKey<String>('member-page-owned'), editsKey = ValueKey<String>('member-page-edits');

  /// A row of one of the sections, by its note (and, for an edit, its version).
  static Key rowKey(String section, String id) => ValueKey<String>('member-page-$section:$id');

  @override
  State<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends State<MemberPage> {
  ChangesAcross? _across;
  List<String> _watched = const [];
  Member? _member;
  Object? _readFor;

  AccountServices? get _services => widget.services;
  int _now() => (widget.now ?? _services?.now ?? () => DateTime.now().millisecondsSinceEpoch)();

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    if (record != null) _across = ChangesAcross(record)..addListener(_changed);
    _services?.changes.addListener(_changed);
    _services?.workspaces?.addListener(_changed);
    _look();
  }

  @override
  void didUpdateWidget(MemberPage old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId || handleKey(old.handle) != handleKey(widget.handle)) {
      _member = null;
      _readFor = null;
      _look();
    }
  }

  @override
  void dispose() {
    _across
      ?..removeListener(_changed)
      ..dispose();
    _services?.changes.removeListener(_changed);
    _services?.workspaces?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Their role and colour, read from the organization once per organization and handle.
  void _look() {
    final services = _services;
    if (services == null || !services.signedIn || services.orgs == null) return;
    final key = (widget.orgId, handleKey(widget.handle));
    if (key == _readFor) return;
    _readFor = key;
    unawaited(() async {
      try {
        final org = await services.orgs!.fetchOrg(widget.orgId);
        final found = org.members.where((m) => handleKey(m.handle) == handleKey(widget.handle)).firstOrNull;
        if (mounted && key == _readFor) setState(() => _member = found);
      } catch (_) {
        // Not read: the page draws from the notes alone.
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final services = _services;
    final row = services != null && services.signedIn ? services.orgs?.orgRow(widget.orgId) : null;
    final now = _now();

    // The organization's notes: filed in its workspace or any folder under it (GHST-107).
    final spaces = services?.workspaces?.value;
    final filed = spaces?.of ?? const <String, String>{};
    final family = workspaceFamily(spaces?.list ?? const [], orgWorkspaceId(widget.orgId)).toSet();
    final here = [for (final note in widget.notes) if (family.contains(filed[note.id])) note];
    final ids = [for (final note in here) note.id];
    if (ids.join('\n') != _watched.join('\n')) {
      _watched = ids;
      _across?.watch(ids);
    }
    final facts = memberFacts(handle: widget.handle, notes: here, changes: _across?.value.changes ?? const [], seen: widget.seen);
    final member = _member;
    final name = member?.handle ?? widget.handle;
    final self = handleKey(widget.handle) == handleKey(services?.session?.handle ?? '');
    final hue = member?.colour;

    final safeTop = t.len('app-safe-top');
    final lg = t.fontSize('lg');
    final sm = t.fontSize('sm');
    final md = t.fontSize('md');
    final bar = safeTop + t.space(2) * 2 + math.max(t.space(8), normalLine(t, lg, weight: 'semibold'));
    final under = bar.roundToDouble();
    final top = math.max(under, safeTop) + t.space(4);
    final foot = t.len('app-safe-bottom') + t.space(10);

    Widget heading(LucideIcon mark, String words, int count) => Row(
          children: [
            ExcludeSemantics(child: AppIcon(mark, size: 15, color: t.color('app-ink-3'))),
            SizedBox(width: t.space(2)),
            Semantics(header: true, child: Text(words, style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2')))),
            if (count > 0) ...[SizedBox(width: t.space(2)), Text('$count', style: pageText(t, sm, color: t.color('app-ink-3')))],
          ],
        );
    Widget none(String words) => Text(words, style: pageText(t, sm, height: t.len('glacier-leading-sm'), color: t.color('app-ink-3')));
    Widget line(Key key, String title, String? aside, VoidCallback onOpen, {LucideIcon icon = Lucide.fileText}) => GlacierPressable(
          key: key,
          onPressed: onOpen,
          semanticLabel: aside == null ? title : '$title, $aside',
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('sm'),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(2)),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('sm')), color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 5%, transparent)') : null),
              child: Row(
                children: [
                  ExcludeSemantics(child: AppIcon(icon, size: 15, color: t.color('app-ink-3'))),
                  SizedBox(width: t.space(2)),
                  Expanded(child: ExcludeSemantics(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, md, color: t.color('app-ink'))))),
                  if (aside != null) ...[SizedBox(width: t.space(2)), ExcludeSemantics(child: Text(aside, maxLines: 1, style: pageText(t, sm, color: t.color('app-ink-3'))))],
                ],
              ),
            ),
          ),
        );
    Widget section(Key key, List<Widget> children) => Semantics(
          key: key,
          container: true,
          explicitChildNodes: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
        );

    final status = facts.online || self
        ? (facts.editing != null ? 'Here now, editing ${facts.editing}' : 'Here now')
        : 'Not in the app now';
    final editingAt = [for (final s in widget.seen) if (!s.ai && handleKey(s.handle) == handleKey(widget.handle) && s.editingNote != null) s.editingNote!].firstOrNull;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlacierScope(
          attrs: {'hue': hue ?? 'ink'},
          child: Builder(
            builder: (context) {
              final there = context.tokens;
              final space = there.colorOf('var(--app-space, var(--app-ink))');
              final side = there.lenOf('3.25rem');
              return Row(
                children: [
                  Container(
                    key: const ValueKey('member-page-round'),
                    width: side,
                    height: side,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hue != null ? there.colorOf('color-mix(in oklch, var(--app-space) 22%, var(--app-paper))') : there.colorOf('color-mix(in oklch, var(--app-ink) 8%, var(--app-paper))'),
                    ),
                    child: ExcludeSemantics(child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(), style: pageText(there, there.fontSize('xl'), weight: 'semibold', color: hue != null ? space : there.color('app-ink')))),
                  ),
                  SizedBox(width: there.space(4)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(name, key: const ValueKey('member-page-name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(there, there.fontSize('2xl'), weight: 'semibold', height: 1.15, color: there.color('app-ink')))),
                            if (member != null) ...[SizedBox(width: there.space(2)), RoleChip(member: member)],
                          ],
                        ),
                        SizedBox(height: there.space(1)),
                        GlacierPressable(
                          key: MemberPage.statusKey,
                          onPressed: editingAt == null ? null : () => widget.onOpenNote(editingAt),
                          semanticLabel: status,
                          builder: (context, state) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (facts.online || self) ...[
                                Container(width: there.lenOf('0.55rem'), height: there.lenOf('0.55rem'), decoration: BoxDecoration(shape: BoxShape.circle, color: space)),
                                SizedBox(width: there.space(2)),
                              ],
                              Flexible(child: ExcludeSemantics(child: Text(status, style: pageText(there, sm, weight: facts.editing != null ? 'medium' : 'regular', color: facts.editing != null ? space : there.color('app-ink-2'))))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: t.space(8)),
        section(MemberPage.ticketsKey, [
          heading(Lucide.ticket, 'Open tickets', facts.tickets.length),
          SizedBox(height: t.space(2)),
          if (facts.tickets.isEmpty)
            none(self ? 'Nothing is assigned to you here.' : 'Nothing is assigned to $name here.')
          else
            for (final each in facts.tickets)
              line(MemberPage.rowKey('ticket', each.note.id), [if (each.ticket.id != null) each.ticket.id!, each.title].join(' '), [each.ticket.status ?? 'To do', if (each.ticket.due != null) 'due ${each.ticket.due}'].join(' · '), () => widget.onOpenNote(each.note.id), icon: Lucide.ticket),
        ]),
        SizedBox(height: t.space(8)),
        section(MemberPage.ownedKey, [
          heading(Lucide.shieldCheck, 'Pages they own', facts.owned.length),
          SizedBox(height: t.space(2)),
          if (facts.owned.isEmpty)
            none('No page here names ${self ? 'you' : name} as its owner or is verified by ${self ? 'you' : 'them'}.')
          else
            for (final note in facts.owned) line(MemberPage.rowKey('owned', note.id), _title(note), null, () => widget.onOpenNote(note.id)),
        ]),
        SizedBox(height: t.space(8)),
        section(MemberPage.editsKey, [
          heading(Lucide.history, 'Recent edits', facts.edits.length),
          SizedBox(height: t.space(2)),
          if (facts.edits.isEmpty)
            none(widget.record == null ? 'Their edits show here once the pages’ history is read.' : '${self ? 'You have' : '$name has'} no edits kept here yet.')
          else
            for (final edit in facts.edits)
              line(MemberPage.rowKey('edit', '${edit.change.noteId}:${edit.change.n}'), edit.title, when.when(edit.change.at, now), () => widget.onOpenNote(edit.change.noteId), icon: Lucide.pencilLine),
        ]),
      ],
    );

    final Widget scroller = SingleChildScrollView(
      key: const ValueKey('member-page-scroll'),
      padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), top, t.len('app-gutter-end'), foot),
      child: DefaultTextStyle(style: pageText(t, md, color: t.color('app-ink')), child: body),
    );

    return GlacierScope(
      attrs: {'hue': row?.hue ?? 'ink'},
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: widget.wisp ? BlurEdge(under: under, child: scroller) : scroller),
              HeaderPane(
                child: Padding(
                  key: MemberPage.barKey,
                  padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start') - t.space(2), t.space(2), t.len('app-gutter-end'), t.space(2)),
                  child: Row(
                    spacing: t.space(2),
                    children: [
                      GlacierPressable(
                        key: MemberPage.backKey,
                        onPressed: widget.onBack,
                        semanticLabel: 'Back to ${row?.name ?? 'the organization'}',
                        builder: (context, state) => GlacierFocusRing(
                          visible: state.focused,
                          child: SizedBox.square(dimension: t.space(8), child: Center(child: AppIcon(Lucide.arrowLeft, size: 20, color: t.color('app-ink')))),
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Row(
                            spacing: t.space(2),
                            children: [
                              ExcludeSemantics(child: HueRound(hue: row?.hue, size: 0.6 * lg)),
                              Flexible(child: Text(row?.name ?? 'Organization', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, lg, weight: 'semibold', tracking: t.len('app-tracking-title', em: lg), color: t.color('app-ink')))),
                              Text.rich(
                                TextSpan(children: [const TextSpan(text: '·'), WidgetSpan(child: SizedBox(width: t.space(2))), TextSpan(text: name)]),
                                style: pageText(t, lg, tracking: t.len('app-tracking-title', em: lg), color: t.color('app-ink-3')),
                                softWrap: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _title(Note note) {
    final title = NoteFacts.of(note).title.trim();
    return title.isEmpty ? 'Untitled' : title;
  }
}
