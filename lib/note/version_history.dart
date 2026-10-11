/// A note's version history, a page of its More sheet, drawn as a timeline (Matt: "include a way to view changes on a
/// timeline in app along with the author of the changes"). A port of `src/app/editor/VersionHistory.tsx` with
/// `VersionHistory.module.css`, and of the timeline's words in `editor/versionWords.ts`.
///
/// Every version kept, newest first, on a line down the page under the day it was kept, each with who made it, when,
/// how much it changed and the first line it changed. A version opened shows what it changed against the one before,
/// then what going back to it would change against the note now, and Restore. Above the timeline a version is saved
/// by hand with a name; under it the versions file is shared and the history switched off.
///
/// What differs:
/// - Days and clocks are written in English in the phone's own order and clock once it has said which
///   (core/locale_dates.dart: "Wed, Oct 7", "2:05 PM" and "Oct 7, 2026, 2:05 PM" on an American phone, "Wed, 7 Oct",
///   "14:05" and "7 Oct 2026, 14:05" on a British one), where the page asks the device's language; the day first on
///   a 24-hour clock until then.
/// - Sharing the file (`core/versions/share.ts`) is asked of [VersionHistory.onShareFile], and the row is off
///   without it.
/// - A toast is [VersionHistory.say].
/// - The timeline was laid out from its stylesheet and looked at; it has not been measured against the page.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/icons.dart';
import '../core/locale_dates.dart';
import '../core/versions_diff.dart';
import '../core/versions_file.dart';
import '../core/versions_record.dart';
import '../sheet/css.dart';
import '../sheet/flow.dart';
import '../sheet/kit.dart';

/// How many lines either side of a change are shown, the rest folded into "12 lines the same" (`CONTEXT`).
const int _context = 2;

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _two(int n) => n.toString().padLeft(2, '0');

/// The day a version was kept, as the timeline heads it: Today, Yesterday, or the date (`dayOf`).
String versionDay(int at, {int? now}) {
  final then = DateTime.fromMillisecondsSinceEpoch(at);
  final today = DateTime.fromMillisecondsSinceEpoch(now ?? DateTime.now().millisecondsSinceEpoch);
  final days = DateTime(today.year, today.month, today.day).difference(DateTime(then.year, then.month, then.day)).inHours / 24;
  if (days.round() == 0) return 'Today';
  if (days.round() == 1) return 'Yesterday';
  return toldDate(then, then.year != today.year ? DateForm.yMMMEd : DateForm.MMMEd) ??
      '${_weekdays[then.weekday - 1]}, ${then.day} ${_months[then.month - 1]}${then.year != today.year ? ' ${then.year}' : ''}';
}

/// The clock beside a version (`clock`): the phone's own, "2:05 PM" or "14:05", once it has said.
String versionClock(int at) {
  final then = DateTime.fromMillisecondsSinceEpoch(at);
  return toldDate(then, DateForm.hm) ?? '${_two(then.hour)}:${_two(then.minute)}';
}

/// The day and the time a version opened says it was kept
/// (`toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })`).
String versionWhen(int at) {
  final then = DateTime.fromMillisecondsSinceEpoch(at);
  return toldDate(then, DateForm.medShort) ?? '${then.day} ${_months[then.month - 1]} ${then.year}, ${versionClock(at)}';
}

/// Who kept a version, as the timeline says it (`authorName`).
String authorName(String by) => by == 'me' ? 'You' : by;

/// "3 min ago" (`agoText`, core/markDetails.ts).
String agoText(int ms, {int? now}) {
  final seconds = (((now ?? DateTime.now().millisecondsSinceEpoch) - ms) / 1000).round().clamp(0, 1 << 52);
  if (seconds < 45) return 'just now';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min ago';
  final hours = (minutes / 60).round();
  if (hours < 24) return '$hours hr ago';
  final days = (hours / 24).round();
  return days == 1 ? 'yesterday' : '$days days ago';
}

/// One row of a drawn change.
enum ChangeKind { same, del, add, fold }

/// The lines that go from [from] to [to], and the lines that come, with a little of what stays around them and the
/// rest folded (`Change`'s rows). Empty of `add` and `del` when the two say the same.
List<({ChangeKind kind, String text})> changeRows(String? from, String to) {
  final before = linesFrom(from);
  final steps = diffLines(before, linesOf(to));
  final rows = <({ChangeKind kind, String text})>[];
  var at = 0;
  for (final (index, step) in steps.indexed) {
    switch (step) {
      case Keep(:final count):
        final lines = before.sublist(at, at + count);
        at += count;
        final head = index == 0 ? 0 : _context;
        final tail = index == steps.length - 1 ? 0 : _context;
        if (lines.length <= head + tail + 1) {
          rows.addAll([for (final text in lines) (kind: ChangeKind.same, text: text)]);
        } else {
          rows.addAll([for (final text in lines.take(head)) (kind: ChangeKind.same, text: text)]);
          final folded = lines.length - head - tail;
          rows.add((kind: ChangeKind.fold, text: folded == 1 ? '1 line the same' : '$folded lines the same'));
          rows.addAll([for (final text in lines.sublist(lines.length - tail)) (kind: ChangeKind.same, text: text)]);
        }
      case Del(:final line):
        at += 1;
        rows.add((kind: ChangeKind.del, text: line));
      case Add(:final line):
        rows.add((kind: ChangeKind.add, text: line));
    }
  }
  return rows;
}

/// `.back`: the way back up a page of a sheet, an arrow and where it goes.
class SheetBack extends StatelessWidget {
  const SheetBack({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final ink = t.color('glacier-text');
    return CssFlow.block(
      // `margin: 0 0 var(--glacier-space-3)`
      margin: EdgeInsets.only(bottom: t.space(3)),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: GlacierPressable(
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => Padding(
            // `padding: var(--glacier-space-1) 0; display: inline-flex; gap: var(--glacier-space-2); font-weight: medium`
            padding: EdgeInsets.symmetric(vertical: t.space(1)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(2),
              children: [
                DrawnIconView(AppIcons.arrowLeft, size: md, color: ink),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, md, weight: 'medium', color: ink))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Who made a version, as a round mark with their first letter (`Author`).
class VersionAuthor extends StatelessWidget {
  const VersionAuthor({super.key, required this.by});
  final String by;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.lenOf('1.75rem');
    final letter = (by == 'me' ? 'Y' : (by.isEmpty ? '?' : String.fromCharCodes(by.runes.take(1)))).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: ring,
        height: ring,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-paper'), border: Border.all(color: t.color('app-rule'), width: snapBorder(context, 1))),
        child: Text(letter, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: t.color('app-ink-2'))),
      ),
    );
  }
}

/// The lines a version changed, as a git diff reads (`Change`, `.change`): the lines that go struck through, the
/// lines that come back tinted, in the note's monospace. [same] is said where nothing changed.
class VersionChange extends StatelessWidget {
  const VersionChange({super.key, required this.from, required this.to, required this.label, this.same = 'The note says exactly this now.'});

  final String? from;
  final String to;
  final String label;
  final String same;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = changeRows(from, to);
    if (!rows.any((row) => row.kind == ChangeKind.add || row.kind == ChangeKind.del)) return SheetNote(same);
    final sm = t.fontSize('sm');
    final ink2 = t.color('app-ink-2'), ink3 = t.color('app-ink-3');
    return CssFlow.block(
      // `margin: 0 0 var(--glacier-space-4); padding: var(--glacier-space-2) 0; border: hairline solid var(--app-rule); border-radius: md`
      margin: EdgeInsets.only(bottom: t.space(4)),
      child: Semantics(
        container: true,
        label: label,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: t.color('app-rule'), width: snapBorder(context, t.len('glacier-hairline'))), borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: t.space(2)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  Semantics(
                    label: switch (row.kind) { ChangeKind.add => 'Comes back: ${row.text}', ChangeKind.del => 'Goes: ${row.text}', _ => null },
                    child: ColoredBox(
                      // `.line[data-kind='add'] { background: color-mix(in oklch, var(--app-ink) 10%, transparent) }`
                      color: row.kind == ChangeKind.add ? t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)') : const Color(0x00000000),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: t.space(2)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // `grid-template-columns: 1.5em minmax(0, 1fr)`
                            SizedBox(
                              width: 1.5 * sm,
                              child: ExcludeSemantics(child: Text(switch (row.kind) { ChangeKind.add => '+', ChangeKind.del => '−', _ => '' }, style: t.textAt(sm, mono: true, height: 1.5, color: ink3))),
                            ),
                            Expanded(
                              child: Text(
                                row.kind == ChangeKind.fold ? row.text : (row.text.isEmpty ? ' ' : row.text),
                                style: switch (row.kind) {
                                  ChangeKind.add => t.textAt(sm, mono: true, height: 1.5, color: t.color('app-ink')),
                                  ChangeKind.del => t.textAt(sm, mono: true, height: 1.5, color: ink3).copyWith(decoration: TextDecoration.lineThrough, decorationColor: ink3),
                                  ChangeKind.fold => t.textAt(sm, height: 1.5, color: ink3).copyWith(fontStyle: FontStyle.italic),
                                  ChangeKind.same => t.textAt(sm, mono: true, height: 1.5, color: ink2),
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VersionHistory extends StatefulWidget {
  const VersionHistory({super.key, required this.noteId, required this.title, required this.record, required this.current, required this.onRestore, this.onBack, this.onShareFile, this.say, this.clock});

  final String noteId;
  final String title;
  final VersionsRecord record;

  /// The note's words now, for what restoring a version would change.
  final String Function() current;

  /// Puts a version's words into the note, through the editor, as one change to undo.
  final void Function(String text, Version version) onRestore;

  /// Back to the note's More sheet. Absent in a side panel, which has its own heading.
  final VoidCallback? onBack;

  /// Shares the versions file, answering what to say after (`shareVersionsFile`); absent, the row is off.
  final Future<String?> Function(String noteId, String title)? onShareFile;
  final void Function(String message)? say;
  final int Function()? clock;

  @override
  State<VersionHistory> createState() => _VersionHistoryState();
}

class _VersionHistoryState extends State<VersionHistory> {
  StreamSubscription<VersionsRead>? _watching;
  VersionsRead? _read;
  Version? _opened;
  String _name = '';

  @override
  void initState() {
    super.initState();
    _watching = widget.record.watch(widget.noteId).listen((read) {
      if (mounted) setState(() => _read = read);
    });
  }

  @override
  void dispose() {
    unawaited(_watching?.cancel());
    super.dispose();
  }

  List<Version> get _versions => _read?.versions ?? const [];

  String? _before(Version version) => version.n >= 2 && version.n - 2 < _versions.length ? _versions[version.n - 2].text : null;

  Future<void> _saveNow() async {
    final name = _name.trim();
    final kept = await widget.record.keepVersion(widget.noteId, widget.current(), label: name.isEmpty ? null : name);
    if (!mounted) return;
    setState(() => _name = '');
    widget.say?.call(kept ? 'Version saved.' : 'Nothing has changed since the last version.');
  }

  List<Widget> _openedPage(BuildContext context, Version opened) {
    final t = context.tokens;
    final now = widget.current();
    return [
      SheetBack(label: 'The timeline', onPressed: () => setState(() => _opened = null)),
      SheetTitle.text('Version ${opened.n}${opened.label != null ? ' · ${opened.label}' : ''}'),
      CssFlow.block(
        // `.byline { display: flex; align-items: center; gap: space-2; margin-block-end: space-3; color: ink-2; font-size: sm }`
        margin: EdgeInsets.only(bottom: t.space(3)),
        child: Row(
          spacing: t.space(2),
          children: [
            VersionAuthor(by: opened.by),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: authorName(opened.by), style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-2'))),
                    TextSpan(text: ' · ${versionWhen(opened.at)}'),
                  ],
                ),
                style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2')),
              ),
            ),
          ],
        ),
      ),
      SheetHeading(opened.n == 1 ? 'The note as it began' : 'What this version changed'),
      if (opened.n == 1 && opened.text.trim().isEmpty)
        const SheetNote('It began empty.')
      else
        VersionChange(from: _before(opened), to: opened.text, label: 'What this version changed', same: 'The same words as the version before, named.'),
      const SheetHeading('Restoring it changes the note like this'),
      VersionChange(from: now, to: opened.text, label: 'What restoring changes'),
      SheetGroup(
        children: [
          SheetRow(
            icon: const AppIcon(Lucide.rotateCcw, size: 18),
            label: 'Restore version ${opened.n}',
            hint: 'The note goes back to these words. Now is kept as a version first, so this can be undone too.',
            onPress: () {
              widget.onRestore(opened.text, opened);
              setState(() => _opened = null);
            },
            disabled: opened.text == now,
          ),
        ],
      ),
    ];
  }

  Widget _timeline(BuildContext context) {
    final t = context.tokens;
    final versions = _versions;
    final days = <({String day, List<Version> versions})>[];
    for (final version in versions.reversed) {
      final day = versionDay(version.at, now: widget.clock?.call());
      if (days.isNotEmpty && days.last.day == day) {
        days.last.versions.add(version);
      } else {
        days.add((day: day, versions: [version]));
      }
    }
    final sm = t.fontSize('sm'), xs = t.fontSize('xs'), md = t.fontSize('md');
    final ink = t.color('app-ink'), ink2 = t.color('app-ink-2'), ink3 = t.color('app-ink-3');
    final ring = t.lenOf('1.75rem');
    return CssFlow.block(
      // `.timeline { display: grid; gap: space-3; margin-block-end: space-4 }`
      margin: EdgeInsets.only(bottom: t.space(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: t.space(3),
        children: [
          for (final (:day, versions: those) in days)
            Semantics(
              container: true,
              label: day,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `.dayName`: xs, medium, 0.06em, capitals, ink-3, `margin: 0 0 space-1`.
                  Padding(
                    padding: EdgeInsets.only(bottom: t.space(1)),
                    child: Semantics(header: true, label: day, child: ExcludeSemantics(child: Text(day.toUpperCase(), style: pageText(t, xs, weight: 'medium', color: ink3, tracking: 0.06 * xs)))),
                  ),
                  Stack(
                    children: [
                      // `.entries::before`: the line the versions hang on, through the middle of the authors' rings.
                      Positioned(top: t.space(3), bottom: t.space(3), left: t.space(2) + ring / 2 - 0.5, width: 1, child: ColoredBox(color: t.colorOf('color-mix(in oklch, var(--app-ink) 22%, transparent)'))),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final version in those)
                            GlacierPressable(
                              key: ValueKey('version:${version.n}'),
                              onPressed: () => setState(() => _opened = version),
                              semanticLabel: 'Version ${version.n}${version.label != null ? ', ${version.label}' : ''}, by ${authorName(version.by)}, ${agoText(version.at, now: widget.clock?.call())}',
                              builder: (context, state) {
                                final peek = firstChange(_before(version), version.text);
                                return DecoratedBox(
                                  // `.entryButton:hover { background: color-mix(in oklch, var(--app-ink) 5%, transparent) }`
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('md')), color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 5%, transparent)') : null),
                                  child: Padding(
                                    padding: EdgeInsets.all(t.space(2)),
                                    child: ExcludeSemantics(
                                      // `grid-template-columns: auto minmax(0, 1fr) auto; align-items: start; gap: space-3`
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        spacing: t.space(3),
                                        children: [
                                          VersionAuthor(by: version.by),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              spacing: 0.15 * md,
                                              children: [
                                                Wrap(
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: t.space(2),
                                                  children: [
                                                    Text(authorName(version.by), style: pageText(t, md, weight: 'medium', color: ink)),
                                                    Text(versionClock(version.at), style: pageText(t, sm, color: ink3)),
                                                    if (version.label != null)
                                                      // `.label`: a small pill.
                                                      Container(
                                                        padding: EdgeInsets.symmetric(horizontal: 0.5 * xs),
                                                        decoration: BoxDecoration(border: Border.all(color: t.color('app-rule'), width: snapBorder(context, 1)), borderRadius: BorderRadius.circular(t.radius('full'))),
                                                        child: Text(version.label!, style: pageText(t, xs, color: ink2)),
                                                      ),
                                                  ],
                                                ),
                                                Row(
                                                  spacing: t.space(2),
                                                  children: [
                                                    Text(
                                                      version.n == 1 ? 'First version' : (version.added != 0 || version.removed != 0 ? '+${version.added} −${version.removed}' : 'Named'),
                                                      style: pageText(t, sm, color: ink2).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                                                    ),
                                                    if (peek != null)
                                                      Expanded(
                                                        child: Text(
                                                          '${peek.kind == 'add' ? '+ ' : '− '}${peek.text}',
                                                          maxLines: 1,
                                                          softWrap: false,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: t.textAt(sm, mono: true, color: ink3).copyWith(decoration: peek.kind == 'del' ? TextDecoration.lineThrough : null, decorationColor: ink3),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.only(top: 0.1 * sm),
                                            child: Text('v${version.n}', style: pageText(t, sm, color: ink3).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opened = _opened;
    if (opened != null) return CssFlow(collapse: true, children: _openedPage(context, opened));
    final read = _read;
    final versions = _versions;
    final byDefault = widget.record.versionsByDefault(widget.noteId);
    final file = (widget.title.trim().isEmpty ? 'Untitled' : widget.title.trim()).replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim();
    final share = widget.onShareFile;
    return CssFlow(
      collapse: true,
      children: [
        if (widget.onBack != null) ...[
          SheetBack(label: widget.title.isEmpty ? 'This note' : widget.title, onPressed: widget.onBack!),
          SheetTitle.text('Version history'),
        ],
        SheetNote(
          byDefault
              ? 'Kept for every note in an organization. A version is saved after a pause in the writing, when you leave the note, and whenever you save one here.'
              : 'A version is saved after a pause in the writing, when you leave the note, and whenever you save one here.',
        ),
        SheetGroup(
          children: [
            SheetField(label: 'Name', value: _name, onChange: (text) => setState(() => _name = text), placeholder: 'What this version is, if anything', autoCorrect: false),
            SheetRow(icon: const AppIcon(Lucide.history, size: 18), label: 'Save a version now', onPress: () => unawaited(_saveNow())),
          ],
        ),
        SheetHeading(read == null ? 'Reading the versions…' : (versions.length == 1 ? '1 version' : '${versions.length} versions')),
        if (versions.isNotEmpty) _timeline(context) else if (read != null) const SheetNote('None yet. The first is saved as you write.'),
        if ((read?.damaged ?? 0) > 0)
          SheetNote(read!.damaged == 1 ? 'One version in the file couldn’t be read, and is left out.' : '${read.damaged} versions in the file couldn’t be read, and are left out.'),
        SheetGroup(
          children: [
            SheetRow(
              icon: const AppIcon(Lucide.share2, size: 18),
              label: 'Share the versions file',
              hint: '$file.versions, beside the note. Every version, each as what changed.',
              onPress: share == null
                  ? null
                  : () => unawaited(
                        share(widget.noteId, widget.title).then<void>((said) {
                          if (said != null && said.isNotEmpty) widget.say?.call(said);
                        }, onError: (Object failure) => widget.say?.call('The file couldn’t be shared.')),
                      ),
              disabled: versions.isEmpty,
            ),
            SheetRow(
              label: 'Stop keeping history',
              hint: 'The versions kept so far stay, and carry on if you switch it on again.',
              onPress: () {
                widget.record.setKeepsVersions(widget.noteId, false);
                widget.onBack?.call();
              },
            ),
          ],
        ),
      ],
    );
  }
}
