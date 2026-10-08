/// Find and replace, as a bar resting on top of the keyboard. Ports `src/app/editor/FindBar.tsx` with
/// `FindBar.module.css`. Opened from the note's settings sheet, or with a selection's words from the
/// press-and-hold menu. The header stays as it is; the bar is there while it is used and gone after (Matt: "I'm not
/// sure where to put things like this in the UI/UX without messing up the UI").
///
/// The find field, where the current match is out of how many, the arrows between them, and Replace, which adds a
/// second field with Replace and All. Done, or the back gesture, closes it and leaves the caret on the last match.
///
/// The page's paper with a hairline over it, one row for finding and one more for replacing.
///
/// What differs:
/// - `position: fixed; inset-block-end: 0` is whoever shows the bar's: this is the bar's own box, as wide as it is
///   given and as tall as its rows, to be laid at the foot of the note's screen above the keyboard (the web page is
///   laid out above the keyboard by its activity, so its foot is the keyboard's top).
/// - the first search runs after the first frame, as an effect does after its render: a search tells the editor's
///   own widgets to draw, which cannot be asked of them while this one is being built. Until it has run the count
///   is empty.
/// - the fields are the app's own text fields, not a browser's `<input>`: no cross to empty the find field (which
///   Chromium draws inside `type="search"` on a desktop and Android's WebView does not), the selection in the kit's
///   own colour, and a placeholder in the grey a browser gives one (`darkgray` under 0.54, measured as
///   rgb(117, 117, 117) in both themes).
/// - a press on a button keeps the field focused because nothing here takes focus on a press, where the page
///   stopped the pointer's default; Done is the same press as the others, and hands the focus to the note itself.
/// - `aria-live="polite"` on the count is `liveRegion`; `role="search"` is a labelled container.
/// - the focus ring of `.app-word` and `.app-pill` (a keyboard's focus) is the kit's [GlacierFocusRing].
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/back.dart';
import '../view/editor_view.dart';
import 'find_marks.dart';

/// The parts of the bar, for whoever needs to find one: a test, a walkthrough.
abstract final class FindBarKeys {
  static const Key bar = ValueKey<String>('find-bar');
  static const Key findRow = ValueKey<String>('find-row');
  static const Key replaceRow = ValueKey<String>('find-replace-row');
  static const Key find = ValueKey<String>('find-field');
  static const Key count = ValueKey<String>('find-count');
  static const Key previous = ValueKey<String>('find-previous');
  static const Key next = ValueKey<String>('find-next');
  static const Key replace = ValueKey<String>('find-replace');
  static const Key done = ValueKey<String>('find-done');
  static const Key replaceWith = ValueKey<String>('find-replace-with');
  static const Key replaceOne = ValueKey<String>('find-replace-one');
  static const Key all = ValueKey<String>('find-all');
  static const Key said = ValueKey<String>('find-said');
}

/// The find bar over `view`, which must have [findBarExtensions] in its state. `initial` is what it opens
/// searching for, chosen to type over; `onClose` is told when it is done with, after the search has ended.
class FindBar extends StatefulWidget {
  const FindBar({super.key, required this.view, this.initial = '', required this.onClose});

  final EditorView view;
  final String initial;
  final VoidCallback onClose;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> with SingleTickerProviderStateMixin {
  late final TextEditingController _query = TextEditingController(text: widget.initial);
  final TextEditingController _replacement = TextEditingController();
  final FocusNode _field = FocusNode(debugLabel: 'Find');
  final FocusNode _replaceField = FocusNode(debugLabel: 'Replace with');
  // `animation: barIn 160ms var(--glacier-ease-out)`
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
  bool _replacing = false;
  String? _said;

  /// What was last searched for; null until the first search has run.
  String? _searched;
  bool _closed = false;

  // The count follows the note's own state, which the arrows and edits change outside this widget.
  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_redraw);
    _field.addListener(_redraw);
    _replaceField.addListener(_redraw);
    // `field.current?.focus(); field.current?.select();`
    _query.selection = TextSelection(baseOffset: 0, extentOffset: _query.text.length);
    _field.requestFocus();
    _afterFrame(_search);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `@media (prefers-reduced-motion: reduce) { .bar { animation: none } }`
    if (context.tokens.reducedMotion) {
      _in.value = 1;
    } else if (!_in.isAnimating && _in.value == 0) {
      _in.forward();
    }
  }

  @override
  void didUpdateWidget(FindBar old) {
    super.didUpdateWidget(old);
    if (identical(old.view, widget.view)) return;
    old.view.removeListener(_redraw);
    widget.view.addListener(_redraw);
    _searched = null;
    _afterFrame(_search);
  }

  @override
  void dispose() {
    widget.view.removeListener(_redraw);
    _in.dispose();
    _query.dispose();
    _replacement.dispose();
    _field.dispose();
    _replaceField.dispose();
    super.dispose();
  }

  void _afterFrame(VoidCallback run) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closed) run();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// `useEffect(() => { search(view, query); redraw(); }, [view, query, redraw])`
  void _search() {
    _searched = _query.text;
    searchIn(widget.view, _query.text);
    _redraw();
  }

  void _typed(String value) {
    if (value == _searched) return;
    _said = null;
    _search();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    endSearchIn(widget.view);
    widget.onClose();
    widget.view.focus();
  }

  void _move(int by) {
    stepIn(widget.view, by);
    fireMotor(HapticKind.selection);
    _redraw();
  }

  KeyEventResult _key(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _move(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final state = findOf(widget.view.state);
    final matches = state.matches;
    final some = matches.isNotEmpty;
    final query = _query.text;
    final gap = t.space(1);
    final hairline = _border(t.len('glacier-hairline'), ratio);
    final small = t.fontSize('sm');
    // `{query ? (matches.length ? `${current + 1} of ${matches.length}` : 'None') : ''}`
    final said = query.isNotEmpty && _searched != null ? (some ? '${state.current + 1} of ${matches.length}' : 'None') : '';

    Widget icon(Key key, String label, LucideIcon glyph, double size, double stroke, VoidCallback? onPressed, {bool? on}) {
      // `.icon { inline-size: 2.25rem; block-size: 2.25rem; border-radius: var(--glacier-radius-full) }`
      final side = t.lenOf('2.25rem');
      return GlacierPressable(
        key: key,
        onPressed: onPressed,
        semanticLabel: label,
        toggled: on,
        canRequestFocus: false,
        builder: (context, press) {
          // `.icon[data-on] { background: var(--glacier-text); color: var(--glacier-bg) }`
          // `.icon:disabled { color: var(--glacier-text-subtle) }`
          final ink = press.disabled ? t.color('glacier-text-subtle') : (on ?? false ? t.color('glacier-bg') : t.color('glacier-text'));
          return Container(
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: on ?? false ? ShapeDecoration(color: t.color('glacier-text'), shape: const CircleBorder()) : null,
            child: AppIcon(glyph, size: size, strokeWidth: stroke, color: ink),
          );
        },
      );
    }

    final findRow = Row(
      key: FindBarKeys.findRow,
      children: <Widget>[
        Expanded(
          child: _Field(
            key: FindBarKeys.find,
            controller: _query,
            focusNode: _field,
            placeholder: 'Find',
            label: 'Find',
            keyboard: true,
            // `type="search" inputMode="search" enterKeyHint="search"`
            action: TextInputAction.search,
            onChanged: _typed,
            // The keyboard's own search key, which is not a key press here: the next match, the field kept.
            onAction: () => _move(1),
            onKey: _key,
          ),
        ),
        SizedBox(width: gap),
        // `.count { flex: none; min-inline-size: 3em; font-size: var(--glacier-font-size-sm);
        //   font-variant-numeric: tabular-nums; text-align: center; color: var(--glacier-text-muted) }`
        Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            key: FindBarKeys.count,
            // With nothing to say it is a span with no words in it: its width, and no height.
            constraints: BoxConstraints(minWidth: small * 3, maxHeight: said.isEmpty ? 0 : double.infinity),
            child: Text(
              said,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: _tabular(t.textAt(small, color: t.color('glacier-text-muted'))),
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
        SizedBox(width: gap),
        icon(FindBarKeys.previous, 'Previous match', Lucide.chevronUp, 20, 2.2, some ? () => _move(-1) : null),
        SizedBox(width: gap),
        icon(FindBarKeys.next, 'Next match', Lucide.chevronDown, 20, 2.2, some ? () => _move(1) : null),
        SizedBox(width: gap),
        icon(FindBarKeys.replace, 'Replace', Lucide.replace, 19, 2.1, () => setState(() => _replacing = !_replacing), on: _replacing),
        SizedBox(width: gap),
        _Word(key: FindBarKeys.done, onPressed: _close, child: const Text('Done')),
      ],
    );

    final replaceRow = !_replacing
        ? null
        : Row(
            key: FindBarKeys.replaceRow,
            children: <Widget>[
              Expanded(
                child: _Field(
                  key: FindBarKeys.replaceWith,
                  controller: _replacement,
                  focusNode: _replaceField,
                  placeholder: 'Replace with',
                  label: 'Replace with',
                  // `type="text" enterKeyHint="done"`
                  action: TextInputAction.done,
                  onChanged: (_) {},
                ),
              ),
              SizedBox(width: gap),
              _Word(
                key: FindBarKeys.replaceOne,
                onPressed: !some
                    ? null
                    : () {
                        replaceOneIn(widget.view, _replacement.text);
                        fireMotor(HapticKind.selection);
                        _redraw();
                      },
                child: const Text('Replace'),
              ),
              SizedBox(width: gap),
              _All(
                key: FindBarKeys.all,
                onPressed: !some
                    ? null
                    : () {
                        final count = replaceAllIn(widget.view, _replacement.text);
                        fireMotor(HapticKind.success);
                        setState(() => _said = 'Replaced $count');
                      },
              ),
            ],
          );

    // `.bar { display: grid; grid-template-columns: minmax(0, 1fr); gap: var(--glacier-space-2);
    //   padding-block: var(--glacier-space-2) calc(var(--glacier-space-2) + var(--app-safe-bottom));
    //   padding-inline: var(--app-gutter-start) var(--app-gutter-end); background: var(--glacier-bg);
    //   border-block-start: var(--glacier-hairline) solid var(--app-rule) }`
    final bar = DecoratedBox(
      key: FindBarKeys.bar,
      decoration: BoxDecoration(
        color: t.color('glacier-bg'),
        border: Border(top: BorderSide(color: t.color('app-rule'), width: hairline)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          top: hairline + t.space(2),
          bottom: t.space(2) + t.len('app-safe-bottom'),
          start: t.len('app-gutter-start'),
          end: t.len('app-gutter-end'),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            findRow,
            if (replaceRow != null) ...<Widget>[SizedBox(height: t.space(2)), replaceRow],
            if (_said != null) ...<Widget>[
              SizedBox(height: t.space(2)),
              // `.said { margin: 0; font-size: var(--glacier-font-size-xs); color: var(--glacier-text-muted) }`
              Text('$_said. Undo takes it back.', key: FindBarKeys.said, style: t.textAt(t.fontSize('xs'), color: t.color('glacier-text-muted')), textScaler: TextScaler.noScaling),
            ],
          ],
        ),
      ),
    );

    return OnBack(
      onBack: _close,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Find in this note',
        // `@keyframes barIn { from { opacity: 0; transform: translateY(6px) } }`
        child: AnimatedBuilder(
          animation: _in,
          builder: (context, child) {
            final at = t.curve('glacier-ease-out').transform(_in.value);
            if (at >= 1) return child!;
            return Opacity(opacity: at, child: Transform.translate(offset: Offset(0, 6 * (1 - at)), child: child));
          },
          child: bar,
        ),
      ),
    );
  }
}

/// A border's width as the page draws it: down to a whole device pixel, never under one.
double _border(double width, double ratio) {
  if (width <= 0) return 0;
  final device = (width * ratio).floorToDouble();
  return (device < 1 ? 1 : device) / ratio;
}

/// `font-variant-numeric: tabular-nums`.
TextStyle _tabular(TextStyle style) => style.copyWith(fontFeatures: <FontFeature>[...?style.fontFeatures, const FontFeature.tabularFigures()]);

/// `.field`: a field of the bar, a line round a pill.
class _Field extends StatefulWidget {
  const _Field({super.key, required this.controller, required this.focusNode, required this.placeholder, required this.label, required this.action, required this.onChanged, this.onAction, this.onKey, this.keyboard = false});

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final String label;
  final TextInputAction action;
  final ValueChanged<String> onChanged;

  /// The keyboard's action key; null leaves it to put the keyboard away.
  final VoidCallback? onAction;
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// Whether the field asks for the keyboard as it arrives: the bar opens with it up.
  final bool keyboard;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _handles = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void initState() {
    super.initState();
    if (!widget.keyboard) return;
    // Focus alone does not always bring the keyboard with it; asked of the field itself once it is there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) editableTextKey.currentState?.requestKeyboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final focused = widget.focusNode.hasFocus;
    // `font: inherit; font-size: var(--glacier-font-size-md); color: var(--glacier-text)`
    final style = t.textAt(t.fontSize('md'), color: t.color('glacier-text'));
    final empty = widget.controller.text.isEmpty;
    Widget editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: style,
      cursorColor: t.color('glacier-text'),
      cursorWidth: 1,
      backgroundCursorColor: t.color('glacier-text-subtle'),
      // A blurred field keeps its selection and stops showing it, as an `<input>` does.
      selectionColor: focused ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _handles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      keyboardType: TextInputType.text,
      textInputAction: widget.action,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      maxLines: 1,
      onChanged: widget.onChanged,
      onEditingComplete: widget.onAction,
      // A press elsewhere on the bar leaves the field as it is; a touch on the note takes the focus itself.
      onTapOutside: (_) {},
      onSelectionChanged: (selection, cause) {
        final show = cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.doubleTap || (cause == SelectionChangedCause.tap && !empty);
        if (show != _handles) setState(() => _handles = show);
      },
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
      textScaler: TextScaler.noScaling,
    );
    if (widget.onKey != null) {
      // `onKeyDown` on the element: the keys reach this before the text does, and a handled one goes no further.
      editable = Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: (node, event) => widget.onKey!(event), child: editable);
    }
    final line = _border(t.len('app-line'), MediaQuery.devicePixelRatioOf(context));
    // `.field { flex: 1; min-inline-size: 0; block-size: 2.5rem; padding: 0 var(--glacier-space-3);
    //   border: var(--app-line) solid var(--glacier-border-strong); border-radius: var(--glacier-radius-full);
    //   background: none }`  `.field:focus { outline: none; border-color: var(--glacier-text) }`
    return Semantics(
      textField: true,
      label: widget.label,
      onTap: () {
        widget.focusNode.requestFocus();
        editableTextKey.currentState?.requestKeyboard();
      },
      child: _gestures.buildGestureDetector(
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: t.lenOf('2.5rem'),
          // The line's own width is the shape's to add.
          padding: EdgeInsets.symmetric(horizontal: t.space(3)),
          alignment: AlignmentDirectional.centerStart,
          decoration: ShapeDecoration(
            shape: StadiumBorder(side: BorderSide(color: focused ? t.color('glacier-text') : t.color('glacier-border-strong'), width: line, strokeAlign: BorderSide.strokeAlignInside)),
          ),
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: <Widget>[
              if (empty) ExcludeSemantics(child: Text(widget.placeholder, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(color: const Color(0xFF757575)), textScaler: TextScaler.noScaling)),
              // The arrows, Backspace and the rest of a hardware keyboard's editing keys.
              DefaultTextEditingShortcuts(child: editable),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.app-word` (app.css) as the bar wears it: `.word { flex: none; padding-inline: var(--glacier-space-2);
/// font-size: var(--glacier-font-size-sm) }`. A button that is only its word, muted until pressed.
class _Word extends StatelessWidget {
  const _Word({super.key, required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      canRequestFocus: false,
      builder: (context, state) {
        // `.app-word { color: var(--glacier-text-muted) }` `:active { color: var(--glacier-text) }`
        // `:disabled { color: var(--glacier-text-subtle) }`
        final color = state.disabled ? t.color('glacier-text-subtle') : (state.pressed ? t.color('glacier-text') : t.color('glacier-text-muted'));
        return GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('sm'),
          // `min-block-size: var(--glacier-space-12); padding: var(--glacier-space-2) 0`, the word in the middle.
          child: Container(
            constraints: BoxConstraints(minHeight: t.space(12)),
            padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(2)),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              // `font: inherit; font-weight: var(--glacier-font-weight-medium)`
              child: DefaultTextStyle.merge(style: t.textAt(t.fontSize('sm'), weight: 'medium', color: color), maxLines: 1, softWrap: false, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// `.app-pill` (ink.css) as the bar wears it (`.all { flex: none }`): the one loud button, ink on paper turned
/// round.
class _All extends StatelessWidget {
  const _All({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('md');
    return GlacierPressable(
      onPressed: onPressed,
      canRequestFocus: false,
      builder: (context, state) {
        // `:disabled { background: var(--app-paper-3); color: var(--app-ink-3) }`
        final ink = state.disabled ? t.color('app-ink-3') : t.color('app-paper');
        return GlacierFocusRing(
          visible: state.focused,
          offset: 3,
          color: t.color('app-ink'),
          child: AnimatedScale(
            // `.app-pill:active { transform: scale(0.98) }`, over the fast duration.
            scale: state.pressed ? 0.98 : 1,
            duration: t.duration('glacier-duration-fast'),
            curve: t.curve('glacier-ease-out'),
            child: Container(
              // `min-block-size: var(--glacier-space-12); padding: 0 var(--glacier-space-6);
              //   border-radius: var(--glacier-radius-full); background: var(--app-ink)`
              constraints: BoxConstraints(minHeight: t.space(12)),
              padding: EdgeInsets.symmetric(horizontal: t.space(6)),
              decoration: ShapeDecoration(color: state.disabled ? t.color('app-paper-3') : t.color('app-ink'), shape: const StadiumBorder()),
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                // `font-size: var(--glacier-font-size-md); font-weight: var(--glacier-font-weight-semibold);
                //   letter-spacing: -0.005em`
                child: Text('All', maxLines: 1, softWrap: false, style: t.textAt(size, weight: 'semibold', color: ink, tracking: -0.005 * size), textScaler: TextScaler.noScaling),
              ),
            ),
          ),
        );
      },
    );
  }
}
