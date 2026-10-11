/// The pieces a bottom sheet is built from, in the sheet's own look: a title, a sentence, a heading, a card of rows,
/// a text field. A port of `src/app/plugins/kit.tsx`, drawing with the classes of `editor/NoteSettings.module.css` it
/// uses there (`.title`, `.note`, `.heading`, `.group`, `.row`, `.icon`, `.label`, `.hint`, `.tick`, `.field`,
/// `.fieldLabel`, `.input`, `.danger`).
///
/// They began as what a plugin's page on a note's cog sheet is made of; the book, canvas, workspace and new-note
/// sheets are drawn from them too. Put them in a [Sheet]'s children: each is a block with the margins its class
/// gives it (flow.dart), so they sit as far apart as they do on the page.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'css.dart';
import 'flow.dart';

/// `SheetTitle` (`.title`): the sheet's name, on one line, cut short with an ellipsis rather than wrapped.
///
/// Differs from the web: [child] is a [Text] (or a [Text.rich] where a mark comes before the words), since the one
/// line and its ellipsis are the text's own here.
class SheetTitle extends StatelessWidget {
  const SheetTitle({super.key, required this.child});

  /// The usual case: words alone.
  SheetTitle.text(String text, {super.key}) : child = Text(text);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('lg');
    final color = t.color('glacier-text');
    return CssFlow.block(
      // `margin: 0 0 var(--glacier-space-4)`
      margin: EdgeInsets.only(bottom: t.space(4)),
      child: Semantics(
        header: true,
        child: IconTheme(
          data: IconThemeData(color: color, size: size),
          // `font-size: var(--glacier-font-size-lg); font-weight: bold; overflow: hidden; text-overflow: ellipsis; white-space: nowrap`
          child: DefaultTextStyle(style: pageText(t, size, weight: 'bold', color: color), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, child: child),
        ),
      ),
    );
  }
}

/// `SheetNote` (`.note`): a sentence under the title, in the quiet ink.
class SheetNote extends StatelessWidget {
  const SheetNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return CssFlow.block(
      // `margin: 0 0 var(--glacier-space-3); font-size: var(--glacier-font-size-sm); color: var(--glacier-text-subtle)`
      margin: EdgeInsets.only(bottom: t.space(3)),
      child: Text(text, style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle'))),
    );
  }
}

/// `SheetHeading` (`.heading`, which composes `.app-eyebrow`): small spaced capitals over a group.
class SheetHeading extends StatelessWidget {
  const SheetHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    return CssFlow.block(
      // `margin: var(--glacier-space-2) 0 var(--glacier-space-2)`
      margin: EdgeInsets.symmetric(vertical: t.space(2)),
      child: Semantics(
        header: true,
        // `.app-eyebrow`: `font-size: xs; font-weight: bold; letter-spacing: var(--app-tracking-caps);
        // text-transform: uppercase; color: var(--app-ink-3)`. Said as written, drawn in capitals.
        label: text,
        child: ExcludeSemantics(
          // In the page's own line (13.5px for these 11.16px capitals), not the engine's whole 14.
          child: ExactLines.of(
            Text(text.toUpperCase(), style: pageText(t, size, weight: 'bold', color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps', em: size))),
            normal: true,
            dpr: t.css.lineDpr,
          ),
        ),
      ),
    );
  }
}

/// Told to a group's child that it comes straight after a row or a field, and so wears the hairline between them
/// (`.row + .row`, `.field + .field`, `.field + .row`, `.row + .field`).
class _AfterRow extends InheritedWidget {
  const _AfterRow({required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_AfterRow>() != null;

  @override
  bool updateShouldNotify(_AfterRow old) => false;
}

/// What [SheetGroup] counts as a row or a field when it rules a line between two of them. A widget of another kind
/// that draws one of the two inside itself says so by implementing this.
abstract interface class SheetRuled {}

/// `SheetGroup` (`.group`): a card of rows on the page's own ground, its corners clipping what is in it.
class SheetGroup extends StatelessWidget {
  const SheetGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(t.radius('lg'));
    return CssFlow.block(
      // `margin-block-end: var(--glacier-space-3); border-radius: var(--glacier-radius-lg);
      // background: var(--glacier-bg); overflow: hidden`
      margin: EdgeInsets.only(bottom: t.space(3)),
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: t.color('glacier-bg'),
          // `display: grid`: one column, each child as wide as the card.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (at, child) in children.indexed)
                if (at > 0 && child is SheetRuled && children[at - 1] is SheetRuled) _AfterRow(child: child) else child,
            ],
          ),
        ),
      ),
    );
  }
}

/// `SheetIcon` (`.icon`): the sheet's icon slot, an 18 px drawing in a 30 px ring of the row's own colour.
///
/// Differs from the web: [icon] is a widget drawn at the size and in the colour of the [IconTheme] this gives it (a
/// [StrokeMark]; an [AppIcon] takes the colour and is given its 18 by the caller), where the page took a component and sized its `svg` by a rule.
class SheetIcon extends StatelessWidget {
  const SheetIcon({super.key, required this.icon});
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = IconTheme.of(context).color ?? t.color('glacier-text');
    final ring = t.lenOf('1.875rem');
    return ExcludeSemantics(
      child: Container(
        width: ring,
        height: ring,
        alignment: Alignment.center,
        // `border-radius: 50%; border: var(--app-line) solid currentColor`
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: snapBorder(context, t.len('app-line')))),
        // `.icon svg { inline-size: 18px; block-size: 18px }`
        child: IconTheme(data: IconThemeData(color: color, size: 18), child: icon),
      ),
    );
  }
}

/// `SheetRow` (`.row`): a line of a group. With [onPress] it is a button; without it, a line of text. [chosen] is a
/// choice among several: pressed, with a tick. [danger] is the one colour a Delete may wear.
///
/// Differs from the web: [label] and [hint] are words, as every row so far gives them; [SheetRow.rich] takes widgets
/// where the page's `ReactNode` was something else.
class SheetRow extends StatelessWidget implements SheetRuled {
  const SheetRow({super.key, this.icon, required String label, String? hint, this.onPress, this.disabled = false, this.chosen, this.on, this.danger = false})
      : _label = label,
        _hint = hint;

  const SheetRow.rich({super.key, this.icon, required Widget label, Widget? hint, this.onPress, this.disabled = false, this.chosen, this.on, this.danger = false})
      : _label = label,
        _hint = hint;

  /// A plugin's mark, drawn in the sheet's icon slot ([SheetIcon]).
  final Widget? icon;

  /// Words, or a widget where the row was made [SheetRow.rich].
  final Object _label;
  final Object? _hint;

  /// Without it the row is a line of text, not a button.
  final VoidCallback? onPress;
  final bool disabled;

  /// A choice among several: pressed, with a tick. Null for a row that is not a choice.
  final bool? chosen;

  /// Something this row starts that is on now (a run of the AI's): pressed, with a dot at its end, rather than the
  /// tick, which marks a choice (`aria-pressed` and `.chosen`). Null for a row that starts nothing of the kind.
  final bool? on;
  final bool danger;

  /// A row's words in [style]: a string in the page's exact line, a widget of the caller's own under the style.
  static Widget _line(Object said, TextStyle style, Tokens t) =>
      said is Widget ? DefaultTextStyle(style: style, child: said) : ExactLines.of(Text(said as String, style: style), normal: true, dpr: t.css.lineDpr);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final sm = t.fontSize('sm');
    final after = _AfterRow.of(context);
    final rule = snapBorder(context, 1);

    Widget row(PressState state) {
      // `.row { color: var(--glacier-text) }`, `.danger { color: var(--glacier-red-9) }`, and, more specific than
      // either, `.row[aria-disabled]` and `.row:disabled { color: var(--glacier-text-muted) }`.
      final color = onPress == null || state.disabled
          ? t.color('glacier-text-muted')
          : danger
              ? t.color('glacier-red-9')
              : t.color('glacier-text');
      final words = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        // `.label { display: grid; gap: 2px; min-inline-size: 0; font-weight: medium }`
        spacing: 2,
        children: [
          // Each in the page's own line (`line-height: normal`: 19.43px for the label's 16.26, 16.38 for the hint's
          // 13.47), where the engine's whole pixels made a row with a two-line hint a pixel short and a sheet of
          // rows drift 1 to 2 device pixels a row beside the page's.
          _line(_label, pageText(t, md, weight: 'medium', color: color), t),
          if (_hint != null)
            // `.hint { font-size: sm; font-weight: regular; color: var(--glacier-text-subtle); overflow-wrap: anywhere }`
            _line(_hint, pageText(t, sm, color: t.color('glacier-text-subtle')), t),
        ],
      );
      return ConstrainedBox(
        // `min-block-size: var(--glacier-space-12)`, the hairline over it inside that height (`box-sizing: border-box`).
        constraints: BoxConstraints(minHeight: t.space(12)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // `.row:active:not([aria-disabled], [data-choice]) { background: var(--app-wash) }`
            color: state.pressed ? t.color('app-wash') : null,
            // `.row + .row { border-block-start: 1px solid var(--glacier-border-subtle) }`
            border: after ? Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: rule)) : null,
          ),
          child: Padding(
            // `padding: var(--glacier-space-3) var(--glacier-space-4)`
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(3) + (after ? rule : 0), t.space(4), t.space(3)),
            child: IconTheme(
              data: IconThemeData(color: color, size: md),
              // `display: flex; align-items: center; gap: var(--glacier-space-3)`
              child: Row(
                spacing: t.space(3),
                children: [
                  if (icon != null) SheetIcon(icon: icon!),
                  Expanded(child: words),
                  // `.tick { margin-inline-start: auto }`: at the row's far end.
                  if (chosen ?? false) _Tick(color: color, em: md),
                  // `.chosen { flex: none; inline-size: 0.55rem; block-size: 0.55rem; border-radius: 50%;
                  //   background: var(--glacier-text) }`
                  if (on ?? false)
                    ExcludeSemantics(child: Container(width: t.lenOf('0.55rem'), height: t.lenOf('0.55rem'), decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('glacier-text')))),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (onPress == null) {
      // `<div class="row" aria-disabled="true">`: said, and not pressed.
      return Semantics(container: true, enabled: false, child: row(const PressState(disabled: true)));
    }
    return GlacierPressable(
      onPressed: disabled ? null : onPress,
      // `aria-pressed`, for a row that is a choice, and for one whose run is on.
      toggled: chosen ?? on,
      builder: (context, state) => row(state),
    );
  }
}

/// `.tick`: the chosen row's tick, drawn with two borders of a small box turned 45 degrees:
/// `inline-size: 0.4em; block-size: 0.8em; border-inline-end: 2px solid currentColor;
/// border-block-end: 2px solid currentColor; transform: rotate(45deg) translate(-0.1em, -0.1em)`.
class _Tick extends StatelessWidget {
  const _Tick({required this.color, required this.em});
  final Color color;
  final double em;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: color, width: 2);
    return ExcludeSemantics(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationZ(0.7853981633974483)..translateByDouble(-0.1 * em, -0.1 * em, 0, 1),
        child: Container(width: 0.4 * em, height: 0.8 * em, decoration: BoxDecoration(border: Border(right: side, bottom: side))),
      ),
    );
  }
}

/// `SheetField` (`.field`, `.fieldLabel`, `.input`): a named line to type on, ruled underneath, the rule in ink
/// while it is being typed in.
///
/// The parameters are the `<input>` attributes the app's sheets pass, under their own names. What differs from the
/// web: [onChange] is handed the text, not an event; with [value] the field is controlled, as in React, and an edit
/// the parent does not take is put back; [onSubmitted] is the soft keyboard's action key or Enter, which the page
/// caught as an `onKeyDown` for `Enter`; and [onKeyDown] sees a key before the text does and answers whether it took
/// it. The field is this file's own line of text rather than the kit's `GlacierInput`, which is a box with a border
/// all round; its selection handles and its cut, copy and paste menu are the kit's.
class SheetField extends StatefulWidget implements SheetRuled {
  const SheetField({
    super.key,
    required this.label,
    this.value,
    this.onChange,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.autoFocus = false,
    this.autoCapitalize = TextCapitalization.sentences,
    this.autoCorrect = true,
    this.inputMode,
    this.enterKeyHint,
    this.maxLength,
    this.onSubmitted,
    this.onKeyDown,
  });

  final String label;

  /// The text, where the parent holds it. Null leaves it to the field, or to a [controller].
  final String? value;
  final ValueChanged<String>? onChange;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final bool autoFocus;
  final TextCapitalization autoCapitalize;
  final bool autoCorrect;

  /// `inputmode`: the soft keyboard.
  final TextInputType? inputMode;

  /// `enterkeyhint`: what the soft keyboard's action key says and does.
  final TextInputAction? enterKeyHint;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final KeyEventResult Function(KeyEvent event)? onKeyDown;

  @override
  State<SheetField> createState() => _SheetFieldState();
}

class _SheetFieldState extends State<SheetField> implements TextSelectionGestureDetectorBuilderDelegate {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _showHandles = false;

  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController(text: widget.value ?? ''));
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'SheetField'));

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_redraw);
    // For the placeholder, which is there only while nothing is typed.
    _controller.addListener(_redraw);
  }

  @override
  void didUpdateWidget(SheetField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_redraw);
      _focus.addListener(_redraw);
    }
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_redraw);
      _controller.addListener(_redraw);
    }
    // Controlled: the text is the parent's. Whatever it hands down is what shows.
    final value = widget.value;
    if (value != null && value != _controller.text) {
      _controller.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    }
  }

  void _redraw() {
    if (!mounted) return;
    // A change made while this is being built is already on its way to the screen.
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) return;
    setState(() {});
  }

  @override
  void dispose() {
    (widget.focusNode ?? _ownFocus)?.removeListener(_redraw);
    (widget.controller ?? _ownController)?.removeListener(_redraw);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onSelection(TextSelection selection, SelectionChangedCause? cause) {
    // Handles for a selection made by touch, as a phone's field shows them; none for a mouse's or a key's.
    final show = _gestures.shouldShowSelectionToolbar && (cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.tap || cause == SelectionChangedCause.doubleTap) && _controller.text.isNotEmpty;
    if (show != _showHandles) setState(() => _showHandles = show);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final xs = t.fontSize('xs');
    final after = _AfterRow.of(context);
    final rule = snapBorder(context, 1);
    final line = snapBorder(context, t.len('app-line'));
    final focused = _focus.hasFocus;
    final style = pageText(t, md, color: t.color('glacier-text'));

    Widget editable = EditableText(
      key: editableTextKey,
      controller: _controller,
      focusNode: _focus,
      style: style,
      // `caret-color: auto` is the text's own colour, and a browser's caret is one pixel wide.
      cursorColor: t.color('glacier-text'),
      cursorWidth: 1,
      backgroundCursorColor: t.color('glacier-text-subtle'),
      selectionColor: focused ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _showHandles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      autofocus: widget.autoFocus,
      autocorrect: widget.autoCorrect,
      keyboardType: widget.inputMode ?? TextInputType.text,
      textInputAction: widget.enterKeyHint,
      textCapitalization: widget.autoCapitalize,
      inputFormatters: [if (widget.maxLength != null) LengthLimitingTextInputFormatter(widget.maxLength)],
      onChanged: (text) {
        widget.onChange?.call(text);
        // Controlled, and the parent did not take the edit: what it holds is what shows.
        final value = widget.value;
        if (value != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final held = widget.value;
            if (mounted && held != null && held != _controller.text) {
              _controller.value = TextEditingValue(text: held, selection: TextSelection.collapsed(offset: held.length));
            }
          });
        }
      },
      onSubmitted: widget.onSubmitted,
      onSelectionChanged: _onSelection,
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
    );
    if (widget.onKeyDown != null) {
      // `onKeyDown` on the element: the keys reach this before the text does, and a handled one goes no further.
      editable = Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: (node, event) => event is KeyUpEvent ? KeyEventResult.ignored : widget.onKeyDown!(event), child: editable);
    }

    final input = _gestures.buildGestureDetector(
      behavior: HitTestBehavior.translucent,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: DecoratedBox(
          // `border-block-end: var(--app-line) solid var(--glacier-border-strong)`, and
          // `.input:focus { border-block-end-color: var(--glacier-text) }`.
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color(focused ? 'glacier-text' : 'glacier-border-strong'), width: line))),
          child: Padding(
            // `padding: var(--glacier-space-2) 0`
            padding: EdgeInsets.only(top: t.space(2), bottom: t.space(2) + line),
            // The input's line is the page's (`line-height: normal`, 19.43px at 16.26), where the engine's field is a
            // whole 20: the field was 5 device pixels taller than the page's with its label's line.
            child: SizedBox(
              height: normalLineBox(style, dpr: t.css.lineDpr).height,
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                if (_controller.text.isEmpty && widget.placeholder != null)
                  ExcludeSemantics(child: Text(widget.placeholder!, style: style.copyWith(color: t.color('glacier-text-subtle')), maxLines: 1, softWrap: false, overflow: TextOverflow.clip)),
                // The arrows, Backspace and the rest of a hardware keyboard's editing keys.
                DefaultTextEditingShortcuts(child: editable),
              ],
            ),
              ),
            ),
          ),
        ),
      ),
    );

    return DecoratedBox(
      // `.field + .field, .field + .row, .row + .field { border-block-start: 1px solid var(--glacier-border-subtle) }`
      decoration: BoxDecoration(border: after ? Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: rule)) : null),
      child: Padding(
        // `.field { display: grid; gap: var(--glacier-space-1); padding: var(--glacier-space-3) var(--glacier-space-4) }`
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(3) + (after ? rule : 0), t.space(4), t.space(3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(1),
          children: [
            // `.fieldLabel`: `font-size: xs; font-weight: bold; letter-spacing: var(--app-tracking-caps-close);
            // text-transform: uppercase; color: var(--glacier-text-subtle)`. The field is named by it; it is not read twice.
            ExcludeSemantics(
              child: ExactLines.of(
                Text(
                  widget.label.toUpperCase(),
                  style: pageText(t, xs, weight: 'bold', color: t.color('glacier-text-subtle'), tracking: t.len('app-tracking-caps-close', em: xs)),
                ),
                normal: true,
                dpr: t.css.lineDpr,
              ),
            ),
            Semantics(label: widget.label, textField: true, child: input),
          ],
        ),
      ),
    );
  }
}

/// `StrokeMark`: a stroke mark in the sheet's icon style, one path on a 24 grid, [size] pixels or the size of the
/// [IconTheme] it is drawn in (the page's `1em`).
///
/// Differs from the web: [path] is the drawing already made, where the page took an SVG path's `d`; this project
/// has no reader of path data outside the pictures `flutter_svg` draws.
class StrokeMark extends StatelessWidget {
  const StrokeMark({super.key, required this.path, this.size});

  /// The mark on a 24 by 24 grid.
  final Path path;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final box = size ?? theme.size ?? 24;
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(box), painter: _StrokePainter(path, theme.color ?? context.tokens.color('glacier-text'))),
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter(this.path, this.color);
  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    // `fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"`
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.path != path || old.color != color;
}
