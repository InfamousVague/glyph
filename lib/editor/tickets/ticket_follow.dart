/// What a ticket's panel shows under its rows for a team (Matt, 2026-10-31, of the ticket features): who watches it
/// and Watch or Unwatch; its history, who changed what and when, three at a time with Show all; its possible
/// duplicates and Merge into…; and, closed as another's duplicate, what it duplicates and Undo merge.
///
/// In simple mode (lib/core/preferences.dart `simple`) the watchers and the history show, and the duplicates and the
/// merge wait behind a quiet More that opens in place, as every fancy thing in simple mode does.
///
/// Everything it writes is the front matter, through the panel's own write (one change, one Undo): `watchers:` for
/// Watch and Unwatch. The history is read from the note's versions (lib/book/ticket_history.dart), the duplicates from
/// the library (lib/book/ticket_duplicates.dart), and a merge is the root's (lib/book/ticket_merge.dart), which asks
/// first and says what it will do.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../book/ticket_duplicates.dart' show duplicateOfKey;
import '../../book/ticket_history.dart';
import '../../book/ticket_watchers.dart';
import '../../book/tickets.dart' show TicketChoice;
import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/properties.dart';
import '../../notes/when.dart' show when;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../fields/field_picker.dart' show StatusIcon;
import '../fields/field_picks.dart' show statusLook;
import '../queries/query_layout.dart';
import '../queries/query_look.dart';

/// A ticket another is likely a duplicate of, and the words their titles share.
typedef LikelyDuplicate = ({TicketChoice ticket, List<String> shared});

/// What the screen hands a ticket's panel for its team's parts (`TicketOptions.follow`); each part is left out
/// without what it needs.
class TicketFollow {
  const TicketFollow({required this.me, this.history, this.duplicates, this.similar, this.merge, this.undoMerge, this.simple, this.now});

  /// Who is reading: the account's handle, or null signed out, where Watch is not offered.
  final String? Function() me;

  /// The ticket's changes, oldest first (lib/book/ticket_history.dart `ticketHistory`).
  final Future<List<TicketChange>> Function()? history;

  /// Its likely duplicates, most alike first.
  final List<LikelyDuplicate> Function()? duplicates;

  /// The tickets a title being typed is likely a duplicate of: what Add sub-ticket's sheet shows under its field.
  final List<LikelyDuplicate> Function(String title)? similar;

  /// Merge this ticket into [target]: the root asks first, writes it, and offers Undo.
  final void Function(TicketChoice target)? merge;

  /// Takes back the merge that closed this ticket, where this device made it; null where there is none to take back.
  final VoidCallback? Function()? undoMerge;

  /// Whether the app is in simple mode; advanced where it is not said.
  final bool Function()? simple;

  /// The time, in ms, for "2 hr ago".
  final int Function()? now;
}

/// How many changes the history shows before Show all.
const int historyShown = 3;

/// The panel's team parts (see the header), ruled off under its rows as its sub-tickets are.
class TicketFollowPart extends StatefulWidget {
  const TicketFollowPart({super.key, required this.look, required this.front, required this.follow, required this.editable, required this.write, required this.choices, this.open, this.self});

  final QueryLook look;

  /// The front matter's lines.
  final String front;
  final TicketFollow follow;
  final bool editable;

  /// The panel's write: one property, one change.
  final void Function(String key, Object? value) write;

  /// Every other ticket, for Merge into….
  final List<TicketChoice> Function() choices;

  /// Opens a ticket by its key or title.
  final void Function(String target)? open;

  /// This ticket, as the merge's sheet names it.
  final String? self;

  @override
  State<TicketFollowPart> createState() => _TicketFollowPartState();
}

class _TicketFollowPartState extends State<TicketFollowPart> {
  bool _all = false;
  bool _more = false;
  bool _merging = false;
  Future<List<TicketChange>>? _changes;
  String? _readFor;

  QueryLook get look => widget.look;

  @override
  void didUpdateWidget(TicketFollowPart old) {
    super.didUpdateWidget(old);
    if (old.front != widget.front) _readFor = null;
  }

  Future<List<TicketChange>>? _history() {
    final read = widget.follow.history;
    if (read == null) return null;
    // Read again when the front matter changes (a version may have been kept with it); the history keeps each pair.
    if (_readFor != widget.front || _changes == null) {
      _readFor = widget.front;
      _changes = read();
    }
    return _changes;
  }

  Widget _tap({required String label, required VoidCallback onTap, required Widget child, Key? key}) => Semantics(
        key: key,
        container: true,
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
      );

  /// A quiet word and its mark, as the panel's foot says More and Sub-ticket.
  Widget _word(String name, LucideIcon icon, String words, {required VoidCallback onTap, String? label, Key? key}) => _tap(
        key: key,
        label: label ?? words,
        onTap: () {
          fireMotor(HapticKind.selection);
          onTap();
        },
        child: Part(
          name,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: look.space(1)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppIcon(icon, size: 13, color: look.ink3),
                SizedBox(width: look.space(1)),
                Flexible(child: PageWords(words, look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      );

  Widget _heading(String words, {Widget? trailing}) => Row(
        children: <Widget>[
          Expanded(child: PageWords(words, look.sans(look.em, color: look.ink3), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ?trailing,
        ],
      );

  Widget _ruled(String name, List<Widget> children) => Padding(
        padding: EdgeInsets.only(top: look.space(1), bottom: look.space(1)),
        child: Part(
          name,
          child: Container(
            padding: EdgeInsets.only(top: look.space(2)),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: look.rule))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );

  // ---- watchers -----------------------------------------------------------------------------------------------------

  Widget? _watchers() {
    final me = widget.follow.me();
    final watchers = watchersOf(widget.front);
    if (me == null && watchers.isEmpty) return null;
    final watching = me != null && watches(widget.front, me);
    final names = watchers.isEmpty ? 'Nobody yet' : [for (final each in watchers) me != null && each.toLowerCase() == me.toLowerCase() ? 'You' : each].join(', ');
    final toggle = me == null || !widget.editable
        ? null
        : _word(
            watching ? 'unwatch' : 'watch',
            watching ? Lucide.eyeOff : Lucide.eye,
            watching ? 'Unwatch' : 'Watch',
            key: ValueKey<String>(watching ? 'ticket-unwatch' : 'ticket-watch'),
            label: watching ? 'Unwatch this ticket' : 'Watch this ticket',
            onTap: () {
              final list = watchersOf(withWatcher(widget.front, me, !watching));
              widget.write(watchersKey, list.isEmpty ? null : [for (final each in list) '@$each']);
            },
          );
    return _ruled('watchers', <Widget>[
      Semantics(
        container: true,
        label: 'Watched by $names',
        child: Row(
          children: <Widget>[
            AppIcon(Lucide.eye, size: 13, color: look.ink3),
            SizedBox(width: look.space(2)),
            Expanded(
              child: ExcludeSemantics(child: PageWords(names, look.sans(look.em, color: watchers.isEmpty ? look.ink4 : look.ink2), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ),
            ?toggle,
          ],
        ),
      ),
    ]);
  }

  // ---- history ------------------------------------------------------------------------------------------------------

  Widget? _historyPart() {
    final future = _history();
    if (future == null) return null;
    final me = widget.follow.me();
    final now = widget.follow.now?.call();
    return FutureBuilder<List<TicketChange>>(
      future: future,
      builder: (context, snapshot) {
        final changes = snapshot.data ?? const <TicketChange>[];
        if (changes.isEmpty) return const SizedBox.shrink();
        final newest = changes.reversed.toList();
        final shown = _all ? newest : newest.take(historyShown).toList();
        return _ruled('history', <Widget>[
          _heading(
            'History',
            trailing: newest.length > historyShown
                ? _word('showAll', _all ? Lucide.chevronUp : Lucide.chevronDown, _all ? 'Show fewer' : 'Show all ${newest.length}', key: const ValueKey<String>('ticket-history-all'), onTap: () => setState(() => _all = !_all))
                : null,
          ),
          SizedBox(height: look.space(1)),
          for (final change in shown)
            Padding(
              padding: EdgeInsets.only(bottom: look.space(1)),
              child: Part(
                'change',
                child: Semantics(
                  container: true,
                  label: '${changeWords(change, me: me)}, ${when(change.at, now)}',
                  excludeSemantics: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: PageWords(changeWords(change, me: me), look.sans(look.xs, color: look.ink2), line: look.lineXs)),
                      SizedBox(width: look.space(2)),
                      PageWords(when(change.at, now), look.sans(look.xs, color: look.ink4), line: look.lineXs, softWrap: false),
                    ],
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }

  // ---- duplicates and merge -----------------------------------------------------------------------------------------

  Widget _duplicateRow(LikelyDuplicate likely) {
    final choice = likely.ticket;
    final key = choice.key;
    final words = key == null ? choice.title : '$key  ${choice.title}';
    final open = widget.open;
    final row = Part(
      'duplicate',
      child: Padding(
        padding: EdgeInsets.only(bottom: look.space(1)),
        child: Row(
          children: <Widget>[
            AppIcon(Lucide.copy, size: 13, color: look.ink3),
            SizedBox(width: look.space(2)),
            Expanded(child: PageWords(words, look.sans(look.em, color: look.ink), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (choice.status != null) ...<Widget>[SizedBox(width: look.space(2)), PageWords(choice.status!, look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false)],
          ],
        ),
      ),
    );
    if (open == null) return row;
    return _tap(key: ValueKey<String>('duplicate:${key ?? choice.title}'), label: 'Possible duplicate: $words', onTap: () => open(key ?? choice.title), child: row);
  }

  Widget? _mergePart() {
    final follow = widget.follow;
    final closedAs = (frontMatterValue(widget.front, duplicateOfKey) ?? '').trim();
    final undo = follow.undoMerge?.call();
    if (closedAs.isNotEmpty) {
      final target = linkTargets(closedAs).firstOrNull ?? closedAs;
      return _ruled('duplicateOf', <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: widget.open == null
                  ? PageWords('Duplicate of $target', look.sans(look.em, color: look.ink2), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)
                  : _tap(
                      label: 'Duplicate of $target. Open it',
                      onTap: () => widget.open!(target),
                      child: PageWords('Duplicate of $target', look.sans(look.em, color: look.ink2), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
            ),
            if (undo != null && widget.editable) _word('undoMerge', Lucide.undo2, 'Undo merge', key: const ValueKey<String>('ticket-undo-merge'), onTap: undo),
          ],
        ),
      ]);
    }
    final likely = follow.duplicates?.call() ?? const <LikelyDuplicate>[];
    final merges = follow.merge != null && widget.editable;
    if (likely.isEmpty && !merges) return null;
    final simple = follow.simple?.call() ?? false;
    if (simple && !_more) {
      return _ruled('followMore', <Widget>[
        _word('more', Lucide.ellipsis, likely.isEmpty ? 'More' : 'More · ${likely.length == 1 ? '1 possible duplicate' : '${likely.length} possible duplicates'}', key: const ValueKey<String>('ticket-follow-more'), onTap: () => setState(() => _more = true)),
      ]);
    }
    return _ruled('duplicates', <Widget>[
      if (likely.isNotEmpty) ...<Widget>[_heading('Possible duplicates'), SizedBox(height: look.space(1)), for (final each in likely) _duplicateRow(each)],
      if (merges) Align(alignment: Alignment.centerLeft, child: _word('mergeInto', Lucide.replace, 'Merge into…', key: const ValueKey<String>('ticket-merge-into'), label: 'Merge this ticket into another', onTap: () => setState(() => _merging = true))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[?_watchers(), ?_historyPart(), ?_mergePart()];
    final merge = widget.follow.merge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...parts,
        if (_merging && merge != null)
          MergeTargetSheet(
            self: widget.self,
            likely: widget.follow.duplicates?.call() ?? const <LikelyDuplicate>[],
            choices: widget.choices,
            onClose: () => setState(() => _merging = false),
            onPick: (target) {
              setState(() => _merging = false);
              merge(target);
            },
          ),
      ],
    );
  }
}

/// The sheet a ticket's merge target is picked from: its likely duplicates first, then every open ticket, found by
/// its key or its title as it is typed.
class MergeTargetSheet extends StatefulWidget {
  const MergeTargetSheet({super.key, required this.self, required this.likely, required this.choices, required this.onPick, required this.onClose});

  final String? self;
  final List<LikelyDuplicate> likely;
  final List<TicketChoice> Function() choices;
  final void Function(TicketChoice target) onPick;
  final VoidCallback onClose;

  @override
  State<MergeTargetSheet> createState() => _MergeTargetSheetState();
}

class _MergeTargetSheetState extends State<MergeTargetSheet> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final needle = _typed.trim().toLowerCase();
    bool found(TicketChoice choice) => needle.isEmpty || '${choice.key ?? ''} ${choice.title}'.toLowerCase().contains(needle);
    final likely = [for (final each in widget.likely) if (found(each.ticket)) each];
    final named = {for (final each in likely) '${each.ticket.key}|${each.ticket.title}'};
    final others = [
      for (final choice in widget.choices())
        if (choice.category != StatusCategory.done && found(choice) && !named.contains('${choice.key}|${choice.title}')) choice,
    ];
    final title = 'Merge ${widget.self ?? 'this ticket'} into…';
    Widget row(TicketChoice choice, {String? hint}) => SheetRow(
          key: ValueKey<String>('merge-target:${choice.key ?? choice.title}'),
          icon: StatusIcon(look: statusLook(choice.status ?? '')),
          label: choice.key != null ? '${choice.key}  ${choice.title}' : choice.title,
          hint: hint ?? choice.status,
          onPress: () {
            final pick = widget.onPick;
            widget.onClose();
            pick(choice);
          },
        );
    return Sheet(
      key: const ValueKey<String>('merge-target-sheet'),
      label: title,
      onClose: widget.onClose,
      children: <Widget>[
        SheetTitle.text(title),
        const SheetNote('Its comments, watchers, labels and links move to the ticket you pick, its words go under a heading there, and it is closed as a duplicate. You can undo it.'),
        SheetField(label: 'Find a ticket', value: _typed, placeholder: 'Its key or its title', onChange: (text) => setState(() => _typed = text)),
        SheetGroup(
          children: <Widget>[
            if (likely.isEmpty && others.isEmpty) SheetRow(label: needle.isEmpty ? 'No other open tickets.' : 'No ticket by that key or title.'),
            for (final each in likely) row(each.ticket, hint: 'Likely duplicate · ${each.shared.join(', ')}'),
            for (final choice in others.take(40)) row(choice),
          ],
        ),
      ],
    );
  }
}

/// Under a title being typed for a new ticket: the tickets it may duplicate, each a tap away (Add sub-ticket's sheet,
/// and any sheet that makes a ticket from a title; the triage's too). Nothing while there are none.
class DuplicateHints extends StatelessWidget {
  const DuplicateHints({super.key, required this.likely, this.onOpen});

  final List<LikelyDuplicate> likely;
  final void Function(TicketChoice ticket)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (likely.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetNote(likely.length == 1 ? 'This may be a duplicate of a ticket you have:' : 'This may be a duplicate of one of these:'),
        SheetGroup(
          children: <Widget>[
            for (final each in likely.take(3))
              SheetRow(
                key: ValueKey<String>('duplicate-hint:${each.ticket.key ?? each.ticket.title}'),
                icon: StatusIcon(look: statusLook(each.ticket.status ?? '')),
                label: each.ticket.key != null ? '${each.ticket.key}  ${each.ticket.title}' : each.ticket.title,
                hint: 'Shares ${each.shared.join(', ')}',
                onPress: onOpen == null ? null : () => onOpen!(each.ticket),
              ),
          ],
        ),
      ],
    );
  }
}
