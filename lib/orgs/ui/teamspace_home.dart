/// The teamspace home (docs/TEAMSPACES.md, "Teamspace home"; Matt, 2026-10-31: "Build first: all four: the sidebar
/// and page tree, the doc page UI, the teamspace home and members, presence"): what an organization's dashboard
/// (organization_screen.dart) draws between its hero and the notes, members and activity it always had.
///
/// - **The members strip**: each member's round in the colour they wear in the organization, with their initial, a dot
///   on it while a device of theirs is in the app (the organization's room says so: lib/live/presence.dart, the
///   same rooms [PagePresence] reads by page), and a press that opens their page (member_page.dart).
/// - **Pinned pages**: the home page's `pins:` (`pinned:` where that is a list; lib/core/page_tree.dart
///   [TeamspaceSettings]), each as a small card with its icon and title, opening it; a pin no note answers to is
///   left out.
/// - **The home page itself**, `orgs/<Org>/Home.md`, drawn as a note is drawn to be read (lib/book/book_view.dart
///   `BookWords`, with the note's own marks and blocks, so its ```query fences are what they find, as anywhere), its
///   front matter and its first heading (the space's name, which the hero already says) left off; Edit opens it in
///   the note's own screen. With no home page yet, "Create the home page" makes one from the template
///   ([teamspaceHomeBody]), filed in the organization so it is the team's.
/// - **Pages open in: Read or Edit**, the home page's `docs:` ([withDocsMode]); in simple mode (GHST-103) behind a
///   More that opens in place.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../book/book_view.dart' show BookDrawing, BookWords;
import '../../core/front_matter.dart' show frontMatterOffset, frontMatterValue;
import '../../core/note.dart';
import '../../core/note_facts.dart';
import '../../core/page_tree.dart';
import '../../core/title_key.dart' show titleKey;
import '../../home/home_organizations.dart' show OrgPresence;
import '../../mentions/mention_syntax.dart' show handleKey;
import '../../sheet/css.dart';
import '../orgs.dart' show Member;

/// The home page's words as the dashboard draws them: no front matter, and no first heading where it is the page's
/// first line (the hero says the space's name).
String homeWords(String body) {
  var text = body.substring(frontMatterOffset(body));
  final lead = RegExp(r'^\s*#[ \t]+[^\n]*\n?').firstMatch(text);
  if (lead != null) text = text.substring(lead.end);
  return text.replaceFirst(RegExp(r'^\s*\n'), '');
}

/// The pinned pages among [notes], in the order the home page names them: each title (or file name) to the first
/// note it answers to; one nothing answers to left out, and a page pinned twice drawn once.
List<Note> pinnedNotes(List<String> pins, Iterable<Note> notes) {
  final byTitle = <String, Note>{};
  for (final note in notes) {
    if (note.inTrash || (note.archivedAt ?? 0) != 0) continue;
    byTitle.putIfAbsent(titleKey(NoteFacts.of(note).title), () => note);
    final path = note.path;
    if (path != null) {
      final file = path.substring(path.lastIndexOf('/') + 1);
      byTitle.putIfAbsent(titleKey(file.toLowerCase().endsWith('.md') ? file.substring(0, file.length - 3) : file), () => note);
    }
  }
  final seen = <String>{};
  return [
    for (final pin in pins)
      if (byTitle[titleKey(pin)] case final note? when seen.add(note.id)) note,
  ];
}

/// What the teamspace home draws (see the library's doc).
class TeamspaceHome extends StatefulWidget {
  const TeamspaceHome({
    super.key,
    required this.space,
    required this.home,
    required this.notes,
    required this.members,
    required this.seen,
    required this.me,
    required this.onOpenNote,
    this.drawing,
    this.onMember,
    this.onCreateHome,
    this.onSetDocs,
    this.simple = false,
  });

  /// The organization's space ([spaceOfOrg]); null where this device has no folder for it, and nothing of the home
  /// page is offered then (the strip still is).
  final Space? space;

  /// Its home page, or null for none yet ([teamspaceHomeIn]).
  final Note? home;

  /// The organization's notes, which the pins are found among.
  final List<Note> notes;

  /// Its members as the service last said them; null while they are being read.
  final List<Member>? members;

  /// Who is in the app now, by device.
  final List<OrgPresence> seen;
  final String me;
  final ValueChanged<String> onOpenNote;

  /// The marks and blocks the home page draws (the root's: lib/root/page_drawing.dart); null draws its words alone.
  final BookDrawing? drawing;

  /// A member's page, by their handle; absent, the rounds are not pressed.
  final ValueChanged<String>? onMember;

  /// Makes the home page; absent, nothing offers to.
  final Future<void> Function()? onCreateHome;

  /// Writes the home page's `docs:` (making the home page first where there is none); absent, no setting.
  final Future<void> Function(DocsMode mode)? onSetDocs;

  /// Simple mode: the setting behind More.
  final bool simple;

  static const Key stripKey = ValueKey<String>('members-strip'), pinsKey = ValueKey<String>('pinned-pages'), pageKey = ValueKey<String>('home-page');
  static const Key createKey = ValueKey<String>('home-create'), editKey = ValueKey<String>('home-edit'), docsKey = ValueKey<String>('home-docs'), moreKey = ValueKey<String>('home-more');

  /// A member's round on the strip, and its dot while they are here.
  static Key memberKey(String handle) => ValueKey<String>('strip-member:${handleKey(handle)}');
  static Key onlineKey(String handle) => ValueKey<String>('strip-online:${handleKey(handle)}');

  /// A pinned page's card, by its note.
  static Key pinKey(String noteId) => ValueKey<String>('pinned:$noteId');

  /// One of the docs setting's two words.
  static Key docsChoiceKey(DocsMode mode) => ValueKey<String>('home-docs-${mode.name}');

  @override
  State<TeamspaceHome> createState() => _TeamspaceHomeState();
}

class _TeamspaceHomeState extends State<TeamspaceHome> {
  bool _more = false;
  bool _making = false;

  Future<void> _create() async {
    final make = widget.onCreateHome;
    if (make == null || _making) return;
    setState(() => _making = true);
    try {
      await make();
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final md = t.fontSize('md');
    final home = widget.home;
    final settings = TeamspaceSettings.of(home?.body);
    final pins = pinnedNotes(settings.pinned, widget.notes);

    Widget heading(LucideIcon mark, String words, {Widget? end}) => Row(
          children: [
            ExcludeSemantics(child: AppIcon(mark, size: 15, color: t.color('app-ink-3'))),
            SizedBox(width: t.space(2)),
            Semantics(header: true, child: Text(words, style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2')))),
            const Spacer(),
            ?end,
          ],
        );

    final children = <Widget>[
      _MembersStrip(key: TeamspaceHome.stripKey, members: widget.members, seen: widget.seen, me: widget.me, onMember: widget.onMember),
      if (pins.isNotEmpty) ...[
        SizedBox(height: t.space(6)),
        heading(Lucide.pin, 'Pinned'),
        SizedBox(height: t.space(3)),
        Wrap(
          key: TeamspaceHome.pinsKey,
          spacing: t.space(2),
          runSpacing: t.space(2),
          children: [for (final note in pins) _PinCard(key: TeamspaceHome.pinKey(note.id), note: note, onOpen: () => widget.onOpenNote(note.id))],
        ),
      ],
      if (widget.space != null && (home != null || widget.onCreateHome != null || widget.onSetDocs != null)) ...[
        SizedBox(height: t.space(6)),
        if (home != null) ...[
          heading(
            Lucide.bookOpenText,
            'Home',
            end: _Word(key: TeamspaceHome.editKey, icon: Lucide.pencil, words: 'Edit', label: 'Edit the home page', onPressed: () => widget.onOpenNote(home.id)),
          ),
          BookWords(key: TeamspaceHome.pageKey, words: homeWords(home.body), drawing: widget.drawing),
        ] else if (widget.onCreateHome != null)
          _CreateHome(making: _making, onCreate: _create),
        if (widget.onSetDocs != null) ...[
          if (home != null || widget.onCreateHome != null) SizedBox(height: t.space(3)),
          if (widget.simple && !_more)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _Word(key: TeamspaceHome.moreKey, icon: Lucide.chevronDown, words: 'More', label: 'More of the space’s settings', onPressed: () => setState(() => _more = true)),
            )
          else
            _DocsChoice(key: TeamspaceHome.docsKey, mode: settings.docs, onChoose: (mode) => unawaited(widget.onSetDocs!(mode))),
        ],
      ],
    ];
    return DefaultTextStyle(
      style: pageText(t, md, color: t.color('app-ink')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// The members' rounds, in their colours, the ones in the app now first after you.
class _MembersStrip extends StatelessWidget {
  const _MembersStrip({super.key, required this.members, required this.seen, required this.me, this.onMember});
  final List<Member>? members;
  final List<OrgPresence> seen;
  final String me;
  final ValueChanged<String>? onMember;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final joined = [for (final m in members ?? const <Member>[]) if (m.state == 'member') m];
    final here = {for (final s in seen) if (!s.ai) handleKey(s.handle)};
    final mine = handleKey(me);
    bool online(Member m) => handleKey(m.handle) == mine || here.contains(handleKey(m.handle));
    final ordered = [...joined]..sort((a, b) {
        final ah = handleKey(a.handle) == mine ? 0 : (online(a) ? 1 : 2), bh = handleKey(b.handle) == mine ? 0 : (online(b) ? 1 : 2);
        return ah != bh ? ah.compareTo(bh) : a.handle.toLowerCase().compareTo(b.handle.toLowerCase());
      });
    final side = t.lenOf('2.25rem');
    final count = here.where((h) => h != mine).length;
    return Semantics(
      container: true,
      label: members == null ? 'Members' : 'Members, ${joined.length}${count > 0 ? ', $count here now' : ''}',
      explicitChildNodes: true,
      child: Wrap(
        spacing: t.space(2),
        runSpacing: t.space(2),
        children: [
          for (final m in ordered)
            GlacierPressable(
              key: TeamspaceHome.memberKey(m.handle),
              onPressed: onMember == null ? null : () => onMember!(m.handle),
              semanticLabel: '${m.handle}${online(m) && handleKey(m.handle) != mine ? ', here now' : ''}',
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                radius: t.radius('full'),
                child: _Round(hue: m.colour, side: side, words: m.handle.isEmpty ? '?' : m.handle.substring(0, 1).toUpperCase(), online: online(m), dotKey: online(m) ? TeamspaceHome.onlineKey(m.handle) : null),
              ),
            ),
        ],
      ),
    );
  }
}

/// A member's round: their colour as a wash with their initial in it, a dot at its corner while they are here.
class _Round extends StatelessWidget {
  const _Round({required this.hue, required this.side, required this.words, required this.online, this.dotKey});
  final String? hue;
  final double side;
  final String words;
  final bool online;
  final Key? dotKey;

  @override
  Widget build(BuildContext context) => GlacierScope(
        // No colour of their own: the page's, as their line under Members wears it.
        attrs: {'hue': ?hue},
        child: Builder(
          builder: (context) {
            final here = context.tokens;
            final hued = hue != null;
            final space = here.colorOf('var(--app-space, var(--app-ink))');
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: side,
                  height: side,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hued ? here.colorOf('color-mix(in oklch, var(--app-space) 22%, var(--app-paper))') : here.colorOf('color-mix(in oklch, var(--app-ink) 8%, var(--app-paper))'),
                  ),
                  child: ExcludeSemantics(child: Text(words, style: pageText(here, here.fontSize('sm'), weight: 'semibold', color: hued ? space : here.color('app-ink')))),
                ),
                if (online)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      key: dotKey,
                      width: here.lenOf('0.62rem'),
                      height: here.lenOf('0.62rem'),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: space, boxShadow: [BoxShadow(color: here.color('app-paper'), spreadRadius: 2)]),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

/// A pinned page: its icon and title on a small card.
class _PinCard extends StatelessWidget {
  const _PinCard({super.key, required this.note, required this.onOpen});
  final Note note;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final facts = NoteFacts.of(note);
    final title = facts.title.trim().isEmpty ? 'Untitled' : facts.title.trim();
    final icon = PageIcon.of(frontMatterValue(note.body, 'icon'));
    final line = snapBorder(context, t.len('glacier-hairline'));
    return GlacierPressable(
      onPressed: onOpen,
      semanticLabel: 'Pinned: $title',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('md'),
        child: Container(
          constraints: BoxConstraints(maxWidth: t.lenOf('16rem'), minHeight: t.lenOf('2.75rem')),
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
          decoration: BoxDecoration(
            color: t.colorOf('color-mix(in oklch, var(--app-ink) ${state.hovered ? 6 : 3}%, transparent)'),
            borderRadius: BorderRadius.circular(t.radius('md')),
            border: Border.all(color: t.color('glacier-border-subtle'), width: line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: icon?.emoji != null ? Text(icon!.emoji!, style: pageText(t, sm)) : AppIcon(icon?.name != null ? (Lucide.all[icon!.name!] ?? Lucide.fileText) : Lucide.fileText, size: 15, color: t.color('app-ink-2')),
              ),
              SizedBox(width: t.space(2)),
              Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink')))),
            ],
          ),
        ),
      ),
    );
  }
}

/// No home page yet: what one is, and the way to make it.
class _CreateHome extends StatelessWidget {
  const _CreateHome({required this.making, required this.onCreate});
  final bool making;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('The space has no home page yet: a page everyone sees first, with what a new member should read, the pinned pages, and the recent changes and open tickets.', style: pageText(t, sm, height: t.len('glacier-leading-sm'), color: t.color('app-ink-3'))),
        SizedBox(height: t.space(3)),
        _Word(key: TeamspaceHome.createKey, icon: Lucide.filePlus, words: making ? 'Making it…' : 'Create the home page', label: 'Create the home page', onPressed: making ? null : onCreate, filled: true),
      ],
    );
  }
}

/// Pages open in: Read or Edit.
class _DocsChoice extends StatelessWidget {
  const _DocsChoice({super.key, required this.mode, required this.onChoose});
  final DocsMode mode;
  final ValueChanged<DocsMode> onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    Widget pill(DocsMode each, String words) {
      final on = each == mode;
      return GlacierPressable(
        key: TeamspaceHome.docsChoiceKey(each),
        onPressed: on ? null : () => onChoose(each),
        semanticLabel: on ? '$words, chosen' : words,
        toggled: on,
        builder: (context, state) => Container(
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius('full')),
            color: on ? t.color('app-ink') : (state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 7%, transparent)') : null),
          ),
          child: Text(words, maxLines: 1, style: pageText(t, sm, weight: 'medium', color: on ? t.color('app-paper') : t.color('app-ink-2'))),
        ),
      );
    }

    return Row(
      children: [
        Flexible(child: Text('Pages open in', style: pageText(t, sm, color: t.color('app-ink-2')))),
        SizedBox(width: t.space(3)),
        pill(DocsMode.read, 'Read'),
        SizedBox(width: t.space(1)),
        pill(DocsMode.edit, 'Edit'),
      ],
    );
  }
}

/// A quiet word with its mark: Edit, More, Create the home page.
class _Word extends StatelessWidget {
  const _Word({super.key, required this.icon, required this.words, required this.label, required this.onPressed, this.filled = false});
  final LucideIcon icon;
  final String words;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final line = snapBorder(context, t.len('glacier-hairline'));
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('full'),
        child: Opacity(
          opacity: state.disabled ? 0.5 : 1,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
            decoration: ShapeDecoration(
              color: t.colorOf('color-mix(in oklch, var(--app-ink) ${state.hovered ? 9 : (filled ? 5 : 0)}%, transparent)'),
              shape: StadiumBorder(side: BorderSide(color: filled ? t.color('glacier-border-subtle') : const Color(0x00000000), width: line)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 14, color: t.color('app-ink-2')),
                SizedBox(width: t.space(1)),
                ExcludeSemantics(child: Text(words, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink-2')))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
