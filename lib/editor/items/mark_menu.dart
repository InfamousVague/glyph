/// The drawer a linked line's row opens (media/linked_rows.dart). Ports `src/app/editor/MarkMenu.tsx` and
/// `MarkMenu.module.css`.
///
/// Matt: "tap on the notion pills to show a few options like opening the ticket in notion or un linking or
/// updating etc. … make the options typography and iconography heavy so they fit the theme on all context menus."
/// It first split the note open at the line; then "the notion opener should open in a drawer instead of rendering
/// in place". So it rises from the bottom over the dimmed note, in the app's sheet: the task (its title set large,
/// its stage and status above, its properties in two quiet columns) and then the things to do, each a full-width
/// row with a drawn icon and a word in display weight:
///
/// - Open in Notion
/// - Mark done in Notion, or Reopen (the board's own first done or to-do status)
/// - Use these words as its title, when the item's words and the task's title differ
/// - Refresh
/// - Unlink: the link comes off the line and the words stay
///
/// Opening it reads the task fresh. It closes on a tap on the dimmed note or the back gesture; an action that
/// changes the note closes it.
///
/// What differs:
/// - `markMenuMount.tsx` (a React root of its own inside a CodeMirror widget) has no counterpart: the row builds
///   this widget, and the sheet draws itself in the app's overlay (lib/sheet/sheet.dart).
/// - `.drawer`'s own size and leading (`className` on the sheet, which lib/sheet does not take) are set on the
///   drawer's own blocks, which is all they reached on the page.
/// - `cursor` and the tap highlight have no counterpart.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../core/text.dart';
import '../../plugins/details_cache.dart' show failureWords;
import '../../plugins/mark_details.dart';
import '../../sheet/css.dart';
import '../../sheet/sheet.dart';
import '../media/linked_rows.dart' show StagePainter;

/// What a drawer is opened with (`MarkMenuProps`).
class MarkMenuProps {
  const MarkMenuProps({required this.name, required this.url, required this.words, required this.say, required this.close, required this.unlink});

  final String name;
  final String url;
  final String words;
  final void Function(String message) say;
  final VoidCallback close;
  final VoidCallback unlink;
}

const Map<MarkActionIcon, LucideIcon> _icons = <MarkActionIcon, LucideIcon>{
  MarkActionIcon.done: Lucide.circleCheck,
  MarkActionIcon.reopen: Lucide.rotateCcw,
  MarkActionIcon.rename: Lucide.pencilLine,
};

final RegExp _status = RegExp('status', caseSensitive: false);

class MarkMenu extends StatefulWidget {
  const MarkMenu({super.key, required this.props});

  final MarkMenuProps props;

  @override
  State<MarkMenu> createState() => _MarkMenuState();
}

class _MarkMenuState extends State<MarkMenu> {
  /// The row whose action is running, or null.
  String? _busy;
  late VoidCallback _off;

  MarkMenuProps get _p => widget.props;

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _off = onMarkDetails(_redraw);
    wantMarkDetails(_p.name, _p.url, fresh: true);
  }

  @override
  void didUpdateWidget(MarkMenu old) {
    super.didUpdateWidget(old);
    if (old.props.name != _p.name || old.props.url != _p.url) wantMarkDetails(_p.name, _p.url, fresh: true);
  }

  @override
  void dispose() {
    _off();
    super.dispose();
  }

  Future<void> _act(String id, FutureOr<String?> Function() run, [String? busyWords]) async {
    haptic(HapticKind.selection);
    final say = _p.say;
    if (busyWords != null && mounted) setState(() => _busy = id);
    try {
      final said = await run();
      if (said != null && said.isNotEmpty) {
        haptic(HapticKind.success);
        say(said);
      }
    } catch (failure) {
      haptic(HapticKind.error);
      say(failureWords(failure));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = capitalise(_p.name);
    final entry = peekMarkDetails(_p.name, _p.url);
    final details = entry is MarkReady ? entry.details : null;
    final reading = entry is MarkLoading || (entry is MarkReady && entry.loading);
    final fields = details == null ? const <MarkField>[] : <MarkField>[
      for (final field in details.fields)
        if (!(details.status != null && _status.hasMatch(field.label))) field,
    ];
    final actions = markActions(_p.name, _p.url, _p.words);
    // '.drawer': { font-size: var(--glacier-font-size-md); line-height: 1.35 }
    const leading = 1.35;
    final ink = t.color('app-ink'), ink2 = t.color('app-ink-2'), ink3 = t.color('app-ink-3');
    final xs = t.fontSize('xs'), sm = t.fontSize('sm');

    // '.eyebrow': { composes: app-eyebrow; display: flex; flex-wrap: wrap; align-items: center;
    //   gap: var(--glacier-space-2) }
    // '.app-eyebrow': { font-size: xs; font-weight: bold; letter-spacing: var(--app-tracking-caps);
    //   text-transform: uppercase; color: var(--app-ink-3) }
    final tracking = t.lenOf('var(--app-tracking-caps)', em: xs);
    TextStyle caps(Color color) => pageText(t, xs, weight: 'bold', color: color, height: leading, tracking: tracking);
    Widget word(String text, Color color, {Key? key}) => KeyedSubtree(key: key, child: cssLines(text.toUpperCase(), caps(color), softWrap: false));
    final status = details?.status;
    final gone = details?.gone ?? false;
    Widget pill(Widget child) => DecoratedBox(
      key: const ValueKey<String>('markMenu-status'),
      // '.status': { display: inline-flex; align-items: center; gap: 0.45em; padding: 0.15em 0.7em;
      //   border-radius: 999px; background: var(--app-ink); color: var(--app-paper) }
      decoration: ShapeDecoration(color: ink, shape: const StadiumBorder()),
      child: Padding(padding: EdgeInsets.symmetric(vertical: xs * 0.15, horizontal: xs * 0.7), child: child),
    );
    final paper = t.color('app-paper');
    final eyebrow = Wrap(
      key: const ValueKey<String>('markMenu-eyebrow'),
      spacing: t.space(2),
      runSpacing: t.space(2),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        word(title, ink3, key: const ValueKey<String>('markMenu-name')),
        if (gone) pill(word('In trash', paper)),
        if (status != null && !gone)
          pill(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // '.stage': { box-sizing: border-box; inline-size: 0.85em; block-size: 0.85em; border-radius: 50%;
                //   border: 0.14em solid currentColor }
                ExcludeSemantics(child: CustomPaint(key: const ValueKey<String>('markMenu-stage'), size: Size.square(xs * 0.85), painter: StagePainter(status.stage, paper, snapBorder(context, xs * 0.14)))),
                SizedBox(width: xs * 0.45),
                word(status.label, paper),
              ],
            ),
          ),
        // '.fact': { color: var(--app-ink-2) }
        for (final (index, fact) in (details?.brief ?? const <String>[]).indexed) word(fact, ink2, key: ValueKey<String>('markMenu-fact-$index')),
      ],
    );

    final headline = details != null && details.title.isNotEmpty ? details.title : (_p.words.isNotEmpty ? _p.words : 'Linked');
    final h3 = t.len('app-h3');
    final quiet = entry is MarkFailed
        ? entry.message
        : details != null
            ? '${details.editedAt != null ? 'Changed ${agoText(details.editedAt!)} · ' : ''}${reading ? 'Reading…' : 'Read ${agoText(details.readAt)}'}'
            : reading
                ? 'Reading from $title…'
                : 'Ghost.md can’t read $title right now.';

    final head = Padding(
      key: const ValueKey<String>('markMenu-head'),
      // '.head': { display: grid; gap: var(--glacier-space-2); padding-block: var(--glacier-space-2) var(--glacier-space-3) }
      padding: EdgeInsets.only(top: t.space(2), bottom: t.space(3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: t.space(2),
        children: <Widget>[
          Align(alignment: AlignmentDirectional.centerStart, child: eyebrow),
          // '.title': { margin: 0; font-size: var(--app-h3); font-weight: bold; line-height: 1.12;
          //   letter-spacing: -0.02em; color: var(--app-ink); overflow-wrap: anywhere }
          KeyedSubtree(key: const ValueKey<String>('markMenu-title'), child: cssLines(headline, pageText(t, h3, weight: 'bold', color: ink, height: 1.12, tracking: h3 * -0.02))),
          if (fields.isNotEmpty)
            // '.fields': { display: grid; grid-template-columns: auto 1fr; column-gap: var(--glacier-space-4);
            //   row-gap: 0.15em; margin: 0; font-size: var(--glacier-font-size-sm) }
            Table(
              key: const ValueKey<String>('markMenu-fields'),
              columnWidths: const <int, TableColumnWidth>{0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
              children: <TableRow>[
                for (final (index, field) in fields.indexed)
                  TableRow(
                    children: <Widget>[
                      // '.field dt': { color: var(--app-ink-3) }
                      Padding(
                        padding: EdgeInsets.only(right: t.space(4), top: index == 0 ? 0 : sm * 0.15),
                        child: KeyedSubtree(key: const ValueKey<String>('markMenu-dt'), child: cssLines(field.label, pageText(t, sm, color: ink3, height: leading), softWrap: false)),
                      ),
                      // '.field dd': { margin: 0; color: var(--app-ink); overflow-wrap: anywhere }
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : sm * 0.15),
                        child: KeyedSubtree(key: const ValueKey<String>('markMenu-dd'), child: cssLines(field.value, pageText(t, sm, color: ink, height: leading))),
                      ),
                    ],
                  ),
              ],
            ),
          // '.quiet': { margin: 0; font-size: var(--glacier-font-size-xs); color: var(--app-ink-3) }
          KeyedSubtree(key: const ValueKey<String>('markMenu-quiet'), child: cssLines(quiet, pageText(t, xs, color: ink3, height: leading))),
        ],
      ),
    );

    final rows = <Widget>[
      _Row(
        id: 'open',
        busy: _busy,
        icon: Lucide.externalLink,
        label: 'Open in $title',
        onPress: () => unawaited(
          _act('open', () async {
            final name = _p.name, url = details != null && details.url.isNotEmpty ? details.url : _p.url;
            _p.close();
            await openMarked(name, url);
            return null;
          }),
        ),
      ),
      for (final action in actions)
        _Row(key: ValueKey<String>('action-${action.id}'), id: action.id, busy: _busy, icon: _icons[action.icon]!, label: action.label, busyLabel: action.busyLabel, onPress: () => unawaited(_act(action.id, action.run, action.busyLabel))),
      _Row(
        id: 'refresh',
        busy: _busy,
        icon: Lucide.refreshCw,
        label: reading ? 'Reading…' : 'Refresh',
        onPress: () => unawaited(
          _act('refresh', () {
            wantMarkDetails(_p.name, _p.url, fresh: true);
            _redraw();
            return null;
          }),
        ),
      ),
      _Row(
        id: 'unlink',
        busy: _busy,
        icon: Lucide.unlink,
        label: 'Unlink',
        quiet: true,
        last: true,
        onPress: () => unawaited(
          _act('unlink', () {
            _p.unlink();
            return 'Unlinked. The words stay.';
          }),
        ),
      ),
    ];
    final rule = snapBorder(context, t.len('glacier-hairline'));
    // '.options': { display: grid; border-block-start: var(--glacier-hairline) solid var(--app-rule) }
    final options = DecoratedBox(
      key: const ValueKey<String>('markMenu-options'),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('app-rule'), width: rule))),
      child: Padding(
        padding: EdgeInsets.only(top: rule),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );

    // The drawer's shell - the scrim, the grip's pull, the back gesture - is the sheet every bottom sheet shares.
    return Sheet(
      label: '$title ${details?.title ?? 'link'}',
      onClose: _p.close,
      children: <Widget>[head, options],
    );
  }
}

/// One of the drawer's rows: a drawn icon and a word in display weight, the busy words while its action runs, and
/// every row still while any runs. A widget of its own, kept by its place, so a redraw keeps the row a person is
/// pressing rather than drawing a new one under the finger.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.id, required this.busy, required this.icon, required this.label, this.busyLabel, required this.onPress, this.quiet = false, this.last = false});

  final String id;

  /// The row whose action is running, or null.
  final String? busy;
  final LucideIcon icon;
  final String label;
  final String? busyLabel;
  final VoidCallback onPress;
  final bool quiet;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rule = snapBorder(context, t.len('glacier-hairline'));
    final xl = t.fontSize('xl');
    final said = busy == id && busyLabel != null ? busyLabel! : label;
    return GlacierPressable(
      key: ValueKey<String>('markMenu-option-$id'),
      onPressed: busy != null ? null : onPress,
      // The drawer says its own: a selection as an action starts, then how it went.
      haptic: null,
      semanticLabel: said,
      builder: (context, state) {
        // '.option': { color: var(--app-ink) } '.option:disabled': { color: var(--app-ink-3) }
        // '.option[data-quiet]': { color: var(--app-ink-2) }, which comes later in the sheet and so wins.
        final color = quiet ? t.color('app-ink-2') : (state.disabled ? t.color('app-ink-3') : t.color('app-ink'));
        return ConstrainedBox(
          // '.option': { display: flex; align-items: center; gap: var(--glacier-space-4); min-block-size: 3.4rem;
          //   padding: 0; border-block-end: var(--glacier-hairline) solid var(--app-rule) }
          // '.option:last-child': { border-block-end: none }
          constraints: BoxConstraints(minHeight: t.lenOf('3.4rem')),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // '.option:active': { background: color-mix(in srgb, var(--app-ink) 6%, transparent) }
              color: state.pressed ? t.colorOf('color-mix(in srgb, var(--app-ink) 6%, transparent)') : null,
              border: last ? null : Border(bottom: BorderSide(color: t.color('app-rule'), width: rule)),
            ),
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : rule),
              child: Row(
                spacing: t.space(4),
                children: <Widget>[
                  // '.icon': { display: grid; place-items: center; inline-size: 1.875rem; block-size: 1.875rem;
                  //   border-radius: 50%; background: var(--app-paper); border: var(--app-line) solid var(--app-ink) }
                  ExcludeSemantics(
                    child: Container(
                      key: const ValueKey<String>('markMenu-icon'),
                      width: t.lenOf('1.875rem'),
                      height: t.lenOf('1.875rem'),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-paper'), border: Border.all(color: t.color('app-ink'), width: snapBorder(context, t.len('app-line')))),
                      child: AppIcon(icon, size: 18, strokeWidth: 2.2, color: color),
                    ),
                  ),
                  // '.label': { font-size: var(--glacier-font-size-xl); font-weight: semibold; letter-spacing: -0.01em }
                  Flexible(
                    child: ExcludeSemantics(
                      child: KeyedSubtree(key: const ValueKey<String>('markMenu-label'), child: cssLines(said, pageText(t, xl, weight: 'semibold', color: color, height: 1.35, tracking: xl * -0.01))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
