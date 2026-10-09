/// The panel a tap on an answer opens (docs/DESIGN.md §145, 7): where it came from, in words, and what can be done
/// with it. A port of `src/app/editor/fillPanel.ts`.
///
/// A filled answer says whose it is and from where (memory, this note, or the web and which source), when it was
/// asked and what, and the one sentence the app says about every model everywhere (ai/backend.dart `modelLimits`),
/// with Keep as mine, Ask again and Put the question back. A worked-out answer shows its working and Write it in. A
/// refusal says why in the app's words, with Ask the model anyway where the model can run, since a word list can be
/// wrong.
///
/// Placed and closed as a mark's note is (editor/view/text_panel.dart): under the words, inside the editor's width,
/// gone on a tap elsewhere, a change or a scroll. Its tap on a filled answer runs before the mark notes'
/// (`Prec.high`), which leave a fill's bracket to this panel (editor/marks/mark_notes.dart). On a page that is only
/// read, the words and no actions.
///
/// What differs:
/// - The page appends a `<div>` to the editor's element. Here the panel a view shows is kept beside the view
///   ([fillPanelOf]) and [EditorFillPanel], which the note's screen stacks over the editor (a `Stack` with the
///   editor, covering it, as `EditorTextPanels` is), draws it, placed from `coordsAtPos` each time it builds. The
///   panel's rules are drawn by that widget, each cited where it is drawn.
/// - `EditorView.domEventHandlers({ scroll })` closed the panel when the note scrolled; the view has no scroll
///   events of its own, so the screen that owns the scroll view calls [closeFillPanel] for that.
/// - A press on a button is a tap: nothing here takes the keyboard's focus from the editor, so the page's
///   `mousedown` with its default taken away has no counterpart.
/// - "28 September 2026" was `Intl.DateTimeFormat(undefined, …)`, the person's own form. The day is written through
///   the facet [fillPanelDay], whose default is that form in English in the phone's own order (core/locale_dates.dart:
///   "September 28, 2026" on an American phone), and day, month, year until the phone has said.
/// - A panel's content is a [PanelContent] a test can read ([fillPanelOf]), where the page's test read the `<p>`s
///   and the `<button>`s.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../ai/backend.dart' show modelLimits, modelName;
import '../../ai/fills/lane.dart';
import '../../ai/fills/queue.dart';
import '../../ai/fills/web.dart' show LookupKind, isMacApp, noSource, sourceName;
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/blanks.dart';
import '../../core/fill_facts.dart';
import '../../core/fill_live.dart';
import '../../core/locale_dates.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../view/editor_view.dart';
import 'blanks.dart';

/// The device, as the panel's words name it: the phone, or this Mac in the Mac app.
String _device() => isMacApp ? 'this Mac' : 'the phone';
String _deviceCapital() => isMacApp ? 'This Mac' : 'The phone';

/// The panel's class on the page, and its name here.
const String fillPanelClass = 'cm-fillPanel';

/// One thing a panel offers (`Action`).
class PanelAction {
  const PanelAction({required this.icon, required this.label, required this.run});

  final LucideIcon icon;
  final String label;
  final VoidCallback run;
}

/// What a panel says (`PanelContent`).
class PanelContent {
  const PanelContent({required this.icon, required this.title, required this.lines, required this.actions});

  final LucideIcon icon;
  final String title;
  final List<String> lines;
  final List<PanelAction> actions;

  /// The panel's words, its title first: what the page's `<p>`s read.
  List<String> get words => <String>[title, ...lines];
}

const Map<FactIcon, LucideIcon> _factIcons = <FactIcon, LucideIcon>{FactIcon.calculator: Lucide.calculator, FactIcon.calendar: Lucide.calendarDays, FactIcon.globe: Lucide.globe};

const List<String> _months = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String _dayMonthYear(DateTime day) => toldDate(day, DateForm.yMMMMd) ?? '${day.day} ${_months[day.month - 1]} ${day.year}';

/// How a day is written in the panel: "28 September 2026" unless the screen says its own form.
final Facet<String Function(DateTime day), String Function(DateTime day)> fillPanelDay =
    Facet.define<String Function(DateTime day), String Function(DateTime day)>(combine: (values) => values.isEmpty ? _dayMonthYear : values.first);

/// "28 September 2026" in the person's own form, from a fill's ISO date.
String _askedOn(EditorState state, String iso) {
  final parts = iso.split('-').map((part) => int.tryParse(part)).toList();
  final y = parts.isNotEmpty ? parts[0] : null, m = parts.length > 1 ? parts[1] : null, d = parts.length > 2 ? parts[2] : null;
  return state.facet(fillPanelDay)(DateTime(y ?? 1970, m ?? 1, d ?? 1, 12));
}

final RegExp _priceWords = RegExp(r'\b(price|prices|cost|costs|cheap|cheapest|fare|fares|pay|budget|deal)\b', caseSensitive: false);
final RegExp _travelWords = RegExp(r'\b(flight|flights|fly|train|trains|bus|hotel|hotels|fare|fares|ticket|tickets|trip)\b', caseSensitive: false);

/// A caveat under a model's answer: the refusal's sentence when the app would have refused it, else advice on
/// prices.
String? _caveat(Lane? lane, String sentence) {
  if (lane is CannotLane) return lane.cannot.words;
  if (lane is LiveLane) return lane.live.words;
  if (_priceWords.hasMatch(sentence)) {
    return _travelWords.hasMatch(sentence) ? 'General advice, not today’s fares.' : 'General advice, not today’s prices.';
  }
  return null;
}

/// The note with a filled answer written back as its blank, and that blank: what it was asked as.
({String text, Blank blank}) _asBlank(String text, ({int from, int to}) span, String question) {
  final written = '{?$question}';
  return (text: '${text.substring(0, span.from)}$written${text.substring(span.to)}', blank: Blank(from: span.from, to: span.from + written.length, question: question));
}

typedef _Fill = ({int from, int to, String words, Filled filled, String bracket});

/// The items of one fill round the tapped one: adjacent lines whose brackets differ only in their place.
List<_Fill> _itemsOfFill(String text, _Fill fill) {
  final place = fill.filled.place;
  if (place == null) return <_Fill>[fill];
  bool same(Filled other) =>
      other.model == fill.filled.model && other.date == fill.filled.date && other.question == fill.filled.question && other.place?.of == place.of && other.source.kind == fill.filled.source.kind;
  final fills = fillsIn(text);
  final at = fills.indexWhere((f) => f.from == fill.from);
  var first = at;
  while (first > 0 && same(fills[first - 1].filled) && fills[first - 1].filled.place!.n == fills[first].filled.place!.n - 1) {
    first -= 1;
  }
  var last = at;
  while (last + 1 < fills.length && same(fills[last + 1].filled) && fills[last + 1].filled.place!.n == fills[last].filled.place!.n + 1) {
    last += 1;
  }
  return fills.sublist(first, last + 1);
}

/// The panel for a filled answer.
PanelContent _fillContent(EditorViewLike view, _Fill fill) {
  final text = view.state.doc.toString();
  final hooks = view.state.facet(blankHooks);
  final editable = view.state.facet(EditorViewLike.editable) && !view.state.readOnly;
  final filled = fill.filled;
  final question = filled.question ?? '';
  final group = _itemsOfFill(text, fill);
  final span = (from: group.first.from, to: group.last.to);
  final asked = _asBlank(text, span, question);
  final lane = hooks != null ? laneOf(asked.blank, asked.text, LaneOptions(clock: FactClock(now: hooks.now?.call() ?? DateTime.now()), learntUntil: hooks.learntUntil(), lookups: hooks.lookups())) : null;
  final lineStart = asked.blank.from <= 0 ? 0 : asked.text.lastIndexOf('\n', asked.blank.from - 1) + 1;
  final lineEnd = asked.text.indexOf('\n', asked.blank.to);
  final sentence = asked.text.substring(lineStart, lineEnd == -1 ? asked.text.length : lineEnd);
  final on = _askedOn(view.state, filled.date);
  final askedLine = question.isNotEmpty ? 'Asked on $on: $question' : 'Asked on $on.';
  final lines = <String>[askedLine];
  var icon = Lucide.lightbulb;
  var title = '${filled.model}, from memory';
  if (filled.source.kind == FillSourceKind.note) {
    icon = Lucide.fileText;
    title = '${filled.model}, from this note';
    lines.add('Its words are in one line of this note, beside what was asked. The model chose them, so check it reads right.');
  } else if (filled.source.kind == FillSourceKind.web) {
    icon = Lucide.wifi;
    title = '${filled.model}, from ${filled.source.name}';
    lines.add(
      filled.model == 'Ghost.md'
          ? '${_deviceCapital()} asked ${filled.source.name}, and the app wrote this from what came back.'
          : '${_deviceCapital()} asked ${filled.source.name}, and the model wrote this from what came back. It can still be wrong.',
    );
  } else {
    lines.add(modelLimits);
    final warning = _caveat(lane, sentence);
    if (warning != null) lines.add(warning);
  }
  final actions = <PanelAction>[];
  if (editable) {
    actions.add(
      PanelAction(
        icon: Lucide.check,
        label: 'Keep as mine',
        run: () => view.dispatch(TransactionSpec(changes: ChangeSpec(from: fill.from, to: fill.to, insert: fill.words), userEvent: 'input.fill')),
      ),
    );
    if (hooks != null && hooks.canFill()) {
      actions.add(
        PanelAction(
          icon: Lucide.rotateCw,
          label: 'Ask again',
          run: () {
            final mark = text.substring(span.from, span.to);
            final words = group.map((g) => g.words).join(', ');
            final key = 'again\u0000${span.from}';
            view.dispatch(TransactionSpec(effects: trackBlanks.of(<TrackedBlank>[(key: key, from: span.from, to: span.to)])));
            hooks.fill(<FillTarget>[FillTarget(key: key, question: question, order: 0, again: FillAgain(mark: mark, words: words))]);
          },
        ),
      );
    }
    actions.add(
      PanelAction(
        icon: Lucide.undo2,
        label: 'Put the question back',
        run: () => view.dispatch(TransactionSpec(changes: ChangeSpec(from: span.from, to: span.to, insert: '{?$question}'), userEvent: 'input.fill')),
      ),
    );
  }
  return PanelContent(icon: icon, title: title, lines: lines, actions: actions);
}

/// The panel for a blank: worked out, refused, paused, or what came of a press.
PanelContent? _blankContent(EditorViewLike view, Blank blank) {
  final state = view.state;
  final hooks = state.facet(blankHooks);
  final text = state.doc.toString();
  final editable = state.facet(EditorViewLike.editable) && !state.readOnly;
  final lane = laneOf(blank, text, LaneOptions(clock: FactClock(now: hooks?.now?.call() ?? DateTime.now(), zone: hooks?.zone?.call()), learntUntil: hooks?.learntUntil() ?? 2024, lookups: hooks?.lookups() ?? Lookups.off));
  final all = editorBlanks(state, false);
  final key = keyOf(all, blank);
  final noteId = hooks?.noteId();
  final status = noteId != null ? fillStatus(noteId, key) : null;
  final outcome = noteId != null ? fillOutcome(noteId, key) : null;
  final order = int.parse(key.split('\u0000')[1]);
  final anyway = editable && hooks != null && hooks.canFill()
      ? PanelAction(
          icon: Lucide.messageCircleQuestionMark,
          label: 'Ask the model anyway',
          run: () {
            view.dispatch(TransactionSpec(effects: trackBlanks.of(<TrackedBlank>[(key: key, from: blank.from, to: blank.to)])));
            hooks.fill(<FillTarget>[FillTarget(key: key, question: blank.question, order: order, anyway: true)]);
          },
        )
      : null;
  if (status?.phase == FillPhase.paused) {
    final source = lane is LiveLane ? sourceName(lane.plan) : null;
    return status!.why == PausedWhy.offline
        ? PanelContent(
            icon: Lucide.wifiOff,
            title: 'Waiting for a connection',
            lines: <String>['${_deviceCapital()} will ask ${source ?? 'the source'} once it is online, and the answer is written from what comes back.'],
            actions: const <PanelAction>[],
          )
        : PanelContent(
            icon: Lucide.wifiOff,
            title: 'Paused',
            lines: <String>['Local only is on, so ${_device()} doesn’t look this up. It goes on when Local only is off.'],
            actions: const <PanelAction>[],
          );
  }
  if (outcome != null) {
    final name = modelName(outcome.model);
    final says = switch (outcome.why) {
      FillWhy.unknown => '$name said it did not know.',
      FillWhy.none => 'No answer came. Try the question in other words.',
      FillWhy.didntFit => 'The answer did not fit the blank, so nothing was written.',
      FillWhy.nothing => outcome.words ?? 'Nothing came back for this.',
    };
    return PanelContent(
      icon: outcome.why == FillWhy.nothing ? Lucide.wifiOff : Lucide.messageCircleQuestionMark,
      title: says,
      lines: const <String>[],
      actions: outcome.why == FillWhy.nothing && anyway != null ? <PanelAction>[anyway] : const <PanelAction>[],
    );
  }
  if (lane is WorkedLane) {
    final worked = lane.worked;
    return PanelContent(
      icon: _factIcons[worked.icon]!,
      title: 'Worked out by the app',
      lines: <String>[worked.working, 'The model was not asked.'],
      actions: editable
          ? <PanelAction>[
              PanelAction(
                icon: Lucide.textCursorInput,
                label: 'Write it in',
                run: () => view.dispatch(TransactionSpec(changes: ChangeSpec(from: blank.from, to: blank.to, insert: worked.answer), userEvent: 'input.fill')),
              ),
            ]
          : const <PanelAction>[],
    );
  }
  if (lane is CannotLane) {
    return PanelContent(icon: _factIcons[lane.cannot.icon]!, title: 'The app can’t work this out', lines: <String>[lane.cannot.words], actions: anyway != null ? <PanelAction>[anyway] : const <PanelAction>[]);
  }
  if (lane is LiveLane) {
    final source = sourceName(lane.plan);
    final why = switch (lane.can) {
      LiveCan.none => lane.plan.kind == LookupKind.none ? lane.plan.why! : noSource,
      LiveCan.localOnly => 'Local only is on, so this waits. ${_deviceCapital()} would ask $source for it.',
      LiveCan.off => 'Look up blanks online is off in Settings, so ${_device()} doesn’t ask the web.',
      LiveCan.look => 'On Fill, ${_device()} asks $source, and the answer is written from what comes back. Only the question goes.',
    };
    return PanelContent(
      icon: lane.can == LiveCan.look ? Lucide.wifi : Lucide.wifiOff,
      title: lane.can == LiveCan.look ? 'Looked up online' : 'The model can’t know this',
      lines: <String>[liveWords(lane.live.kind), why],
      actions: lane.can == LiveCan.look || anyway == null ? const <PanelAction>[] : <PanelAction>[anyway],
    );
  }
  return null;
}

/// A panel as a view shows it: what it says, and the position it hangs under.
class ShownFillPanel {
  const ShownFillPanel({required this.at, required this.content});

  final int at;
  final PanelContent content;
}

final Expando<ValueNotifier<ShownFillPanel?>> _panels = Expando<ValueNotifier<ShownFillPanel?>>('fillPanel');

/// The fill panel `view` is showing, or null.
ValueNotifier<ShownFillPanel?> fillPanelOf(EditorViewLike view) => _panels[view] ??= ValueNotifier<ShownFillPanel?>(null);

/// Shows `content` under the words at `at`, in place of any panel showing.
void _show(EditorViewLike view, int at, PanelContent content) => fillPanelOf(view).value = ShownFillPanel(at: at, content: content);

/// Takes the panel away, if one is showing: the screen calls this when the note scrolls.
void closeFillPanel(EditorViewLike view) {
  final shown = fillPanelOf(view);
  if (shown.value != null) shown.value = null;
}

/// A press on one of the panel's buttons (`button.addEventListener('click', …)`): the panel goes, then the action
/// runs.
void pressPanelAction(EditorViewLike view, PanelAction action) {
  closeFillPanel(view);
  action.run();
}

/// The panel for whatever sits at `at`: a blank's words after it, or a filled answer.
bool openFillPanel(EditorViewLike view, int at) {
  final text = view.state.doc.toString();
  final fill = fillsIn(text).where((f) => at >= f.from && at <= f.to).firstOrNull;
  if (fill != null) {
    _show(view, fill.from + 2, _fillContent(view, fill));
    return true;
  }
  final blank = blankMatches(text).where((b) => at >= b.from && at <= b.to).firstOrNull;
  if (blank == null) return false;
  final content = _blankContent(view, blank);
  if (content == null) return false;
  _show(view, blank.from, content);
  return true;
}

class _Tapped extends PluginValue {
  @override
  void update(ViewUpdate update) {
    if (update.docChanged) closeFillPanel(update.view);
  }
}

final ViewPlugin<_Tapped> _tapped = ViewPlugin.fromClass<_Tapped>(
  (_) => _Tapped(),
  eventHandlers: EditorEventHandlers(
    pointerDown: (event, view) {
      // A press on the panel itself never reaches the editor: the panel lies over it.
      final pos = view.posAtCoords(event.position);
      final text = view.state.doc.toString();
      final fill = pos == null ? null : fillsIn(text).where((f) => pos >= f.from + 2 && pos <= f.to).firstOrNull;
      if (fill == null) {
        closeFillPanel(view);
        return false;
      }
      // The caret still goes where the finger went, so the words can be edited straight after, as a mark's note does.
      _show(view, fill.from + 2, _fillContent(view, fill));
      return false;
    },
  ),
);

/// Draws a view's fill panel over it. Put in a `Stack` with the editor, covering it (`Positioned.fill`).
class EditorFillPanel extends StatelessWidget {
  const EditorFillPanel({super.key, required this.view});

  final EditorView view;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<ShownFillPanel?>(
      valueListenable: fillPanelOf(view),
      builder: (context, shown, _) {
        final coords = shown == null ? null : view.coordsAtPos(shown.at);
        if (shown == null) return const SizedBox.shrink();
        final content = shown.content;
        final window = MediaQuery.sizeOf(context);
        final look = view.look;
        // [`.${PANEL}`]: { position: 'absolute', zIndex: '30', maxInlineSize: 'min(22rem, 86vw)',
        //   padding: '0.55em 0.75em 0.6em', borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
        //   background: 'var(--app-paper-2, var(--glacier-surface))',
        //   border: '1px solid var(--app-rule, var(--glacier-border-subtle))',
        //   boxShadow: '0 6px 20px rgb(0 0 0 / 0.18)', font: 'inherit', fontSize: '0.84em', lineHeight: '1.4',
        //   color: 'var(--app-ink-2, currentColor)' }
        final em = (look?.env.body ?? t.len('app-body')) * 0.84;
        final base = look?.line(LookElement(null)).base.style ?? t.textAt(em);
        final face = Tokens.resized(base, em).copyWith(height: 1.4, leadingDistribution: TextLeadingDistribution.even, color: t.color('app-ink-2'), decoration: TextDecoration.none);
        // '.cm-fillPanelHead': { display: 'flex', alignItems: 'center', gap: '0.4em',
        //   color: 'var(--app-ink, currentColor)', fontWeight: '600' }
        final head = face.copyWith(
          color: t.color('app-ink'),
          fontWeight: FontWeight.w600,
          fontVariations: <FontVariation>[
            for (final variation in face.fontVariations ?? const <FontVariation>[])
              if (variation.axis != 'wght') variation,
            const FontVariation('wght', 600),
          ],
        );
        final rem = t.lenOf('22rem'), most = rem < window.width * 0.86 ? rem : window.width * 0.86;
        // '.cm-fillPanelIcon': { display: 'inline-flex', inlineSize: '1em', blockSize: '1em', flex: 'none' }
        // '.cm-fillPanelIcon svg': { inlineSize: '1em', blockSize: '1em' }
        Widget glyph(LucideIcon icon, Color color) => AppIcon(icon, size: em, strokeWidth: 2.2, color: color);
        final rows = <Widget>[
          // [`.${PANEL} p`]: { margin: '0 0 0.35em' }
          Padding(
            padding: EdgeInsets.only(bottom: 0.35 * em),
            child: Row(
              key: const ValueKey<String>('cm-fillPanelHead'),
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                glyph(content.icon, t.color('app-ink')),
                SizedBox(width: 0.4 * em),
                Flexible(child: Text(content.title, style: head, textScaler: TextScaler.noScaling)),
              ],
            ),
          ),
          for (final (index, line) in content.lines.indexed)
            Padding(
              // The last paragraph's margin and the actions' own lie over each other, as margins do.
              padding: EdgeInsets.only(bottom: (index == content.lines.length - 1 && content.actions.isNotEmpty ? 0 : 0.35) * em),
              child: Text(line, key: ValueKey<String>('cm-fillPanelLine-$index'), style: face, textScaler: TextScaler.noScaling),
            ),
          if (content.actions.isNotEmpty)
            // '.cm-fillPanelActions': { display: 'flex', flexWrap: 'wrap', gap: '0.2em 0.9em',
            //   marginBlockStart: '0.45em' }
            Padding(
              padding: EdgeInsets.only(top: (content.lines.isEmpty ? 0.45 - 0.35 : 0.45) * em),
              child: Wrap(
                key: const ValueKey<String>('cm-fillPanelActions'),
                spacing: 0.9 * em,
                runSpacing: 0.2 * em,
                children: <Widget>[
                  for (final action in content.actions)
                    // '.cm-fillPanelActions button': { appearance: 'none', border: 'none', background: 'transparent',
                    //   padding: '0.3em 0', font: 'inherit', color: 'var(--app-ink, currentColor)',
                    //   display: 'inline-flex', alignItems: 'center', gap: '0.35em', cursor: 'pointer',
                    //   WebkitTapHighlightColor: 'transparent' }
                    Semantics(
                      button: true,
                      label: action.label,
                      onTap: () => _press(action),
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          key: ValueKey<String>('cm-fillPanelAction-${action.label}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _press(action),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 0.3 * em),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                glyph(action.icon, t.color('app-ink')),
                                SizedBox(width: 0.35 * em),
                                Text(action.label, style: face.copyWith(color: t.color('app-ink')), textScaler: TextScaler.noScaling),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ];
        return CustomSingleChildLayout(
          // Where the words are drawn; at the editor's own corner where they are not laid out.
          delegate: _Under(coords, context),
          child: Semantics(
            label: content.title,
            container: true,
            child: Container(
              key: const ValueKey<String>(fillPanelClass),
              constraints: BoxConstraints(maxWidth: most),
              padding: EdgeInsets.fromLTRB(0.75 * em, 0.55 * em, 0.75 * em, 0.6 * em),
              decoration: BoxDecoration(
                color: t.color('app-paper-2'),
                border: Border.all(color: t.color('app-rule')),
                borderRadius: BorderRadius.circular(t.radius('lg')),
                boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x2E000000), offset: Offset(0, 6), blurRadius: 20)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows),
            ),
          ),
        );
      },
    );
  }

  void _press(PanelAction action) => pressPanelAction(view, action);
}

/// panel.style.top = `${coords.bottom - frame.top + 6}px`;
/// panel.style.left = `${Math.max(8, Math.min(coords.left - frame.left, frame.width - width - 8))}px`
class _Under extends SingleChildLayoutDelegate {
  _Under(this.coords, this.context);

  /// Where the tapped words are, on the screen; null where they are not laid out.
  final Rect? coords;
  final BuildContext context;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(maxWidth: constraints.maxWidth - 16 < 0 ? 0 : constraints.maxWidth - 16);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.attached ? box.localToGlobal(Offset.zero) : Offset.zero;
    final at = coords;
    final left = at == null ? 0.0 : at.left - origin.dx, most = size.width - childSize.width - 8;
    return Offset(left < most ? (left < 8 ? 8 : left) : (most < 8 ? 8 : most), (at == null ? 0 : at.bottom - origin.dy) + 6);
  }

  @override
  bool shouldRelayout(_Under oldDelegate) => oldDelegate.coords != coords;
}

/// The panel, its look, and its tap on a filled answer. The look is [EditorFillPanel]'s to draw, and the scroll
/// that closes the panel is the screen's to tell ([closeFillPanel]).
Extension fillPanel() => Extension.list(<Extension>[
      Prec.high(_tapped),
      panelOpener.of((view, at) => openFillPanel(view, at)),
    ]);
