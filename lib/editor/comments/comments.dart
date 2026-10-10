/// Comments drawn in the note (../glyph docs/SHARED.md, S8; lib/comments/format.dart is the format). Ports
/// `src/app/editor/comments.ts`. Matt: "make sure comments were added to the app like we discussed previously".
///
/// - **The anchor**, `[^c1]`, is drawn as a small round in its author's colour where it sits; a tap on it opens the
///   thread's card ([CommentHooks.open]). A resolved thread's round is a ring. The caret on the anchor shows it as
///   written, so it can be edited or taken out by hand, as a drawn block steps aside for its lines
///   (view/drawn_block.dart).
/// - **The words round a selection**, `==the words==`, are a highlight already (lib/plugins/marks.dart: the
///   Highlight mark); an open thread's are washed in its author's colour instead of the highlighter's blue, and a
///   resolved thread's lose their wash.
/// - **The ```comments fence** is drawn as the list of threads, as a ```query fence is drawn as what it finds
///   (queries/queries.dart): a tap on a thread opens its card and brings its anchor into view, and the pencil at
///   its head puts the caret in the fence to show its lines. The caret in the fence shows the lines.
///
/// Where the editor is given no hooks (a note drawn small on a card, a shared page) none of this is installed, and
/// the anchor and the fence read as the text they are, a footnote's marker and a block of lines.
///
/// What differs:
/// - **The wash.** The page set the highlight's own colour, `--app-mark`, on a mark round it, and the highlight's
///   span inside read it. A run here has no custom properties to inherit, so the rule for what stands inside a
///   `.cm-commentWash` finds the ground the highlight painted in that token's colour and paints it in the author's
///   instead ([_theme]); a highlight that names a colour of its own (`==so==(green)`) keeps it, as it does there.
/// - **The round** is a box told where it stands on its line ([InlineBox]) where the page's was an inline block
///   raised 0.28em with a `::before` inside its padding: the same disc in the same place, and the same room for a
///   thumb round it.
/// - **The list's words** are set in the note's own face at the editor's 1.6, which the page's card inherited from
///   the editor it was drawn in ([_noteType]).
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../comments/format.dart';
import '../../comments/ui/card.dart';
import '../editor.dart';
import '../items/inline_box.dart';
import '../looks/look.dart';
import '../looks/note_face.dart';
import '../looks/sheets.dart';
import '../marks/run_paint.dart';
import '../view/blocks.dart';
import '../view/drawn_block.dart';
import '../view/editor_view.dart';
import '../view/line.dart' show EditorRunScope;

/// What the note's screen answers for the drawing (`CommentHooks`).
class CommentHooks {
  const CommentHooks({required this.open, required this.colour, required this.me, this.changed});

  /// Opens a thread's card.
  final void Function(String id) open;

  /// Whose colour a handle wears here: a workspace hue, `ink` for none (lib/comments/colours.dart).
  final String Function(String handle) colour;

  /// This person's handle, for "You".
  final String Function() me;

  /// The note's words changed: a card that is open reads its thread again.
  final VoidCallback? changed;
}

/// The colours changed, or anything else the drawing reads from outside the note: everything is drawn again.
final StateEffectType<Null> refreshComments = StateEffect.define<Null>();

/// A thread's round, where its anchor is.
class RoundWidget extends EditorWidget {
  const RoundWidget({required this.id, required this.hue, required this.resolved, required this.label, required this.hooks});

  final String id;

  /// `data-hue`.
  final String hue;
  final bool resolved;

  /// What a screen reader hears: "Comment by sam, 1 reply".
  final String label;
  final CommentHooks? Function() hooks;

  @override
  bool eq(RoundWidget other) => other.id == id && other.hue == hue && other.resolved == resolved && other.label == label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final em = EditorRunScope.maybeOf(context)?.look.fontSize ?? t.len('app-body');
    final space = hued(t, hue).color('app-space');
    // '.cm-commentRound': { display: 'inline-block', padding: '0.22em', marginInline: '0.02em',
    //   verticalAlign: '0.28em', lineHeight: '0', cursor: 'pointer' }
    // '.cm-commentRound::before': { inlineSize: '0.58em', blockSize: '0.58em', borderRadius: '50%',
    //   boxSizing: 'border-box', background: 'var(--app-space)' }
    // The disc stands on the box's baseline, 0.22em over its foot, and the box is raised 0.28em: its foot is 0.06em
    // over the line's baseline and its top 1.08em over it.
    return Semantics(
      button: true,
      label: label,
      onTap: () => hooks()?.open(id),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 0.02 * em),
        child: InlineBox(
          above: 1.08 * em,
          below: -0.06 * em,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The press is the round's: no caret lands on the anchor under it, which would show it as written.
            onTap: () => hooks()?.open(id),
            child: Padding(
              padding: EdgeInsets.all(0.22 * em),
              child: resolved
                  // '.cm-commentRound[data-resolved]::before': { background: 'none',
                  //   border: '0.1em solid var(--app-space)', opacity: '0.7' }
                  ? Opacity(
                      opacity: 0.7,
                      child: Container(width: 0.58 * em, height: 0.58 * em, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: space, width: 0.1 * em))),
                    )
                  : Container(width: 0.58 * em, height: 0.58 * em, decoration: BoxDecoration(shape: BoxShape.circle, color: space)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The fence drawn as the list of threads.
class ListWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  ListWidget({required this.threads, required this.at, required this.colours, required this.canEdit, required this.hooks}) : key = '$colours|${_keyOf(threads)}';

  final List<Thread> threads;

  /// Where the caret goes to show the fence's lines: its first line inside.
  final int at;

  /// Moves with every refresh, so a colour arriving redraws the list.
  final String colours;

  /// Whether the note can be changed here: only then is there a pencil.
  final bool canEdit;
  final CommentHooks? Function() hooks;

  /// What the list shows, as data: compared to decide whether to draw again.
  final String key;

  static String _keyOf(List<Thread> threads) => [
        for (final thread in threads)
          [
            thread.id,
            thread.head.by,
            thread.head.at,
            thread.head.words,
            for (final reply in thread.replies) ...[reply.by, reply.at, reply.words],
            thread.resolved?.by ?? '',
            thread.resolved?.at ?? '',
          ].join('\u0000'),
      ].join('\u0001');

  @override
  String get className => 'cm-commentList';

  @override
  bool eq(ListWidget other) => other.key == key && other.at == at && other.canEdit == canEdit;

  @override
  double get estimatedHeight => 60 + threads.length * 56;

  @override
  Widget build(BuildContext context) => DrawnComments(widget: this);

  /// A press in the drawing is the drawing's, as a query's is: no caret lands in the fence under it.
  @override
  bool takesPointer(_) => true;
}

/// This moment in ms, as the drawn list reads it for "2 hr ago"; a test holds it still.
int Function() commentsNow = () => DateTime.now().millisecondsSinceEpoch;

/// The words of the drawn list: the note's own face at the editor's leading, which the page's card inherited from
/// the editor it stood in (looks/note_face.dart).
CardType _noteType(Tokens t, Look? look) => CardType((px, {weight = 'regular', color}) => noteFace(t, look, px, weight: weight, color: color), normal: false);

/// The list in its card (`CommentCard.module.css` `.drawn`), and what a press in it does.
class DrawnComments extends StatelessWidget {
  const DrawnComments({super.key, required this.widget});

  final ListWidget widget;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.of(context);
    final t = context.tokens;
    final look = view is EditorView ? view.look : null;
    final type = _noteType(t, look);
    final given = widget.hooks();
    final people = CardPeople(colour: (handle) => given?.colour(handle) ?? 'ink', me: given?.me() ?? 'me');
    final note = look?.env.body ?? t.len('app-body');
    final bleed = layoutUnitFloor(look?.env.gutter ?? t.len('app-gutter'));
    final quiet = t.color('glacier-text-subtle');
    final edit = t.lenOf('2rem');
    return Padding(
      // '.cm-commentList': { paddingBlock: '0.4em', paddingInline: 'var(--cm-board-bleed, var(--app-gutter, 1rem))' }
      padding: EdgeInsets.symmetric(vertical: layoutUnitFloor(0.4 * note), horizontal: bleed),
      child: Semantics(
        container: true,
        label: 'Comments',
        child: DecoratedBox(
          // `.drawn { border: 1px solid var(--glacier-border-subtle); border-radius: var(--glacier-radius-lg) }`
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: t.color('glacier-border-subtle'))),
          child: Padding(
            // `padding: var(--glacier-space-3) var(--glacier-space-4)`, inside the border.
            padding: EdgeInsets.symmetric(vertical: t.space(3) + 1, horizontal: t.space(4) + 1),
            // `display: grid; gap: var(--glacier-space-2)`
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(2),
              children: [
                // `.drawnHead { display: flex; align-items: center; justify-content: space-between;
                //   gap: var(--glacier-space-3); font-size: sm; font-weight: semibold;
                //   color: var(--glacier-text-subtle) }`
                Row(
                  spacing: t.space(3),
                  children: [
                    Expanded(child: type.words(context, countWords(widget.threads) ?? '', t.fontSize('sm'), weight: 'semibold', color: quiet)),
                    if (widget.canEdit)
                      GlacierPressable(
                        semanticLabel: 'Show the comments as written',
                        // Focused first, so the caret lands in a view that has the focus and the drawing steps
                        // aside at once.
                        onPressed: () {
                          view.focus();
                          view.dispatch(TransactionSpec(selection: EditorSelection.single(widget.at), scrollIntoView: true));
                        },
                        // `.edit { inline-size: 2rem; block-size: 2rem; border-radius: 50%;
                        //   color: var(--glacier-text-subtle) }`
                        builder: (context, state) => SizedBox(width: edit, height: edit, child: Center(child: AppIcon(Lucide.pencil, size: 16, strokeWidth: 2.2, color: quiet))),
                      ),
                  ],
                ),
                CommentList(
                  threads: [for (final thread in widget.threads) cardThread(thread)],
                  people: people,
                  type: type,
                  now: commentsNow(),
                  onOpen: (id) {
                    // The card, and the anchor brought into view under it: the list is at the foot of the note, the
                    // words it is about are not.
                    final anchor = commentsOf(view.state.doc).anchors.where((each) => each.id == id).firstOrNull;
                    if (anchor != null) view.dispatch(TransactionSpec(effects: EditorViewLike.scrollIntoView(anchor.from, y: ScrollStrategy.center)));
                    widget.hooks()?.open(id);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The words a thread's anchor is round, delimiters aside; null for an anchor after a line's words, or none
/// (`quoteOf`).
String? quoteOf(EditorState state, NoteComments comments, String id) {
  for (final anchor in comments.anchors) {
    final wash = anchor.wash;
    if (anchor.id == id && wash != null) return state.sliceDoc(wash.from + 2, wash.to - 2);
  }
  return null;
}

/// What a round says: who started the thread, how many answered, and whether it is closed.
String roundLabel(Thread thread, CardPeople people) {
  final replies = thread.replies.length;
  return 'Comment by ${nameOf(thread.head.by, people)}${replies > 0 ? ', ${repliesWords(replies)}' : ''}${thread.resolved != null ? ', resolved' : ''}';
}

DecorationSet _decorate(EditorState state, NoteComments comments, CommentHooks? Function() hooks, String colours) {
  final given = hooks();
  final fence = comments.fence;
  if (given == null || fence == null) return Decoration.none;
  final decorations = <Range<Decoration>>[];
  final people = CardPeople(colour: given.colour, me: given.me());
  for (final anchor in comments.anchors) {
    final thread = threadOf(comments, anchor.id);
    if (thread == null) continue;
    final hue = given.colour(thread.head.by);
    final resolved = thread.resolved != null;
    final wash = anchor.wash;
    if (wash != null) {
      decorations.add(Decoration.mark(className: 'cm-commentWash', attributes: <String, String>{'data-hue': hue, if (resolved) 'data-resolved': ''}).range(wash.from, wash.to));
    }
    if (caretIn(state, anchor.from, anchor.to)) continue;
    decorations.add(Decoration.replace(widget: RoundWidget(id: anchor.id, hue: hue, resolved: resolved, label: roundLabel(thread, people), hooks: hooks)).range(anchor.from, anchor.to));
  }
  final editable = state.facet(EditorViewLike.editable) && !state.readOnly;
  if (comments.threads.isNotEmpty && !(editable && caretIn(state, fence.from, fence.to))) {
    final lines = state.doc.lines;
    final at = state.doc.line(fence.open + 1 < lines ? fence.open + 1 : lines).from;
    decorations.add(Decoration.replace(widget: ListWidget(threads: comments.threads, at: at, colours: colours, canEdit: editable, hooks: hooks), block: true).range(fence.from, fence.to));
  }
  return Decoration.set(decorations, true);
}

class _Drawn {
  const _Drawn(this.comments, this.stamp, this.decorations);
  final NoteComments comments;

  /// Moves with every refresh, so a colour arriving redraws the rounds.
  final int stamp;
  final DecorationSet decorations;
}

/// The washes whose rule is waiting to run, as `LookRule.when` met them (looks/look.dart runs every rule's `when`
/// before any rule's `box`).
final List<LookElement> _washes = <LookElement>[];

/// A highlight's ground and its spread, painted in another colour where they were the highlighter's own.
RunPainter? _rewashed(RunPainter? painter, Color from, Color to) {
  if (painter is! MarkPaint) return painter;
  var changed = false;
  final layers = <PaintLayer>[
    for (final layer in painter.layers)
      if (layer is BoxLayer && (layer.color == from || layer.spreadColor == from))
        () {
          changed = true;
          return BoxLayer(
            color: layer.color == from ? to : layer.color,
            radius: layer.radius,
            spread: layer.spread,
            spreadColor: layer.spreadColor == from ? to : layer.spreadColor,
            edge: layer.edge,
            onTop: layer.onTop,
            padStart: layer.padStart,
            padEnd: layer.padEnd,
            border: layer.border,
            borderColor: layer.borderColor,
            inset: layer.inset,
            insetColor: layer.insetColor,
            fill: layer.fill,
            fillColor: layer.fillColor,
            fillPart: layer.fillPart,
            fillPad: layer.fillPad,
            top: layer.top,
            bottom: layer.bottom,
          );
        }()
      else
        layer,
  ];
  return changed ? MarkPaint(layers) : painter;
}

final LookSheet _theme = LookSheet('editor/comments.ts', <LookRule>[
  // The highlight inside is drawn with `--app-mark` (plugins/marks `Highlight`): the author's colour for an open
  // thread.
  // '.cm-commentWash': { '--app-mark': 'color-mix(in oklch, var(--app-space) 30%, transparent)' }
  // '.cm-commentWash[data-resolved]': { '--app-mark': 'transparent' }
  // Over a mark's own `style` (marks/format_looks.dart, 90), since it is that style's `var(--app-mark)` this
  // answers.
  LookRule.under(
    'cm-commentWash',
    null,
    classes: 91,
    when: (element, context) {
      _washes.add(element);
      return true;
    },
    box: (p, e) {
      if (_washes.isEmpty) return;
      final wash = _washes.removeAt(0);
      final own = e.t.colorOf('var(--app-mark, var(--app-wash))', current: p.color);
      final worn = wash.attrs.containsKey('data-resolved')
          ? const Color(0x00000000)
          : hued(e.t, wash.attrs['data-hue'] ?? 'ink').colorOf('color-mix(in oklch, var(--app-space) 30%, transparent)', current: p.color);
      p.painter = _rewashed(p.painter, own, worn);
    },
  ),
]);

/// A line that could open the comments' fence: a fence's run at its start and the word after it. The fence itself
/// is read by lib/comments/format.dart; this is only whether a note can have one.
final LineFact<bool> _fenceish = LineFact<bool>((text) => (text.startsWith('```') || text.startsWith('~~~')) && text.toLowerCase().contains('comments') ? true : null);

final DocMemo<NoteComments> _comments = DocMemo<NoteComments>((doc) => _fenceish.nowhere(doc) ? NoteComments.none : readComments(doc.toString()));

/// A document's comments: `readComments(doc.toString())`, read once for each document, and not read at all for a
/// note with no line that could open their fence, which is every note that has none.
NoteComments commentsOf(Doc doc) => _comments.of(doc);

/// Comments drawn: the anchors as rounds, the selections washed, the fence as the list, with `hooks` saying what a
/// tap opens and whose colour is whose. `hooks` is read when it is used, so the screen's callbacks can change
/// without the editor being made again; [refreshComments] draws everything again when the colours do.
Extension noteComments(CommentHooks? Function() hooks) {
  final field = StateField.define<_Drawn>(
    create: (state) {
      final comments = commentsOf(state.doc);
      return _Drawn(comments, 0, _decorate(state, comments, hooks, '0'));
    },
    update: (value, tr) {
      final refreshed = tr.effects.any((effect) => effect.isOf(refreshComments));
      if (!refreshed && !tr.docChanged && tr.selection == null && !tr.reconfigured && !focusMoved(tr)) return value;
      final comments = tr.docChanged ? commentsOf(tr.state.doc) : value.comments;
      // A note with no comments draws none, whatever was typed and wherever the caret went.
      if (!refreshed && identical(comments, NoteComments.none) && identical(value.comments, NoteComments.none) && identical(value.decorations, Decoration.none)) return value;
      final stamp = value.stamp + (refreshed ? 1 : 0);
      return _Drawn(comments, stamp, _decorate(tr.state, comments, hooks, '$stamp'));
    },
    provide: (field) => EditorViewLike.decorations.from<_Drawn>(field, (value) => value.decorations),
  );
  return Extension.list(<Extension>[
    trackFocus,
    field,
    EditorViewLike.updateListener.of((update) {
      if (update.docChanged) hooks()?.changed?.call();
    }),
    baseTheme(_theme),
  ]);
}
