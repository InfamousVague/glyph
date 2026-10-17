/// A query drawn as a timeline (`show: gantt`): Mermaid's own gantt, as on the page. Ports `GanttView` of
/// `src/app/editor/QueryView.tsx`, with `.gantt` of `QueryView.module.css`.
///
/// The page hands the text lib/core/query/gantt.dart writes (`ganttOf`) to Mermaid (`drawDiagram`) and shows
/// Mermaid's picture in the card, quieted by `.gantt`'s rules: the axis in the third ink, its lines in the rule, no
/// band behind a section, the section's name in the second ink. So does this: the same text is handed to the same
/// Mermaid, on the app's own page in the platform's web view (lib/editor/diagrams: its store and its bridge), with
/// those rules ([DiagramTimeline]), and the picture is shown. So weeks tick where Mermaid ticks them and a bar's
/// name is where Mermaid puts it, inside the bar when it fits.
///
/// - Until the picture comes, and where it never does, the text itself (`<pre className={styles.lines}>`).
/// - A timeline that could not be drawn says "This timeline could not be drawn here." under the text, whatever
///   went wrong: no web view on this platform, or a text Mermaid would not read.
/// - Records with no start and no due day are counted under it, in the page's words.
/// - Mermaid draws a line down the bars at today. The page drew a timeline once each time the app was opened
///   (mermaid.ts `drawn`, a map in memory); pictures here are kept in a folder too, so the day is part of what a
///   timeline's picture is kept by ([DiagramTimeline.day]) and a card read tomorrow is drawn for tomorrow.
///
/// What differs:
/// - The picture is a bitmap made for the card's width at the device's ratio, where the page's is an SVG: a card
///   shown at another width asks again, and shows the one it has, fitted, until the new one comes.
/// - The page's card scrolls a drawing wider than itself sideways (`overflow-x: auto`); Mermaid sizes a gantt to
///   the window, and the picture is fitted to the card (`max-inline-size: 100%`), so there is nothing to scroll.
library;

import 'package:flutter/widgets.dart';

import '../../core/query/query.dart';
import '../diagrams/diagrams.dart';
import 'query_layout.dart';
import 'query_look.dart';

/// A font-family as a stylesheet writes it: the interface's faces, and the system's own after them.
String _sans(List<String> families) => <String>[for (final family in families) "'${family.replaceAll("'", '')}'", 'ui-sans-serif', 'system-ui', 'sans-serif'].join(', ');

/// What decides the picture of a timeline's `code` drawn `room` wide in a query's card: the card's type
/// (`.query { font-family: var(--glacier-font-sans); font-size: var(--glacier-font-size-sm) }`), no gutter
/// (`.gantt { padding-inline: 0 !important }`), the three inks `.gantt` gives the axis and the sections, and
/// `today`, the day Mermaid's line down the bars stands at.
DiagramAsk timelineAsk(BuildContext context, QueryLook look, String code, double room, String today) {
  final t = look.t;
  final sans = _sans(t.families('glacier-font-sans'));
  return DiagramAsk(
    code: code,
    dark: t.isDark,
    viewport: MediaQuery.sizeOf(context).width,
    room: room,
    gutter: 0,
    em: look.em,
    ui: sans,
    note: sans,
    coding: false,
    ink: look.ink,
    ratio: MediaQuery.devicePixelRatioOf(context),
    timeline: DiagramTimeline(tick: look.ink3, rule: look.rule, section: look.ink2, day: today),
  );
}

class QueryGantt extends StatefulWidget {
  const QueryGantt({super.key, required this.look, required this.result, required this.today});

  final QueryLook look;
  final QueryResult result;

  /// The card's own today (`2026-10-08`), which moves at midnight: the timeline is drawn again for the new day.
  final String today;

  @override
  State<QueryGantt> createState() => QueryGanttState();
}

class QueryGanttState extends State<QueryGantt> {
  /// The picture shown: of what is asked for, or of what was while the new one is made.
  DiagramPicture? _picture;

  /// The key of what is asked for now, whether its answer is here, and whether the answer was no picture.
  String? _asked;
  bool _answered = false;
  bool _failed = false;

  /// Whether the picture shown is of the timeline as it is now.
  bool get drawn => _picture != null && _answered && !_failed;

  /// Whether the timeline could not be drawn.
  bool get failed => _answered && _failed;

  void _want(DiagramAsk ask) {
    final key = ask.key;
    if (key == _asked) return;
    _asked = key;
    _answered = false;
    _failed = false;
    final store = diagramStore;
    final kept = store.held(ask);
    if (kept != null) {
      store.forget(this);
      _take(kept);
      return;
    }
    store.draw(ask, slot: this).then((made) {
      // Asked again since, or gone: the answer is somebody else's, or nobody's.
      if (!mounted || made == null || key != _asked) {
        if (made is DiagramPicture) made.dispose();
        return;
      }
      setState(() => _take(made));
    });
  }

  void _take(DiagramDrawing made) {
    _answered = true;
    switch (made) {
      case DiagramPicture():
        _picture?.dispose();
        _picture = made;
        _failed = false;
      case DiagramMistake():
        _picture?.dispose();
        _picture = null;
        _failed = true;
    }
  }

  @override
  void dispose() {
    diagramStore.forget(this);
    _picture?.dispose();
    _picture = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final result = widget.result;
    final code = result.gantt?.code ?? '';
    // .warning, .empty { margin: var(--glacier-space-1) 0; color: var(--app-ink-3) }
    Widget quiet(String name, String text) => Padding(
          padding: EdgeInsets.symmetric(vertical: look.space(1)),
          child: Part(name, child: PageWords(text, look.sans(look.em, color: look.ink3), line: look.line)),
        );
    if (code.isEmpty) return quiet('empty', 'Nothing here has a start or a due day to put on a timeline.');
    final unplaced = result.shown - (result.gantt?.placed ?? 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.maxWidth;
            if (room.isFinite && room > 0) _want(timelineAsk(context, look, code, room, widget.today));
            final picture = _picture;
            if (picture != null) {
              // Mermaid's own drawing: `<div className="cm-mermaid gantt" data-drawn role="img" aria-label="Timeline">`.
              // The full-screen button beside the picture, not inside it: the picture is read as Timeline alone.
              return Part(
                'gantt',
                child: WithFullScreen(
                  onFullScreen: () => openDiagramFullScreen(context, ask: timelineAsk(context, look, code, room, widget.today), shown: picture, label: 'Timeline'),
                  child: Semantics(container: true, image: true, label: 'Timeline', child: _Picture(picture: picture, room: room)),
                ),
              );
            }
            // .lines { padding: var(--glacier-space-2) var(--glacier-space-3); border-radius: var(--glacier-radius-md);
            //   background: var(--app-paper); font-family: var(--glacier-font-mono);
            //   font-size: var(--glacier-font-size-xs); line-height: 1.6; white-space: pre-wrap; color: var(--app-ink-2) }
            return Part(
              'lines',
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: look.space(3), vertical: look.space(2)),
                decoration: BoxDecoration(color: look.paper, borderRadius: BorderRadius.circular(look.t.radius('md'))),
                child: PageWords(code, look.mono(look.xs, color: look.ink2), line: pageLine(look.xs, 1.6)),
              ),
            );
          },
        ),
        if (failed) quiet('warning', 'This timeline could not be drawn here.'),
        if (unplaced > 0) quiet('warning', unplaced == 1 ? 'One has no start or due day, and is not on the timeline.' : '$unplaced have no start or due day, and are not on the timeline.'),
      ],
    );
  }
}

/// The timeline's picture in its block (`.cm-mermaid`, its padding included): one image, where the page had it. In
/// a card narrower than the one it was made for it is fitted, until the picture made for this card comes.
class _Picture extends StatelessWidget {
  const _Picture({required this.picture, required this.room});

  final DiagramPicture picture;
  final double room;

  @override
  Widget build(BuildContext context) {
    final block = picture.block, at = picture.at;
    final fit = room.isFinite && room < block.width ? room / block.width : 1.0;
    final across = room.isFinite ? room : block.width;
    return SizedBox(
      height: block.height * fit,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: (across - block.width * fit) / 2 + at.left * fit,
            top: at.top * fit,
            width: at.width * fit,
            height: at.height * fit,
            child: RawImage(key: const ValueKey<String>('query-timeline'), image: picture.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
        ],
      ),
    );
  }
}
