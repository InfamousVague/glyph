/// An index's card: on a teamspace's home, and in the sheet a folder's menu opens at "Keep an index…"
/// (docs/AI_INDEXES.md §6). Matt, 2026-11-02: "for any folder or org, the AI keeps an index note (what's here, the key
/// decisions, who owns what) and updates it as notes change. New teammates read one page instead of fifty."
///
/// The switch, "Keep an index"; on, the line under it says where it stands: "Updated 2 hr ago · Claude" with Refresh,
/// "Updating… 2 of 5" with Stop, "Kept by the Mac" on a device that is not its writer, or why no AI can write it here.
/// How often, Rebuild, Take over and Open the page are the rest; in simple mode (GHST-103) behind a More that opens in
/// place. Turning it on asks first where the first build is a big one (lib/activity/activity_cost.dart `askJobCost`),
/// as Rebuild does.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../activity/activity_cost.dart' show askJobCost;
import '../../art/art.dart';
import '../../note/version_history.dart' show agoText;
import '../../sheet/css.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'index_keeper.dart';
import 'index_section.dart' show IndexEvery;

/// The card (see the header) for [folder], called [title], kept by [keeper].
class IndexCard extends StatefulWidget {
  const IndexCard({super.key, required this.keeper, required this.folder, required this.title, this.onOpen, this.simple = false, this.now});

  final IndexKeeper keeper;
  final String folder, title;

  /// Opens the folder's page, where the index is; absent, no Open.
  final ValueChanged<String>? onOpen;

  /// Simple mode: the switch and its line, the rest behind More.
  final bool simple;

  /// The clock "Updated … ago" is read by; the device's own where not said.
  final DateTime Function()? now;

  static const Key switchKey = ValueKey<String>('index-switch'), lineKey = ValueKey<String>('index-line'), refreshKey = ValueKey<String>('index-refresh');
  static const Key stopKey = ValueKey<String>('index-stop'), moreKey = ValueKey<String>('index-more'), rebuildKey = ValueKey<String>('index-rebuild');
  static const Key takeOverKey = ValueKey<String>('index-take-over'), openKey = ValueKey<String>('index-open');

  /// One of How often's choices.
  static Key everyKey(IndexEvery every) => ValueKey<String>('index-every-${every.written}');

  @override
  State<IndexCard> createState() => _IndexCardState();
}

class _IndexCardState extends State<IndexCard> {
  bool _more = false;
  String? _said;

  IndexKeeper get _keeper => widget.keeper;

  Future<void> _guard(Future<String?> Function() act) async {
    try {
      final said = await act();
      if (mounted) setState(() => _said = said);
    } catch (failure) {
      if (mounted) setState(() => _said = '$failure');
    }
  }

  Future<String?> _build({required bool full}) async {
    final estimate = _keeper.estimate(widget.folder, full: full);
    if (estimate != null && !await askJobCost(context, estimate, title: full ? 'Rebuild the index?' : 'Build the index?')) return null;
    return _keeper.refresh(widget.folder, title: widget.title, full: full, person: true);
  }

  Future<void> _switch(bool on) => _guard(() async {
        if (!on) {
          await _keeper.turnOff(widget.folder, title: widget.title);
          return null;
        }
        await _keeper.turnOn(widget.folder, title: widget.title);
        if (!mounted) return null;
        return _build(full: true);
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _keeper, builder: (context, _) => _card(context, _keeper.status(widget.folder)));

  Widget _card(BuildContext context, IndexStatus s) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final quiet = pageText(t, sm, height: t.len('glacier-leading-sm'), color: t.color('app-ink-3'));
    final now = (widget.now ?? DateTime.now)();
    final updated = s.updated == null ? null : 'Updated ${agoText(s.updated!.millisecondsSinceEpoch, now: now.millisecondsSinceEpoch)}';
    final String line;
    if (!s.on) {
      line = 'A page that says what is here, the key decisions and who owns what, kept up to date by the AI as notes change.';
    } else if (s.running) {
      line = s.total > 1 ? 'Updating… ${s.done + 1 > s.total ? s.total : s.done + 1} of ${s.total}' : 'Updating…';
    } else if (!s.mine) {
      line = ['Kept by ${s.byName == null ? 'another device' : 'the ${s.byName}'}', ?updated].join(' · ');
    } else if (s.why != null) {
      line = s.why!;
    } else {
      line = [updated ?? 'Not built yet', if (s.by != null && s.updated != null) s.by!, if (s.dirty && s.updated != null) 'notes changed since'].join(' · ');
    }
    final error = _said ?? s.error;
    final more = !widget.simple || _more;
    final line2 = <Widget>[
      if (s.on && s.running) _Word(key: IndexCard.stopKey, icon: Lucide.square, words: 'Stop', label: 'Stop updating the index', onPressed: () => _keeper.stop(widget.folder)),
      if (s.on && !s.running && s.mine && s.why == null) _Word(key: IndexCard.refreshKey, icon: Lucide.refreshCw, words: 'Refresh', label: 'Refresh the index', onPressed: () => unawaited(_guard(() => _build(full: false)))),
      if (s.on && widget.simple && !_more) _Word(key: IndexCard.moreKey, icon: Lucide.chevronDown, words: 'More', label: 'More of the index’s settings', onPressed: () => setState(() => _more = true)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ExcludeSemantics(child: AppIcon(Lucide.listTree, size: 15, color: t.color('app-ink-3'))),
            SizedBox(width: t.space(2)),
            Expanded(child: Semantics(header: true, child: Text('Keep an index', style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2'))))),
            GlacierSwitch(key: IndexCard.switchKey, ariaLabel: 'Keep an index of ${widget.title}', checked: s.on, disabled: s.on && !s.mine, onCheckedChange: (on) => unawaited(_switch(on))),
          ],
        ),
        SizedBox(height: t.space(1)),
        Semantics(liveRegion: true, child: Text(line, key: IndexCard.lineKey, style: quiet)),
        if (error != null) ...[
          SizedBox(height: t.space(1)),
          Semantics(liveRegion: true, child: Text(error, style: pageText(t, sm, height: t.len('glacier-leading-sm'), color: t.color('app-ink-2')))),
        ],
        if (line2.isNotEmpty) ...[
          SizedBox(height: t.space(2)),
          Wrap(spacing: t.space(1), runSpacing: t.space(1), children: line2),
        ],
        if (s.on && more) ...[
          SizedBox(height: t.space(3)),
          Row(
            children: [
              Flexible(child: Text('Update', style: pageText(t, sm, color: t.color('app-ink-2')))),
              SizedBox(width: t.space(3)),
              for (final each in IndexEvery.values) ...[
                _Pill(key: IndexCard.everyKey(each), words: each == IndexEvery.quarter ? 'Every 15 min' : each.words, on: each == s.every, onChoose: s.mine ? () => unawaited(_guard(() async {
                      await _keeper.setEvery(widget.folder, each, title: widget.title);
                      return null;
                    })) : null),
                SizedBox(width: t.space(1)),
              ],
            ],
          ),
          SizedBox(height: t.space(2)),
          Wrap(
            spacing: t.space(1),
            runSpacing: t.space(1),
            children: [
              if (s.mine && !s.running && s.why == null) _Word(key: IndexCard.rebuildKey, icon: Lucide.sparkles, words: 'Rebuild', label: 'Rebuild the index from every note', onPressed: () => unawaited(_guard(() => _build(full: true)))),
              if (!s.mine)
                _Word(key: IndexCard.takeOverKey, icon: Lucide.refreshCw, words: 'Take over', label: 'Keep the index from this device', onPressed: () => unawaited(_guard(() async {
                      await _keeper.takeOver(widget.folder, title: widget.title);
                      return null;
                    }))),
              if (widget.onOpen != null && s.pageId != null) _Word(key: IndexCard.openKey, icon: Lucide.fileText, words: 'Open the index', label: 'Open the index page', onPressed: () => widget.onOpen!(s.pageId!)),
            ],
          ),
          if (!s.mine) ...[
            SizedBox(height: t.space(2)),
            Text('One device keeps an index, so two never write it at once. Take over to keep it from this one.', style: quiet),
          ],
        ],
      ],
    );
  }
}

/// Opens [folder]'s card in the app's sheet: what a folder's menu's "Keep an index…" opens.
void showIndexSheet(BuildContext context, {required IndexKeeper keeper, required String folder, required String title, ValueChanged<String>? onOpen, bool simple = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  var gone = false;
  void close() {
    if (gone) return;
    gone = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => Sheet(
      key: const ValueKey('index-sheet'),
      label: 'Index of $title',
      onClose: close,
      children: [
        SheetTitle.text(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: IndexCard(
            keeper: keeper,
            folder: folder,
            title: title,
            simple: simple,
            onOpen: onOpen == null
                ? null
                : (id) {
                    close();
                    onOpen(id);
                  },
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
}

/// One of How often's choices.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.words, required this.on, required this.onChoose});
  final String words;
  final bool on;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      onPressed: on ? null : onChoose,
      semanticLabel: on ? '$words, chosen' : words,
      toggled: on,
      builder: (context, state) => Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radius('full')),
          color: on ? t.color('app-ink') : (state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 7%, transparent)') : null),
        ),
        child: Text(words, maxLines: 1, style: pageText(t, sm, weight: 'medium', color: on ? t.color('app-paper') : t.color('app-ink-2'))),
      ),
    );
  }
}

/// A quiet word with its mark: Refresh, Stop, More, Rebuild.
class _Word extends StatelessWidget {
  const _Word({super.key, required this.icon, required this.words, required this.label, required this.onPressed});
  final LucideIcon icon;
  final String words;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final line = snapBorder(context, t.len('glacier-hairline'));
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('full'),
        child: Opacity(
          opacity: state.disabled ? 0.5 : 1,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
            decoration: ShapeDecoration(
              color: t.colorOf('color-mix(in oklch, var(--app-ink) ${state.hovered ? 9 : 4}%, transparent)'),
              shape: StadiumBorder(side: BorderSide(color: t.color('glacier-border-subtle'), width: line)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 14, color: t.color('app-ink-2')),
                SizedBox(width: t.space(1)),
                ExcludeSemantics(child: Text(words, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink-2')))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
