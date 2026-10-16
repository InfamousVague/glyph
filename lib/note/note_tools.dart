/// The note's tools: the view switch and More, and the actions that come out of More into the bar while there is
/// room. A port of `src/app/editor/NoteTools.tsx`, of `editor/toolRoom.ts`, and of the tools' share of
/// `NoteScreen.module.css` (`.tools`, `.cog`, `.more`).
///
/// The note's screen draws them in its own header or, wherever the app's top bar is there to take them, hands them
/// to the bar (shell/top_bar_tools.dart `TopBarFill`). This is only the drawing: what each one does is the screen's.
///
/// What differs:
/// - The page's portal kept the buttons the screen's own elements; a widget handed to the bar is built there, so
///   [NoteTools] listens to a [NoteToolsModel] the screen changes, and is itself handed over once.
/// - `useToolRoom` read the row's width from the DOM, less everything else on it. The bar's slot is already that:
///   the row gives the slot what its other controls leave (notes/tabs/bar_parts.dart `ToolRow`), and the slot scrolls
///   sideways, so the room is the slot's viewport, read after each layout ([NoteTools.room] where there is no bar).
///   The first frame draws none of the spare ones, as the page does where it has nothing to measure.
/// - `title`, a pointer's tooltip, is not drawn.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';

/// One of the note's actions that comes out of More into the bar when there is room for it, in this order: Share,
/// History, Comment, Bookmark, Pin/Unpin, Archive, Speak (`ToolAction`). Each stays in More as well.
@immutable
class ToolAction {
  const ToolAction({required this.id, required this.label, required this.icon, required this.onPress, this.on, this.count});

  final String id;
  final String label;
  final LucideIcon icon;
  final VoidCallback onPress;

  /// A toggle that is on now: the bookmark set, the note pinned. Null for an action that is not a toggle.
  final bool? on;

  /// A number worn on the ring, small at its corner: how many notes link here (lib/links). Null or 0 for none.
  final int? count;
}

/// What the note is drawn as when it is not its source (`NoteKind`).
enum NoteKind { canvas, book, words }

/// The switch's words: what it says it is showing and what a press shows, and its short title (`viewSwitchWords`).
({String label, String title}) viewSwitchWords(NoteKind kind, {required bool page}) => switch (kind) {
      NoteKind.canvas => page ? (label: 'Showing the canvas. Show its JSON.', title: 'Canvas') : (label: 'Showing the canvas as JSON. Show the canvas.', title: 'JSON'),
      NoteKind.book => page ? (label: 'Showing the index. Show its Markdown.', title: 'Index') : (label: 'Showing the index as Markdown. Show the index.', title: 'Markdown'),
      NoteKind.words => page ? (label: 'Showing the formatted note. Show the marks.', title: 'Formatted') : (label: 'Showing the marks. Show the formatted note.', title: 'Markdown'),
    };

/// `NoteTools`'s props.
@immutable
class NoteToolsModel {
  const NoteToolsModel({required this.kind, required this.page, required this.switchable, required this.onSwitch, required this.onMore, this.more = true, this.actions = const []});

  final NoteKind kind;

  /// The page rather than its source: a canvas or a book's index drawn; for words, the formatted note.
  final bool page;

  /// The switch works: the note's own view is up.
  final bool switchable;
  final VoidCallback onSwitch;
  final VoidCallback onMore;

  /// False when More is drawn on its own, at the bar's end.
  final bool more;

  /// The actions to bring out of More while there is room, first first.
  final List<ToolAction> actions;
}

/// How many of [spare] buttons fit in [room] beside [always] that are always drawn, each [ring] wide and [gap]
/// apart (`useToolRoom`'s sum, with the 4px it keeps back).
int toolsThatFit({required double room, required int always, required int spare, required double ring, required double gap}) {
  if (ring <= 0 || !room.isFinite) return 0;
  final step = ring + gap;
  final fixed = always * ring + (always > 1 ? (always - 1) * gap : 0);
  final fits = ((room - fixed - 4) / step).floor();
  return fits < 0 ? 0 : (fits > spare ? spare : fits);
}

/// `.cog`: one round control of the note's, the size of the bar's own rings and with no ring drawn.
class NoteToolButton extends StatelessWidget {
  const NoteToolButton({super.key, required this.icon, required this.label, required this.onPressed, this.strokeWidth = 2.1, this.on, this.turns = true, this.tool, this.count});

  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final double strokeWidth;

  /// `aria-pressed` and `data-on`.
  final bool? on;

  /// `.cog:active svg { transform: rotate(45deg) }`; false for More, which only answers the press
  /// (`.more:active svg { transform: scale(0.9) }`).
  final bool turns;

  /// `data-tool`: the id of a spare action.
  final String? tool;

  /// [ToolAction.count], at the ring's corner.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    final ink = t.color('glacier-text');
    final counted = count ?? 0;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      toggled: on,
      // The glyph answers the press; the box does not shrink.
      pressScale: null,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('md'),
        child: _countedIf(
          counted,
          SizedBox(
            width: ring,
            height: ring,
            child: Center(
              // `.cog svg { transition: transform var(--app-turn) }`: 420ms cubic-bezier(0.3, 1.4, 0.5, 1).
              child: AnimatedContainer(
                duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 420),
                curve: const Cubic(0.3, 1.4, 0.5, 1),
                transformAlignment: Alignment.center,
                transform: !state.pressed ? Matrix4.identity() : (turns ? Matrix4.rotationZ(0.7853981633974483) : Matrix4.diagonal3Values(0.9, 0.9, 1)),
                child: AppIcon(icon, size: 20, strokeWidth: strokeWidth, color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _countedIf(int count, Widget ring) => count > 0 ? _Counted(count: count, child: ring) : ring;
}

/// A ring with its number at the corner: the number in the bar's ink on the paper, so it reads over the glyph.
class _Counted extends StatelessWidget {
  const _Counted({required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final words = count > 99 ? '99+' : '$count';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          top: 3,
          end: 1,
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.color('app-paper'), borderRadius: BorderRadius.circular(8), border: Border.all(color: t.color('glacier-text'), width: 1)),
              child: Text(words, style: t.textAt(9.5, weight: 'bold', color: t.color('glacier-text'), height: 1.15)),
            ),
          ),
        ),
      ],
    );
  }
}

/// More for this note: the view's look, the bookmark, the mic, the AI's runs, pin, archive, links, delete
/// (`NoteMore`).
class NoteMore extends StatelessWidget {
  const NoteMore({super.key, required this.onMore});
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => NoteToolButton(icon: Lucide.ellipsisVertical, strokeWidth: 2.6, label: 'More for this note', onPressed: onMore, turns: false);
}

class NoteTools extends StatefulWidget {
  const NoteTools({super.key, required this.model, this.room});

  final ValueListenable<NoteToolsModel> model;

  /// The room the tools have, where they are not in the bar's slot: the note's own header row.
  final double? room;

  @override
  State<NoteTools> createState() => _NoteToolsState();
}

class _NoteToolsState extends State<NoteTools> {
  int _fits = 0;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_changed);
  }

  @override
  void didUpdateWidget(NoteTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) {
      oldWidget.model.removeListener(_changed);
      widget.model.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The room the row leaves the slot, once it has been laid out: measured again after every build, since the
  /// window's width and what else is in the row are what it depends on.
  void _measure(double ring, double gap) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final model = widget.model.value;
      var room = widget.room;
      if (room == null) {
        // The slot scrolls sideways and is as wide as what is in it; what the row LEFT it is the most it was allowed.
        final slot = Scrollable.maybeOf(context);
        final box = slot?.context.findRenderObject();
        if (slot != null && axisDirectionToAxis(slot.axisDirection) == Axis.horizontal && box is RenderBox && box.hasSize && box.constraints.maxWidth.isFinite) room = box.constraints.maxWidth;
      }
      final fits = room == null ? 0 : toolsThatFit(room: room, always: model.more ? 2 : 1, spare: model.actions.length, ring: ring, gap: gap);
      if (fits != _fits) setState(() => _fits = fits);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final model = widget.model.value;
    final words = viewSwitchWords(model.kind, page: model.page);
    // `.tools { gap: var(--glacier-space-2) }`, and `@media (max-width: 440px) { gap: var(--glacier-space-1) }`.
    final gap = MediaQuery.sizeOf(context).width <= 440 ? t.space(1) : t.space(2);
    _measure(t.len('app-bar-ring'), gap);
    final out = model.actions.take(_fits);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: gap,
      children: [
        for (final action in out) NoteToolButton(key: ValueKey('tool:${action.id}'), icon: action.icon, label: action.label, onPressed: action.onPress, on: action.on, tool: action.id, count: action.count),
        // One ring like the others: the glyph is the view you are in, and the label says what a press does.
        NoteToolButton(key: const ValueKey('tool-switch'), icon: model.page ? Lucide.bookOpen : Lucide.code, label: words.label, onPressed: model.switchable ? model.onSwitch : null),
        if (model.more) NoteMore(onMore: model.onMore),
      ],
    );
  }
}
