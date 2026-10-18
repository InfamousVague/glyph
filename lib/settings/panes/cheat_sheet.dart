import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart';
import '../kit/settings_type.dart';
import '../settings_screen.dart' show SettingsNoSwipe;
import '../settings_search.dart';
import 'marks.g.dart';

/// What Settings' search finds on the cheat sheet (`findable`, src/app/guide/CheatSheet.findable.ts): every mark it
/// shows, by its name and its characters, so looking for "bold" or "||" lands on it.
List<SettingsFindable> cheatSheetFindable() => [
  for (final group in markGroups)
    for (final row in group.rows) SettingsFindable(row.name, row.symbol),
];

/// The basics (GHST-103; Matt: "work on making formatting and stuff easier to understand"): the dozen marks most
/// notes are made of, each with a line saying what it does in plain words, first on the sheet in both modes. The
/// rows are marks.g.dart's own, found by name, so what each shows to type is what the whole sheet shows; only the
/// plain line is written here, since the snapshot is made, not written, and has no field for one.
const String basicsTitle = 'The basics';
const String basicsLead = 'Most notes are made of these dozen marks.';

/// Each basic by the name marks.g.dart gives it, with its plain line.
const List<(String, String)> basicsPlain = [
  ('Title', 'The note’s name, on its first line.'),
  ('Heading', 'A name for a section, so the note has parts.'),
  ('Bold', 'Makes the words stand out.'),
  ('Italic', 'Slants the words, for a stress or an aside.'),
  ('A link', 'Words that open a web page when tapped.'),
  ('A list', 'Points, one to a line, each with a dot.'),
  ('In order', 'Steps, numbered.'),
  ('A to-do', 'A box to tick when it is done.'),
  ('A quote', 'Someone else’s words, set apart from yours.'),
  ('A table', 'Rows and columns, drawn from the bars.'),
  ('A picture', 'A picture in the note, from a file or a link.'),
  ('A dividing line', 'A line across the page between parts.'),
];

/// The plain line for a mark, where it is one of the basics.
String? plainLineOf(MarkRow row) {
  for (final (name, line) in basicsPlain) {
    if (name == row.name) return line;
  }
  return null;
}

/// The basics as a group: the rows of [markGroups] named in [basicsPlain], in that order. A name the snapshot
/// does not have (a plugin's mark gone) is left out rather than invented.
MarkGroup basicsGroup() {
  final byName = <String, MarkRow>{
    for (final group in markGroups)
      for (final row in group.rows) row.name: row,
  };
  return MarkGroup(title: basicsTitle, lead: basicsLead, rows: [for (final (name, _) in basicsPlain) ?byName[name]]);
}

/// The title of the disclosure the rest of the sheet sits behind in simple mode.
const String everythingElseTitle = 'Everything else';

/// The marks left after the field (`found`): a mark is found by its name, its characters, or the words of its
/// example. The basics are not searched: each is in its own group too, and would be found twice.
List<MarkGroup> marksFound(String looking) {
  final words = looking.trim().toLowerCase();
  if (words.isEmpty) return markGroups;
  return [
    for (final group in markGroups)
      if (group.rows.any((row) => _has(row, words)))
        MarkGroup(
          title: group.title,
          lead: group.lead,
          rows: [
            for (final row in group.rows)
              if (_has(row, words)) row,
          ],
        ),
  ];
}

bool _has(MarkRow row, String words) => [row.name, row.symbol, row.typed, row.words].any((part) => part.toLowerCase().contains(words));

/// Port of `CheatSheet` (src/app/guide/CheatSheet.tsx with CheatSheet.module.css): every formatting character. A
/// field to find a mark by name or by the characters themselves, a line of chips to jump by group, and a card for
/// each mark: its icon, its name, the characters in a ring, and the line to type. The field and the chips stay at
/// the top of the page as it scrolls. One column on a phone, two or more where there is room.
///
/// The rows are the web app's own guide/marks.ts, read off the running page into marks.g.dart.
///
/// What differs from the web original:
/// - **"Reads" is not drawn.** On the page each card ends with the same line as the note itself draws it
///   (guide/MarkExample.tsx is the note's editor, read-only). The editor is stage 4, so a card here stops at what to
///   type; the label and the example come back with it.
/// - The rows are every mark with every plugin on, as the page had them when they were read: there are no plugins
///   here to switch one off (stage 9), where the page reads its registry live.
/// - The search finds each mark by name, and opening one from Settings' search lands on the page without lighting
///   the card, since the card's name is not one of the kit's parts.
/// - The field is an `EditableText` with the kit's handles and menu; the page's was an `<input type=search>`.
/// - **The basics come first** ([basicsGroup]), in both modes, each card with its plain line. In simple mode
///   (GHST-103) the groups after them sit behind one disclosure, Everything else, closed until pressed; in
///   advanced they are open, as the page's are. A search shows what it finds in either mode.
class CheatSheet extends StatefulWidget {
  const CheatSheet({super.key, this.simple});

  /// Simple mode (see above); null asks the preferences.
  final bool? simple;

  @override
  State<CheatSheet> createState() => _CheatSheetState();
}

class _CheatSheetState extends State<CheatSheet> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'find a mark');
  final Map<String, GlobalKey> _heads = {for (final group in [basicsGroup(), ...markGroups]) group.title: GlobalKey(debugLabel: 'marks ${group.title}')};
  final GlobalKey _sheet = GlobalKey(debugLabel: 'cheat sheet');

  /// Simple mode's Everything else has been opened.
  bool _rest = false;

  bool get _simple => widget.simple ?? preferences.value.simple;

  /// How many groups are built: the first [_soon] with the page, and [_soon] more each frame after. The sheet is
  /// a hundred cards and more, and built whole its one frame was 22 ms on a Mac (measured, tool/perf.sh); the
  /// groups past the second are under the window's foot.
  int _built = _soon;
  bool _waiting = false;
  static const int _soon = 2;

  /// [_soon] more of the groups a frame from now.
  void _more() {
    if (_waiting) return;
    _waiting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _waiting = false;
      if (mounted) setState(() => _built += _soon);
    });
  }

  @override
  void initState() {
    super.initState();
    _field.addListener(_changed);
    _focus.addListener(_changed);
    if (widget.simple == null) preferences.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    if (widget.simple == null) preferences.removeListener(_changed);
    super.dispose();
  }

  /// Everything else, opened: its groups built from here, and the page taken to its first.
  void _openRest() {
    setState(() => _rest = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jump(markGroups.first.title);
    });
  }

  /// The chips are a way down a long page: the group's heading goes to the top of whatever is scrolling
  /// (`scrollIntoView({ block: 'start' })`, a `--glacier-space-2` short of it).
  void _jump(String title) {
    final context = _heads[title]?.currentContext;
    final object = context?.findRenderObject();
    if (context == null || object == null) return;
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return;
    final t = context.tokens;
    final to = (RenderAbstractViewport.of(object).getOffsetToReveal(object, 0).offset - t.space(2)).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (t.reducedMotion) {
      position.jumpTo(to);
    } else {
      position.animateTo(to, duration: t.duration('glacier-duration-slow'), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final looking = _field.text;
    final simple = _simple;
    // Searching: what is found, flat. Not: the basics, then the rest, which simple keeps behind Everything else.
    final behind = simple && !_rest && looking.isEmpty;
    final found = looking.isEmpty ? [basicsGroup(), if (!behind) ...markGroups] : marksFound(looking);
    final ground = t.colorOf('var(--sheet-ground, var(--glacier-bg))');
    final sm = t.fontSize('sm');
    final subtle = t.color('glacier-text-subtle');
    final muted = t.color('glacier-text-muted');

    final sticky = _Pinned(
      within: _sheet,
      child: Container(
        padding: EdgeInsets.only(bottom: t.space(2)),
        decoration: BoxDecoration(
          color: ground,
          // A soft foot rather than a hard edge, so the cards pass under the strip rather than being cut by it.
          boxShadow: [BoxShadow(color: ground, offset: const Offset(0, 12), blurRadius: 12, spreadRadius: -8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _MarkField(controller: _field, focusNode: _focus, ground: ground),
            SizedBox(height: t.space(3)),
            if (looking.isEmpty)
              Semantics(
                container: true,
                label: 'The groups of marks',
                child: SettingsNoSwipe(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(top: t.space(2)),
                    child: Row(
                      children: [
                        for (var i = 0; i < found.length; i++) ...[
                          if (i > 0) SizedBox(width: t.space(2)),
                          _Chip(key: ValueKey('chip ${found[i].title}'), title: found[i].title, ground: ground, onPress: () => _jump(found[i].title)),
                        ],
                        // Behind the disclosure, one chip for all of it, which opens it.
                        if (behind) ...[
                          SizedBox(width: t.space(2)),
                          _Chip(key: const ValueKey('chip $everythingElseTitle'), title: everythingElseTitle, ground: ground, onPress: _openRest),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (_built < found.length) _more();
    final groups = <Widget>[
      for (var g = 0; g < found.length && g < _built; g++)
        Padding(
          key: ValueKey('group ${found[g].title}'),
          // `.group + .group { margin-block-start: var(--glacier-space-8) }`
          padding: EdgeInsets.only(top: g == 0 ? 0 : t.space(8)),
          // A layer of its own for each group: the strip over them is moved at every frame of a scroll to stay at
          // the page's top (`_Pinned`), and what shares a layer with it is drawn again with it, which was every
          // card and every example on the page, sixty times a second (on the Fold a fling of the cheat sheet was
          // 4.3 ms of build a frame, 415 of 561 frames late; a third of the Mac's samples were paragraphs painted).
          child: RepaintBoundary(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                key: _heads[found[g].title],
                header: true,
                label: found[g].title,
                child: ExcludeSemantics(
                  child: Text(
                    found[g].title.toUpperCase(),
                    style: pageText(
                      t,
                      sm,
                      weight: 'semibold',
                      color: subtle,
                      tracking: t.len('app-tracking-caps', em: sm),
                    ),
                  ),
                ),
              ),
              SizedBox(height: t.space(1)),
              Text(
                found[g].lead,
                style: pageText(t, sm, height: t.len('glacier-leading-md'), color: muted),
              ),
              SizedBox(height: t.space(3)),
              _Cards(rows: found[g].rows, ground: ground, plain: found[g].title == basicsTitle),
            ],
          )),
        ),
      // Simple mode: the rest of the sheet, closed, with how much there is. Matt: "fancy features hidden behind
      // more".
      if (behind)
        Padding(
          padding: EdgeInsets.only(top: t.space(8)),
          child: _Disclosure(
            key: const ValueKey('everything-else'),
            title: everythingElseTitle,
            line: '${[for (final group in markGroups) group.rows.length].fold(0, (sum, n) => sum + n)} more marks, in ${markGroups.length} groups.',
            onPress: _openRest,
          ),
        ),
      if (found.isEmpty)
        Padding(
          padding: EdgeInsets.only(top: t.space(6)),
          child: Text(
            'No mark by that name. Try “bold”, “||” or “board”.',
            textAlign: TextAlign.center,
            style: pageText(t, t.lenOf('1rem'), color: subtle),
          ),
        ),
    ];

    // The strip is the first thing on the page and the last thing painted, so the cards pass under it: the column
    // is built from its foot up.
    return Padding(
      key: _sheet,
      padding: EdgeInsets.only(bottom: t.space(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, verticalDirection: VerticalDirection.up, children: [...groups.reversed, sticky]),
    );
  }
}

/// `position: sticky; inset-block-start: 0`: its child stays at the top of whatever scrolls it for as long as
/// [within] is on the page.
class _Pinned extends StatelessWidget {
  const _Pinned({required this.within, required this.child});
  final GlobalKey within;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return child;
    return AnimatedBuilder(
      animation: position,
      child: child,
      builder: (context, child) {
        var dy = 0.0;
        final own = context.findRenderObject();
        final all = within.currentContext?.findRenderObject();
        if (own is RenderBox && own.hasSize && all is RenderBox && all.hasSize && position.hasPixels) {
          final top = RenderAbstractViewport.of(all).getOffsetToReveal(all, 0).offset;
          final room = all.size.height - own.size.height;
          dy = (position.pixels - top).clamp(0.0, room < 0 ? 0.0 : room);
        }
        return Transform.translate(offset: Offset(0, dy), child: RepaintBoundary(child: child));
      },
    );
  }
}

/// Everything else, closed: a row the shape of a card, its title and how much is behind it, and a chevron pointing
/// down, since pressing it opens the rest below.
class _Disclosure extends StatelessWidget {
  const _Disclosure({super.key, required this.title, required this.line, required this.onPress});
  final String title;
  final String line;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: '$title, $line',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('lg'),
        child: Container(
          padding: EdgeInsets.all(t.space(3)),
          decoration: BoxDecoration(
            color: Color.alphaBlend(t.color('app-ink').withValues(alpha: state.pressed ? 0.08 : 0.04), t.color('glacier-bg')),
            borderRadius: BorderRadius.circular(t.radius('lg')),
            border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)'), width: t.len('glacier-hairline')),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: pageText(t, t.fontSize('md'), weight: 'semibold')),
                    SizedBox(height: t.space(1)),
                    Text(line, style: pageText(t, sm, color: muted)),
                  ],
                ),
              ),
              SizedBox(width: t.space(2)),
              AppIcon(Lucide.chevronDown, size: 18, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.chip`: a group's name in an outlined pill.
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.title, required this.ground, required this.onPress});
  final String title;
  final Color ground;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    return GlacierPressable(
      onPressed: onPress,
      builder: (context, state) {
        final ink = state.pressed ? t.color('glacier-text') : muted;
        return GlacierFocusRing(
          visible: state.focused,
          radius: 999,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 0.35 * sm, horizontal: 0.85 * sm),
            decoration: ShapeDecoration(
              color: state.pressed ? Color.alphaBlend(ink.withValues(alpha: 0.10), ground) : null,
              shape: StadiumBorder(
                side: BorderSide(
                  color: ink.withValues(alpha: ink.a * 0.18),
                  width: t.len('glacier-hairline'),
                ),
              ),
            ),
            child: Text(title, maxLines: 1, softWrap: false, style: pageText(t, sm, color: ink)),
          ),
        );
      },
    );
  }
}

/// `.cards`: `repeat(auto-fill, minmax(17rem, 1fr))`, a `--glacier-space-3` apart. The cards of a row are one
/// height, and a board takes a row to itself. A basic's card is keyed apart from the same mark's card in its own
/// group, since both are on the page.
class _Cards extends StatelessWidget {
  const _Cards({required this.rows, required this.ground, this.plain = false});
  final List<MarkRow> rows;
  final Color ground;

  /// The basics: each card carries its plain line.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(3);
    return LayoutBuilder(
      builder: (context, box) {
        final least = t.lenOf('17rem');
        final across = ((box.maxWidth + gap) / (least + gap)).floor().clamp(1, 99);
        final lines = <List<MarkRow>>[];
        for (final row in rows) {
          if (row.looks == 'board' || lines.isEmpty || lines.last.length == across || lines.last.first.looks == 'board') {
            lines.add([row]);
          } else {
            lines.last.add(row);
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              if (across == 1 || lines[i].first.looks == 'board')
                MarkCard(key: ValueKey(plain ? 'basic ${lines[i].first.name}' : lines[i].first.name), row: lines[i].first, ground: ground, plain: plain ? plainLineOf(lines[i].first) : null)
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < across; c++) ...[
                        if (c > 0) SizedBox(width: gap),
                        Expanded(
                          child: c < lines[i].length ? MarkCard(key: ValueKey(plain ? 'basic ${lines[i][c].name}' : lines[i][c].name), row: lines[i][c], ground: ground, plain: plain ? plainLineOf(lines[i][c]) : null) : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// One mark (`Card`, `.card`): its icon and name, the characters in a ring, and what to type. One of the basics
/// says in a line what it does, under its name ([plainLineOf]).
class MarkCard extends StatelessWidget {
  const MarkCard({super.key, required this.row, this.ground, this.plain});
  final MarkRow row;
  final Color? ground;

  /// What the mark does, in plain words; absent on all but the basics.
  final String? plain;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    final sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final icon = Lucide.all[row.icon];
    final tile = t.lenOf('1.75rem');
    return Container(
      padding: EdgeInsets.all(t.space(3)),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.color('app-ink').withValues(alpha: 0.04), ground ?? t.color('glacier-bg')),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)'), width: t.len('glacier-hairline')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: tile,
                  height: tile,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.color('app-wash'), borderRadius: BorderRadius.circular(t.radius('md'))),
                  child: icon == null ? null : AppIcon(icon, size: 16, color: muted),
                ),
              ),
              SizedBox(width: t.space(2)),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(row.name, style: pageText(t, t.fontSize('md'), weight: 'semibold')),
                ),
              ),
              SizedBox(width: t.space(2)),
              // The mark itself, in a ring, so the eye finds it before the words.
              Container(
                padding: EdgeInsets.symmetric(vertical: 0.15 * sm, horizontal: 0.45 * sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.radius('md')),
                  border: Border.all(color: t.color('glacier-border-strong'), width: t.len('glacier-hairline')),
                ),
                child: Text(row.symbol, maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'semibold', mono: true)),
              ),
            ],
          ),
          if (plain != null) ...[
            SizedBox(height: t.space(2)),
            Text(plain!, style: pageText(t, sm, height: t.len('glacier-leading-md'), color: muted)),
          ],
          // `.head { margin-block-end }` and the card's own gap.
          SizedBox(height: t.space(1) * 2),
          Semantics(
            label: 'Type',
            child: ExcludeSemantics(
              child: Text(
                'TYPE',
                style: pageText(
                  t,
                  xs,
                  color: t.color('glacier-text-subtle'),
                  tracking: t.len('app-tracking-caps', em: xs),
                ),
              ),
            ),
          ),
          SizedBox(height: t.space(1)),
          Container(
            key: const ValueKey('mark-typed'),
            width: double.infinity,
            margin: EdgeInsets.only(bottom: t.space(2)),
            padding: EdgeInsets.all(t.space(2)),
            decoration: BoxDecoration(color: t.color('glacier-surface-sunken'), borderRadius: BorderRadius.circular(t.radius('md'))),
            child: Text(row.typed, style: pageText(t, sm, color: muted, height: 1.5, mono: true)),
          ),
        ],
      ),
    );
  }
}

/// `.find`: the field, a pill a shade off the page with a line inside its edge.
class _MarkField extends StatefulWidget {
  const _MarkField({required this.controller, required this.focusNode, required this.ground});
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color ground;

  @override
  State<_MarkField> createState() => _MarkFieldState();
}

class _MarkFieldState extends State<_MarkField> implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _handles = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    final subtle = t.color('glacier-text-subtle');
    final style = pageText(t, t.fontSize('md'), color: t.color('glacier-text'));
    final focused = widget.focusNode.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;
    final editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: style,
      cursorColor: t.color('glacier-text'),
      cursorWidth: 1,
      backgroundCursorColor: subtle,
      selectionColor: focused ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _handles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      // `inputMode="search" autoCapitalize="off" autoCorrect="off" spellCheck={false}`
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      maxLines: 1,
      onSelectionChanged: (selection, cause) {
        final show = cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.doubleTap || (cause == SelectionChangedCause.tap && hasText);
        final touch = switch (defaultTargetPlatform) {
          TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
          _ => false,
        };
        if (_handles != (show && touch)) setState(() => _handles = show && touch);
      },
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      // `box-shadow: inset 0 0 0 1px`: a line inside the pill's edge, which takes no room.
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Color.alphaBlend(ink.withValues(alpha: 0.08), widget.ground),
          shape: StadiumBorder(
            side: BorderSide(
              color: ink.withValues(alpha: focused ? 0.45 : 0.16),
              width: focused ? t.len('app-line') : 1,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(3)),
          child: Row(
            children: [
              ExcludeSemantics(child: AppIcon(Lucide.search, size: 16, color: subtle)),
              SizedBox(width: t.space(2)),
              Expanded(
                child: ConstrainedBox(
                  // The page's `<input>`: its line, and the pixel a browser keeps over and under it.
                  constraints: BoxConstraints(minHeight: (style.height ?? 1.25) * style.fontSize! + 2),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: _gestures.buildGestureDetector(
                      behavior: HitTestBehavior.translucent,
                      child: Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [
                          if (!hasText)
                            ExcludeSemantics(
                              child: Text('Find a mark', maxLines: 1, softWrap: false, style: style.copyWith(color: subtle)),
                            ),
                          DefaultTextEditingShortcuts(
                            child: Semantics(
                              label: 'Find a mark',
                              onTap: () {
                                widget.focusNode.requestFocus();
                                editableTextKey.currentState?.requestKeyboard();
                              },
                              child: editable,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (hasText) ...[
                SizedBox(width: t.space(2)),
                GlacierPressable(
                  onPressed: widget.controller.clear,
                  semanticLabel: 'Clear',
                  builder: (context, state) => AppIcon(Lucide.x, size: 16, color: subtle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
