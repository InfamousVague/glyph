import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/locale_dates.dart';
import '../../core/note.dart';
import '../../editor/band/menu_band.dart' show BandTip;
import '../../mail/mail_in.dart' show MailIn;
import '../../mail/mail_name.dart';
import '../../settings/account_forms.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/kit/settings_type.dart' show pageText;
import '../meet_api.dart';
import '../meet_in.dart';
import '../meet_note.dart' show awaitsWriteUp;

/// Ghost in meetings, Settings › Meetings (lib/settings/panes/meetings_pane.dart, lib/meet/meet_in.dart, docs/MEET.md):
/// the mail-to-note address is also the address Ghost is invited by, so the cards are drawn only once there is one
/// ([meetCardShown]). Two cards. First the ways to invite Ghost (Matt, 2026-10-23: "move the invite card to the top"):
/// a Meet link sent now, then the address to put on a Calendar invite, with Copy and, beside it, a new address in its
/// place (Matt, 2026-10-24: "add a refresh button next to the email so i can regeenrate the email"). This card is the
/// one place the address is shown, mail to a note's as much as Ghost's (Account points here). Then what Ghost does
/// and where the sound goes, over the meetings Ghost is booked for and was in with where each stands, and a way to
/// tell Ghost not to join one or to leave.
///
/// A new address turns the old one off at once, for invites and mail alike, and a Calendar invite that has it as a
/// guest goes nowhere after, so the refresh asks first, in the card, as Settings asks (the library folder's move):
/// the question under the address with Make it and Cancel. It is the service's own `POST mail/address`
/// ([MailIn.newAddress]), what Email to a note's "Make a new address" always ran. The new address is drawn in the old
/// one's row, and the card's foot says so; a refusal is said there instead, and the old address stays. Shown in
/// Simple too, as an icon beside Copy: making a new address is what a person needs once an old one is given out too
/// widely, not a fancy thing.
///
/// Or a name of one's own (Matt, 2026-10-24: "i'd like you to add the ability to create our own custom name for the
/// email if the name is available like matt@in.ghostmarkdown.com"): "Choose a name…" beside Copy opens a field under
/// the address, in the card, with the domain after it, and says as one types - once a pause in typing is 400 ms long
/// - "Available", "Taken", or what is wrong with the name in plain words (lib/mail/mail_name.dart checks the rules
/// first, and asks the service only about a name that keeps them). "Use this name" then asks as the refresh asks,
/// with the same warning, and Switch puts it in the old one's place ([MailIn.chooseAddress]). A refusal is said under
/// the field, and the old address stays. It is a word of its own beside Copy rather than a choice behind the refresh,
/// so the refresh stays the one press it was, and a name, which is what most people will want once, is in sight
/// rather than a step down; also in Simple, as the refresh is.
///
/// A meeting that became a note opens it (Matt, 2026-10-24: "add the ability to click a meeting to jump to the
/// associated note"): the row is pressed, and [MeetCard.onOpenNote] shuts Settings and opens the note, as the home
/// page opens one. Which note is [meetingNoteFor]'s, read against this device's notes ([AccountServices.listNotes]).
/// A meeting done whose note has not come yet (the take waits on the service for a device to file it) says "Not
/// written up yet" and is not pressed; one booked, in the call, skipped or failed has no note to open.
///
/// Recurring meetings and the history in pages (Matt, 2026-10-24: "show recurring meetings in the meetings UI and
/// paginate the meeting history"):
///
/// - **Recurring**, a card of its own between the two, where the service lists series ([MeetIn.series]; none from a
///   service before them, and then no card, and nothing said): a row a series, its title over its rule in words
///   ([meetSeriesRule]: "Every weekday at 9:30", the zone named where the phone's clock differs, how it ends) and
///   "Next: Mon 27 Oct" ([meetSeriesNext]). Its one word, "Stop joining", asks first, in the card, as a new address
///   does: "Ghost won’t join Engineering Standup any more. Past recordings stay.", with Stop joining and Cancel; then
///   [MeetIn.stopSeries]. A refusal is said under the card. Skipping only the next one is that occurrence's own Don't
///   join, in the list, as before.
/// - **The list in two parts**: those to come or going on, soonest first, under "Coming up"; then those over, the
///   latest first, under a heading for each day ("Today", "Yesterday", "Mon 20 Oct": a small muted line in the card,
///   not a card each), each with its time. A row's words are as they were; a meeting the sweep has forgotten the title
///   of is "A meeting", and an occurrence of a series has the repeat mark for its calendar.
/// - **Show more**, the card's last row while there are older meetings ([MeetIn.hasMore]): the next page comes in
///   below those shown, so nothing above it moves; while it comes the row says "Loading…" in the word's own place, and
///   a failure is said in the row beside Retry. The footer adds how far back the list goes, against a service that
///   pages ([meetHistoryKept]). The same in Simple: nothing here is a fancy thing.
bool meetCardShown(AccountServices services) => services.meetIn != null && services.meetIn!.available && services.mailIn?.address?.address != null;

/// What the question before a new address, made or chosen, warns of.
const String meetNewAddressWarning = 'Invites and mail sent to the old one are turned away from then on. A Calendar invite with it as a guest needs the new one.';

/// How long a pause in typing a name is before the service is asked about it.
const Duration meetNameSettle = Duration(milliseconds: 400);

/// What the card says under itself: where a meeting's sound goes.
const String meetCardFooter = 'The meeting’s sound passes through Ghost.md’s server while it records, sealed to your account as it arrives; it is written up on your device.';

/// What the footer adds against a service that pages: how far back the list goes (bookings are kept thirty days,
/// server/src/meet.rs `KEPT_FOR`).
const String meetHistoryKept = 'Meetings are kept here for 30 days after they end.';

String _two(int n) => n.toString().padLeft(2, '0');

/// A day of meetings over, as its heading says it: "Today", "Yesterday", or "Mon 20 Oct".
String meetDay(int ms, {required int now}) {
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  final today = DateTime.fromMillisecondsSinceEpoch(now);
  final days = DateTime(today.year, today.month, today.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => '${localeDate(at, DateForm.E)} ${localeDayMonth(at, DateForm.MMMd)}',
  };
}

/// Whether [meeting] is among those to come: not yet past its end, or Ghost still in it (a meeting runs over).
bool meetAhead(MeetBooking meeting, {required int now}) =>
    meeting.endsAt > now || meeting.state == MeetState.joining || meeting.state == MeetState.inCall || meeting.state == MeetState.leave;

/// The meetings as the list draws them: those to come, soonest first, then those over, the latest first, each
/// under the day it was on ([meetDay]). A day's heading comes before the first meeting of it.
List<({String? day, MeetBooking meeting})> meetListed(List<MeetBooking> meetings, {required int now}) {
  final ahead = [for (final m in meetings) if (meetAhead(m, now: now)) m]..sort((a, b) => a.startsAt != b.startsAt ? a.startsAt.compareTo(b.startsAt) : a.id.compareTo(b.id));
  final over = [for (final m in meetings) if (!meetAhead(m, now: now)) m]..sort((a, b) => a.startsAt != b.startsAt ? b.startsAt.compareTo(a.startsAt) : b.id.compareTo(a.id));
  String? last;
  return [
    for (final (at, m) in ahead.indexed) (day: at == 0 && over.isNotEmpty ? 'Coming up' : null, meeting: m),
    for (final m in over)
      (
        day: () {
          final day = meetDay(m.startsAt, now: now);
          if (day == last) return null;
          last = day;
          return day;
        }(),
        meeting: m,
      ),
  ];
}

/// When a meeting is, as the card says it: "Today, 14:00", "Tomorrow, 09:30", "18 Oct, 14:00".
String meetWhen(int ms, {required int now}) {
  if (ms <= 0) return 'Now';
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  final today = DateTime.fromMillisecondsSinceEpoch(now);
  final days = DateTime(at.year, at.month, at.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => localeDayMonth(at, DateForm.MMMd),
  };
  return '$day, ${_two(at.hour)}:${_two(at.minute)}';
}

/// The card.
class MeetCard extends StatefulWidget {
  const MeetCard({super.key, required this.services, this.onOpenNote});

  final AccountServices services;

  /// Opens a meeting's note; without it no meeting is pressed.
  final void Function(String id)? onOpenNote;

  @override
  State<MeetCard> createState() => _MeetCardState();
}

class _MeetCardState extends State<MeetCard> {
  String? _said;
  String _link = '';
  bool _busy = false;

  /// The question a new address asks first is showing.
  bool _asking = false;

  /// The series whose "Stop joining" is asking first, and what the Recurring card says under itself.
  String? _stopping;
  String? _seriesSaid;

  /// A name of one's own: the field is open, what is typed in it, what is said under it, whether the service said
  /// the name as typed is free, and whether the question before switching to it is showing. [_nameAsked] counts the
  /// asks, so an answer to a name since typed over is dropped.
  bool _naming = false;
  String _name = '';
  String? _nameSaid;
  bool _nameFree = false;
  bool _nameAsking = false;
  Timer? _nameWait;
  int _nameAsked = 0;

  /// This device's notes, by id, for which meeting became which; empty until read, or where nothing reads them.
  Map<String, Note> _notes = const {};
  Object? _notesFor;

  Listenable? _heard;

  @override
  void initState() {
    super.initState();
    _listen();
    // Read as the page opens, unless it was a moment ago: the build's [MeetIn.readSoon] waits a minute between reads,
    // which showed a page just opened as it was up to a minute before.
    widget.services.meetIn?.readNow(within: MeetIn.openFresh);
  }

  @override
  void didUpdateWidget(MeetCard old) {
    super.didUpdateWidget(old);
    if (old.services != widget.services) {
      _heard?.removeListener(_readNotes);
      _listen();
    }
  }

  @override
  void dispose() {
    _heard?.removeListener(_readNotes);
    _nameWait?.cancel();
    super.dispose();
  }

  void _listen() {
    final meet = widget.services.meetIn;
    _heard = Listenable.merge([?meet, widget.services.prefs])..addListener(_readNotes);
    _notesFor = null;
    _readNotes();
  }

  /// The notes read again whenever what decides a meeting's note changes: the meetings, which notes are meetings,
  /// and which meeting each was kept against.
  void _readNotes() {
    final list = widget.services.listNotes;
    final prefs = widget.services.prefs.value;
    final now = (widget.services.meetIn?.meetings, prefs.meetings, prefs.more[meetingNotesKey]);
    if (list == null || now == _notesFor) return;
    _notesFor = now;
    unawaited(() async {
      try {
        final notes = {for (final note in await list()) note.id: note};
        if (mounted && now == _notesFor) setState(() => _notes = notes);
      } catch (_) {
        // No meeting opens its note; each says where it stands.
      }
    }());
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      await work();
    } catch (failure) {
      if (mounted) setState(() => _said = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy(String address) async {
    try {
      await Clipboard.setData(ClipboardData(text: address));
      if (mounted) setState(() => _said = 'The address is copied.');
    } catch (_) {
      if (mounted) setState(() => _said = address);
    }
  }

  /// A new address in the old one's place (see the header), once asked.
  Future<void> _renew(MailIn mail) => _run(() async {
        setState(() => _asking = false);
        final next = await mail.newAddress();
        if (mounted) setState(() => _said = 'A new address: $next. The old one takes no more invites or mail.');
      });

  /// The name field opened or shut; shut, it forgets what was typed. Either question is put away.
  void _toggleNaming() {
    _nameWait?.cancel();
    _nameAsked++;
    setState(() {
      _naming = !_naming;
      _asking = false;
      _name = '';
      _nameSaid = null;
      _nameFree = false;
      _nameAsking = false;
    });
  }

  /// A name typed: said nothing of until a pause in typing ([meetNameSettle]), then checked here, and asked about
  /// only if it keeps the rules.
  void _typed(MailIn mail, String text) {
    _nameWait?.cancel();
    _nameAsked++;
    setState(() {
      _name = text;
      _nameSaid = null;
      _nameFree = false;
      _nameAsking = false;
    });
    if (text.trim().isEmpty) return;
    _nameWait = Timer(meetNameSettle, () => unawaited(_checkName(mail)));
  }

  Future<void> _checkName(MailIn mail) async {
    final name = mailNameNormal(_name);
    final unfit = mailNameUnfit(name);
    if (unfit != null) {
      setState(() => _nameSaid = unfit.words);
      return;
    }
    final asked = ++_nameAsked;
    setState(() => _nameSaid = 'Checking…');
    String said;
    var free = false;
    try {
      final check = await mail.checkName(name);
      said = check.words;
      free = check.available;
    } catch (failure) {
      said = accountFailureText(failure);
    }
    if (!mounted || asked != _nameAsked) return;
    setState(() {
      _nameSaid = said;
      _nameFree = free;
    });
  }

  /// The name in the old address's place, once asked; a refusal said under the field, the old address kept.
  Future<void> _switchName(MailIn mail) async {
    final name = mailNameNormal(_name);
    setState(() {
      _busy = true;
      _said = null;
      _nameAsking = false;
    });
    try {
      final next = await mail.chooseAddress(name);
      if (!mounted) return;
      _nameAsked++;
      setState(() {
        _naming = false;
        _name = '';
        _nameSaid = null;
        _nameFree = false;
        _said = 'Your address is now $next. The old one takes no more invites or mail.';
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          _nameSaid = accountFailureText(failure);
          _nameFree = false;
        });
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The field, what is said of the name, and Use this name; or, once that is pressed, the question.
  List<Widget> _namingRows(BuildContext context, MailIn mail, String address) {
    final t = context.tokens;
    final domain = '@${address.split('@').last}';
    final whole = '${mailNameNormal(_name)}$domain';
    return [
      SettingsForm(
        key: const ValueKey('meet-name'),
        children: [
          Row(
            children: [
              Expanded(
                child: GlacierInput(
                  key: const ValueKey('meet-name-field'),
                  ariaLabel: 'A name of your own for the address',
                  placeholder: 'yourname',
                  value: _name,
                  autoFocus: true,
                  autoCapitalize: TextCapitalization.none,
                  autoCorrect: false,
                  spellCheck: false,
                  maxLength: mailNameMost + 8,
                  type: GlacierInputType.email,
                  onChange: (text) => _typed(mail, text),
                  onSubmitted: (_) {
                    if (_nameFree && !_busy) setState(() => _nameAsking = true);
                  },
                ),
              ),
              SizedBox(width: t.space(2)),
              Text(domain, key: const ValueKey('meet-name-domain'), style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'))),
            ],
          ),
          FormProblem(key: const ValueKey('meet-name-said'), _nameSaid ?? 'Anyone who guesses a name can send mail to it. What arrives is still sealed to your account.'),
          if (!_nameAsking)
            Row(
              children: [
                FormSubmit(wordKey: const ValueKey('meet-name-use'), 'Use this name', onPressed: _nameFree && !_busy ? () => setState(() => _nameAsking = true) : null),
                SizedBox(width: t.space(3)),
                RowAction(onPress: _toggleNaming, child: const Text('Cancel')),
              ],
            ),
        ],
      ),
      if (_nameAsking)
        SettingRow(
          key: const ValueKey('meet-name-ask'),
          label: 'Switch to ${whole.replaceFirst('@', '@​')}?',
          hint: const Text(meetNewAddressWarning),
          // On a phone, Switch and Cancel under the words, as Copy is under the address: beside them the address
          // broke into three lines.
          layout: MediaQuery.sizeOf(context).width < 600 ? SettingRowLayout.stacked : SettingRowLayout.trailing,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RowAction(disabled: _busy, onPress: () => unawaited(_switchName(mail)), child: const Text('Switch')),
              RowAction(onPress: () => setState(() => _nameAsking = false), child: const Text('Cancel')),
            ],
          ),
        ),
    ];
  }

  /// "Stop joining", once asked: the series goes from the card; a refusal is said under it.
  Future<void> _stop(MeetIn meet, MeetSeries series) async {
    setState(() {
      _busy = true;
      _stopping = null;
      _seriesSaid = null;
    });
    try {
      await meet.stopSeries(series.id);
      if (mounted) setState(() => _seriesSaid = 'Ghost won’t join ${series.title ?? 'that meeting'} any more.');
    } catch (failure) {
      if (mounted) setState(() => _seriesSaid = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// One meeting's row: [when] the hint's first words ("Today, 14:00" for one to come, the time alone under a day).
  Widget _meetingRow(MeetIn meet, MeetBooking meeting, String? noteId, String when, void Function(String id)? open) => SettingRow(
        key: ValueKey('meet-${meeting.id}'),
        icon: AppIcon(switch (meeting.state) {
          MeetState.done => Lucide.circleCheck,
          MeetState.failed => Lucide.circleAlert,
          MeetState.skipped || MeetState.cancelled => Lucide.ban,
          MeetState.joining || MeetState.inCall || MeetState.leave => Lucide.ghost,
          _ => meeting.series != null ? Lucide.repeat : Lucide.calendarDays,
        }, size: 20),
        label: meeting.title ?? 'A meeting',
        hint: Text('$when · ${_whereItStands(meeting, noteId == null ? null : _notes[noteId])}'),
        onPress: noteId == null || open == null ? null : () => open(noteId),
        control: meeting.state.open
            ? RowAction(
                disabled: _busy,
                onPress: () => unawaited(_run(() => meet.skip(meeting.id))),
                child: Text(meeting.state == MeetState.booked ? 'Don’t join' : 'Leave now'),
              )
            : null,
      );

  /// The Recurring card's rows: a series each, and under the one asking, the question.
  List<Widget> _seriesRows(BuildContext context, MeetIn meet, List<MeetSeries> series, int now) => [
        for (final s in series) ...[
          SettingRow(
            key: ValueKey('meet-series-${s.id}'),
            icon: const AppIcon(Lucide.repeat, size: 20),
            label: s.title ?? 'A meeting',
            hint: Text('${meetSeriesRule(s, now: now)}\n${meetSeriesNext(s)}'),
            control: RowAction(
              key: ValueKey('meet-series-stop-${s.id}'),
              disabled: _busy,
              onPress: () => setState(() => _stopping = _stopping == s.id ? null : s.id),
              child: const Text('Stop joining'),
            ),
          ),
          if (_stopping == s.id)
            SettingRow(
              key: ValueKey('meet-series-ask-${s.id}'),
              label: 'Stop joining ${s.title ?? 'this meeting'}?',
              hint: Text(meetStopWarning(s)),
              layout: MediaQuery.sizeOf(context).width < 600 ? SettingRowLayout.stacked : SettingRowLayout.trailing,
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RowAction(key: ValueKey('meet-series-yes-${s.id}'), disabled: _busy, onPress: () => unawaited(_stop(meet, s)), child: const Text('Stop joining')),
                  RowAction(onPress: () => setState(() => _stopping = null), child: const Text('Cancel')),
                ],
              ),
            ),
        ],
      ];

  Future<void> _send(MeetIn meet) => _run(() async {
        final booked = await meet.sendNow(_link);
        if (!mounted) return;
        setState(() {
          _link = '';
          _said = booked == null ? null : 'Ghost is on its way into the meeting.';
        });
      });

  @override
  Widget build(BuildContext context) {
    final meet = widget.services.meetIn, mail = widget.services.mailIn;
    if (meet == null || mail == null || mail.address?.address == null) return const SizedBox.shrink();
    meet.readSoon();
    return ListenableBuilder(
      listenable: Listenable.merge([meet, mail]),
      builder: (context, _) {
        final address = mail.address?.address;
        if (address == null) return const SizedBox.shrink();
        final now = widget.services.now();
        final meetings = meet.meetings;
        final prefs = widget.services.prefs.value;
        final filed = meetingNotesOf(prefs);
        final open = widget.onOpenNote;
        final t = context.tokens;
        final ready = meetLink(_link) != null && !_busy;
        final invite = PaneSection(
          title: 'Invite Ghost',
          description: const Text('Paste a Google Meet link to send Ghost in now, or add your address as a guest on a Google Calendar invite and Ghost joins by itself.'),
          footer: _said == null ? null : Text(_said!),
          children: [
            // The link and Join beside it (Matt, 2026-10-24: "change the \"send ghost to a meeting now\" to be a
            // button called \"join\" to the right of the meet invite input"), where the line under it said it whole.
            SettingsForm(
              children: [
                Row(
                  spacing: t.space(3),
                  children: [
                    Expanded(
                      child: GlacierInput(
                        ariaLabel: 'Meet link',
                        placeholder: 'meet.google.com/abc-defg-hij',
                        value: _link,
                        onChange: (text) => setState(() => _link = text),
                        onSubmitted: (_) {
                          if (ready) unawaited(_send(meet));
                        },
                      ),
                    ),
                    Semantics(
                      label: 'Send Ghost to this meeting now',
                      child: FormSubmit(wordKey: const ValueKey('meet-send'), _busy ? 'Joining…' : 'Join', onPressed: ready ? () => unawaited(_send(meet)) : null),
                    ),
                  ],
                ),
              ],
            ),
            SettingRow(
              key: const ValueKey('meet-address'),
              icon: const AppIcon(Lucide.calendarPlus, size: 20),
              // Broken, where a phone's width must break it, after the @ and nowhere in a word.
              label: address.replaceFirst('@', '@​'),
              hint: const Text('Add this address as a guest on a Google Calendar invite. Mail sent to it becomes a note in your Inbox.'),
              // On a phone, Copy and the new address under the words: beside them they leave the address too little
              // width, and it broke inside the domain.
              layout: MediaQuery.sizeOf(context).width < 600 ? SettingRowLayout.stacked : SettingRowLayout.trailing,
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RowAction(onPress: () => unawaited(_copy(address)), child: const Text('Copy')),
                  RowAction(key: const ValueKey('meet-name-open'), disabled: _busy, onPress: _toggleNaming, child: const Text('Choose a name…')),
                  _NewAddressButton(
                    disabled: _busy,
                    onPressed: () {
                      if (_naming) _toggleNaming();
                      setState(() => _asking = !_asking);
                    },
                  ),
                ],
              ),
            ),
            if (_naming) ..._namingRows(context, mail, address),
            if (_asking)
              SettingRow(
                key: const ValueKey('meet-new-ask'),
                label: 'Make a new address?',
                hint: const Text(meetNewAddressWarning),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RowAction(disabled: _busy, onPress: () => unawaited(_renew(mail)), child: const Text('Make it')),
                    RowAction(onPress: () => setState(() => _asking = false), child: const Text('Cancel')),
                  ],
                ),
              ),
          ],
        );
        final series = meet.series;
        final recurring = series == null || (series.isEmpty && _seriesSaid == null)
            ? null
            : PaneSection(
                title: 'Recurring',
                footer: _seriesSaid == null ? null : Text(_seriesSaid!, key: const ValueKey('meet-series-said')),
                children: series.isEmpty
                    ? [const SettingRow(key: ValueKey('meet-series-none'), icon: AppIcon(Lucide.repeat, size: 20), label: 'No recurring meetings')]
                    : _seriesRows(context, meet, series, now),
              );
        final list = PaneSection(
          title: 'Ghost in meetings',
          description: const Text('Ghost joins by itself, records the meeting, and files it as a note, written up with who said what.'),
          footer: Text(meet.pages ? '$meetCardFooter $meetHistoryKept' : meetCardFooter),
          children: [
            // Check now: the list read at once rather than at the minute's read (MeetIn.checkNow), with when it was
            // last read under it.
            SettingRow(
              key: const ValueKey('meet-check'),
              icon: const AppIcon(Lucide.refreshCw, size: 20),
              label: 'Check for new meetings',
              hint: Text(meet.checking ? 'Checking…' : (meetings != null ? meet.problem : null) ?? meetCheckedSaid(meet.checkedAt, now: now)),
              control: RowAction(key: const ValueKey('meet-check-now'), disabled: meet.checking, onPress: () => unawaited(meet.checkNow()), child: const Text('Check now')),
            ),
            if (meetings == null)
              SettingRow(key: const ValueKey('meet-reading'), icon: const AppIcon(Lucide.clock, size: 20), label: meet.problem ?? 'Reading your meetings…')
            else if (meetings.isEmpty)
              const SettingRow(key: ValueKey('meet-none'), icon: AppIcon(Lucide.ghost, size: 20), label: 'No meetings yet', hint: Text('A meeting Ghost is invited to shows here, with where it stands.'))
            else
              for (final (at, (:day, :meeting)) in meetListed(meetings, now: now).indexed) ...[
                if (day != null) _DayHeading(key: ValueKey('meet-day-$day'), words: day, first: at == 0),
                _meetingRow(
                  meet,
                  meeting,
                  meetingNoteFor(meeting, filed: filed, meetings: prefs.meetings, notes: _notes),
                  meetAhead(meeting, now: now) ? meetWhen(meeting.startsAt, now: now) : _hm(meeting.startsAt),
                  open,
                ),
              ],
            if (meetings != null && (meet.hasMore || meet.moreProblem != null)) _MoreRow(meet: meet),
          ],
        );
        // The cards with the gap a pane puts between its own (PaneBody).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [invite, SizedBox(height: t.space(4)), if (recurring != null) ...[recurring, SizedBox(height: t.space(4))], list],
        );
      },
    );
  }
}

/// When the meetings were last read, as the Check now row says it: "Checked just now", "Checked 3 min ago", or, before
/// a read has come back, what the minute's read does.
String meetCheckedSaid(int? at, {required int now}) {
  if (at == null) return 'Ghost.md checks every minute while this page is open.';
  final minutes = ((now - at) / 60000).floor();
  if (minutes < 1) return 'Checked just now';
  if (minutes < 60) return 'Checked $minutes min ago';
  return 'Checked ${minutes ~/ 60} hr ago';
}

/// Where a meeting stands, as its row says it: [meetStateWords], but a meeting done is "Written up" only once its
/// [note] is here, "Being written up" while the note waits for its write-up, and "Not written up yet" before it has
/// come.
String _whereItStands(MeetBooking meeting, Note? note) {
  if (meeting.state != MeetState.done) return meetStateWords(meeting);
  if (note == null) return 'Not written up yet';
  return awaitsWriteUp(note.body) ? 'Being written up' : meetStateWords(meeting);
}

/// A meeting's time of day, "14:00", under its day's heading.
String _hm(int ms) {
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(at.hour)}:${_two(at.minute)}';
}

/// A day's heading among the meetings over: a small muted line in the card, a hairline over it where rows come
/// before. Not a row of the card's ([PaneRow]), so the card draws no line between it and its first meeting.
class _DayHeading extends StatelessWidget {
  const _DayHeading({super.key, required this.words, required this.first});

  final String words;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.lenOf('0.72rem');
    return Semantics(
      header: true,
      child: Container(
        decoration: first ? null : BoxDecoration(border: Border(top: BorderSide(color: t.color('app-rule'), width: t.len('glacier-hairline')))),
        padding: EdgeInsets.fromLTRB(t.space(3), t.space(3), t.space(3), t.space(1)),
        child: Text(words, style: pageText(t, size, weight: 'semibold', color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps', em: size))),
      ),
    );
  }
}

/// "Show more", the list's last row: the next page loaded below those shown ([MeetIn.more]). While it loads the word
/// says "Loading…" where it stood, and a failure is said beside Retry, so the row keeps its height.
class _MoreRow extends StatelessWidget implements PaneRow {
  const _MoreRow({required this.meet});

  final MeetIn meet;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final problem = meet.moreProblem;
    final loading = meet.loadingMore;
    return Padding(
      key: const ValueKey('meet-more-row'),
      padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
      child: Row(
        children: [
          Expanded(
            child: problem == null || loading
                ? const SizedBox.shrink()
                : Text(problem, key: const ValueKey('meet-more-problem'), style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'))),
          ),
          RowAction(
            key: const ValueKey('meet-more'),
            disabled: loading,
            onPress: () => unawaited(meet.more()),
            child: Text(loading ? 'Loading…' : (problem != null ? 'Retry' : 'Show more')),
          ),
        ],
      ),
    );
  }
}

/// The refresh beside Copy: a round button with the turning arrows, named "Make a new address" to a screen reader and
/// in a tip while the pointer rests on it (the invite links' buttons, lib/settings/invite_links.dart).
class _NewAddressButton extends StatelessWidget {
  const _NewAddressButton({required this.disabled, required this.onPressed});

  final bool disabled;
  final VoidCallback onPressed;

  static const String name = 'Make a new address';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BandTip(
      message: name,
      child: GlacierPressable(
        key: const ValueKey('meet-new'),
        onPressed: disabled ? null : onPressed,
        semanticLabel: name,
        builder: (context, state) => GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('full'),
          child: Container(
            width: t.space(10),
            height: t.space(10),
            decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 7%, transparent)') : null),
            alignment: Alignment.center,
            child: AppIcon(Lucide.refreshCw, size: 16, color: state.disabled ? t.color('glacier-text-subtle') : (state.hovered ? t.color('app-ink') : t.color('app-ink-2'))),
          ),
        ),
      ),
    );
  }
}
