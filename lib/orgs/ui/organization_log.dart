/// An organization's audit log. A port of `src/app/notes/OrganizationLog.tsx` with OrganizationLog.module.css, and
/// of the parts of the version history it draws with (`editor/VersionHistory.tsx`'s `Author` and `Change`,
/// `editor/versionWords.ts`, VersionHistory.module.css) (Matt: "an "audit log" for organizations to be able to
/// browse history of changes across all files").
///
/// A page under the dashboard with every change to every note filed in the organization's workspace - each version
/// kept of each note (lib/core/versions_log.dart) - and the team's own news from the feed between them, newest
/// first under the day it happened, on the version history's timeline.
///
/// Each change is who, what they did (created, edited, named a version of) and to which note, when, "+3 −1" and the
/// first line it changed; the team's news is its sentence with the kind's mark where an author's initial would be.
/// Over the timeline a field narrows the log to a note, a person or a version's name, and three pills show
/// everything, the notes alone or the team alone. A change opened is what that version changed against the one
/// before, line by line, with the way to the note and to only that note's changes. The figures under the tools say
/// how much there is, and which of the workspace's notes keep no history.
///
/// What differs from the web page:
/// - The feed, the organizations and the workspaces are the [AccountServices] it is handed; the versions are the
///   [VersionsRecord] it is handed (lib/core/versions_record.dart), and without one the log is the team's news
///   alone.
/// - **The version history's own screen is not ported**, so its author's ring and its diff live here until it is.
/// - Days, clocks and dates are written in English in the phone's own order and clock once it has said which
///   (core/locale_dates.dart: "Tue, 7 Oct" and "18:05" on a British phone), and as an American page writes them
///   ("Tue, Oct 7", "6:05 PM") until then, where the page asked the device's language.
/// - The filter is a plain field in All notes' pill; it has no selection handles or toolbar of its own.
/// - A change opened is left by its own word or by the bar's arrow; the phone's back gesture is the shell's, which
///   goes to the dashboard.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/locale_dates.dart';
import '../../core/note.dart';
import '../../core/note_text.dart';
import '../../core/notifications.dart';
import '../../core/preferences.dart';
import '../../core/versions_diff.dart';
import '../../core/versions_file.dart';
import '../../core/versions_log.dart';
import '../../core/versions_record.dart';
import '../../core/workspaces.dart';
import '../../sheet/css.dart';
import '../../shell/header_pane.dart';
import '../orgs.dart';
import 'org_news.dart';
import 'organization_screen.dart' show OrgPill;
import 'parts.dart';

// --- the words (editor/versionWords.ts) ------------------------------------------------------------------------------

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Yesterday", or the date: a day's heading on the timeline (`dayOf`).
String logDayOf(int at, {int? now}) {
  DateTime day(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day);
  }

  final today = day(now ?? DateTime.now().millisecondsSinceEpoch), then = day(at);
  final days = (today.difference(then).inHours / 24).round();
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return toldDate(then, then.year != today.year ? DateForm.yMMMEd : DateForm.MMMEd) ??
      '${_weekdays[then.weekday - 1]}, ${_months[then.month - 1]} ${then.day}${then.year != today.year ? ', ${then.year}' : ''}';
}

/// The time of day a version was kept, beside it on the timeline (`clock`).
String logClock(int at) {
  final d = DateTime.fromMillisecondsSinceEpoch(at);
  final told = toldDate(d, DateForm.hm);
  if (told != null) return told;
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$hour:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// A date and a time, as a change opened says when (`toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })`).
String logDateTime(int at) {
  final d = DateTime.fromMillisecondsSinceEpoch(at);
  return toldDate(d, DateForm.medShort) ?? '${_months[d.month - 1]} ${d.day}, ${d.year}, ${logClock(at)}';
}

/// A version's author in words: "You" for one kept here without an account (`authorName`).
String authorName(String by) => by == 'me' ? 'You' : by;

/// "Roadmap", "Roadmap and Standup", "Roadmap, Standup and Groceries" (`listWords`).
String listWords(List<String> words) {
  if (words.length <= 1) return words.isEmpty ? '' : words.first;
  return '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';
}

String _count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

/// What a change did to its note, as the row says it (`didWords`).
String didWords(Change change) => change.first ? 'created' : (change.added != 0 || change.removed != 0 ? 'edited' : 'named a version of');

/// How long ago, for a screen reader (core/markDetails.ts `agoText`, as far as the log says it).
String _ago(int at, int now) {
  final minutes = ((now - at) / 60000).floor();
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours hr ago';
  final days = hours ~/ 24;
  return days == 1 ? 'yesterday' : '$days days ago';
}

/// A line of the log: a change to a note, or a piece of the team's news (`Entry`).
class _Entry {
  const _Entry.change(this.key, this.at, Change this.change) : news = null;
  const _Entry.news(this.key, this.at, FeedNotification this.news) : change = null;
  final String key;
  final int at;
  final Change? change;
  final FeedNotification? news;
}

/// The organization's audit log (`src/app/notes/OrganizationLog.tsx`).
class OrganizationLog extends StatefulWidget {
  const OrganizationLog({super.key, required this.services, required this.orgId, required this.notes, required this.onBack, required this.onOpenNote, this.record, this.wisp = true, this.now});

  final AccountServices? services;
  final String orgId;

  /// The notes this device holds (not the trash), of which those filed in the organization's workspace are logged.
  final List<Note> notes;

  /// The dashboard.
  final VoidCallback onBack;
  final ValueChanged<String> onOpenNote;

  /// Where the notes' versions are kept; null logs the team's news alone.
  final VersionsRecord? record;
  final bool wisp;
  final int Function()? now;

  @override
  State<OrganizationLog> createState() => _OrganizationLogState();
}

class _OrganizationLogState extends State<OrganizationLog> {
  final ScrollController _scroller = ScrollController();
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'Filter the log');
  ChangesAcross? _across;
  List<String> _watched = const [];

  /// `all`, `notes` or `team` (`Shown`).
  String _shown = 'all';
  String _query = '';
  String? _only;
  Change? _opened;

  AccountServices? get _services => widget.services;
  PreferencesStore get _prefs => _services?.prefs ?? preferences;
  int _now() => (widget.now ?? _services?.now ?? () => DateTime.now().millisecondsSinceEpoch)();

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    if (record != null) _across = ChangesAcross(record)..addListener(_changed);
    _services?.changes.addListener(_changed);
    _services?.workspaces?.addListener(_changed);
    _prefs.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    _across
      ?..removeListener(_changed)
      ..dispose();
    _services?.changes.removeListener(_changed);
    _services?.workspaces?.removeListener(_changed);
    _prefs.removeListener(_changed);
    _focus.dispose();
    _field.dispose();
    _scroller.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// A change opened, or the log again, starts at the top; the list's own place is not kept.
  void _open(Change? change) {
    setState(() => _opened = change);
    if (_scroller.hasClients) _scroller.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final services = _services;
    final row = services != null && services.signedIn ? services.orgs?.orgRow(widget.orgId) : null;
    final name = row?.name ?? 'the organization';
    final now = _now();

    // The notes filed in its workspace, the archived among them: their changes happened too.
    final workspaceId = orgWorkspaceId(widget.orgId);
    final filed = services?.workspaces?.value.of ?? const <String, String>{};
    final here = [for (final note in widget.notes) if (filed[note.id] == workspaceId) note];
    final ids = [for (final note in here) note.id];
    final titles = {for (final note in here) note.id: noteTitle(note.body).isEmpty ? 'Untitled' : noteTitle(note.body)};
    if (ids.join('\n') != _watched.join('\n')) {
      _watched = ids;
      _across?.watch(ids);
    }
    final read = _across?.value ?? const ChangesRead();
    final news = services?.newsOf(widget.orgId) ?? const <FeedNotification>[];
    // Switched off from their More (lib/core/versions_record.dart): their changes since are not here.
    final versions = _prefs.value.versions;
    final off = [for (final note in here) if (versions[note.id] == false) note];

    final q = _query.trim().toLowerCase();
    final only = _only;
    final all = <_Entry>[
      if (_shown != 'team')
        for (final change in read.changes) _Entry.change('${change.noteId}:${change.n}', change.at, change),
      if (_shown != 'notes' && only == null)
        for (final n in news) _Entry.news(n.id, n.at, n),
    ];
    // Newest first; a stable sort, as the page's is.
    final placed = [for (var i = 0; i < all.length; i++) (i, all[i])]..sort((a, b) => a.$2.at != b.$2.at ? b.$2.at.compareTo(a.$2.at) : a.$1.compareTo(b.$1));
    final entries = [
      for (final (_, entry) in placed)
        if (entry.change case final change?)
          if ((only == null || change.noteId == only) && (q.isEmpty || [titles[change.noteId] ?? '', authorName(change.by), change.label ?? ''].any((words) => words.toLowerCase().contains(q)))) entry else ...[]
        else if (q.isEmpty || sentenceOf(entry.news!).toLowerCase().contains(q))
          entry,
    ];
    final days = <({String day, List<_Entry> entries})>[];
    for (final entry in entries) {
      final day = logDayOf(entry.at, now: now);
      if (days.isNotEmpty && days.last.day == day) {
        days.last.entries.add(entry);
      } else {
        days.add((day: day, entries: [entry]));
      }
    }

    final people = {for (final change in read.changes) change.by}.length;
    final reading = read.read < read.total;
    final narrowed = _shown != 'all' || q.isNotEmpty || only != null;
    final figures = reading
        ? 'Reading the history… ${read.read} of ${_count(read.total, 'note', 'notes')}'
        : '${_count(read.changes.length, 'change', 'changes')} across ${_count(here.length, 'note', 'notes')}${people != 0 ? ' · ${_count(people, 'person', 'people')}' : ''}${narrowed ? ' · ${_count(entries.length, 'line', 'lines')} shown' : ''}';
    final asides = [
      if (off.isNotEmpty) 'History is off for ${listWords([for (final note in off.take(3)) titles[note.id] ?? 'Untitled'])}${off.length > 3 ? ' and ${_count(off.length - 3, 'more', 'more')}' : ''}.',
      if (read.damaged != 0) read.damaged == 1 ? 'One version couldn’t be read, and is left out.' : '${read.damaged} versions couldn’t be read, and are left out.',
    ];

    final safeTop = t.len('app-safe-top');
    final lg = t.fontSize('lg');
    final sm = t.fontSize('sm');
    final bar = safeTop + t.space(2) * 2 + math.max(t.space(8), normalLine(t, lg, weight: 'semibold'));
    final under = bar.roundToDouble();
    final top = math.max(under, safeTop) + t.space(4);
    final foot = t.len('app-safe-bottom') + t.space(10);
    final opened = _opened;

    Widget tools(bool wide) {
      final search = _Filter(controller: _field, focusNode: _focus, filled: q.isNotEmpty, onQuery: (words) => setState(() => _query = words));
      final kinds = Semantics(
        container: true,
        label: 'What the log shows',
        explicitChildNodes: true,
        child: Wrap(
          spacing: t.space(2),
          runSpacing: t.space(2),
          alignment: wide ? WrapAlignment.end : WrapAlignment.start,
          children: [
            for (final (value, words) in const [('all', 'Everything'), ('notes', 'Notes'), ('team', 'Team')])
              OrgPill(key: ValueKey('log-kind-$value'), label: words, showHue: false, pressed: _shown == value, onPressed: () => setState(() => _shown = value)),
            if (only != null)
              OrgPill(
                key: const ValueKey('log-only'),
                label: titles[only] ?? 'One note',
                semanticLabel: 'Only ${titles[only] ?? 'one note'}; press for every note',
                showHue: false,
                dashed: true,
                leading: const AppIcon(Lucide.fileText, size: 13, strokeWidth: 2.2),
                trailing: const AppIcon(Lucide.x, size: 13, strokeWidth: 2.4),
                onPressed: () => setState(() => _only = null),
              ),
          ],
        ),
      );
      return wide ? Row(children: [Expanded(child: search), SizedBox(width: t.space(3)), kinds]) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [search, SizedBox(height: t.space(3)), kinds]);
    }

    Widget log(bool wide) {
      final xl = t.fontSize('xl');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          tools(wide),
          SizedBox(height: t.space(4)),
          Semantics(
            liveRegion: true,
            child: Text(figures, key: const ValueKey('log-figures'), style: pageText(t, sm, color: t.color('app-ink-2')).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          for (final words in asides) ...[SizedBox(height: t.space(1)), Text(words, style: pageText(t, sm, color: t.color('app-ink-3')))],
          if (days.isNotEmpty) ...[
            SizedBox(height: t.space(5)),
            for (var i = 0; i < days.length; i++) ...[
              if (i > 0) SizedBox(height: t.space(3)),
              LogDay(
                day: days[i].day,
                children: [
                  for (final entry in days[i].entries)
                    if (entry.change case final change?)
                      _ChangeLine(key: ValueKey('log:${entry.key}'), change: change, title: titles[change.noteId] ?? 'Untitled', now: now, onOpen: _open)
                    else
                      _NewsLine(key: ValueKey('log:${entry.key}'), n: entry.news!),
                ],
              ),
            ],
            SizedBox(height: t.space(4)),
          ] else if (!reading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(6)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Ghost(scene: narrowed ? GhostScene.searchNothing : GhostScene.emptyWorkspace, size: GhostSize.small, color: t.color('app-ink-3')),
                  SizedBox(height: t.space(4)),
                  Text(narrowed ? 'Nothing matches.' : 'Nothing has changed here yet.', style: pageText(t, xl, weight: 'semibold', tracking: t.len('app-tracking-title', em: xl), color: t.color('glacier-text-subtle'))),
                  SizedBox(height: t.space(2)),
                  Text(
                    narrowed ? 'Try other words, or show everything again.' : 'Every version of a note filed in $name, and what the team does, shows here as it happens.',
                    style: pageText(t, t.fontSize('md'), color: t.color('glacier-text-muted')),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final column = LayoutBuilder(
      builder: (context, box) {
        // `@container org-log (min-width: 44rem)`
        final wide = box.maxWidth >= t.lenOf('44rem');
        if (opened == null) return log(wide);
        return _Opened(
          key: ValueKey('${opened.noteId}:${opened.n}'),
          change: opened,
          title: titles[opened.noteId] ?? 'Untitled',
          record: widget.record,
          onBack: () => _open(null),
          onOpenNote: () => widget.onOpenNote(opened.noteId),
          onOnly: () {
            setState(() {
              _only = opened.noteId;
              _shown = 'all';
            });
            _open(null);
          },
        );
      },
    );
    final Widget scroller = SingleChildScrollView(
      key: const ValueKey('organization-log-scroll'),
      controller: _scroller,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), top, t.len('app-gutter-end'), foot),
      child: column,
    );

    return GlacierScope(
      attrs: {'hue': row?.hue ?? 'ink'},
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: widget.wisp ? WispEdge(under: under, child: scroller) : scroller),
              HeaderPane(
                child: Padding(
                  key: const ValueKey('organization-log-bar'),
                  padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start') - t.space(2), t.space(2), t.len('app-gutter-end'), t.space(2)),
                  child: Row(
                    spacing: t.space(2),
                    children: [
                      GlacierPressable(
                        key: const ValueKey('organization-log-back'),
                        onPressed: widget.onBack,
                        semanticLabel: 'Back to $name',
                        builder: (context, state) => GlacierFocusRing(
                          visible: state.focused,
                          child: SizedBox.square(dimension: t.space(8), child: Center(child: AppIcon(Lucide.arrowLeft, size: 20, color: t.color('app-ink')))),
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Row(
                            spacing: t.space(2),
                            children: [
                              ExcludeSemantics(child: HueRound(hue: row?.hue, size: 0.6 * lg)),
                              Flexible(
                                child: Text(
                                  row?.name ?? 'Organization',
                                  style: pageText(t, lg, weight: 'semibold', tracking: t.len('app-tracking-title', em: lg), color: t.color('app-ink')),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // `.titleWhat::before { content: '·'; margin-inline-end: var(--glacier-space-2) }`
                              Text.rich(
                                TextSpan(children: [const TextSpan(text: '·'), WidgetSpan(child: SizedBox(width: t.space(2))), const TextSpan(text: 'Audit log')]),
                                style: pageText(t, lg, tracking: t.len('app-tracking-title', em: lg), color: t.color('app-ink-3')),
                                softWrap: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The filter, in All notes' pill (`.search`, `.searchMark`, `.field`, `.clear`).
class _Filter extends StatelessWidget {
  const _Filter({required this.controller, required this.focusNode, required this.filled, required this.onQuery});
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool filled;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final style = pageText(t, md, color: t.color('app-ink'));
    final focused = focusNode.hasFocus;
    const words = 'Filter by note, person or name';
    return Semantics(
      label: 'Filter the log',
      textField: true,
      onTap: focusNode.requestFocus,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: focusNode.requestFocus,
        child: Container(
          key: const ValueKey('log-filter'),
          padding: EdgeInsetsDirectional.only(start: t.space(3), end: t.space(1)),
          decoration: BoxDecoration(
            color: t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)'),
            border: Border.all(color: focused ? t.color('glacier-border-strong') : t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: Row(
            spacing: t.space(2),
            children: [
              AppIcon(Lucide.search, size: 16, strokeWidth: 2.2, color: focused ? t.color('app-ink-2') : t.color('app-ink-3')),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: t.space(8)),
                  child: Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [
                      if (controller.text.isEmpty) ExcludeSemantics(child: Text(words, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(color: t.color('app-ink-3')))),
                      EditableText(
                        controller: controller,
                        focusNode: focusNode,
                        style: style,
                        cursorColor: t.color('app-ink'),
                        cursorWidth: 1,
                        backgroundCursorColor: t.color('app-ink-3'),
                        selectionColor: focused ? t.color('glacier-selection') : null,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                        enableSuggestions: false,
                        spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                        textCapitalization: TextCapitalization.none,
                        onChanged: onQuery,
                        keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
                      ),
                    ],
                  ),
                ),
              ),
              if (filled)
                GlacierPressable(
                  key: const ValueKey('log-filter-clear'),
                  onPressed: () {
                    controller.clear();
                    onQuery('');
                    focusNode.requestFocus();
                  },
                  semanticLabel: 'Clear the filter',
                  builder: (context, state) => GlacierFocusRing(
                    visible: state.focused,
                    child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)')),
                      child: AppIcon(Lucide.x, size: 14, strokeWidth: 2.4, color: t.color('app-ink-2')),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A day of the timeline (`.dayName`, `.entries` and its line down the authors' rings).
class LogDay extends StatelessWidget {
  const LogDay({super.key, required this.day, required this.children});
  final String day;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    return Semantics(
      container: true,
      label: day,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Text(day.toUpperCase(), style: pageText(t, xs, weight: 'medium', tracking: 0.06 * xs, color: t.color('app-ink-3')))),
          SizedBox(height: t.space(1)),
          CustomPaint(
            // `.entries::before`: a line a pixel wide down the middle of the rings, a `--glacier-space-3` in from each end.
            painter: _Rail(x: t.space(2) + t.lenOf('0.875rem') - 0.5, inset: t.space(3), color: t.colorOf('color-mix(in oklch, var(--app-ink) 22%, transparent)')),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
          ),
        ],
      ),
    );
  }
}

class _Rail extends CustomPainter {
  const _Rail({required this.x, required this.inset, required this.color});
  final double x;
  final double inset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= inset * 2) return;
    canvas.drawRect(Rect.fromLTWH(x, inset, 1, size.height - inset * 2), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Rail old) => old.x != x || old.inset != inset || old.color != color;
}

/// Who made a version, as a round mark with their first letter (`Author`, `.author`); or, with [child], the ring
/// round a kind of news's mark (`.newsRing`).
class AuthorRing extends StatelessWidget {
  const AuthorRing({super.key, this.by, this.child});
  final String? by;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final by = this.by ?? '';
    final letter = (by == 'me' ? 'Y' : (by.isEmpty ? '?' : by.substring(0, 1))).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: t.lenOf('1.75rem'),
        height: t.lenOf('1.75rem'),
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-paper'), border: Border.all(color: t.color('app-rule'))),
        child: child ?? Text(letter, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: t.color('app-ink-2'))),
      ),
    );
  }
}

/// A change on the timeline (`ChangeLine`): its author's ring, who did what to which note, when, its name, how much
/// and the first line.
class _ChangeLine extends StatelessWidget {
  const _ChangeLine({super.key, required this.change, required this.title, required this.now, required this.onOpen});
  final Change change;
  final String title;
  final int now;
  final ValueChanged<Change> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final rem = t.lenOf('1rem');
    final did = didWords(change);
    final label = change.label;
    final peek = change.peek;
    final quiet = pageText(t, sm, color: t.color('app-ink-3'));
    return GlacierPressable(
      onPressed: () => onOpen(change),
      semanticLabel: '${authorName(change.by)} $did $title, version ${change.n}${label != null && label.isNotEmpty ? ', $label' : ''}, ${_ago(change.at, now)}',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('md'),
        offset: 1,
        child: Container(
          key: const ValueKey('log-change'),
          padding: EdgeInsets.all(t.space(2)),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('md')), color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 5%, transparent)') : null),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthorRing(by: change.by),
              SizedBox(width: t.space(3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: t.space(2),
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(authorName(change.by), style: pageText(t, rem, weight: 'medium', color: t.color('app-ink'))),
                        Text(did, style: pageText(t, rem, color: t.color('app-ink-2'))),
                        Text(title, style: pageText(t, rem, weight: 'medium', color: t.color('app-ink'))),
                        Text(logClock(change.at), style: quiet),
                        if (label != null && label.isNotEmpty)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 0.5 * t.fontSize('xs')),
                            decoration: ShapeDecoration(shape: StadiumBorder(side: BorderSide(color: t.color('app-rule')))),
                            child: Text(label, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-2'))),
                          ),
                      ],
                    ),
                    SizedBox(height: 0.15 * rem),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          change.first ? 'First version' : (change.added != 0 || change.removed != 0 ? '+${change.added} −${change.removed}' : 'Named'),
                          style: pageText(t, sm, color: t.color('app-ink-2')).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        if (peek != null) ...[
                          SizedBox(width: t.space(2)),
                          Expanded(
                            child: Text(
                              '${peek.kind == 'add' ? '+ ' : '− '}${peek.text}',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: pageText(t, sm, mono: true, color: t.color('app-ink-3')).copyWith(decoration: peek.kind == 'del' ? TextDecoration.lineThrough : null),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: t.space(3)),
              Padding(
                padding: EdgeInsets.only(top: 0.1 * sm),
                child: Text('v${change.n}', style: quiet.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A piece of the team's news on the same line (the log's `NewsLine`): the kind's mark in a ring, its sentence as
/// the drawer words it, when.
class _NewsLine extends StatelessWidget {
  const _NewsLine({super.key, required this.n});
  final FeedNotification n;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rem = t.lenOf('1rem');
    return Padding(
      padding: EdgeInsets.all(t.space(2)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthorRing(child: OrgNewsMark(kind: n.kind, fallback: t.color('app-ink-2'))),
          SizedBox(width: t.space(3)),
          Expanded(
            child: Wrap(
              spacing: t.space(2),
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(sentenceOf(n), style: pageText(t, rem, color: t.color('app-ink-2'))),
                Text(logClock(n.at), style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A change opened (`Opened`): what that version changed against the one before, read from the note's file now
/// (the log keeps only each change's line), with the way to the note and to only its changes.
class _Opened extends StatefulWidget {
  const _Opened({super.key, required this.change, required this.title, required this.record, required this.onBack, required this.onOpenNote, required this.onOnly});
  final Change change;
  final String title;
  final VersionsRecord? record;
  final VoidCallback onBack;
  final VoidCallback onOpenNote;
  final VoidCallback onOnly;

  @override
  State<_Opened> createState() => _OpenedState();
}

class _OpenedState extends State<_Opened> {
  StreamSubscription<VersionsRead>? _watching;
  List<Version>? _versions;

  @override
  void initState() {
    super.initState();
    _watching = widget.record?.watch(widget.change.noteId).listen((read) {
      if (mounted) setState(() => _versions = read.versions);
    });
  }

  @override
  void dispose() {
    unawaited(_watching?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final change = widget.change;
    final sm = t.fontSize('sm');
    final xl = t.fontSize('xl');
    final rem = t.lenOf('1rem');
    final versions = _versions;
    Version? version;
    for (final each in versions ?? const <Version>[]) {
      if (each.n == change.n && each.at == change.at) version = each;
    }
    final before = version != null && version.n >= 2 && versions!.length >= version.n - 1 ? versions[version.n - 2].text : null;
    final label = change.label;
    final quiet = pageText(t, sm, color: t.color('app-ink-3'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `.toLog` (VersionHistory.module.css `.back`)
        GlacierPressable(
          key: const ValueKey('log-to-log'),
          onPressed: widget.onBack,
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(1)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(Lucide.arrowLeft, size: 24, color: t.color('glacier-text')),
                  SizedBox(width: t.space(2)),
                  Text('The log', style: pageText(t, rem, weight: 'medium', color: t.color('glacier-text'))),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: t.space(3)),
        Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              text: widget.title,
              children: [TextSpan(text: ' · Version ${change.n}${label != null && label.isNotEmpty ? ' · $label' : ''}', style: pageText(t, xl, tracking: t.len('app-tracking-title', em: xl), color: t.color('app-ink-3')))],
            ),
            style: pageText(t, xl, weight: 'semibold', tracking: t.len('app-tracking-title', em: xl), color: t.color('app-ink')),
          ),
        ),
        SizedBox(height: t.space(3)),
        Row(
          children: [
            AuthorRing(by: change.by),
            SizedBox(width: t.space(2)),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: authorName(change.by), style: pageText(t, sm, weight: 'medium', color: t.color('app-ink-2'))),
                    TextSpan(text: ' ${didWords(change)} it · ${logDateTime(change.at)}'),
                  ],
                ),
                style: pageText(t, sm, color: t.color('app-ink-2')),
              ),
            ),
          ],
        ),
        SizedBox(height: t.space(3) + t.space(4)),
        Semantics(header: true, child: Text(change.first ? 'The note as it began' : 'What this version changed', style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2')))),
        SizedBox(height: t.space(2)),
        if (versions == null && widget.record != null)
          Text('Reading the version…', style: quiet)
        else if (version == null)
          Text('This version is not in the note’s file any more.', style: quiet)
        else if (change.first && version.text.trim().isEmpty)
          Text('It began empty.', style: quiet)
        else
          VersionChange(from: before, to: version.text, label: 'What this version changed', same: 'The same words as the version before, named.'),
        SizedBox(height: t.space(4)),
        Wrap(
          spacing: t.space(2),
          runSpacing: t.space(2),
          children: [
            OrgAction(key: const ValueKey('log-open-note'), label: 'Open the note', icon: const AppIcon(Lucide.fileText, size: 15, strokeWidth: 2.1), onPressed: widget.onOpenNote),
            OrgAction(key: const ValueKey('log-only-this'), label: 'Only this note', icon: const AppIcon(Lucide.listFilter, size: 15, strokeWidth: 2.1), onPressed: widget.onOnly),
          ],
        ),
      ],
    );
  }
}

/// How many lines that stay are shown round a change (`CONTEXT`, editor/VersionHistory.tsx).
const int _context = 2;

/// The lines that go from [from] to [to], and the lines that come, with a little of what stays around them
/// (`Change`, editor/VersionHistory.tsx; `.change`, `.line`, `.mark`).
class VersionChange extends StatelessWidget {
  const VersionChange({super.key, required this.from, required this.to, required this.label, this.same = 'The note says exactly this now.'});
  final String? from;
  final String to;
  final String label;
  final String same;

  /// The rows the diff draws: `same`, `del`, `add` or `fold`, and the words.
  static List<({String kind, String text})> rowsOf(String? from, String to) {
    final before = linesFrom(from);
    final steps = diffLines(before, linesOf(to));
    final rows = <({String kind, String text})>[];
    var at = 0;
    for (var index = 0; index < steps.length; index++) {
      final step = steps[index];
      switch (step) {
        case Keep(:final count):
          final lines = before.sublist(at, at + count);
          at += count;
          final head = index == 0 ? 0 : _context;
          final tail = index == steps.length - 1 ? 0 : _context;
          if (lines.length <= head + tail + 1) {
            rows.addAll([for (final text in lines) (kind: 'same', text: text)]);
          } else {
            rows.addAll([for (final text in lines.take(head)) (kind: 'same', text: text)]);
            final folded = lines.length - head - tail;
            rows.add((kind: 'fold', text: folded == 1 ? '1 line the same' : '$folded lines the same'));
            rows.addAll([for (final text in lines.skip(lines.length - tail)) (kind: 'same', text: text)]);
          }
        case Del(:final line):
          at += 1;
          rows.add((kind: 'del', text: line));
        case Add(:final line):
          rows.add((kind: 'add', text: line));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final rows = rowsOf(from, to);
    if (!rows.any((row) => row.kind == 'add' || row.kind == 'del')) {
      return Text(same, style: pageText(t, sm, color: t.color('app-ink-3')));
    }
    return Semantics(
      container: true,
      label: label,
      explicitChildNodes: true,
      child: Container(
        key: const ValueKey('version-change'),
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: t.space(2)),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('md')), border: Border.all(color: t.color('app-rule'), width: snapBorder(context, t.len('glacier-hairline')))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows)
              Semantics(
                label: row.kind == 'add' ? 'Comes back: ${row.text}' : (row.kind == 'del' ? 'Goes: ${row.text}' : null),
                child: ColoredBox(
                  color: row.kind == 'add' ? t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)') : const Color(0x00000000),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: t.space(2)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 1.5 * sm, child: ExcludeSemantics(child: Text(row.kind == 'add' ? '+' : (row.kind == 'del' ? '−' : ''), style: pageText(t, sm, mono: true, height: 1.5, color: t.color('app-ink-3'))))),
                        Expanded(
                          child: Text(
                            row.kind == 'fold' ? row.text : (row.text.isEmpty ? ' ' : row.text),
                            style: pageText(
                              t,
                              sm,
                              mono: row.kind != 'fold',
                              height: 1.5,
                              color: row.kind == 'add' ? t.color('app-ink') : (row.kind == 'same' ? t.color('app-ink-2') : t.color('app-ink-3')),
                            ).copyWith(decoration: row.kind == 'del' ? TextDecoration.lineThrough : null, fontStyle: row.kind == 'fold' ? FontStyle.italic : null),
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
    );
  }
}
