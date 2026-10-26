/// Discord calls, on the Discord plugin's page (calls.dart, docs/DISCORD_CALLS.md). Matt, 2026-10-26: Discord calls
/// belong to the Discord plugin, its switch and its linking on the plugin's page, and the same day: "I want settings
/// / meetings to be broken up into three plugins where each zoom, Google meets and discord handle their own
/// meetings". So everything about Ghost in a Discord call is here and nothing is in Settings › Meetings:
///
/// - **Not linked**: what Ghost does in a call, and **Link Discord**. Pressed, the account's encryption key is seen
///   to and a code comes, shown large with the two steps: Ghost added to the server (its invite link where this build
///   knows the app, [discordInviteUrl]), then `/ghost link K7QM-2XRP` in any channel there, with Copy. The code works
///   once, for ten minutes; the page reads the link every few seconds meanwhile, and the name replaces the code
///   once it is used.
/// - **Linked**: "Linked as sam_lee" with Unlink, which asks first, in the card; **Join Discord calls**, the switch
///   the bot reads on every `/ghost join` (on from the linking); and how to start one: `/ghost join` from a voice
///   channel, the notice Ghost posts there, `/ghost leave`.
/// - **Your Discord calls**: this account's meetings of kind `discord` ([discordCallsOf]), as Settings › Meetings
///   lists meetings (lib/meet/ui/meet_card.dart: those going on first, then by day, each with where it stands), a
///   call going on with Leave now, and one written up opening its note. The shared list filtered by kind that the
///   Meet and Zoom pages are getting was not on main when this was written; this is the same rows, built the same
///   way, and can move onto it.
///
/// Signed out, or against a service with no Discord routes, the card says so and offers nothing.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/note.dart';
import '../../meet/meet_api.dart';
import '../../meet/meet_in.dart';
import '../../meet/ui/meet_card.dart' show meetListed, meetWhen;
import '../../settings/account_forms.dart' show FormSubmit;
import '../../settings/kit/settings_kit.dart';
import '../../settings/kit/settings_type.dart' show pageText;
import 'calls.dart';

/// The Discord application's id this build was made with (`--dart-define=GHOST_DISCORD_APP_ID=…`), for the link that
/// adds Ghost to a server; empty where it was made without, and the step then says to ask for the link.
const String discordAppId = String.fromEnvironment('GHOST_DISCORD_APP_ID');

/// What the bot needs in a server: View Channels, Send Messages and Connect (docs/DISCORD_CALLS.md).
const int discordBotPermissions = 1024 | 2048 | 1048576;

/// The link that adds Ghost to a Discord server, or null without [discordAppId].
String? discordInviteUrl([String app = discordAppId]) =>
    app.isEmpty ? null : 'https://discord.com/oauth2/authorize?client_id=$app&scope=bot%20applications.commands&permissions=$discordBotPermissions';

/// The command a code is run with.
String discordLinkCommand(String code) => '/ghost link $code';

/// What the card says under itself: where the sound goes, and that the call is told.
const String discordCallsFooter =
    'Ghost says in the voice channel’s chat that it is recording, and who for. The call’s sound passes through Ghost.md’s server sealed to your account as it arrives; it is written up on your device.';

class DiscordCallsSection extends StatefulWidget {
  const DiscordCallsSection({super.key, required this.services, this.onOpenNote, this.onOpenLink, this.calls});

  final AccountServices? services;

  /// Opens a call's note (Settings shuts); without it no call is pressed.
  final void Function(String id)? onOpenNote;

  /// Opens the invite link outside the app; without it the step shows the link to copy.
  final void Function(String url)? onOpenLink;

  /// The link's state, made here from the account's own when not given (a test hands one in).
  final DiscordCalls? calls;

  @override
  State<DiscordCallsSection> createState() => _DiscordCallsSectionState();
}

class _DiscordCallsSectionState extends State<DiscordCallsSection> {
  DiscordCalls? _calls;
  bool _own = false;
  bool _askingUnlink = false;
  String? _said;
  Map<String, Note> _notes = const {};

  @override
  void initState() {
    super.initState();
    _make();
  }

  void _make() {
    final meet = widget.services?.meetIn;
    _calls = widget.calls ?? (meet == null ? null : DiscordCalls(account: meet.account, keys: meet.keys, api: meet.api, crypto: meet.crypto));
    _own = widget.calls == null && _calls != null;
    unawaited(_calls?.refresh());
    meet?.readNow(within: MeetIn.openFresh);
    unawaited(_readNotes());
  }

  @override
  void didUpdateWidget(DiscordCallsSection old) {
    super.didUpdateWidget(old);
    if (old.services != widget.services || old.calls != widget.calls) {
      if (_own) _calls?.dispose();
      _make();
    }
  }

  @override
  void dispose() {
    if (_own) _calls?.dispose();
    super.dispose();
  }

  Future<void> _readNotes() async {
    final list = widget.services?.listNotes;
    if (list == null) return;
    try {
      final notes = {for (final note in await list()) note.id: note};
      if (mounted) setState(() => _notes = notes);
    } catch (_) {
      // No call opens its note; each says where it stands.
    }
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _said = 'Copied. Paste it in Discord.');
    } catch (_) {
      if (mounted) setState(() => _said = text);
    }
  }

  List<Widget> _codeRows(BuildContext context, DiscordCode code) {
    final t = context.tokens;
    final invite = discordInviteUrl();
    final command = discordLinkCommand(code.code);
    return [
      SettingRow(
        key: const ValueKey('discord-code'),
        icon: const AppIcon(Lucide.keyRound, size: 20),
        label: code.code,
        hint: const Text('Your code. It works once, for ten minutes.'),
        control: RowAction(key: const ValueKey('discord-code-copy'), onPress: () => unawaited(_copy(command)), child: const Text('Copy')),
      ),
      SettingRow(
        key: const ValueKey('discord-step-invite'),
        icon: const AppIcon(Lucide.userPlus, size: 20),
        label: '1. Add Ghost to your Discord server',
        hint: Text(invite == null
            ? 'Once for each server, by someone who may manage it: with Ghost.md’s invite link.'
            : 'Once for each server, by someone who may manage it. Ghost asks to see channels, send messages and connect to voice.'),
        control: invite == null || widget.onOpenLink == null ? null : RowAction(key: const ValueKey('discord-invite'), onPress: () => widget.onOpenLink!(invite), child: const Text('Add Ghost')),
      ),
      SettingRow(
        key: const ValueKey('discord-step-link'),
        icon: const AppIcon(Lucide.terminal, size: 20),
        label: '2. Run the command there',
        hint: Text.rich(TextSpan(children: [
          const TextSpan(text: 'In any channel of that server, type '),
          TextSpan(text: command, style: pageText(t, t.fontSize('sm'), weight: 'semibold')),
          const TextSpan(text: '. This page shows your Discord name when it has worked.'),
        ])),
      ),
    ];
  }

  List<Widget> _linkedRows(DiscordCalls calls, DiscordLink link) => [
        SettingRow(
          key: const ValueKey('discord-linked'),
          icon: const AppIcon(Lucide.link, size: 20),
          label: 'Linked as ${link.name}',
          hint: const Text('Ghost records the calls this Discord account asks it into, for this Ghost.md account.'),
          control: RowAction(key: const ValueKey('discord-unlink'), disabled: calls.busy, onPress: () => setState(() => _askingUnlink = !_askingUnlink), child: const Text('Unlink')),
        ),
        if (_askingUnlink)
          SettingRow(
            key: const ValueKey('discord-unlink-ask'),
            label: 'Unlink ${link.name}?',
            hint: const Text('Ghost stops joining calls for it. Calls already recorded stay.'),
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RowAction(
                  key: const ValueKey('discord-unlink-yes'),
                  disabled: calls.busy,
                  onPress: () {
                    setState(() => _askingUnlink = false);
                    unawaited(calls.unlink());
                  },
                  child: const Text('Unlink'),
                ),
                RowAction(onPress: () => setState(() => _askingUnlink = false), child: const Text('Cancel')),
              ],
            ),
          ),
        SettingRow(
          key: const ValueKey('discord-calls-switch'),
          label: 'Join Discord calls',
          hint: const Text('On, Ghost joins a voice channel when you run /ghost join there. Off, it says it is switched off.'),
          control: GlacierSwitch(ariaLabel: 'Join Discord calls', checked: link.calls, onCheckedChange: calls.busy ? null : (on) => unawaited(calls.setCalls(on))),
        ),
        const SettingRow(
          key: ValueKey('discord-how'),
          icon: AppIcon(Lucide.audioLines, size: 20),
          label: 'Start from a voice channel',
          hint: Text('Join the voice channel and run /ghost join. Ghost posts there that it is taking notes for you. Anyone in the call can stop it with /ghost leave; it also leaves once everyone else has, and after three hours.'),
        ),
      ];

  Widget _callRow(MeetIn meet, MeetBooking call, int now) {
    final prefs = widget.services!.prefs.value;
    final noteId = meetingNoteFor(call, filed: meetingNotesOf(prefs), meetings: prefs.meetings, notes: _notes);
    final open = widget.onOpenNote;
    final when = meetWhen(call.startsAt, now: now);
    return SettingRow(
      key: ValueKey('discord-call-${call.id}'),
      icon: AppIcon(switch (call.state) {
        MeetState.done => Lucide.circleCheck,
        MeetState.failed => Lucide.circleAlert,
        MeetState.skipped || MeetState.cancelled => Lucide.ban,
        _ => Lucide.ghost,
      }, size: 20),
      label: call.title ?? 'A Discord call',
      hint: Text('$when · ${call.state == MeetState.done && noteId == null ? 'Not written up yet' : meetStateWords(call)}'),
      onPress: noteId == null || open == null ? null : () => open(noteId),
      control: call.state == MeetState.joining || call.state == MeetState.inCall
          ? RowAction(key: ValueKey('discord-leave-${call.id}'), onPress: () => unawaited(meet.skip(call.id).catchError((Object _) {})), child: const Text('Leave now'))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final calls = _calls;
    if (services == null || !services.signedIn || calls == null) {
      return const PaneSection(
        title: 'Discord calls',
        children: [SettingRow(key: ValueKey('discord-calls-signed-out'), icon: AppIcon(Lucide.audioLines, size: 20), label: 'Sign in to have Ghost join your Discord calls', hint: Text('Under Settings › Account. A call is sealed to your account as it is recorded.'))],
      );
    }
    final meet = services.meetIn!;
    return ListenableBuilder(
      listenable: Listenable.merge([calls, meet, services.prefs]),
      builder: (context, _) {
        final t = context.tokens;
        final link = calls.link;
        final code = calls.code;
        final now = services.now();
        final said = calls.problem ?? _said;
        final card = PaneSection(
          title: 'Discord calls',
          description: const Text('Ghost joins a Discord voice channel when you ask it there, records the call, and files it here as a note written up with who said what.'),
          footer: said == null ? null : Text(said, key: const ValueKey('discord-calls-said')),
          children: [
            if (!calls.available)
              const SettingRow(key: ValueKey('discord-calls-not-here'), icon: AppIcon(Lucide.audioLines, size: 20), label: 'Discord calls are not on this service yet')
            else if (!calls.read)
              const SettingRow(key: ValueKey('discord-calls-reading'), icon: AppIcon(Lucide.clock, size: 20), label: 'Reading your Discord link…')
            else if (link != null)
              ..._linkedRows(calls, link)
            else ...[
              SettingRow(
                key: const ValueKey('discord-link'),
                icon: const AppIcon(Lucide.link, size: 20),
                label: 'Link Discord',
                hint: const Text('Once: a code from here, run as a command in your Discord server, tells Ghost which Discord account is yours.'),
                control: FormSubmit(wordKey: const ValueKey('discord-link-make'), calls.busy ? 'Making…' : (code == null ? 'Link Discord' : 'New code'), onPressed: calls.busy ? null : () => unawaited(calls.makeCode())),
              ),
              if (code != null) ..._codeRows(context, code),
            ],
          ],
        );
        final mine = discordCallsOf(meet.meetings);
        final list = PaneSection(
          title: 'Your Discord calls',
          footer: Text(meet.pages ? '$discordCallsFooter $meetHistoryKeptWords' : discordCallsFooter),
          children: [
            if (meet.meetings == null)
              SettingRow(key: const ValueKey('discord-calls-list-reading'), icon: const AppIcon(Lucide.clock, size: 20), label: meet.problem ?? 'Reading your calls…')
            else if (mine.isEmpty)
              const SettingRow(key: ValueKey('discord-calls-none'), icon: AppIcon(Lucide.ghost, size: 20), label: 'No Discord calls yet', hint: Text('A call Ghost records shows here, with where it stands.'))
            else
              for (final (:day, :meeting) in meetListed(mine, now: now)) ...[
                if (day != null) Padding(padding: EdgeInsets.fromLTRB(t.space(3), t.space(3), t.space(3), t.space(1)), child: Text(day, style: pageText(t, t.lenOf('0.72rem'), weight: 'semibold', color: t.color('app-ink-3')))),
                _callRow(meet, meeting, now),
              ],
          ],
        );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [card, SizedBox(height: t.space(4)), list]);
      },
    );
  }
}

/// How far back the list goes (bookings are kept thirty days, server/src/meet.rs `KEPT_FOR`).
const String meetHistoryKeptWords = 'Calls are kept here for 30 days after they end.';
