/// Report a person or a message (GMFB-40, from the Uplink gap review: "Report a user or message"; Matt approved the
/// reporting half): why, a note, and for a message the message and a little of what was said round it, sealed so only
/// the reviewer reads it (lib/safety/abuse_report.dart) and sent to the Marketplace's review on the relay. Reporting a
/// person offers to block them too.
///
/// Offered from a message's press-and-hold menu in a username chat or a space, and from a Ghost person's profile card.
/// What was reported is listed in Settings › Privacy › Reports you've made, on this device alone.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter, TextCapitalization, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../feedback/feedback_api.dart' show FeedbackReport;
import '../friends/buddies.dart';
import '../kit/semantic_colors.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../market/market_api.dart';
import '../me/me.dart';
import '../plugins/pack/pack.dart' show InstalledPlugins;
import '../safety/abuse_report.dart';
import '../voice/channels.dart';
import '../voice/hangout.dart';
import 'circles/members_drawer.dart' show showMembersDrawer;
import 'common.dart';
import 'drawer_head.dart' show DrawerHead;
import 'settings_panes.dart' show appVersion;

/// Who or what is reported, from where it was opened.
class ReportTarget {
  const ReportTarget({required this.id, this.username = '', required this.name, required this.place, this.placeName = '', this.messages = const []});

  /// Their Ghost id where it is known ('' for a username chat whose friend isn't known here), their username, their
  /// name as shown.
  final String id;
  final String username;
  final String name;

  /// 'chat', 'space' or 'profile', and the chat's or space's name.
  final String place;
  final String placeName;

  /// For a message: it, marked, and what was said round it ([withContext]); empty for a person.
  final List<ReportedMessage> messages;

  bool get isMessage => messages.any((m) => m.reported);

  /// "@name", else their name.
  String get shown => username.isNotEmpty ? '@$username' : name;

  String get whereWords => switch (place) {
        'space' => placeName.isEmpty ? 'A space' : placeName,
        'chat' => placeName.isEmpty ? 'A chat' : 'Chat with $placeName',
        _ => 'Their profile',
      };
}

/// Sends a sealed report: its id on the relay. The app's is [sendReportLive]; a test gives its own.
typedef ReportSend = Future<String> Function(AbuseReport report);

/// Seals [report] to the review keys this build trusts and sends it to Ghost Messaging's own relay.
Future<String> sendReportLive(AbuseReport report) async {
  final api = MarketApi.live();
  final signer = api.signer ?? Voice.instance.signer;
  if (signer == null) throw const MarketError('no_identity', 'Reporting needs your Ghost identity on this device. Become the same you as your phone in Settings › Me.');
  final here = InstalledPlugins.instance;
  final keys = [for (final k in here.reviewKeys) if (!here.retiredKeys.contains(k)) k];
  final sealed = await sealReport(report, signer: signer, reviewKeys: keys);
  return api.reportPerson(sealed, signer: signer);
}

/// Blocks a Ghost person: Buddies.block in the app; a test gives its own.
typedef ReportBlock = Future<void> Function(ReportTarget target);

Future<void> blockLive(ReportTarget t) => Buddies.instance.block(t.id, username: t.username);

/// Where the reports made here are kept with the app's choices (MadeReport).
const reportsMadeKey = 'reports_made';

/// Opens the report sheet for [target].
Future<void> showReportSheet(BuildContext context, ReportTarget target, {ReportSend? send, ReportBlock? block}) => showMembersDrawer(
      context,
      title: target.isMessage ? 'Report message' : 'Report ${target.shown}',
      subtitle: 'Only the Ghost Messaging reviewer can read it',
      list: (_) => ReportForm(key: const ValueKey('report-drawer'), target: target, send: send, block: block),
    );

class ReportForm extends StatefulWidget {
  const ReportForm({super.key, required this.target, this.send, this.block});
  final ReportTarget target;
  final ReportSend? send;
  final ReportBlock? block;

  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  final _note = TextEditingController();
  final _focus = FocusNode();
  ReportReason? _reason;
  bool _block = false;
  bool _sending = false;

  ReportTarget get _t => widget.target;

  /// Only a Ghost person, known by their id, not already blocked, is offered Block here.
  bool get _canBlock => _t.id.isNotEmpty && !Buddies.instance.isBlocked(_t.id);

  @override
  void dispose() {
    _note.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _ready => !_sending && _reason != null;

  Future<void> _send() async {
    final reason = _reason;
    if (!_ready || reason == null) return;
    final app = AppState.of(context);
    final report = AbuseReport(
      kind: _t.isMessage ? 'message' : 'person',
      reason: reason,
      note: _note.text.trim(),
      subjectId: _t.id,
      subjectUsername: _t.username,
      subjectName: _t.name,
      place: _t.place,
      placeName: _t.placeName,
      messages: _t.isMessage ? _t.messages : const [],
      reporterUsername: Me.instance.username ?? '',
      at: DateTime.now().millisecondsSinceEpoch,
      platform: FeedbackReport.thisPlatform,
      version: appVersion,
    );
    setState(() => _sending = true);
    try {
      final id = await (widget.send ?? sendReportLive)(report);
      var blocked = false;
      if (_block && _canBlock) {
        try {
          await (widget.block ?? blockLive)(_t);
          blocked = true;
        } catch (_) {}
      }
      app.set(reportsMadeKey, MadeReport.withAdded(app.choice(reportsMadeKey, '[]'), MadeReport(id: id, kind: report.kind, reason: reason, who: _t.shown, where: _t.whereWords, at: report.at, blocked: blocked)));
      if (!mounted) return;
      toast(context, blocked ? 'Reported, and ${_t.shown} is blocked' : (_block ? 'Reported. Couldn\'t block them just now.' : 'Reported. Thank you.'));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, e is MarketError ? e.message : 'Couldn\'t send the report: $e', tone: GlacierToastTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = SizedBox(height: t.space(3));
    final ink = pageText(t, t.fontSize('md'), color: t.color('app-ink'), height: 1.4);
    final gutter = DrawerHead.gutter(t);
    return SettingsPaneScope(
      finder: SettingsFinder(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, t.space(3), gutter, t.space(4)),
        shrinkWrap: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          PaneSection(title: 'Why?', children: [
            for (final r in ReportReason.values)
              SettingRow(
                key: ValueKey('report-reason-${r.wire}'),
                icon: AppIcon(_reason == r ? Lucide.circleCheck : Lucide.circle, size: 18, color: _reason == r ? t.color('app-accent') : t.color('app-ink-3')),
                label: r.label,
                hint: Text(r.hint),
                onPress: _sending ? null : () => setState(() => _reason = r),
              ),
          ]),
          gap,
          PaneSection(title: 'Anything to add?', children: [
            SettingRowBox(
              child: GestureDetector(
                onTap: _focus.requestFocus,
                child: Container(
                  constraints: BoxConstraints(minHeight: t.lenOf('5rem')),
                  padding: EdgeInsets.all(t.space(3)),
                  decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(t.radius('md'))),
                  child: Stack(children: [
                    if (_note.text.isEmpty) IgnorePointer(child: Text('A note for the reviewer (optional)', style: ink.copyWith(color: t.color('app-ink-3')))),
                    Semantics(
                      label: 'Note',
                      textField: true,
                      child: EditableText(
                        key: const ValueKey('report-note'),
                        controller: _note,
                        focusNode: _focus,
                        style: ink,
                        cursorColor: t.color('app-ink'),
                        backgroundCursorColor: t.color('app-ink-3'),
                        selectionColor: t.textSelection,
                        minLines: 3,
                        maxLines: 8,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: [LengthLimitingTextInputFormatter(AbuseReport.noteMost)],
                        readOnly: _sending,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
          if (_t.isMessage) ...[
            gap,
            PaneSection(
              title: 'What goes with it',
              description: const Text('The relay can\'t read your chats, so the message and a few either side go with the report, sealed for the reviewer alone.'),
              children: [
                for (final m in _t.messages)
                  SettingRow(
                    icon: AppIcon(m.reported ? Lucide.flag : Lucide.messageSquare, size: 16, color: m.reported ? t.danger : t.color('app-ink-3')),
                    label: m.mine ? 'You' : m.name,
                    hint: Text(m.text.isEmpty ? '(no words: a picture, a file or a sticker)' : (m.text.length > 160 ? '${m.text.substring(0, 160)}…' : m.text), maxLines: 3, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ],
          if (_canBlock) ...[
            gap,
            PaneSection(children: [
              SettingRow(
                label: 'Also block ${_t.shown}',
                hint: const Text('Ends being friends; their friend requests and messages to you are dropped.'),
                control: GlacierSwitch(
                  key: const ValueKey('report-block'),
                  checked: _block,
                  disabled: _sending,
                  onCheckedChange: (v) => setState(() => _block = v),
                  ariaLabel: 'Also block them',
                ),
              ),
            ]),
          ],
          gap,
          PaneSection(
            footer: const Text('Sealed on this device to the reviewer\'s key: nobody else, the relay included, can open it. The person isn\'t told who reported them.'),
            children: [
              SettingRow(
                key: const ValueKey('report-send'),
                icon: AppIcon(Lucide.send, size: 18),
                label: _sending ? 'Sending…' : 'Send report',
                hint: Text(_reason == null ? 'Choose why first.' : 'It goes to the Ghost Messaging reviewer.'),
                disabled: !_ready,
                onPress: _ready ? () => unawaited(_send()) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The report sheet for [m], someone else's message in [room]'s chat, with what was said round it in the same chat (or
/// the same thread), oldest first.
void reportSpaceMessage(BuildContext context, HangoutRoom room, HangoutMessage m, {ReportSend? send}) {
  final shown = [for (final x in room.messages) if (x.thread == m.thread) x]..sort((a, b) => a.at.compareTo(b.at));
  final index = shown.indexWhere((x) => x.id == m.id);
  String words(HangoutMessage x) => x.text.isNotEmpty ? x.text : (x.sticker != null ? '(a sticker)' : (x.files.isNotEmpty ? '(${x.files.length == 1 ? 'a file' : '${x.files.length} files'})' : ''));
  ReportedMessage of(HangoutMessage x, {bool reported = false}) => ReportedMessage(from: x.from, name: x.from == room.me ? 'You' : x.name, at: x.at, text: words(x), reported: reported, mine: x.from == room.me);
  unawaited(showReportSheet(
    context,
    ReportTarget(
      id: m.from,
      username: room.usernames[m.from] ?? '',
      name: m.name,
      place: 'space',
      placeName: room.channel.name,
      messages: index < 0 ? [of(m, reported: true)] : withContext([for (final x in shown) of(x)], index),
    ),
    send: send,
  ));
}

/// Settings › Privacy › Reports you've made: what this device reported, newest first.
class ReportsMadeList extends StatelessWidget {
  const ReportsMadeList({super.key});

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final list = MadeReport.readAll(AppState.of(context).choice(reportsMadeKey, '[]'));
    return PaneSection(
      title: 'Reports you\'ve made',
      description: const Text('Kept on this device alone. Each went sealed to the Ghost Messaging reviewer; the person wasn\'t told who reported them.'),
      children: [
        if (list.isEmpty) const SettingRow(key: ValueKey('reports-made-none'), label: 'You haven\'t reported anyone'),
        for (final r in list.take(math.min(list.length, MadeReport.most)))
          SettingRow(
            key: ValueKey('reports-made-${r.id}'),
            icon: AppIcon(r.kind == 'message' ? Lucide.messageSquare : Lucide.userRound, size: 18),
            label: '${r.who} · ${r.reason.label}',
            hint: Text([r.kind == 'message' ? 'A message' : 'The person', r.where, _date(r.at), if (r.blocked) 'blocked'].join(' · ')),
          ),
      ],
    );
  }
}
