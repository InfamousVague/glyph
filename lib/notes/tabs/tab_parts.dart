import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/tabs.dart';
import '../../core/workspaces.dart';
import '../../shell/pop_menu.dart';
import 'bar_icon.dart';
import 'bar_parts.dart';
import 'tab_row.dart';

// What stands in the tab row (notes/NoteTabs.tsx `tabRow`, NoteTabs.module.css): a tab, a group's chip
// (notes/GroupChip.tsx), Home pinned at the row's start, the + at its end, and the two menus (notes/TabMenus.tsx).

/// A name written where it was shown: a canvas's in its tab, a group's in its chip. Focused as it appears with its
/// words selected; Enter keeps them, leaving the field keeps them too (a phone has no Escape, and losing the words to
/// a stray tap would be worse than a name kept by accident), and Escape leaves the name it had.
class _NameField extends StatefulWidget {
  const _NameField({required this.initial, required this.label, required this.style, this.around = EdgeInsets.zero, required this.onDone});

  final String initial;

  /// The padding its box has on the page, drawn by whoever holds it: brought into view with the field.
  final EdgeInsets around;

  /// `aria-label`.
  final String label;
  final TextStyle style;

  /// The end of the rename, however it ends, once: the words, and whether they are to be kept.
  final void Function(String words, bool keep) onDone;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _words = TextEditingController(text: widget.initial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  late final FocusNode _focus = FocusNode(debugLabel: widget.label, onKeyEvent: _onKey);
  bool _done = false;

  /// The field closes first, so the blur that follows it finds nothing open and cannot keep the same name twice.
  void _end(bool keep) {
    if (_done) return;
    _done = true;
    widget.onDone(_words.text, keep);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _end(false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _end(true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _end(true);
    });
    // `autoFocus`: the field takes the focus when it is made, whoever had it. An `autofocus` alone is given the
    // focus only where nothing in its scope has it, and a tab's menu closing had, so Rename put up a field with no
    // caret and no keyboard until it was tapped (seen beside the Tauri app, whose keyboard comes with the field).
    // And the row brings it into view, as a page does a field that takes the focus: the far end first, where the
    // last tab's field runs off the window, then the near one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _done) return;
      _focus.requestFocus();
      final position = Scrollable.maybeOf(context)?.position;
      final box = context.findRenderObject();
      if (position == null || box is! RenderBox || !box.hasSize) return;
      // The field's box on the page is its padding too ([around]), where the ring is drawn.
      final rect = widget.around.inflateRect(Offset.zero & box.size);
      final viewport = RenderAbstractViewport.of(box);
      final atEnd = viewport.getOffsetToReveal(box, 1, rect: rect).offset, atStart = viewport.getOffsetToReveal(box, 0, rect: rect).offset;
      final to = position.pixels < atEnd ? atEnd : (position.pixels > atStart ? atStart : position.pixels);
      position.jumpTo(to.clamp(position.minScrollExtent, position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _words.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = widget.style.fontSize ?? 16;
    return Semantics(
      label: widget.label,
      textField: true,
      child: LineBox(
        height: normalLine(size, dpr: t.css.lineDpr),
        baseline: baselineIn(size, null, t.css.lineDpr),
        child: SizedBox(
          width: double.infinity,
          child: EditableText(
            controller: _words,
            focusNode: _focus,
            autofocus: true,
            style: widget.style,
            cursorColor: t.color('glacier-text'),
            backgroundCursorColor: t.color('glacier-text-subtle'),
            selectionColor: t.colorOf('color-mix(in oklch, var(--app-ink) 22%, transparent)'),
            maxLines: 1,
            onSubmitted: (_) => _end(true),
          ),
        ),
      ),
    );
  }
}

/// `.homeTab` (NoteTabs.module.css): Home pinned at the start of the row of tabs, in the Ledger - a house in a tab's
/// shape and a tab's height, never a tab itself, so the drag and the hold pass it by. On, at home, it is ringed in
/// ink as every "on" ring is.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onPressed, required this.atHome});

  final VoidCallback onPressed;
  final bool atHome;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.len('app-tab-h');
    final md = Radius.circular(t.radius('md'));
    final ink = t.color('app-ink');
    return Semantics(
      selected: atHome ? true : null,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: 'Home',
        builder: (context, state) {
          final lit = state.hovered;
          // `.homeTab[data-on] { border-radius: var(--glacier-radius-md) }`: all four corners once it is ringed.
          final radius = atHome ? BorderRadius.all(md) : BorderRadius.only(topLeft: md, topRight: md);
          return GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('md'),
            offset: -2,
            child: SizedBox(
              width: side,
              height: side,
              child: InsetRing(
                on: atHome,
                color: t.color('glacier-text'),
                width: t.len('app-line'),
                radius: radius,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: lit ? inkWash(t, 6) : null, borderRadius: radius),
                  // `border: 1px solid transparent; border-block-end: 0`: the glyph is centred in what is left.
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(1, 1, 1, 0),
                    child: Center(child: BarIcon(BarGlyph.house, size: 18, color: lit || atHome ? ink : t.color('glacier-text-muted'))),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `.newTab` (NoteTabs.module.css): the + after the last tab, a bare glyph the size of a tab's own close. Not a tab
/// itself, so dragging and the hold never take it for one.
class NewTabButton extends StatelessWidget {
  const NewTabButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.space(6);
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: 'New note in a new tab',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('sm'),
        offset: -2,
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(color: state.hovered ? inkWash(t, 6) : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
          child: Center(child: BarIcon(BarGlyph.plus, size: 15, color: state.hovered ? t.color('app-ink') : t.color('app-ink-3'))),
        ),
      ),
    );
  }
}

/// `.space` (NoteTabs.module.css): the workspace a note is filed in, worn as its own coloured pill in front of the
/// name, so two notes called Monday are told apart by colour before either is read.
class SpacePill extends StatelessWidget {
  const SpacePill(this.space, {super.key});

  final Workspace space;

  @override
  Widget build(BuildContext context) {
    return GlacierScope(
      attrs: {'hue': space.hue ?? 'ink'},
      child: Builder(
        builder: (context) {
          final t = context.tokens;
          final size = t.fontSize('sm');
          final color = t.colorOf('var(--app-space, var(--glacier-text-muted))');
          final style = t.textAt(size, color: color, height: 1);
          // `max-inline-size: calc(8ch + 1.6em + 2px)`: eight characters of the name, and the ring around them. A
          // `ch` is the width of the face's zero.
          final zero = (TextPainter(text: TextSpan(text: '0', style: style), textDirection: TextDirection.ltr)..layout()).width;
          // `border: 1px solid`, as wide as a phone draws it: whole device pixels (two at 2.625, 0.76px), which is
          // what the page's pill is as tall by (measured: 76.11 device pixels where a border of 1 made it 77.4).
          final hair = t.len('glacier-hairline');
          return ExcludeSemantics(
            child: Container(
              constraints: BoxConstraints(maxWidth: 8 * zero + 1.6 * size + 2 * hair),
              // The ring is the box's own border, which a container counts into its padding.
              padding: EdgeInsets.symmetric(vertical: 0.52 * size, horizontal: 0.8 * size),
              decoration: BoxDecoration(
                border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink-3)) 55%, transparent)'), width: hair),
                borderRadius: BorderRadius.circular(t.radius('full')),
              ),
              // `line-height: 1`: the line is the size of its words, so the ring is even above and below them.
              child: LineBox(height: size, baseline: baselineIn(size, size, t.css.lineDpr), child: Text(space.name, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis)),
            ),
          );
        },
      ),
    );
  }
}

/// One tab (`.tab`, `.name`, `.title`, `.close`, `.groupLine` of NoteTabs.module.css): the note's name behind its
/// workspace's pill, and a cross that closes it. The ones behind are bare words; the one being read takes the page's
/// ink, and its outline is the row's (notes/tabs/tab_row.dart).
class NoteTab extends StatefulWidget {
  const NoteTab({
    super.key,
    required this.shape,
    required this.title,
    required this.active,
    this.space,
    this.group,
    required this.showClose,
    required this.onOpen,
    required this.onClose,
    this.onNudge,
    this.naming = false,
    this.onNamed,
    required this.anchorKey,
    required this.closeKey,
    this.menu,
  });

  final TabShape shape;
  final String title;

  /// `data-active`: the tab being read.
  final bool active;
  final Workspace? space;
  final TabGroup? group;

  /// In every way but Classic the cross is the open tab's alone; the others close from their menu.
  final bool showClose;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  /// The tab moved a place by the arrow keys with the platform's own modifier: -1 left, 1 right. Absent, no tab moves.
  final ValueChanged<int>? onNudge;

  /// The tab's name is open as a field: a canvas or a book being renamed in the row.
  final bool naming;

  /// The end of the rename: the words, and whether they are to be kept.
  final void Function(String words, bool keep)? onNamed;

  /// Where the tab's menu hangs from: the foot of the tab (`.menuAnchor`).
  final GlobalKey anchorKey;

  /// The cross's own box, which a hold must not start on.
  final GlobalKey closeKey;

  /// The tab's menu, while it is open.
  final Widget? menu;

  @override
  State<NoteTab> createState() => _NoteTabState();
}

class _NoteTabState extends State<NoteTab> {
  bool _hovered = false;

  /// `@starting-style`: a tab put into a group gets its line drawn out from its middle.
  bool _lineIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _lineIn = true);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final nudge = widget.onNudge;
    if (nudge == null || event is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (!keys.isMetaPressed && !keys.isControlPressed) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      nudge(-1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      nudge(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shape = widget.shape;
    final active = widget.active;
    final capsule = shape == TabShape.capsule;
    final tabH = t.len('app-tab-h');
    final hair = t.len('glacier-hairline');
    final md = Radius.circular(t.radius('md'));
    final ink = t.color('app-ink');
    final lit = _hovered && !active;

    // `.bar[data-style='islands'] .tab[data-active]`: the open capsule is the inverse, ink on paper turned round.
    final color = active ? (capsule ? t.color('app-paper') : ink) : (lit ? ink : t.color('glacier-text-muted'));
    final ground = capsule && active
        ? ink
        : lit && shape != TabShape.indexLine
            ? inkWash(t, 6)
            : null;
    final radius = switch (shape) {
      TabShape.tab => BorderRadius.only(topLeft: md, topRight: md),
      TabShape.indexLine => BorderRadius.zero,
      TabShape.capsule => BorderRadius.circular(t.radius('full')),
    };

    final size = t.fontSize('md');
    final style = t.textAt(size, color: color);
    // `.name { padding: calc(space-1 * 1.3) space-1 calc(space-1 * 1.3) space-3 }`, none above and below in a
    // capsule, and 2px either side on the index line.
    final padV = capsule ? 0.0 : t.space(1) * 1.3;
    final padding = shape == TabShape.indexLine ? EdgeInsets.symmetric(vertical: padV, horizontal: 2) : EdgeInsets.fromLTRB(t.space(3), padV, t.space(1), padV);
    final space = widget.space;

    Widget name;
    if (widget.naming) {
      // The browser's own width for a field of twenty characters in this face, which no rule here changes.
      // `.name:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: -2px }`: a field with
      // the caret in it always wears the ring on the page.
      name = GlacierFocusRing(
        visible: true,
        radius: t.radius('sm'),
        offset: -2,
        child: Container(
          constraints: BoxConstraints(maxWidth: t.lenOf('16rem')),
          width: 11.206 * size + padding.horizontal,
          padding: padding,
          child: _NameField(initial: widget.title, label: 'Canvas name', style: style, around: padding, onDone: (words, keep) => widget.onNamed?.call(words, keep)),
        ),
      );
    } else {
      name = Semantics(
        role: SemanticsRole.tab,
        selected: active,
        // Said rather than shown twice: the pill is a colour to the eye and the workspace's name to a reader.
        label: space != null ? '${widget.title}, in ${space.name}' : widget.title,
        onTap: widget.onOpen,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onKeyEvent: _onKey,
          child: GlacierPressable(
            onPressed: widget.onOpen,
            excludeSemantics: true,
            builder: (context, state) => GlacierFocusRing(
              visible: state.focused,
              radius: t.radius('sm'),
              offset: -2,
              child: Container(
                constraints: BoxConstraints(maxWidth: t.lenOf('16rem')),
                padding: padding,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: t.space(2),
                    children: [
                      if (space != null) SpacePill(space),
                      Flexible(child: BarLine(widget.title, style: style)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final close = !widget.showClose
        ? null
        : Padding(
            padding: EdgeInsets.only(right: t.space(1)),
            child: GlacierPressable(
              onPressed: widget.onClose,
              semanticLabel: 'Close ${widget.title}',
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                radius: t.radius('sm'),
                offset: -2,
                child: Opacity(
                  // `.close { opacity: 0.7 }`, whole on a hover or a press.
                  opacity: state.hovered || state.pressed ? 1 : 0.7,
                  child: SizedBox(key: widget.closeKey, width: t.space(6), height: t.space(6), child: Center(child: BarIcon(BarGlyph.close, size: 15, color: color))),
                ),
              ),
            ),
          );

    final group = widget.group;
    final slow = t.duration('glacier-duration-normal');
    final ease = t.curve('glacier-ease-out');
    // Drawn in to its middle and faded under the tab being read, and grown back out under the one it has left.
    final lineShown = _lineIn && !active;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        constraints: BoxConstraints(minHeight: capsule ? tabH - 4 : tabH, maxWidth: t.lenOf('17rem')),
        // `border: 1px solid transparent; border-block-end: 0`, which a capsule and an index word do not wear. As
        // wide as a phone draws it (the hairline, whole device pixels).
        padding: shape == TabShape.tab ? EdgeInsets.fromLTRB(hair, hair, hair, 0) : EdgeInsets.zero,
        decoration: BoxDecoration(color: ground, borderRadius: radius),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // `display: inline-flex; align-items: center`, in what the tab's least height leaves it.
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: (capsule ? tabH - 4 : tabH) - (shape == TabShape.tab ? hair : 0)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: name), ?close]),
            ),
            if (shape == TabShape.indexLine && active)
              // `box-shadow: inset 0 -2px 0 var(--app-ink)`: the open word underlined in ink.
              Positioned(left: 0, right: 0, bottom: 0, height: 2, child: ColoredBox(color: ink)),
            if (group != null)
              // `.groupLine`: the group's colour along the foot of each of its tabs, as Chrome draws a group. Its
              // insets are of the row's own type, the page's 16px.
              Positioned(
                left: capsule ? 12.8 : 5.6,
                right: capsule ? 12.8 : 5.6,
                bottom: capsule ? 2 : 0,
                height: 2,
                child: IgnorePointer(
                  child: GlacierScope(
                    attrs: {'hue': group.hue},
                    child: Builder(
                      builder: (context) => AnimatedOpacity(
                        opacity: lineShown ? 1 : 0,
                        duration: slow,
                        curve: ease,
                        // `transform: scaleX(0.2)`: across only, from its middle.
                        child: AnimatedContainer(
                          duration: slow,
                          curve: ease,
                          transform: Matrix4.diagonal3Values(lineShown ? 1 : 0.2, 1, 1),
                          transformAlignment: Alignment.center,
                          decoration: BoxDecoration(color: context.tokens.colorOf('var(--app-space, var(--app-ink-3))'), borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(left: 0, bottom: 0, child: SizedBox.shrink(key: widget.anchorKey)),
            ?widget.menu,
          ],
        ),
      ),
    );
  }
}

/// A group's chip, before its first tab in the row (notes/GroupChip.tsx; `.group`, `.groupChip`, `.groupCount`,
/// `.groupName`): its name in its colour, as Chrome draws one. A tap folds the group to the chip and opens it again;
/// a right-click or a long press opens its menu. Folded, it stands for every tab it holds. It is not a tab, so the
/// drag and the hold pass it by.
class GroupChip extends StatelessWidget {
  const GroupChip({
    super.key,
    required this.group,
    required this.count,
    required this.renaming,
    required this.onToggle,
    required this.onMenu,
    required this.onRename,
    required this.anchorKey,
    this.menu,
  });

  final TabGroup group;
  final int count;

  /// Its name is open as a field: a group just made, or Rename chosen from its menu.
  final bool renaming;
  final VoidCallback onToggle;
  final VoidCallback onMenu;

  /// The name it is left with, however the field closes: Enter and a blur keep the words, Escape the name it had.
  final ValueChanged<String> onRename;

  /// Where its menu hangs from: the foot of the chip.
  final GlobalKey anchorKey;

  /// Its menu, while it is open.
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    return GlacierScope(
      attrs: {'hue': group.hue},
      child: Builder(
        builder: (context) {
          final t = context.tokens;
          final size = t.fontSize('sm');
          final sm = t.radius('sm');
          Widget face;
          if (renaming) {
            // `.groupName { inline-size: 8rem; padding: 0.25em 0.6em; border: 1px solid var(--app-space) }`
            face = Container(
              width: t.lenOf('8rem'),
              padding: EdgeInsets.symmetric(vertical: 0.25 * size, horizontal: 0.6 * size),
              decoration: BoxDecoration(border: Border.all(color: t.colorOf('var(--app-space, var(--app-ink-3))')), borderRadius: BorderRadius.circular(sm)),
              child: _NameField(
                initial: group.name,
                label: 'Group name',
                style: t.textAt(size, color: t.color('app-ink')),
                onDone: (words, keep) => onRename(keep ? words : group.name),
              ),
            );
          } else {
            final color = t.colorOf('var(--app-space, var(--app-ink-2))');
            final style = t.textAt(size, weight: 'semibold', color: color);
            face = Semantics(
              expanded: !group.collapsed,
              child: GestureDetector(
                // A mouse's right-click opens its menu, as a long press does.
                onSecondaryTapUp: (_) => onMenu(),
                child: GlacierPressable(
                  onPressed: onToggle,
                  onLongPress: () {
                    // A long press opens it with the finger still down: its one tick now, and none as it lifts.
                    HapticsProvider.of(context)(HapticKind.selection);
                    onMenu();
                  },
                  semanticLabel: '${group.name}, $count ${count == 1 ? 'tab' : 'tabs'}${group.collapsed ? ', folded' : ''}',
                  builder: (context, state) => GlacierFocusRing(
                    visible: state.focused,
                    radius: sm,
                    offset: 1,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: t.lenOf('10rem')),
                      padding: EdgeInsets.symmetric(vertical: 0.3 * size, horizontal: 0.7 * size),
                      decoration: BoxDecoration(
                        color: t.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink-3)) 22%, transparent)'),
                        borderRadius: BorderRadius.circular(sm),
                      ),
                      child: ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 0.4 * size,
                          children: [
                            Flexible(child: BarLine(group.name, style: style)),
                            // Open or folded alike, so folding a group leaves its chip the size it was.
                            Opacity(
                              opacity: 0.75,
                              child: BarLine('$count', style: style.copyWith(fontFeatures: [...?style.fontFeatures, const FontFeature.tabularFigures()]), ellipsis: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              face,
              Positioned(left: 0, bottom: 0, child: SizedBox.shrink(key: anchorKey)),
              ?menu,
            ],
          );
        },
      ),
    );
  }
}

/// "milk" to "Milk" (`capitalise`, core/text.ts).
String _capitalise(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// What a tab's menu does (`TabMenu`, notes/TabMenus.tsx): rename a canvas or a book, group it, take it out of its
/// group, close it, delete its note. It says what it is for, so a screen reader hears "Groceries tab" rather than a
/// bare list of verbs.
class TabMenu extends StatelessWidget {
  const TabMenu({
    super.key,
    required this.anchor,
    required this.noteId,
    required this.title,
    required this.groups,
    required this.onDismiss,
    this.onRename,
    required this.onNewGroup,
    required this.onGroups,
    required this.onCloseTab,
    this.onDeleteNote,
    this.coarse,
  });

  final GlobalKey anchor;
  final String noteId;
  final String title;
  final TabGroups groups;
  final VoidCallback onDismiss;

  /// Only a canvas or a book is renamed from its tab: a note is named by its first line, written in the note itself.
  final VoidCallback? onRename;
  final VoidCallback onNewGroup;
  final ValueChanged<TabGroups> onGroups;
  final VoidCallback onCloseTab;

  /// The tab's note to the Trash, with an Undo; absent, the menu has no Delete.
  final VoidCallback? onDeleteNote;
  final bool? coarse;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final groupId = groups.of[noteId];
    final others = [for (final g in groups.list) if (g.id != groupId) g];
    return PopMenu(
      anchor: GlacierAnchor.key(anchor),
      placement: Placement.bottomStart,
      reach: PopReach.down,
      ariaLabel: '$title tab',
      onDismiss: onDismiss,
      coarse: coarse,
      children: [
        if (onRename != null) GlacierMenuItem(onSelect: onRename, child: const Text('Rename')),
        GlacierMenuItem(onSelect: onNewGroup, child: const Text('Add to a new group')),
        if (others.isNotEmpty)
          ...PopSub.rows(
            context,
            label: 'Add to group',
            reach: PopReach.down,
            coarse: coarse,
            children: [
              for (final g in others)
                GlacierMenuItem(ariaLabel: 'Add to ${g.name}', onSelect: () => onGroups(joinGroup(groups, noteId, g.id)), icon: HueDot(g.hue), child: Text(g.name)),
            ],
          ),
        if (groupId != null) GlacierMenuItem(onSelect: () => onGroups(leaveGroup(groups, noteId)), child: const Text('Remove from group')),
        const GlacierMenuSeparator(),
        GlacierMenuItem(onSelect: onCloseTab, child: const Text('Close tab')),
        if (onDeleteNote != null) GlacierMenuItem(danger: true, style: dangerRowStyle(t), onSelect: onDeleteNote, child: const Text('Delete note')),
      ],
    );
  }
}

/// What a group's menu does (`GroupMenu`, notes/TabMenus.tsx): rename it, colour it, ungroup its tabs, or close
/// them all.
class GroupMenu extends StatelessWidget {
  const GroupMenu({
    super.key,
    required this.anchor,
    required this.group,
    required this.groups,
    required this.tabIds,
    required this.onDismiss,
    required this.onRename,
    required this.onGroups,
    this.onCloseTabs,
    this.coarse,
  });

  final GlobalKey anchor;
  final TabGroup group;
  final TabGroups groups;

  /// The tabs in the row, in the order drawn: the group's own are closed in that order.
  final List<String> tabIds;
  final VoidCallback onDismiss;
  final VoidCallback onRename;
  final ValueChanged<TabGroups> onGroups;
  final ValueChanged<List<String>>? onCloseTabs;
  final bool? coarse;

  @override
  Widget build(BuildContext context) {
    return PopMenu(
      anchor: GlacierAnchor.key(anchor),
      placement: Placement.bottomStart,
      reach: PopReach.down,
      ariaLabel: '${group.name} group',
      onDismiss: onDismiss,
      coarse: coarse,
      children: [
        GlacierMenuItem(onSelect: onRename, child: const Text('Rename')),
        ...PopSub.rows(
          context,
          label: 'Colour',
          reach: PopReach.down,
          coarse: coarse,
          children: [
            for (final hue in workspaceHues)
              GlacierMenuItem(
                ariaLabel: 'Colour: ${_capitalise(hue)}',
                onSelect: () => onGroups(recolourGroup(groups, group.id, hue)),
                icon: HueDot(hue),
                child: Text(_capitalise(hue)),
              ),
          ],
        ),
        const GlacierMenuSeparator(),
        GlacierMenuItem(onSelect: () => onGroups(ungroup(groups, group.id)), child: const Text('Ungroup')),
        GlacierMenuItem(danger: true, onSelect: () => onCloseTabs?.call(membersOf(groups, group.id, tabIds)), child: const Text('Close group')),
      ],
    );
  }
}
