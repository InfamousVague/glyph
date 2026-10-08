/// The Academy's live page: what you type, and the same thing as a note draws it, right underneath (Matt: "set it up
/// as a live code type thing where it teaches you then you type it and see it format below"). A port of
/// `src/app/academy/Playground.tsx` with `Playground.module.css`.
///
/// The top half is a plain field, in the typewriter face, with nothing helping or hiding: the marks have to be
/// visible, since they are the thing being taught. Autocorrect and autocapitalising are off, or a phone would turn
/// `# weekend` into `# Weekend` and the underscores into quotes while somebody is trying to learn what they do.
///
/// The bottom half is the note's own editor (lib/editor/editor_widget.dart `Editor`), read-only and formatted: the
/// real marks drawn by the real app, so what is learned here is what a note does. It is redrawn as the words change,
/// which is the whole point: a star typed is a word gone bold underneath.
///
/// A to-do's box and a choice's take a tap here as they do in a note (`boxTapsWhileReadOnly`), and the change goes
/// back into the field above, so a choice is learned by picking one and the words show the x move.
///
/// The field owns what is in it: its controller is written only when the app changed the text (Show me, or the next
/// lesson), never with what was typed. A phone keyboard composes as you type and commits the word on space; a field
/// written back into the middle of that composition has the letters committed again (Matt, on the phone: "when doing
/// the ## and then hitting space on the academy it shows an extra # and the lesson isn't passed").
///
/// What differs:
/// - **A ```query and a ```board are not drawn**, they are their fence's lines: the page's editor draws both, the
///   query over a library of one note, what is typed (`PAGE.queries`). This editor's query and board pieces are not
///   put together yet; whoever wires the app hands them in through [Playground.extensions] when they are.
/// - Pictures, link cards and films are not drawn either (no store of pictures, no previews on a page to play on).
/// - The note shown is in the interface's face, as the page's is (`.room` has the scroller inherit the page's face
///   while the rest of the note's look stays the person's own): [_RoomEnv] is the note's look with that one face.
/// - The editor is a sliver, so it sits in a scroll view of its own that is as tall as its lines and never scrolls;
///   the page's sat in its box with `grow`.
/// - The field's two-line least height is `minLines: 2` (the page's `rows={2}`), and it grows with its lines as
///   the page's grew by its `scrollHeight`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor/editor.dart';
import '../editor/editor_widget.dart';
import '../editor/items/items.dart';
import '../editor/looks/look.dart';
import '../editor/marks/marks.dart';
import '../editor/tables/tables.dart';
import '../editor/view/base.dart';
import '../editor/view/editor_view.dart';
import '../editor/view/view_mode.dart';
import '../plugins/registry.dart';

/// The playground's library: no other notes, and links that go nowhere. The page is to play on, and has no other
/// notes to open (`PAGE`).
final WikiOptions _page = WikiOptions(known: (_) => false, open: (_, [_]) {});

/// The look of the note shown: the page's own sizes, with the words in the interface's face
/// (guide/MarkExample.module.css `.room :global(.cm-scroller) { font-family: inherit }`). Everything else a note's
/// face decides (a coding face's own features, no optical size, no tracking) stays as the person's notes have it,
/// as on the page.
class _RoomEnv extends LookEnv {
  _RoomEnv({required super.t, required super.body, required super.headings, required super.gutter, super.devicePixelRatio, super.dark, super.tabSize, super.contentTop, super.contentBottom});

  @override
  List<String> get noteFamilies => t.families('glacier-font-sans');
}

class Playground extends StatefulWidget {
  const Playground({super.key, required this.value, required this.onChange, required this.placeholder, this.extensions = const <Extension>[]});

  /// What is typed, as the screen holds it.
  final String value;

  /// Every change: a key in the field, or a box tapped in the note shown.
  final ValueChanged<String> onChange;

  /// Shown in the empty field: the lesson's example.
  final String placeholder;

  /// More of the editor's pieces for the note shown (a query's drawing, a board's), from whoever wires the app. The
  /// same list each build: another list is another editor.
  final List<Extension> extensions;

  @override
  State<Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<Playground> implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextEditingController _field = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode(debugLabel: 'Type the markdown');
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _handles = false;

  Registry? _registry;
  List<GlyphFormat> _formats = const <GlyphFormat>[];
  EditorView? _view;

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
    _listen();
  }

  /// The plugins as they are now: a mark switched off is not drawn, as a note would not draw it.
  void _listen() {
    final now = plugins;
    if (!identical(now, _registry)) {
      _registry?.removeListener(_switched);
      _registry = now..addListener(_switched);
    }
    _formats = now.formats();
  }

  void _switched() {
    if (!mounted) return;
    final next = plugins.formats();
    if (listEquals(next, _formats)) return;
    setState(() {
      _formats = next;
      _view?.destroy();
      _view = null;
    });
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  EditorView _make(String doc) => EditorView(
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(
        formats: _formats,
        display: NoteView.formatted,
        readOnly: true,
        more: <Extension>[
          editorInput(),
          markExtensions(_formats),
          itemExtensions(wiki: _page),
          drawnTables(),
          boxTapsWhileReadOnly.of(true),
          EditorViewLike.updateListener.of((update) {
            if (!update.docChanged) return;
            final text = update.state.doc.toString();
            // A box tapped in the note shown: the change goes back into the field above.
            if (text != widget.value) widget.onChange(text);
          }),
          ...widget.extensions,
        ],
      ),
    ),
  );

  @override
  void didUpdateWidget(Playground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
    // Written only when it really differs, which leaves a keyboard's composition alone (see the header).
    if (_field.text != widget.value) _field.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    if (!identical(oldWidget.extensions, widget.extensions)) {
      _view?.destroy();
      _view = null;
    }
    final view = _view;
    if (view != null) {
      final doc = view.state.doc.toString();
      if (doc != widget.value) view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: doc.length, insert: widget.value)));
    }
  }

  @override
  void dispose() {
    _registry?.removeListener(_switched);
    _view?.destroy();
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  /// The note shown: the editor, in a scroll view as tall as its lines that never scrolls.
  Widget _note(BuildContext context, EditorView view) {
    final t = context.tokens;
    // The room a mark's example has (guide/MarkExample.module.css `.room`): no ground, no padding, no gutters.
    final env = _RoomEnv(
      t: t,
      body: t.len('app-body'),
      headings: <double>[for (var level = 1; level <= 6; level++) t.len('app-h$level')],
      gutter: 0,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      dark: t.isDark,
      tabSize: view.state.tabSize,
      contentTop: 0,
      contentBottom: 0,
    );
    return CustomScrollView(
      key: const ValueKey('playground-note'),
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      slivers: [Editor(view: view, env: env, fill: false)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    final quiet = t.color('app-ink-3');
    final xs = t.fontSize('xs');
    // `.label`: xs, spaced capitals, the third ink.
    final label = t.textAt(xs, color: quiet, tracking: t.len('app-tracking-caps', em: xs));
    // `.field`: the typewriter face at sm, `line-height: var(--glacier-leading-md)`.
    final typed = t.textAt(t.fontSize('sm'), mono: true, color: ink, height: t.len('glacier-leading-md'));
    final showing = widget.value.trim().isNotEmpty;

    final editable = EditableText(
      key: editableTextKey,
      controller: _field,
      focusNode: _focus,
      style: typed,
      cursorColor: ink,
      cursorWidth: 1,
      backgroundCursorColor: quiet,
      selectionColor: _focus.hasFocus ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _handles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      // `rows={2}`, and as tall as what is in it, so a list of five lines is not typed through a two-line window.
      minLines: 2,
      maxLines: null,
      // `spellCheck={false} autoCapitalize="off" autoCorrect="off" autoComplete="off"`; a phone's Enter must make a
      // new line here, not send anything (`enterKeyHint="enter"`).
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      onChanged: widget.onChange,
      onSelectionChanged: (selection, cause) {
        final show = cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.doubleTap || (cause == SelectionChangedCause.tap && _field.text.isNotEmpty);
        final touch = switch (defaultTargetPlatform) {
          TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
          _ => false,
        };
        if (_handles != (show && touch)) setState(() => _handles = show && touch);
      },
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
    );

    final field = GlacierFocusRing(
      // `.field:focus-visible { outline: 2px solid var(--glacier-accent-solid); outline-offset: 1px }`
      visible: _focus.hasFocus,
      offset: 1,
      radius: t.radius('md'),
      color: t.color('glacier-accent-solid'),
      child: DecoratedBox(
        // `background: color-mix(in oklch, currentColor 5%, transparent)`
        decoration: BoxDecoration(color: ink.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(t.radius('md'))),
        child: Padding(
          padding: EdgeInsets.all(t.space(3)),
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: _gestures.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: Stack(
                children: [
                  if (_field.text.isEmpty)
                    // `.field::placeholder`: the example, in the third ink, and never taller than the field.
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: ClipRect(
                          child: OverflowBox(alignment: Alignment.topLeft, maxHeight: double.infinity, child: Text(widget.placeholder, style: typed.copyWith(color: quiet))),
                        ),
                      ),
                    ),
                  DefaultTextEditingShortcuts(
                    child: Semantics(
                      label: 'Type the markdown',
                      onTap: () {
                        _focus.requestFocus();
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
    );

    Widget shown;
    if (showing) {
      final view = _view ??= _make(widget.value);
      shown = _note(context, view);
    } else {
      // `.waiting`
      shown = Text('Whatever you type appears here, drawn the way a note draws it.', key: const ValueKey('playground-waiting'), style: t.textAt(t.fontSize('sm'), color: quiet));
    }

    return DecoratedBox(
      key: const ValueKey('playground'),
      // `background: var(--app-paper); box-shadow: inset 0 0 0 1px color-mix(in oklch, currentColor 10%, transparent)`
      decoration: BoxDecoration(
        color: t.color('app-paper'),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: ink.withValues(alpha: 0.1), width: 1, strokeAlign: BorderSide.strokeAlignInside),
      ),
      child: Padding(
        padding: EdgeInsets.all(t.space(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          // `.playground { gap: var(--glacier-space-3) }`, `.part { gap: var(--glacier-space-2) }`
          spacing: t.space(3),
          children: [
            Column(
              key: const ValueKey('playground-typed'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(2),
              children: [
                Text('YOU TYPE', style: label),
                KeyedSubtree(key: const ValueKey('playground-field'), child: field),
              ],
            ),
            Column(
              key: const ValueKey('playground-shows'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(2),
              children: [
                Text('YOUR NOTE SHOWS', style: label),
                // `.shown`: the rule above it is the line between typing and reading.
                Container(
                  key: const ValueKey('playground-shown'),
                  constraints: BoxConstraints(minHeight: t.lenOf('3em', em: t.lenOf('1rem'))),
                  alignment: Alignment.topLeft,
                  // The rule takes its own pixel of the box, over the padding.
                  padding: EdgeInsets.only(top: t.len('glacier-hairline') + t.space(3)),
                  foregroundDecoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')))),
                  child: shown,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
