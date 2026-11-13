import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/ghost_icons.dart';
import '../art/lucide.g.dart';
import '../backgrounds.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'background_picker.dart';
import 'common.dart';
import 'encryption.dart';

/// One conversation's own settings, from the cog at its top (Matt, 2026-11-13: "we should have chat backgrounds be on
/// a per chat setting, each chat should get it's own settings cog"): who is in it, its background and the colour of
/// your bubbles in it, its encryption, and whether it is muted or pinned.
class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key, required this.thread, required this.people});
  final int thread;
  final List<Person> people;

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  Conversation? _conversation;
  E2eState _e2e = const E2eState();
  StreamSubscription<int>? _changes;

  bool get _group => widget.people.length > 1;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = Sms.instance.changes.stream.listen((_) => _load());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await Sms.instance.conversations();
      final c = all.where((c) => c.id == widget.thread).firstOrNull;
      if (mounted) setState(() => _conversation = c);
    } catch (_) {}
    if (_group || widget.people.isEmpty) return;
    try {
      final e = await Sms.instance.e2e(widget.people.first.address);
      if (mounted) setState(() => _e2e = e);
    } catch (_) {}
  }

  Future<void> _flag(String name, bool on) async {
    await Sms.instance.threadFlag(name, widget.thread, on);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.of(context);
    final thread = widget.thread;
    final people = widget.people;
    final c = _conversation;
    final own = ChatBackground.own(app, thread);
    final title = people.isEmpty ? 'Conversation' : (_group ? people.map((p) => p.label.split(' ').first).join(', ') : people.first.label);
    return GlacierScope(
      attrs: const {'hue': 'indigo'},
      child: Builder(builder: (context) {
        final t = context.tokens;
        return SettingsPaneScope(
          finder: SettingsFinder(),
          child: GhostPage(
            title: 'Conversation settings',
            body: ListView(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
              children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Avatar(people: people, size: t.lenOf('4.5rem')),
                  SizedBox(height: t.space(3)),
                  Text(title, textAlign: TextAlign.center, style: pageText(t, t.fontSize('xl'), weight: 'bold', color: t.color('app-ink'))),
                  if (_e2e.on) ...[
                    SizedBox(height: t.space(1)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon(Lucide.lock, size: 12, strokeWidth: 2.4, wash: false, color: t.color('app-ink-3')),
                      const SizedBox(width: 4),
                      Text(_e2e.verified ? 'Encrypted · verified' : 'Encrypted', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                    ]),
                  ],
                ]),
                SizedBox(height: t.space(5)),
                PaneSection(title: _group ? '${people.length} people' : 'Person', children: [
                  for (final p in people)
                    SettingRow(
                      icon: const AppIcon(Lucide.phone, size: 18),
                      label: p.label,
                      hint: p.name != null && p.name!.isNotEmpty ? Text(p.address) : null,
                      onPress: () => const MethodChannel('ghost_messaging/sms').invokeMethod('dial', {'address': p.address}),
                    ),
                ]),
                SizedBox(height: t.space(5)),
                PaneSection(
                  title: 'Look',
                  footer: const Text('For this conversation alone. Every other conversation keeps what it wears.'),
                  children: [
                    SettingRow(
                      icon: const AppIcon(Lucide.image, size: 18),
                      label: 'Chat background',
                      value: Text(own == null ? 'Same as every chat' : own.label),
                      onPress: () => push<void>(context, (_) => BackgroundPicker(thread: thread, who: _group ? null : (people.isEmpty ? null : people.first.label), people: people)),
                    ),
                    SettingRow(
                      icon: const AppIcon(Lucide.palette, size: 18),
                      label: 'Your bubbles here',
                      layout: SettingRowLayout.stacked,
                      control: BubbleSwatches(chosen: app.choice('bubble_$thread', ''), same: true, onPick: (id) => app.set('bubble_$thread', id)),
                    ),
                    SettingRowBox(child: BackgroundPreview(background: ChatBackground.of(app, thread), thread: thread)),
                  ],
                ),
                if (!_group && people.isNotEmpty) ...[
                  SizedBox(height: t.space(5)),
                  PaneSection(title: 'Privacy', children: [
                    SettingRow(
                      icon: AppIcon(_e2e.on ? (_e2e.verified ? Lucide.shieldCheck : Lucide.lock) : Lucide.keyRound, size: 18),
                      label: 'Encryption',
                      hint: Text(switch (_e2e.state) {
                        'on' => _e2e.verified ? 'On, and the safety number is verified.' : 'On. Compare the safety number to be sure nobody is in the middle.',
                        'pending' => _e2e.changed ? '${people.first.label} sent a NEW key. Review it before accepting.' : '${people.first.label} sent their key and waits for your yes.',
                        'offered' => 'Your key was sent. It starts when ${people.first.label} accepts.',
                        _ => _e2e.hasGhost ? '${people.first.label} has Ghost Messaging too: your texts can go sealed so only your two phones read them.' : 'Off. It needs ${people.first.label} to have Ghost Messaging too.',
                      }),
                      onPress: () => showEncryptionChoices(context, people.first, _e2e, _load),
                    ),
                  ]),
                ],
                SizedBox(height: t.space(5)),
                PaneSection(title: 'This conversation', children: [
                  SettingRow(
                    icon: const AppIcon(GhostIcons.bellOff, size: 18),
                    label: 'Mute notifications',
                    hint: const Text('Messages still arrive, quietly.'),
                    control: GlacierSwitch(checked: c?.muted ?? false, onCheckedChange: (on) => _flag('muted', on), ariaLabel: 'Mute notifications'),
                  ),
                  SettingRow(
                    icon: const AppIcon(Lucide.pin, size: 18),
                    label: 'Pin to top',
                    control: GlacierSwitch(checked: c?.pinned ?? false, onCheckedChange: (on) => _flag('pinned', on), ariaLabel: 'Pin to top'),
                  ),
                  SettingRow(
                    icon: AppIcon((c?.archived ?? false) ? Lucide.archiveRestore : Lucide.archive, size: 18),
                    label: (c?.archived ?? false) ? 'Move back to Messages' : 'Archive',
                    onPress: () async {
                      final to = !(c?.archived ?? false);
                      await Sms.instance.archive(thread, to);
                      await _load();
                      if (context.mounted) toast(context, to ? 'Archived' : 'Moved back to Messages');
                    },
                  ),
                ]),
              ],
            ),
          ),
        );
      }),
    );
  }
}
