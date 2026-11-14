import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app_state.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../backgrounds.dart';
import '../../kit/settings_kit.dart';
import '../../ui/common.dart';
import '../../ui/computers.dart';
import '../desk.dart';
import '../link/link.dart';
import '../updates.dart';
import 'update_bar.dart';
import 'wizard.dart';

/// The Mac's settings: the phone it is paired with and how the two connect, unpairing, and how this Mac draws
/// conversations. The phone's own settings stay on the phone.
class DeskSettingsScreen extends StatefulWidget {
  const DeskSettingsScreen({super.key});

  @override
  State<DeskSettingsScreen> createState() => _DeskSettingsScreenState();
}

class _DeskSettingsScreenState extends State<DeskSettingsScreen> {
  final _address = TextEditingController();
  bool _read = false;

  /// How much of what was read is kept on this Mac (lib/desktop/cache.dart); null until it has been counted.
  ({int conversations, int bytes})? _kept;

  void _countKept() {
    DeskScope.of(context).calls.cache.size().then((k) {
      if (mounted) setState(() => _kept = k);
    });
  }

  /// "Kept on this Mac" was pressed: what is kept can be thrown away, and is read from the phone again as it is
  /// opened.
  void _clearKept() {
    final calls = DeskScope.of(context).calls;
    showChoices(context, title: 'Clear the conversations and messages kept on this Mac? They are read from your phone again as you open them.', choices: [
      Choice('Clear what is kept', Lucide.trash2, () async {
        await calls.clearKept();
        if (!mounted) return;
        toast(context, 'Cleared');
        _countKept();
      }, danger: true),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) return;
    _read = true;
    _address.text = AppState.of(context).choice('peer', '');
    _countKept();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  static String _keptSize(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

  /// The phone's address, given by hand for a network where it is not found by itself.
  void _saveAddress() {
    final scope = DeskScope.of(context);
    final app = AppState.of(context);
    final text = _address.text.trim();
    final peer = Peer.parse(text);
    if (text.isNotEmpty && peer == null) {
      toast(context, 'That isn\'t an address and a port, like 192.168.1.20:47811', tone: GlacierToastTone.danger);
      return;
    }
    app.set('peer', text);
    scope.link.given = [...scope.envPeers, ?peer];
    scope.link.look();
    toast(context, text.isEmpty ? 'The phone is looked for by itself' : 'Saved. Trying it now.');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = DeskScope.of(context);
    final app = AppState.of(context);
    Widget icon(LucideIcon i) => AppIcon(i, size: 18);
    return GhostPage(
      title: 'Settings',
      body: ListenableBuilder(
        listenable: scope.link,
        builder: (context, _) {
          final phone = scope.link.phone;
          final sections = <Widget>[
            if (phone != null) ...[
              PaneSection(title: 'Your phone', children: [
                SettingRow(
                  icon: icon(LucideMore.smartphone),
                  label: phone.name,
                  hint: Text('${linkLine(scope.link)} · paired ${listWhen(phone.since)}'),
                ),
              ]),
              ConnectionChoice(value: phone.mode, relay: phone.relay, onChanged: (m) => scope.link.setMode(m)),
              PaneSection(
                title: 'If the phone isn\'t found',
                footer: const Text('The phone announces itself on the network and this Mac looks for it. Where a network keeps the two from finding each other, give the phone\'s address: it is on the phone under Settings › Computers.'),
                children: [
                  SettingRowBox(
                    child: GlacierInput(
                      controller: _address,
                      placeholder: '192.168.1.20:47811',
                      ariaLabel: 'The phone\'s address and port',
                      autoCorrect: false,
                      autoCapitalize: TextCapitalization.none,
                      size: GlacierFieldSize.md,
                      onSubmitted: (_) => _saveAddress(),
                      onBlur: _saveAddress,
                    ),
                  ),
                ],
              ),
              PaneSection(children: [
                SettingRow(
                  icon: icon(Lucide.unlink),
                  label: 'Unpair this phone',
                  hint: const Text('This Mac stops showing the phone\'s texts, and the key is deleted from both.'),
                  onPress: () => showChoices(context, title: 'Unpair ${phone.name}? Its conversations leave this Mac, and the key the two share is deleted.', choices: [
                    Choice('Unpair', Lucide.unlink, () async {
                      scope.calls.forget();
                      await scope.link.unpair();
                    }, danger: true),
                  ]),
                ),
              ]),
            ],
            PaneSection(title: 'Appearance', children: [
              SettingRow(
                icon: icon(Lucide.sunMoon),
                label: 'Theme',
                layout: SettingRowLayout.stacked,
                control: GlacierSegmentedControl(
                  fullWidth: true,
                  value: app.theme,
                  onValueChange: app.setTheme,
                  options: const [
                    GlacierSegmentedOption(value: 'system', label: Text('System')),
                    GlacierSegmentedOption(value: 'light', label: Text('Light')),
                    GlacierSegmentedOption(value: 'dark', label: Text('Dark')),
                  ],
                ),
              ),
              SettingRow(
                icon: icon(Lucide.messageSquare),
                label: 'Your bubbles',
                layout: SettingRowLayout.stacked,
                control: BubbleSwatches(chosen: app.bubble == 'wallpaper' ? 'ghost' : app.bubble, onPick: app.setBubble),
              ),
            ]),
            PaneSection(title: 'Messages', children: [
              SettingRow(
                icon: icon(Lucide.send),
                label: 'Enter sends',
                hint: const Text('Off, Enter starts a new line and the button sends.'),
                control: GlacierSwitch(checked: app.enterSends, onCheckedChange: (v) => app.setFlag('enter_sends', v), ariaLabel: 'Enter sends'),
              ),
              SettingRow(
                icon: icon(Lucide.sparkles),
                label: 'Message effects',
                control: GlacierSwitch(checked: app.effects, onCheckedChange: app.setEffects, ariaLabel: 'Message effects'),
              ),
              // What was read from the phone is kept here (Matt, 2026-11-14: "cache messages on the desktop app so
              // that we don't need to fetch them all from the phone every time"): how much, and a way to clear it.
              SettingRow(
                icon: icon(Lucide.hardDrive),
                label: 'Kept on this Mac',
                value: _kept == null || _kept!.bytes == 0 ? null : Text(_keptSize(_kept!.bytes)),
                hint: Text(_kept == null || _kept!.bytes == 0
                    ? 'Conversations you open are kept here, sealed with your pairing\'s key, so they open at once and are there while your phone is away.'
                    : 'The list and ${_kept!.conversations} ${_kept!.conversations == 1 ? 'conversation\'s' : 'conversations\''} messages, sealed with your pairing\'s key. They open at once, and only what is new is fetched from your phone. Press to clear.'),
                onPress: _kept == null || _kept!.bytes == 0 ? null : _clearKept,
              ),
            ]),
            PaneSection(title: 'About', children: [
              SettingRow(
                icon: icon(Lucide.info),
                label: 'Ghost Messaging for the Mac ${scope.link.app}',
                hint: const Text('This Mac keeps the pairing, these choices, and the conversations you have read, sealed with the pairing\'s key so nothing else on it can read them (Messages, above, clears them). The phone sends and receives; a relay, where one is used, only ever carries sealed data.'),
              ),
              // The app's own updates (lib/desktop/updates.dart): where they stand, and a look for one when asked.
              if (scope.updates != null)
                ListenableBuilder(
                  listenable: scope.updates!,
                  builder: (context, _) {
                    final u = scope.updates!;
                    final here = u.installed;
                    if (here == null) return const SizedBox.shrink();
                    final ready = u.phase == MacUpdatePhase.ready;
                    final busy = u.phase == MacUpdatePhase.checking || u.phase == MacUpdatePhase.downloading || u.phase == MacUpdatePhase.restarting;
                    return SettingRow(
                      icon: icon(Lucide.download),
                      label: ready ? 'Restart to update' : 'Look for an update',
                      hint: Text('${updateLine(u).replaceFirst(RegExp(r'\.$'), '')}. This is ${here.version} (${here.build}); it updates itself from ghost-sms.com, and quitting puts a waiting update in place too.'),
                      disabled: busy,
                      onPress: busy ? null : (ready ? u.restart : u.check),
                    );
                  },
                ),
            ]),
          ];
          return ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8)),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < sections.length; i++) ...[if (i > 0) SizedBox(height: t.space(4)), sections[i]],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
