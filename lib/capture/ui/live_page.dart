/// The note being spoken, as its page: the same lines the note opens in, the note's older text above, and what is
/// being said written onto its end. A port of `src/app/capture/LivePage.tsx` (and `.livePage` of
/// CaptureScreen.module.css), with the half of `src/app/editor/wispArrivals.ts` that draws a word arriving.
///
/// Matt: "as the text is understood from the transcriptions it should render into the active note showing the old
/// notes above instead of always going to this new UI … As we understand and rewrite the text I speak I want the text
/// to appear and disappear with the wisp effect."
///
/// Set as it will read, not as it is written: the page is in the formatted view, so a heading is a heading and a
/// bullet a bullet as it is said, without the marks around them. The marks are all there in the note it saves.
///
/// The page is read-only while it is being written. Each change of what was heard is written into the editor's state
/// as the smallest edit that gets there (the shared start and end kept), marked `wisp` (`editor/marks/wisp_motion.dart`):
/// new words come in out of smoke, each letter through `art/wisp_text.dart`'s filter, and a guess being corrected
/// loses its old letters into it. The page follows the newest words down unless the person has scrolled up to read.
///
/// Words for a note's list are written into the list, where they will be saved (place.dart `placeTake`, the same the
/// recorder's Done writes with), so the page follows the words where they arrive rather than the bottom.
///
/// What differs:
/// - The web mounts its `Editor` read-only; here it is an `EditorView` over the whole document in an `EditorColumn`
///   (what `editor/markdown_view.dart` draws a note to be read with), inside a scroller of this page's own. The
///   editor has no placeholder of its own yet, so the one on an empty page ("Start talking.") is drawn here, on the
///   first line's place in `.cm-placeholder`'s ink.
/// - `wispArrivals.ts` is not ported in `lib/editor/marks` (that folder draws the leaving half, `wispDepartures`); the
///   arriving half is [liveArrivals] here: a mark over each word the state says is arriving, whose painter draws the
///   word bent and blurred until it sets: its letters, without the mark's own characters round them (`**bold`),
///   which the formatted view hides. A word with none of its own (a list's dash, a to-do's box) or with more round
///   it (a link's address) simply appears. When the editor has its own, this one goes.
/// - The ripples the voice sends through the newest lines (`editor/wispRipples.ts`) are not ported.
/// - The top line is a height ([LivePage.under]), not an element measured (`--wisp-under`).
/// - [LivePageState.document] is the page's Markdown as it reads now, for a test, where the web's test reads
///   `.cm-content`, and [LivePageState.lineRects] its lines' boxes, where the measuring script reads `.cm-line`.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/wisp_edge.dart';
import '../../editor/ai/wisp_arrivals.dart' show wispArrivals;
import '../../editor/ai/wisp_ripples.dart' show RippleSource, wispRipples;
import '../../art/wisp_kit.dart';
import '../../art/wisp_text.dart' show paintWispLetter, wispLetterBend, wispLetterFrequency, wispLetterSoft, wispSlotSeed;
import '../../editor/editor.dart';
import '../../editor/looks/look.dart';
import '../../editor/looks/sheets.dart' show baseTheme;
import '../../editor/marks/run_paint.dart';
import '../../editor/marks/wisp_motion.dart';
import '../../editor/syntax/language.dart' show InlineFormatSyntax;
import '../../editor/view/base.dart';
import '../../editor/view/column.dart';
import '../../editor/view/editor_view.dart';
import '../../editor/view/view_mode.dart';
import '../place.dart';

/// Within this far of the bottom, the page keeps following the newest words (`FOLLOW_PX`).
const double livePageFollowPx = 160;

// ---- words arriving ------------------------------------------------------------------------------------------------

/// The letters of a word the formatted view draws as they are written: letters, figures and the stops a sentence
/// carries. Round them a word may wear a mark's own characters (`**bold`, `words**`, `==lit==`), which that view
/// hides; anything else round them (a link's address, a bracket) and the word is not one to redraw.
final RegExp _plainCore = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’.,!?;:…-]*", unicode: true);
final RegExp _marksOnly = RegExp(r'^[*_~|=^%@+`]*$');

/// Where in [word] its drawn letters are, or null for a word that simply appears.
({int start, int end})? _drawnIn(String word) {
  final core = _plainCore.firstMatch(word);
  if (core == null) return null;
  if (!_marksOnly.hasMatch(word.substring(0, core.start)) || !_marksOnly.hasMatch(word.substring(core.end))) return null;
  return (start: core.start, end: core.end);
}

/// A word arriving, drawn in place of the paragraph's: unseen while it waits its turn, then out of the smoke, the
/// bend and the blur easing off as it sets (`art/WispText.module.css` `wispIn`).
class _Arriving extends LetterLayer {
  const _Arriving(super.text, this.id, this.at, this.dur);

  final int id;
  final double at;
  final double dur;

  @override
  bool get moves => true;

  @override
  void drawLetter(Canvas canvas, LetterGlyph glyph, Offset at, Size box, RunLook look) {
    final t = dur <= 0 ? 1.0 : ((wispNow() - this.at) / dur).clamp(0.0, 1.0);
    if (t <= 0) return;
    if (t >= 1) {
      glyph.painter.paint(canvas, Offset.zero);
      return;
    }
    final eased = Curves.easeOut.transform(t);
    final opacity = eased;
    final bend = wispLetterBend * (1 - eased), soft = wispLetterSoft * (1 - eased);
    final kit = WispKit.maybe;
    final seed = wispSlotSeed(id % 12);
    final table = kit?.tableNow(seed);
    if (kit == null || table == null || (bend < 0.05 && soft < 0.05)) {
      final paint = Paint()..color = Color.fromRGBO(0, 0, 0, opacity);
      if (soft >= 0.05) paint.imageFilter = ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.decal);
      canvas.saveLayer(Rect.fromLTWH(-24, -24, box.width + 48, box.height + 48), paint);
      glyph.painter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      paintWispLetter(canvas, kit: kit, table: table, glyph: glyph.image(), glyphRect: glyph.imageRect, box: box, smoke: WispSmoke.flat(seed: seed, frequency: wispLetterFrequency, bend: bend, blur: soft), opacity: opacity);
    }
  }
}

final LookSheet _arrivalsLook = LookSheet('editor/wispArrivals.ts', <LookRule>[
  LookRule(
    'cm-wispIn',
    null,
    classes: 2,
    box: (p, e) {
      final attrs = p.element?.attrs ?? const <String, String>{};
      p.painter = MarkPaint.add(
        p.painter,
        _Arriving(attrs['data-text'] ?? '', int.tryParse(attrs['data-id'] ?? '') ?? 0, double.tryParse(attrs['data-at'] ?? '') ?? 0, double.tryParse(attrs['data-dur'] ?? '') ?? 0),
      );
    },
  ),
]);

DecorationSet _arriving(EditorState state) {
  final arriving = <Moving>[
    for (final m in moving(state))
      if (m.gone.isEmpty && m.to > m.from) m,
  ]..sort((a, b) => a.from != b.from ? a.from - b.from : a.id - b.id);
  final marks = <Range<Decoration>>[];
  var last = -1;
  for (final m in arriving) {
    if (m.from < last) continue;
    final word = state.doc.sliceString(m.from, m.to);
    final drawn = _drawnIn(word);
    if (drawn == null) continue;
    final text = word.substring(drawn.start, drawn.end);
    marks.add(Decoration.mark(className: 'cm-wispIn', attributes: <String, String>{'data-text': text, 'data-id': '${m.id}', 'data-at': '${m.at}', 'data-dur': '${m.dur}'}).range(m.from + drawn.start, m.from + drawn.end));
    last = m.to;
  }
  return marks.isEmpty ? Decoration.none : Decoration.set(marks);
}

/// **Not what the recorder's page uses any more**: [LivePage] takes lib/editor/ai's `wispArrivals()` and
/// `wispRipples`, as a note's editor does; this is the arriving half as it was drawn before those were ported.
///
/// What the recorder writes arrives out of smoke and what it takes back leaves into it: the field that decides
/// (`wispState`), the ghosts of what left (`wispDepartures`), and the words arriving, drawn. [still] is reduced
/// motion, under which nothing is set in motion.
Extension liveArrivals({bool still = false}) => Extension.list(<Extension>[
  wispDepartures(typing_: false),
  wispStill.of(still),
  Prec.highest(EditorViewLike.decorations.compute(<Object>[wispState], _arriving)),
  baseTheme(_arrivalsLook),
  markMotion,
]);

// ---- the page ------------------------------------------------------------------------------------------------------

class LivePage extends StatefulWidget {
  const LivePage({
    super.key,
    required this.base,
    required this.markdown,
    required this.placeholder,
    this.under = 0,
    this.placing = end,
    this.from,
    this.arrivals = true,
    this.formats = const <InlineFormatSyntax>[],
    this.ripples,
  });

  /// The continued note's text before this capture, or '' for a new note.
  final String base;

  /// This capture's markdown so far, the phrase still being guessed included.
  final String markdown;

  /// Shown on an empty page.
  final String placeholder;

  /// The height of the recorder's top line, which the page runs under: the wisp sits below it, and the page pads by
  /// it.
  final double under;

  /// Where the words go in the note: its end (the default), or its lists.
  final Placing placing;

  /// The document to start from, when the page was just switched to this note: the words then arrive through the
  /// wisp.
  final String? from;

  /// Whether what is heard arrives through the wisp (the `wisp` preference).
  final bool arrivals;

  /// The switched-on plugins' inline formattings, drawn as the note draws them.
  final Iterable<InlineFormatSyntax> formats;

  /// The voice's level as it comes, which the arriving words ripple with (lib/editor/ai/wisp_ripples.dart); null
  /// and they arrive without.
  final RippleSource? ripples;

  @override
  State<LivePage> createState() => LivePageState();
}

class LivePageState extends State<LivePage> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _column = GlobalKey();
  EditorView? _view;

  /// The placeholder, drawn as a line of the note so it stands where the first word will.
  EditorView? _hint;
  VoidCallback? _release;
  Timer? _settling;

  /// Where the page last followed the words to, for telling whether the person has scrolled away to read.
  double? _followed;
  bool _opened = false;

  /// The page's Markdown as it reads now.
  String get document => _view?.state.doc.toString() ?? '';

  /// Each line's box on the screen, top to bottom, for a test held to the page's own lines.
  List<Rect> get lineRects => [
        for (final line in _view?.lines ?? const <RenderBox>[])
          if (line.attached && line.hasSize) line.localToGlobal(Offset.zero) & line.size,
      ];

  /// The words still arriving out of the smoke, and the ghosts of what left still fading: for a test, and for a
  /// caller wondering whether to wait.
  List<Moving> get inMotion => _view == null ? const <Moving>[] : moving(_view!.state);

  String get _next => placeTake(widget.base, widget.markdown, widget.placing).body;

  @override
  void initState() {
    super.initState();
    // While the phone listens, the smoke holds still: each drift step redraws the page, next to the microphone and
    // the voice model.
    _release = WispDrift.instance.hold();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_view != null) return;
    final still = MediaQuery.disableAnimationsOf(context) || !widget.arrivals;
    // The document the editor starts with; everything after is written in as edits.
    _view = EditorView(
      wholeDocument: true,
      state: EditorState.create(
        doc: widget.from ?? _next,
        extensions: noteExtensions(formats: widget.formats, display: NoteView.formatted, readOnly: true, more: <Extension>[
          // What the recorder writes arrives as what the AI writes does (lib/editor/ai/wisp_arrivals.dart), and the
          // voice sends its ripples through the words while they do.
          wispArrivals(),
          wispStill.of(still),
          if (widget.ripples case final ripples?) wispRipples(ripples),
        ]),
      ),
    );
    _hint = _hintFor(widget.placeholder);
    // Switched to this note with words already said: they arrive now.
    if (widget.from != null) WidgetsBinding.instance.addPostFrameCallback((_) => _write());
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void didUpdateWidget(LivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placeholder != widget.placeholder) {
      _hint?.destroy();
      _hint = _hintFor(widget.placeholder);
    }
    if (oldWidget.base != widget.base || oldWidget.markdown != widget.markdown || oldWidget.placing != widget.placing) _write();
  }

  EditorView _hintFor(String words) => EditorView(wholeDocument: true, state: EditorState.create(doc: words, extensions: noteExtensions(display: NoteView.formatted, readOnly: true)));

  /// What was heard, written into the page as the smallest edit that gets there.
  void _write() {
    final view = _view;
    if (view == null || !mounted) return;
    final next = _next;
    final now = view.state.doc.toString();
    if (now == next) return;
    final ends = commonEnds(now, next);
    final removed = now.length - ends.prefix - ends.suffix;
    final inside = widget.placing is! PlacingEnd;
    // At the end, the bottom is where the words are; in a list, where they went in is, and the page follows that
    // while the person has stayed within reach of where it last followed to.
    var following = false;
    if (_scroll.hasClients) {
      final position = _scroll.position;
      following = inside ? _followed == null || (position.pixels - _followed!).abs() < livePageFollowPx : position.maxScrollExtent - position.pixels < livePageFollowPx;
    }
    final at = next.length - ends.suffix;
    view.dispatch(TransactionSpec(
      changes: ChangeSpec(from: ends.prefix, to: now.length - ends.suffix, insert: next.substring(ends.prefix, at)),
      annotations: wisp.of(removed > 0 ? WispKind.rewrite : WispKind.heard),
    ));
    _settleLater();
    if (!following) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (inside) {
        _centre(math.min(at, next.length), animate: true);
        _followed = _scroll.position.pixels;
      } else {
        unawaited(_scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 240), curve: Curves.easeOut));
      }
    });
  }

  /// Opened on a long note: start at its end, where the words will go, or at the list they will go into.
  void _open() {
    if (_opened || !mounted || !_scroll.hasClients) return;
    _opened = true;
    if (widget.placing is PlacingEnd) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      return;
    }
    // Where a word said now would go in: the first place the note with one more item differs from it.
    final prefix = commonEnds(widget.base, placeTake(widget.base, 'Here.', widget.placing).body).prefix;
    _centre(math.min(prefix, _view!.state.doc.length), animate: false);
    _followed = _scroll.position.pixels;
  }

  /// `EditorView.scrollIntoView(pos, { y: 'center' })`.
  void _centre(int pos, {required bool animate}) {
    final rect = _view?.coordsAtPos(pos);
    final box = context.findRenderObject();
    if (rect == null || box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(rect.center);
    final position = _scroll.position;
    final to = (position.pixels + local.dy - box.size.height / 2).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (animate) {
      unawaited(_scroll.animateTo(to, duration: const Duration(milliseconds: 240), curve: Curves.easeOut));
    } else {
      _scroll.jumpTo(to);
    }
  }

  /// What has set is let go of, so the paragraph draws it again: the drawing telling the field it has settled.
  void _settleLater() {
    final view = _view;
    if (view == null || _settling != null) return;
    final pieces = moving(view.state).where((m) => m.gone.isEmpty).toList();
    if (pieces.isEmpty) return;
    final now = wispNow();
    final soonest = pieces.map((m) => m.at + m.dur - now).reduce(math.min);
    _settling = Timer(Duration(milliseconds: math.max(40, soonest.ceil())), () {
      _settling = null;
      if (!mounted) return;
      final at = wispNow();
      final done = <int>[
        for (final m in moving(view.state))
          if (m.gone.isEmpty && m.at + m.dur <= at) m.id,
      ];
      if (done.isNotEmpty) view.dispatch(TransactionSpec(effects: settle.of(done)));
      _settleLater();
    });
  }

  @override
  void dispose() {
    _settling?.cancel();
    _release?.call();
    _view?.destroy();
    _hint?.destroy();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = _view!;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final env = LookEnv.page(t, devicePixelRatio: ratio, tabSize: view.state.tabSize);
    final empty = view.state.doc.length == 0;
    // `.livePage { flex: 1; overflow-y: auto; overscroll-behavior: contain; padding-block-start: var(--wisp-under) }`
    final scroller = SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.only(top: widget.under),
      child: Stack(
        children: [
          IgnorePointer(child: ExcludeSemantics(child: EditorColumn(key: _column, view: view, env: env))),
          if (empty && _hint != null)
            // `.cm-placeholder { color: var(--glacier-text-subtle) }`: the words in the note's own face, on the first
            // line's place, in the placeholder's ink.
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => LinearGradient(colors: [t.color('glacier-text-subtle'), t.color('glacier-text-subtle')]).createShader(bounds),
                    child: Align(alignment: Alignment.topCenter, child: EditorColumn(view: _hint!, env: env)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // The older text goes to smoke under the recorder's top line, like any page (art/wisp_edge.dart).
    return WispEdge(under: widget.under, child: scroller);
  }
}
