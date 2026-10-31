import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/notifications.dart';
import '../core/preferences.dart' show NotificationPrefs;
import '../sheet/css.dart';
import 'floating_card.dart';
import 'when.dart';
import '../shell/wide_screen.dart' show hoverPointer;
import '../core/iphone_app.dart' show recordsVoice;

/// The notifications, in a drawer hung from the bell (docs/TEAMS.md; Matt: "implement a full notification system and
/// put the invites in there with an inline accept and deny"). A port of `src/app/notes/NotificationsDrawer.tsx` and
/// `NotificationsDrawer.module.css`.
///
/// It is the floating card the notes drawer and the aside are ([FloatingCard]), at the right under the bell, a
/// little wider than theirs and never the window's width: the page stays live beside it, and a press outside it,
/// Escape, the back gesture or the bell again closes it. Its head is the name with the count of unread, Mark all
/// read, Clear all, and a close; under it the rows scroll inside the card. A row is its kind's mark, its sentence
/// (core/notifications.dart [sentenceOf]) wrapped whole, the first line Claude changed under it on up to two lines,
/// and when. An invitation carries Accept and Decline inline. A row about a note opens the note - an edit at its
/// first changed line - and a row about an organization opens the organization, each read as it is tapped and the
/// drawer closed behind it. What Settings › Notifications switched off, and a muted organization's news, is not
/// drawn; an invitation always is.
///
/// What differs from the web, all of it because the feed is a later stage (account and sync):
/// - The rows are [notifications], handed in as the feed would list them ([listed]), where the web read its feed;
///   and what the person does is told to the caller ([onMarkRead], [onMarkAllRead], [onHide], [onHideAll]) rather
///   than done to it.
/// - [signedIn], [localOnly] and [prefs] are handed in, where the web read the account and the preferences.
/// - A sealed row's words are asked of [detailsOf] (the web's `openDetails`, which opens the seal under the account
///   key); without it every sealed row is drawn by its kind alone.
/// - [memberOf] is the organizations the person is still in, which the web read from its own list.
/// - [onOpened] is told once as the drawer opens, when nothing holds the feed: the web took the feed again there
///   (`syncNotificationsNow`).
/// - Accept and Decline are this file's own pair (the web's `settings/InviteActions.tsx`, shared with the home page
///   and Settings, which are not ported): [onAnswerInvite] gives the answer and says what went wrong, if anything.
/// - [emptyArt] is the small ghost with everything ticked (`Ghost scene="all-ticked" size="small"`), lib/art's to
///   draw; without it the words stand alone.
/// - The icon that opens it is wrapped in a [FloatingCardToggle] named [notificationsToggle].
/// - The cross that clears a row waits to be pointed at on a desktop and never on a phone, which is how `@media
///   (hover: hover)` is answered on each (shell/wide_screen.dart `hoverPointer`).
class NotificationsDrawer extends StatefulWidget {
  const NotificationsDrawer({
    super.key,
    required this.notifications,
    required this.onClose,
    required this.onOpenNote,
    required this.onOpenOrganization,
    required this.onAccount,
    this.prefs = const NotificationPrefs(),
    this.signedIn = true,
    this.localOnly = false,
    this.memberOf = const {},
    this.detailsOf,
    this.onMarkRead,
    this.onMarkAllRead,
    this.onHide,
    this.onHideAll,
    this.onAnswerInvite,
    this.onOpened,
    this.emptyArt,
    this.now,
    this.onUnwatch,
  });

  /// The rows as the feed lists them: of a kind this build knows, not hidden, newest first.
  final List<FeedNotification> notifications;
  final VoidCallback onClose;

  /// A note a row is about, opened: `at` is the line an edit landed on, as the note screen takes it.
  final void Function(String id, String? at) onOpenNote;

  /// An organization a row is about, opened.
  final void Function(String orgId) onOpenOrganization;

  /// Settings at Account, from the signed-out words.
  final VoidCallback onAccount;
  final NotificationPrefs prefs;
  final bool signedIn;
  final bool localOnly;

  /// The ids of the organizations the person is a member of.
  final Set<String> memberOf;

  /// A sealed row's payload once it has been opened, or null while it is sealed or will not open.
  final NotificationDetails? Function(FeedNotification row)? detailsOf;
  final void Function(String id)? onMarkRead;
  final VoidCallback? onMarkAllRead;
  final void Function(String id)? onHide;
  final void Function(List<String> ids)? onHideAll;

  /// The invitation to an organization answered. What it answers is shown under the two words when it is not null:
  /// the service's words for an answer that did not arrive.
  final Future<String?> Function(String orgId, bool accept)? onAnswerInvite;
  final VoidCallback? onOpened;
  final Widget? emptyArt;

  /// This moment, in ms, for "2 hr ago"; the clock's when left out.
  final int? now;

  /// A ticket's change told to this account as one of its watchers: the ticket's note, to watch no more
  /// (lib/book/ticket_events.dart). Absent, its row offers no Unwatch.
  final void Function(String noteId)? onUnwatch;

  @override
  State<NotificationsDrawer> createState() => _NotificationsDrawerState();
}

class _NotificationsDrawerState extends State<NotificationsDrawer> {
  bool get _held => !widget.signedIn || widget.localOnly;

  /// The Mentions filter (Matt, 2026-10-30: "add all 12"): only the rows where someone named you.
  bool _mentionsOnly = false;

  @override
  void initState() {
    super.initState();
    // Opened: the feed taken again now, so what arrived while the app was away is here before the drawer is read.
    if (!_held) WidgetsBinding.instance.addPostFrameCallback((_) => widget.onOpened?.call());
  }

  @override
  void didUpdateWidget(NotificationsDrawer old) {
    super.didUpdateWidget(old);
    final was = !old.signedIn || old.localOnly;
    if (was && !_held) widget.onOpened?.call();
  }

  void _open(FeedNotification n) {
    if (n.readAt == null) widget.onMarkRead?.call(n.id);
    final details = widget.detailsOf?.call(n);
    if (details != null) {
      widget.onClose();
      // An edit at its first changed line, a mention at the line that names the person.
      widget.onOpenNote(details.noteId, details.kind == 'note-edited' || details.kind == 'mention' ? details.at : null);
      return;
    }
    // An organization the person is still in; a row about one they left or that is gone only reads.
    final org = n.org;
    if (orgKinds.contains(n.kind) && org != null && widget.memberOf.contains(org.id)) {
      widget.onClose();
      widget.onOpenOrganization(org.id);
    }
  }

  void _toAccount() {
    widget.onClose();
    widget.onAccount();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Signed out there is no feed, and so no rows (`notifications()` answers none); with Local only on, the rows the
    // device holds still count in the head, under the words that say nothing more is coming.
    final all = widget.signedIn ? widget.notifications : const <FeedNotification>[];
    final wanted = [for (final n in all) if (isWanted(n, widget.prefs)) n];
    // The filter is there once someone has mentioned you; with it on, only those rows.
    final mentioned = wanted.any(isMention);
    final filtering = _mentionsOnly && mentioned;
    final shown = filtering ? [for (final n in wanted) if (isMention(n)) n] : wanted;
    final unread = unreadCount(widget.prefs, all);
    // What Clear all takes: every row shown but an invitation still waiting for its answer, which would go with no
    // way back to it.
    final clearable = [for (final n in shown) if (!isPendingInvite(n)) n];
    final hairline = snapBorder(context, t.len('glacier-hairline'));
    final sm = t.fontSize('sm');
    final md = t.fontSize('md');

    final Widget inside;
    if (_held) {
      // `.held { margin: var(--glacier-space-3) var(--glacier-space-2); font-size: sm; line-height: var(--glacier-leading-sm); color: var(--app-ink-2) }`
      final style = pageText(t, sm, color: t.color('app-ink-2'), height: t.len('glacier-leading-sm'));
      InlineSpan go(String word) => WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: _GoWord(word, style: style, onPress: _toAccount));
      inside = Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(3), horizontal: t.space(2)),
        child: CssLines(
          line: sm * t.len('glacier-leading-sm'),
          child: Text.rich(
          TextSpan(
            style: style,
            children: widget.signedIn
                ? [go('Local only'), const TextSpan(text: ' is on, so nothing arrives until it is off.')]
                : [
                    TextSpan(text: 'Notifications come with an account: an invitation to a team, what Claude wrote${recordsVoice ? ', a meeting written up' : ''}. Sign in under '),
                    go('Account'),
                    const TextSpan(text: '.'),
                  ],
          ),
          ),
        ),
      );
    } else if (shown.isEmpty) {
      // `.empty { display: flex; flex-direction: column; align-items: center; gap: var(--glacier-space-1);
      // padding: var(--glacier-space-6) var(--glacier-space-4); text-align: center }`
      inside = Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(6), horizontal: t.space(4)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(1),
          children: [
            // `.emptyArt { margin-block-end: var(--glacier-space-2) }`
            if (widget.emptyArt != null) Padding(padding: EdgeInsets.only(bottom: t.space(2)), child: widget.emptyArt),
            Text('Nothing yet.', textAlign: TextAlign.center, style: pageText(t, md, weight: 'medium', color: t.color('app-ink'))),
            cssLines(
              'Invitations, what Claude wrote and your meetings written up arrive here.',
              pageText(t, sm, color: t.color('app-ink-3'), height: t.len('glacier-leading-sm')),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      inside = Semantics(
        // `<ol aria-label="Notifications">`
        container: true,
        explicitChildNodes: true,
        label: 'Notifications',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, n) in shown.indexed)
              _Row(
                key: ValueKey('notification-${n.id}'),
                n: n,
                index: i,
                last: i == shown.length - 1,
                opened: widget.detailsOf?.call(n),
                now: widget.now,
                onOpen: () => _open(n),
                onClear: isPendingInvite(n) ? null : () => widget.onHide?.call(n.id),
                onAnswer: widget.onAnswerInvite,
                onUnwatch: widget.onUnwatch,
              ),
          ],
        ),
      );
    }

    return FloatingCard(
      side: FloatingCardSide.end,
      wide: true,
      label: 'Notifications',
      toggle: notificationsToggle,
      onClose: widget.onClose,
      // `.panel { display: flex; flex-direction: column; min-block-size: 0 }`
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            key: const ValueKey('notifications-head'),
            // `.head { border-block-end: var(--glacier-hairline) solid var(--app-rule) }`
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule'), width: hairline))),
            child: Padding(
              // `padding: var(--glacier-space-3) var(--glacier-space-3) var(--glacier-space-3) var(--glacier-space-4)`
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(3), t.space(3) + hairline),
              // `display: flex; align-items: center; gap: var(--glacier-space-2)`
              child: Row(
                spacing: t.space(2),
                children: [
                  // `.title { flex: 1; display: flex; align-items: center; gap: var(--glacier-space-2); min-inline-size: 0 }`:
                  // what room the words leave is the title's, and where that is less than it needs it is drawn past
                  // its own edge, as the page draws it.
                  Expanded(
                    child: OverflowBox(
                      alignment: AlignmentDirectional.centerStart,
                      minWidth: 0,
                      maxWidth: double.infinity,
                      fit: OverflowBoxFit.deferToChild,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: t.space(2),
                        children: [
                          Semantics(
                            header: true,
                            // `font-size: md; font-weight: semibold; letter-spacing: var(--app-tracking-title); color: var(--app-ink)`
                            child: Text('Notifications', maxLines: 1, softWrap: false, style: pageText(t, md, weight: 'semibold', color: t.color('app-ink'), tracking: t.len('app-tracking-title', em: md))),
                          ),
                          // The count is the title's child, and takes its tracking with it.
                          if (unread > 0) _Count(unread, tracking: t.len('app-tracking-title', em: md)),
                        ],
                      ),
                    ),
                  ),
                  // Mark all read: the app's quiet word with the kit's double tick, there only while something is unread.
                  if (unread > 0) _Word(key: const ValueKey('mark-all-read'), icon: Lucide.checkCheck, word: 'Mark all read', onPressed: () => widget.onMarkAllRead?.call()),
                  if (clearable.isNotEmpty) _Word(key: const ValueKey('clear-all'), icon: Lucide.brushCleaning, word: 'Clear all', onPressed: () => widget.onHideAll?.call([for (final n in clearable) n.id])),
                  _Round(label: 'Close notifications', icon: Lucide.x, iconSize: 16, stroke: 2.2, side: t.lenOf('2rem'), ink: 'app-ink-2', wash: 6, onPressed: widget.onClose),
                ],
              ),
            ),
          ),
          if (mentioned && !_held) _Filter(mentions: filtering, onChanged: (mentions) => setState(() => _mentionsOnly = mentions)),
          Flexible(
            child: SingleChildScrollView(
              // `.scroll { overflow-y: auto; overscroll-behavior: contain; padding: var(--glacier-space-1) var(--glacier-space-2) var(--glacier-space-3) }`
              padding: EdgeInsets.fromLTRB(t.space(2), t.space(1), t.space(2), t.space(3)),
              child: inside,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bell's filter: every row, or the mentions alone.
class _Filter extends StatelessWidget {
  const _Filter({required this.mentions, required this.onChanged});
  final bool mentions;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    Widget pill(String word, bool on, bool value) => GlacierPressable(
          key: ValueKey('filter-${value ? 'mentions' : 'all'}'),
          onPressed: () => onChanged(value),
          semanticLabel: on ? '$word, shown' : word,
          builder: (context, state) => Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius('full')),
              color: on ? t.color('app-ink') : (state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 7%, transparent)') : null),
            ),
            child: Text(word, maxLines: 1, style: pageText(t, sm, weight: 'medium', color: on ? t.color('app-paper') : t.color('app-ink-2'))),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), 0),
      child: Row(spacing: t.space(1), children: [pill('All', !mentions, false), pill('Mentions', mentions, true)]),
    );
  }
}

/// `.count`: the number unread, in the ink turned round.
class _Count extends StatelessWidget {
  const _Count(this.count, {required this.tracking});
  final int count;

  /// The `letter-spacing` it inherits, in px.
  final double tracking;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    return Container(
      key: const ValueKey('notifications-count'),
      // `display: inline-grid; place-items: center; min-inline-size: 1.5em; padding-inline: 0.45em;
      // border-radius: var(--glacier-radius-full); background: var(--app-ink); color: var(--app-paper)`
      constraints: BoxConstraints(minWidth: 1.5 * xs),
      padding: EdgeInsets.symmetric(horizontal: 0.45 * xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('full'))),
      // `font-size: xs; font-weight: semibold; font-variant-numeric: tabular-nums; line-height: 1.5`
      child: cssLines('$count', pageText(t, xs, weight: 'semibold', color: t.color('app-paper'), height: 1.5, tracking: tracking).copyWith(fontFeatures: [...t.typography.features, const FontFeature.tabularFigures()])),
    );
  }
}

/// `.app-word` as the drawer wears it. In the head (`.readAll`) it is a mark and a word in the second ink at the
/// small size; under an invitation it is Accept or Decline at the page's own size.
class _Word extends StatelessWidget {
  const _Word({super.key, this.icon, required this.word, required this.onPressed, this.size, this.weight = 'medium', this.ink = 'app-ink-2'});
  final LucideIcon? icon;
  final String word;
  final VoidCallback? onPressed;

  /// `font: inherit` where the class sets no size; `.readAll { font-size: var(--glacier-font-size-sm) }`.
  final double? size;
  final String weight;
  final String ink;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final px = size ?? t.fontSize('sm');
    return GlacierPressable(
      onPressed: onPressed,
      builder: (context, state) {
        // `.app-word:active { color: var(--glacier-text) }`; `.app-word:disabled { color: var(--glacier-text-subtle) }`
        final color = state.disabled
            ? t.color('glacier-text-subtle')
            : state.pressed
                ? t.color('glacier-text')
                : t.color(ink);
        return GlacierFocusRing(
          // `.app-word:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: 2px; border-radius: var(--glacier-radius-sm) }`
          visible: state.focused,
          radius: t.radius('sm'),
          child: ConstrainedBox(
            // `.app-word { padding: var(--glacier-space-2) 0; min-block-size: var(--glacier-space-12) }`
            constraints: BoxConstraints(minHeight: t.space(12)),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(2)),
              // `.readAll { display: inline-flex; align-items: center; gap: 0.35em; white-space: nowrap }`
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 0.35 * px,
                children: [
                  if (icon != null) ExcludeSemantics(child: lucide(icon!, size: 15, strokeWidth: 2.2, color: color)),
                  Text(word, maxLines: 1, softWrap: false, style: pageText(t, px, weight: weight, color: color)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `.close` and `.clear`: a round bare button, lit when pointed at.
class _Round extends StatelessWidget {
  const _Round({required this.label, required this.icon, required this.iconSize, required this.stroke, required this.side, required this.ink, required this.wash, required this.onPressed});
  final String label;
  final LucideIcon icon;
  final double iconSize;

  /// `strokeWidth={…}`: 2.2 on the head's Close, 2.4 on a row's Clear.
  final double stroke;
  final double side;

  /// Its ink at rest; pointed at, it is `--app-ink`.
  final String ink;

  /// How much of the ink its ground is when pointed at, in percent.
  final int wash;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        // `:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: 1px }`
        visible: state.focused,
        offset: 1,
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          // `:hover { background: color-mix(in oklch, var(--app-ink) N%, transparent); color: var(--app-ink) }`
          decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) $wash%, transparent)') : null),
          child: ExcludeSemantics(child: lucide(icon, size: iconSize, strokeWidth: stroke, color: t.color(state.hovered ? 'app-ink' : ink))),
        ),
      ),
    );
  }
}

/// `GoWord` (`.app-word.setk-go`, settings/kit/settingsKit.tsx): a word in a sentence that goes somewhere, set in the
/// line as a word of it, in ink and underlined.
class _GoWord extends StatelessWidget {
  const _GoWord(this.word, {required this.style, required this.onPress});
  final String word;
  final TextStyle style;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    return GlacierPressable(
      onPressed: onPress,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('sm'),
        // `.app-word { font-weight: medium }`, `.setk-go { color: var(--app-ink); text-decoration: underline;
        // text-decoration-thickness: var(--glacier-hairline); text-underline-offset: 0.2em }`
        child: Text(
          word,
          style: pageText(t, style.fontSize!, weight: 'medium', color: ink, height: style.height).copyWith(decoration: TextDecoration.underline, decorationColor: ink, decorationThickness: 1),
        ),
      ),
    );
  }
}

/// Each kind's mark at the start of its row, from the kit (`MARKS`).
const Map<String, LucideIcon> _marks = {
  'invite': Lucide.mail,
  'invite-accepted': Lucide.userCheck,
  'invite-declined': Lucide.userX,
  'member-joined': Lucide.userPlus,
  'member-left': Lucide.userMinus,
  'member-removed': Lucide.userMinus,
  'role-changed': Lucide.crown,
  'org-renamed': Lucide.pencil,
  'org-deleted': Lucide.trash2,
  'note-created': Lucide.filePlus,
  'note-edited': Lucide.penLine,
  'note-appended': Lucide.listPlus,
  'journal-entry': Lucide.bookOpen,
  'rule-added': Lucide.scrollText,
  'summary-written': Lucide.audioLines,
  'sync-conflict': Lucide.triangleAlert,
  'form-answer': Lucide.ticket,
  'mention': Lucide.atSign,
  'page-expired': Lucide.shieldCheck,
  'ticket': Lucide.ticket,
  'ticket-digest': Lucide.sunrise,
};

/// One notification (`Row`): its mark, its sentence and the line under it, when, and Accept and Decline for an
/// invitation; and a cross that clears it out of the list, there on a hover with a mouse and always on a touch
/// screen.
class _Row extends StatefulWidget {
  const _Row({super.key, required this.n, required this.index, required this.last, required this.opened, required this.now, required this.onOpen, required this.onClear, required this.onAnswer, this.onUnwatch});

  final FeedNotification n;
  final int index;
  final bool last;
  final NotificationDetails? opened;
  final int? now;
  final VoidCallback onOpen;
  final VoidCallback? onClear;
  final Future<String?> Function(String orgId, bool accept)? onAnswer;
  final void Function(String noteId)? onUnwatch;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> with SingleTickerProviderStateMixin {
  /// `animation: rowRise 260ms var(--glacier-ease-out) both; animation-delay: calc(var(--i, 0) * 24ms)`.
  late final AnimationController _rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Timer? _wait;
  bool _started = false;
  bool _hovered = false;
  bool _clearHovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // `@media (prefers-reduced-motion: reduce) { .row { animation: none } }`
    if (context.tokens.reducedMotion) {
      _rise.value = 1;
      return;
    }
    // `style={{ '--i': Math.min(index, 12) }}`
    final delay = Duration(milliseconds: 24 * (widget.index < 12 ? widget.index : 12));
    if (delay == Duration.zero) {
      _rise.forward();
    } else {
      _wait = Timer(delay, _rise.forward);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = widget.n;
    final sentence = sentenceOf(n, widget.opened);
    final detail = detailOf(widget.opened);
    final pending = isPendingInvite(n);
    final answered = n.kind == 'invite' && !pending ? (n.state == 'accepted' ? 'Accepted' : 'Declined') : null;
    final unread = n.readAt == null;
    final sm = t.fontSize('sm');
    final xs = t.fontSize('xs');
    final leading = t.len('glacier-leading-sm');
    final hairline = snapBorder(context, t.len('glacier-hairline'));
    final rem = t.lenOf('1rem');
    final clear = widget.onClear;
    final org = n.org;

    // `.detail`: the first line Claude changed, or how an invitation was answered, on two lines at most.
    Widget line(String words) => cssLines(words, pageText(t, xs, color: t.color('app-ink-3'), height: leading), maxLines: 2, overflow: TextOverflow.ellipsis);

    final body = GlacierPressable(
      onPressed: widget.onOpen,
      builder: (context, state) => GlacierFocusRing(
        // `.body:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: -2px }`
        visible: state.focused,
        offset: -2,
        radius: t.radius('md'),
        child: DecoratedBox(
          // `.body:hover, .row:has(.clear:hover) .body { background: color-mix(in oklch, var(--app-ink) 5%, transparent) }`
          decoration: BoxDecoration(
            color: state.hovered || _clearHovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 5%, transparent)') : null,
            borderRadius: BorderRadius.circular(t.radius('md')),
          ),
          child: Padding(
            // `padding: var(--glacier-space-3) var(--glacier-space-2)`, and room at the body's end for the cross
            // that lies over it: `.row:has(.clear) .body { padding-inline-end: calc(1.75rem + var(--glacier-space-3)) }`.
            padding: EdgeInsets.fromLTRB(t.space(2), t.space(3), clear != null ? 1.75 * rem + t.space(3) : t.space(2), t.space(3)),
            // `display: grid; grid-template-columns: auto minmax(0, 1fr) auto; align-items: start; column-gap: var(--glacier-space-3)`
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: t.space(3),
              children: [
                _KindRound(kind: n.kind, unread: unread),
                Expanded(
                  // `.words { display: flex; flex-direction: column; gap: 0.15rem }`
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 0.15 * rem,
                    children: [
                      // `.sentence { font-size: sm; line-height: var(--glacier-leading-sm); color: var(--app-ink-2) }`,
                      // `.row[data-unread] .sentence { color: var(--app-ink); font-weight: medium }`
                      cssLines(sentence, pageText(t, sm, weight: unread ? 'medium' : 'regular', color: t.color(unread ? 'app-ink' : 'app-ink-2'), height: leading)),
                      if (detail != null) line(detail),
                      if (answered != null) line(answered),
                    ],
                  ),
                ),
                Padding(
                  // `.when { padding-block-start: 0.1em; font-size: xs; font-variant-numeric: tabular-nums; color: var(--app-ink-3); white-space: nowrap }`
                  padding: EdgeInsets.only(top: 0.1 * xs),
                  child: Text(
                    when(n.at, widget.now),
                    maxLines: 1,
                    softWrap: false,
                    style: pageText(t, xs, color: t.color('app-ink-3')).copyWith(fontFeatures: [...t.typography.features, const FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final ease = t.curve('glacier-ease-out');
    return AnimatedBuilder(
      animation: _rise,
      // `@keyframes rowRise { from { opacity: 0; transform: translateY(4px) } }`
      builder: (context, child) {
        final at = ease.transform(_rise.value);
        return Opacity(opacity: at, child: Transform.translate(offset: Offset(0, 4 * (1 - at)), child: child));
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: DecoratedBox(
          // `.row { border-block-end: var(--glacier-hairline) solid var(--app-rule) }`; `.row:last-child { border-block-end: 0 }`
          decoration: BoxDecoration(border: widget.last ? null : Border(bottom: BorderSide(color: t.color('app-rule'), width: hairline))),
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.last ? 0 : hairline),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The body spans the whole row and the cross sits over its end, so the cross is inside the card
                // the body's wash draws, not beside it.
                Stack(
                  children: [
                    body,
                    if (clear != null)
                      Positioned(
                        // `.clear { margin: var(--glacier-space-2) var(--glacier-space-2) 0 0 }`
                        top: t.space(2),
                        right: t.space(2),
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _clearHovered = true),
                          onExit: (_) => setState(() => _clearHovered = false),
                          child: Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            child: Builder(
                              builder: (context) {
                                // `@media (hover: hover) { .clear { opacity: 0; transition: opacity 120ms ease }
                                // .row:hover .clear, .row:focus-within .clear { opacity: 1 } }`
                                final shown = !hoverPointer || _hovered || Focus.of(context).hasFocus;
                                return AnimatedOpacity(
                                  opacity: shown ? 1 : 0,
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.ease,
                                  child: _Round(label: 'Clear: $sentence', icon: Lucide.x, iconSize: 14, stroke: 2.4, side: 1.75 * rem, ink: 'app-ink-3', wash: 8, onPressed: clear),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // A ticket watched: Unwatch under its words, as an invitation's answers are.
                if (isTicketEvent(n) && widget.opened != null && widget.onUnwatch != null)
                  Padding(
                    // Under the line, in the words' column: up into the body's own foot, so it reads as the row's.
                    padding: EdgeInsets.fromLTRB(2 * rem + t.space(3) + t.space(2), 0, t.space(2), t.space(2)),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Transform.translate(
                        offset: Offset(0, -t.space(2)),
                        child: GlacierPressable(
                          key: ValueKey('unwatch-${n.id}'),
                          semanticLabel: 'Unwatch ${widget.opened!.title}',
                          onPressed: () => widget.onUnwatch!(widget.opened!.noteId),
                          builder: (context, state) => Padding(
                            padding: EdgeInsets.symmetric(vertical: t.space(1)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 0.35 * xs,
                              children: [
                                ExcludeSemantics(child: lucide(Lucide.eyeOff, size: 13, strokeWidth: 2.2, color: t.color(state.pressed ? 'app-ink' : 'app-ink-3'))),
                                Text('Unwatch', maxLines: 1, softWrap: false, style: pageText(t, xs, weight: 'medium', color: t.color(state.pressed ? 'app-ink' : 'app-ink-3'))),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (pending && org != null)
                  Padding(
                    // `.actions { padding: 0 var(--glacier-space-2) var(--glacier-space-3) calc(2rem + var(--glacier-space-3) + var(--glacier-space-2)) }`
                    padding: EdgeInsets.fromLTRB(2 * rem + t.space(3) + t.space(2), 0, t.space(2), t.space(3)),
                    child: Align(alignment: AlignmentDirectional.centerStart, child: _InviteActions(orgId: org.id, onAnswer: widget.onAnswer)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.mark`: the kind's mark on a round, in its colour with a wash of it behind; unread, the ink itself, with a dot at
/// the round's corner.
class _KindRound extends StatelessWidget {
  const _KindRound({required this.kind, required this.unread});
  final String kind;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final hue = kindHues[kind];
    final round = Builder(
      builder: (context) {
        final t = context.tokens;
        final side = t.lenOf('2rem');
        return ExcludeSemantics(
          child: SizedBox.square(
            key: const ValueKey('notification-mark'),
            dimension: side,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Container(
                    alignment: Alignment.center,
                    // `.mark { border-radius: full; background: var(--app-paper-2); color: var(--app-ink-2) }`,
                    // `.mark[data-hue] { background: color-mix(in oklch, var(--app-space) 16%, transparent); color: var(--app-space) }`,
                    // `.row[data-unread] .mark { color: var(--app-ink) }`
                    decoration: BoxDecoration(shape: BoxShape.circle, color: hue == null ? t.color('app-paper-2') : t.colorOf('color-mix(in oklch, var(--app-space) 16%, transparent)')),
                    child: lucide(
                      _marks[kind] ?? Lucide.mail,
                      size: 18,
                      color: unread
                          ? t.color('app-ink')
                          : hue == null
                              ? t.color('app-ink-2')
                              : t.color('app-space'),
                    ),
                  ),
                ),
                if (unread)
                  // `.row[data-unread] .mark::after { inset-block-start: -1px; inset-inline-end: -1px; inline-size: 7px;
                  // block-size: 7px; border-radius: full; background: var(--glacier-accent-9); box-shadow: 0 0 0 2px var(--glacier-bg) }`
                  Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      key: const ValueKey('notification-unread'),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('glacier-accent-9'), boxShadow: [BoxShadow(color: t.color('glacier-bg'), spreadRadius: 2)]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    return hue == null ? round : GlacierScope(attrs: {'hue': hue}, child: round);
  }
}

/// Accept and Decline, inline, for an invitation to an organization: the drawer's own pair, standing for
/// `settings/InviteActions.tsx` (`InviteActions.module.css`). Two words, the app's own quiet buttons: Accept in ink,
/// Decline in the muted ink. Held dim while the answer is on its way, and the service's words under them if it did
/// not arrive.
class _InviteActions extends StatefulWidget {
  const _InviteActions({required this.orgId, required this.onAnswer});
  final String orgId;
  final Future<String?> Function(String orgId, bool accept)? onAnswer;

  @override
  State<_InviteActions> createState() => _InviteActionsState();
}

class _InviteActionsState extends State<_InviteActions> {
  bool _pending = false;
  String? _problem;

  Future<void> _answer(bool accept) async {
    final answer = widget.onAnswer;
    if (answer == null) return;
    setState(() {
      _pending = true;
      _problem = null;
    });
    final problem = await answer(widget.orgId, accept);
    // Only the words' own state waits on their still being drawn.
    if (!mounted) return;
    setState(() {
      _pending = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rem = t.lenOf('1rem');
    final problem = _problem;
    // `.actions { display: inline-flex; flex-direction: column; align-items: flex-start; gap: var(--glacier-space-1) }`
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: t.space(1),
      children: [
        // `.actions[data-pending] .words { opacity: 0.5 }`
        Opacity(
          opacity: _pending ? 0.5 : 1,
          // `.words { display: inline-flex; align-items: center; gap: var(--glacier-space-3); white-space: nowrap }`
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: t.space(3),
            children: [
              // `.accept { color: var(--app-ink); font-weight: semibold }`
              _Word(word: 'Accept', size: rem, weight: 'semibold', ink: 'app-ink', onPressed: _pending ? null : () => unawaited(_answer(true))),
              // `.decline { color: var(--app-ink-2) }`
              _Word(word: 'Decline', size: rem, onPressed: _pending ? null : () => unawaited(_answer(false))),
            ],
          ),
        ),
        if (problem != null)
          Semantics(
            // `role="alert"`
            liveRegion: true,
            // `.problem { font-size: sm; line-height: var(--glacier-leading-sm); color: var(--app-ink-2) }`
            child: cssLines(problem, pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: t.len('glacier-leading-sm'))),
          ),
      ],
    );
  }
}
