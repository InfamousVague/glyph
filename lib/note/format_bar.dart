/// Simple mode's Format bar: Bold, Italic, Heading, List, To-do and Link, six of the press-and-hold menu's Style
/// rows pressed from outside the menu (lib/editor/band/style_items.dart `formatBarTools`). Matt, 2026-10-18
/// (GHST-103): "simple mode has a much more approachable UI with fancy features hidden behind more and work on
/// making formatting and stuff easier to understand", and for it "A small Format bar in the editor", a deliberate
/// exception to the editor's rule of no toolbar (docs/STAGE4.md). Advanced mode never draws it.
///
/// It takes one of three looks, for where the note's screen stands it (lib/note/note_screen.dart):
///
/// - [FormatBarLook.strip]: on a phone, a row in the page's own paper with a hairline over it, pinned just above the
///   soft keyboard while the editor is focused and the keyboard is up, the page ending above it so it never covers
///   the caret. Android's, and any other phone with no bar of its own on the keyboard.
/// - [FormatBarLook.row]: the six alone, for the iPhone's keyboard bar, where they share the row with its Done
///   (lib/app/iphone_page.dart `IPhoneKeyboardBar.tools`): the bar draws the paper and the hairline there.
/// - [FormatBarLook.pill]: on a desktop or a wide window with the keyboard down, a pill of glass in the dock's own
///   hand (docs/DOCK.md: the blurred ground, the hairline, rings `--app-ring` across with `--glacier-space-2`
///   between), lying across the page's foot to the dock's start, so it stands "in the dock" as Matt asked without
///   making the dock's column twice as tall. On a desktop each ring's hint comes up over it while the pointer rests
///   there (`BandTip`).
///
/// A press never takes the editor's focus: the rings cannot ask for it, the edit is dispatched to the view, and
/// the editor is given its focus back after, so the keyboard stays up and typing goes on. What is lit is read from
/// the editor's state on every draw, as the Style page's rows are, and the bar is drawn again whenever the view
/// has something new (a move of the caret into a heading lights Heading).
///
/// After the six, a tail (GHST-105; Matt: "build out a clean simple UI", the Format bar "gets a picture and a mic
/// at its end"): a divider, then a picture ([FormatBar.onPicture], the press-and-hold band's Add image), the +
/// ([FormatBar.onAdd], the +'s list for the caret's line, which the dock carried in advanced mode) and a mic
/// ([FormatBar.onSpeak], Talk into this note). Where Claude's Talk is on the page's dock, that ring stands in the
/// mic's place instead ([FormatBar.talk]): one microphone only (GHST-104). Each of the three is drawn only where it
/// is given, and the divider only before something. On the iPhone's row the six stay first and the row scrolls
/// sideways past Done where it is too long, as Apple Notes' own bar does.
library;

import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/plain.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../editor/band/menu_band.dart' show BandTip, MenuIcon;
import '../editor/band/style_items.dart';
import '../editor/view/editor_view.dart';

/// Where the bar stands, which says how it is drawn.
enum FormatBarLook { strip, row, pill }

/// The strip's and the row's height: the iPhone's own 44pt keyboard row, which is also the least a finger is given.
const double formatBarHeight = 44;

class FormatBar extends StatefulWidget {
  const FormatBar({super.key, required this.view, required this.look, this.felt, this.onPicture, this.onAdd, this.onSpeak, this.speakLabel = 'Talk into this note', this.talk});

  final EditorView view;
  final FormatBarLook look;

  /// Says a tick; the kit's haptics where null.
  final void Function(HapticKind kind)? felt;

  /// The tail: a picture put in the note (the band's Add image), the +'s list for the caret's line, and the note's
  /// mic with its words. Each left out, its button is not drawn.
  final VoidCallback? onPicture;
  final VoidCallback? onAdd;
  final VoidCallback? onSpeak;
  final String speakLabel;

  /// Claude's Talk ring (lib/claude/claude_dock.dart), standing in the mic's place where it is given: one mic.
  final Widget? talk;

  /// The bar's key for each look, for whoever looks for it.
  static const Key stripKey = ValueKey<String>('format-bar-strip'), rowKey = ValueKey<String>('format-bar-row'), pillKey = ValueKey<String>('format-bar-pill');

  /// The tail's keys.
  static const Key pictureKey = ValueKey<String>('format-picture'), addKey = ValueKey<String>('format-add'), micKey = ValueKey<String>('format-mic'), talkKey = ValueKey<String>('format-talk');

  /// A button's key: `format-<the Style page's key>`, `format-mark:bold`.
  static Key keyOf(StyleTool tool) => ValueKey<String>('format-${tool.key}');

  @override
  State<FormatBar> createState() => _FormatBarState();
}

class _FormatBarState extends State<FormatBar> {
  late final List<StyleTool> _tools = formatBarTools();

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_changed);
  }

  @override
  void didUpdateWidget(FormatBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) {
      oldWidget.view.removeListener(_changed);
      widget.view.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.view.removeListener(_changed);
    super.dispose();
  }

  /// The view has something new: what is lit is read again. The view also speaks while the editor's own column is
  /// built or laid out, when nothing above it may be marked; then the bar is drawn after the frame.
  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  void _press(StyleTool tool) {
    final view = widget.view;
    (widget.felt ?? HapticsProvider.of(context))(HapticKind.selection);
    final tr = tool.run(view.state, view.hasFocus);
    if (tr != null) view.dispatch(tr);
    view.focus();
  }

  /// One of the tail pressed: a tick, then what it does. The focus is not handed back here: a picture's picker,
  /// the +'s list and the recorder each take the screen, and each gives the editor back when it is done.
  VoidCallback _tail(VoidCallback what) => () {
        (widget.felt ?? HapticsProvider.of(context))(HapticKind.selection);
        what();
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = widget.view.state;
    final round = widget.look == FormatBarLook.pill;
    final gap = round ? t.space(2) : 0.0;
    final onPicture = widget.onPicture, onAdd = widget.onAdd, onSpeak = widget.onSpeak, talk = widget.talk;
    final tail = <Widget>[
      if (onPicture != null) _FormatButton(key: FormatBar.pictureKey, icon: Lucide.imagePlus, label: 'Add image', hint: 'A picture in the note', lit: false, round: round, onPress: _tail(onPicture)),
      if (onAdd != null) _FormatButton(key: FormatBar.addKey, icon: Lucide.plus, label: 'Add to this line', hint: 'A list, a table, a date and more', lit: false, round: round, onPress: _tail(onAdd)),
      // One microphone (GHST-104): Claude's Talk where it is on the page, else the note's own.
      if (talk != null)
        _tailSlot(round, talk, FormatBar.talkKey)
      else if (onSpeak != null)
        _FormatButton(key: FormatBar.micKey, icon: Lucide.mic, label: widget.speakLabel, hint: 'Say it, and it is written', lit: false, round: round, onPress: _tail(onSpeak)),
    ];
    final buttons = <Widget>[
      for (final (i, tool) in _tools.indexed) ...<Widget>[
        if (i > 0 && gap > 0) SizedBox(width: gap),
        _FormatButton(key: FormatBar.keyOf(tool), icon: tool.icon, label: tool.label, hint: tool.hint, lit: tool.lit(state), round: round, onPress: () => _press(tool)),
      ],
      if (tail.isNotEmpty) ...<Widget>[
        // The divider: a hairline the ring's height, a step in from each side, between the six and the tail.
        SizedBox(width: gap),
        _Divider(round: round),
        SizedBox(width: gap),
        for (final (i, one) in tail.indexed) ...<Widget>[if (i > 0 && gap > 0) SizedBox(width: gap), one],
      ],
    ];
    switch (widget.look) {
      case FormatBarLook.row:
        return _scrolling(context, FormatBar.rowKey, buttons);
      case FormatBarLook.strip:
        final ratio = MediaQuery.devicePixelRatioOf(context);
        // A hairline is a device pixel, as the iPhone's bar and the find bar have it.
        final hairline = (t.len('glacier-hairline') * ratio).roundToDouble().clamp(1.0, double.infinity) / ratio;
        return DecoratedBox(
          key: FormatBar.stripKey,
          decoration: BoxDecoration(
            color: t.color('glacier-bg'),
            border: Border(top: BorderSide(color: t.color('app-rule'), width: hairline)),
          ),
          child: Padding(
            // In from a notch or a curved edge by the safe area; the keyboard covers the bottom's.
            padding: EdgeInsetsDirectional.only(start: t.len('app-safe-left'), end: t.len('app-safe-right')),
            child: _scrolling(context, null, buttons),
          ),
        );
      case FormatBarLook.pill:
        final radius = BorderRadius.circular(t.radius('full'));
        return Semantics(
          key: FormatBar.pillKey,
          container: true,
          label: 'Format',
          explicitChildNodes: true,
          child: ClipRRect(
            borderRadius: radius,
            // The dock's own glass (lib/shell/page_dock.dart `PageDock`), one reading of what lies behind with the
            // bars' and the dock's.
            child: BackdropFilter.grouped(
              enabled: !ghostPlain,
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: EdgeInsets.all(gap + t.len('glacier-hairline')),
                foregroundDecoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')), borderRadius: radius),
                decoration: BoxDecoration(color: t.colorOf(ghostPlain ? 'color-mix(in srgb, var(--glacier-bg) 94%, transparent)' : 'color-mix(in srgb, var(--glacier-bg) 82%, transparent)'), borderRadius: radius),
                child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
              ),
            ),
          ),
        );
    }
  }

  /// The six in a row the bar's height, scrolling sideways on a screen too narrow for all of them, in from the
  /// start by a step.
  Widget _scrolling(BuildContext context, Key? key, List<Widget> buttons) {
    final t = context.tokens;
    return Semantics(
      key: key,
      container: true,
      label: 'Format',
      explicitChildNodes: true,
      child: SizedBox(
        height: formatBarHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsetsDirectional.only(start: t.space(2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
        ),
      ),
    );
  }
}

/// A ring of the dock's own ([talk], Claude's Talk) in the tail: in the pill it is a ring among rings; on the strip
/// and the row it stands in the middle of a square the bar's height, as the other buttons do.
Widget _tailSlot(bool round, Widget ring, Key key) => round ? KeyedSubtree(key: key, child: ring) : SizedBox(key: key, width: formatBarHeight, height: formatBarHeight, child: Center(child: ring));

/// The hairline between the six and the tail, the icon's own height, in the page's rule.
class _Divider extends StatelessWidget {
  const _Divider({required this.round});

  final bool round;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: SizedBox(
        width: round ? t.len('glacier-hairline') : t.space(2) + t.len('glacier-hairline'),
        height: round ? t.len('app-ring') : formatBarHeight,
        child: Center(child: Container(width: t.len('glacier-hairline'), height: round ? t.len('app-ring') - t.space(3) : formatBarHeight - t.space(5), color: t.color('app-rule'))),
      ),
    );
  }
}

/// One of the six, or of the tail: its icon, lit (printed in reverse, as a Style row is) while it applies. [round],
/// a ring of the dock's size and line; otherwise a square the bar's height, a finger's width. Its words are said to
/// a screen reader with its hint after them, and the hint comes up over it on a desktop.
class _FormatButton extends StatelessWidget {
  const _FormatButton({super.key, required this.icon, required this.label, required this.hint, required this.lit, required this.round, required this.onPress});

  final MenuIcon icon;
  final String label;
  final String hint;
  final bool lit;
  final bool round;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color(lit ? 'app-paper' : 'app-ink');
    final Widget button = MergeSemantics(
      child: Semantics(
        hint: hint,
        child: GlacierPressable(
          onPressed: onPress,
          semanticLabel: label,
          toggled: lit,
          // The press must not take the focus from the words it is about: the keyboard would go and come back,
          // and the selection with it.
          canRequestFocus: false,
          builder: (context, state) {
            if (round) {
              final ring = t.len('app-ring');
              return GlacierFocusRing(
                visible: state.focused,
                child: Container(
                  width: ring,
                  height: ring,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: lit ? t.color('app-ink') : (state.pressed || state.hovered ? t.color('app-paper-3') : t.color('glacier-bg')),
                    shape: BoxShape.circle,
                    border: Border.all(color: lit ? t.color('app-ink') : t.color('glacier-border-strong'), width: t.len('app-line')),
                  ),
                  child: AppIcon(icon, size: t.lenOf('1.15rem'), strokeWidth: 2, color: ink),
                ),
              );
            }
            // The lit square is the icon's own box with a breath round it, not the whole finger's width, so six
            // lit at once do not read as one black bar.
            return SizedBox(
              width: formatBarHeight,
              height: formatBarHeight,
              child: Center(
                child: Container(
                  width: formatBarHeight - t.space(2),
                  height: formatBarHeight - t.space(2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: lit ? t.color('app-ink') : (state.pressed ? t.color('app-paper-3') : null),
                    borderRadius: BorderRadius.circular(t.radius('sm')),
                  ),
                  child: AppIcon(icon, size: 20, strokeWidth: 2.1, color: ink),
                ),
              ),
            );
          },
        ),
      ),
    );
    return BandTip(message: hint, child: button);
  }
}
