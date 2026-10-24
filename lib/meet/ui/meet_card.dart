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
bool meetCardShown(AccountServices services) => services.meetIn != null && services.meetIn!.available && services.mailIn?.address?.address != null;

/// What the question before a new address, made or chosen, warns of.
const String meetNewAddressWarning = 'Invites and mail sent to the old one are turned away from then on. A Calendar invite with it as a guest needs the new one.';

/// How long a pause in typing a name is before the service is asked about it.
const Duration meetNameSettle = Duration(milliseconds: 400);

/// What the card says under itself: where a meeting's sound goes.
const String meetCardFooter = 'The meeting’s sound passes through Ghost.md’s server while it records, sealed to your account as it arrives; it is written up on your device.';

String _two(int n) => n.toString().padLeft(2, '0');

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
            SettingsForm(
              children: [
                GlacierInput(
                  ariaLabel: 'Meet link',
                  placeholder: 'meet.google.com/abc-defg-hij',
                  value: _link,
                  onChange: (text) => setState(() => _link = text),
                  onSubmitted: (_) {
                    if (ready) unawaited(_send(meet));
                  },
                ),
                FormSubmit(wordKey: const ValueKey('meet-send'), _busy ? 'One moment…' : 'Send Ghost to a meeting now', onPressed: ready ? () => unawaited(_send(meet)) : null),
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
        final list = PaneSection(
          title: 'Ghost in meetings',
          description: const Text('Ghost joins by itself, records the meeting, and files it as a note, written up with who said what.'),
          footer: const Text(meetCardFooter),
          children: [
            if (meetings == null)
              SettingRow(key: const ValueKey('meet-reading'), icon: const AppIcon(Lucide.clock, size: 20), label: meet.problem ?? 'Reading your meetings…')
            else if (meetings.isEmpty)
              const SettingRow(key: ValueKey('meet-none'), icon: AppIcon(Lucide.ghost, size: 20), label: 'No meetings yet', hint: Text('A meeting Ghost is invited to shows here, with where it stands.'))
            else
              for (final (meeting, noteId) in [for (final m in meetings) (m, meetingNoteFor(m, filed: filed, meetings: prefs.meetings, notes: _notes))])
                SettingRow(
                  key: ValueKey('meet-${meeting.id}'),
                  icon: AppIcon(switch (meeting.state) {
                    MeetState.done => Lucide.circleCheck,
                    MeetState.failed => Lucide.circleAlert,
                    MeetState.skipped || MeetState.cancelled => Lucide.ban,
                    MeetState.joining || MeetState.inCall || MeetState.leave => Lucide.ghost,
                    _ => Lucide.calendarDays,
                  }, size: 20),
                  label: meeting.title ?? 'A meeting',
                  hint: Text('${meetWhen(meeting.startsAt, now: now)} · ${_whereItStands(meeting, noteId == null ? null : _notes[noteId])}'),
                  onPress: noteId == null || open == null ? null : () => open(noteId),
                  control: meeting.state.open
                      ? RowAction(
                          disabled: _busy,
                          onPress: () => unawaited(_run(() => meet.skip(meeting.id))),
                          child: Text(meeting.state == MeetState.booked ? 'Don’t join' : 'Leave now'),
                        )
                      : null,
                ),
          ],
        );
        // Two cards with the gap a pane puts between its own (PaneBody).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [invite, SizedBox(height: t.space(4)), list],
        );
      },
    );
  }
}

/// Where a meeting stands, as its row says it: [meetStateWords], but a meeting done is "Written up" only once its
/// [note] is here, "Being written up" while the note waits for its write-up, and "Not written up yet" before it has
/// come.
String _whereItStands(MeetBooking meeting, Note? note) {
  if (meeting.state != MeetState.done) return meetStateWords(meeting);
  if (note == null) return 'Not written up yet';
  return awaitsWriteUp(note.body) ? 'Being written up' : meetStateWords(meeting);
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
