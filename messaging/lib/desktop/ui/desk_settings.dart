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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) return;
    _read = true;
    _address.text = AppState.of(context).choice('peer', '');
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

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
            ]),
            PaneSection(title: 'About', children: [
              SettingRow(
                icon: icon(Lucide.info),
                label: 'Ghost Messaging for the Mac ${scope.link.app}',
                hint: const Text('This Mac keeps the pairing and these choices, and nothing else: your texts are held in memory while the app is open and read from the phone again each time. The phone sends and receives; a relay, where one is used, only ever carries sealed data.'),
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
