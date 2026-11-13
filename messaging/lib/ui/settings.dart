import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../sms.dart';
import 'common.dart';

/// Settings: the look, this phone's number, and what Android has allowed.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SmsStatus? _status;
  String? _own;
  final _number = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await Sms.instance.status();
    final own = await Sms.instance.ownNumber();
    if (!mounted) return;
    setState(() {
      _status = s;
      _own = own;
      if (_number.text.isEmpty && own != null) _number.text = own;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = AppState.of(context);
    final s = _status;
    Widget chip(LucideIcon icon) => AppIcon(icon, size: 18);
    return GhostPage(
      title: 'Settings',
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            GlacierScope(
              attrs: const {'hue': 'indigo'},
              child: PaneSection(title: 'Look', children: [
                SettingRow(
                  icon: chip(Lucide.sunMoon),
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
              ]),
            ),
            SizedBox(height: t.space(6)),
            GlacierScope(
              attrs: const {'hue': 'green'},
              child: PaneSection(
                title: 'Your number',
                footer: Text(_own == null || _own!.isEmpty
                    ? 'Android didn\'t say this phone\'s number. Type it here so group picture messages don\'t list you as one of the people.'
                    : 'Used to leave you out of a group message\'s list of people.'),
                children: [
                  SettingRow(
                    icon: chip(Lucide.phone),
                    label: 'This phone',
                    layout: SettingRowLayout.stacked,
                    control: GlacierInput(
                      controller: _number,
                      placeholder: '+1 555 123 4567',
                      ariaLabel: 'This phone\'s number',
                      inputMode: TextInputType.phone,
                      size: GlacierFieldSize.md,
                      onSubmitted: (v) async {
                        await Sms.instance.setOwnNumber(v.trim());
                        if (context.mounted) toast(context, 'Saved');
                        _refresh();
                      },
                      onBlur: () => Sms.instance.setOwnNumber(_number.text.trim()),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: t.space(6)),
            GlacierScope(
              attrs: const {'hue': 'blue'},
              child: PaneSection(title: 'Android', children: [
                SettingRow(
                  icon: chip(Lucide.messageSquare),
                  label: 'Default SMS app',
                  value: Text(s == null ? '' : (s.isDefault ? 'Yes' : 'No')),
                  onPress: s == null || s.isDefault ? null : () async { await Sms.instance.requestDefault(); _refresh(); },
                ),
                SettingRow(
                  icon: chip(Lucide.users),
                  label: 'Contacts',
                  hint: const Text('Names and photos in place of numbers.'),
                  value: Text(s == null ? '' : (s.contacts ? 'Allowed' : 'Off')),
                  onPress: s == null || s.contacts ? null : () async { await Sms.instance.requestPermissions(); _refresh(); },
                ),
                SettingRow(
                  icon: chip(Lucide.bell),
                  label: 'Notifications',
                  value: Text(s == null ? '' : (s.notifications ? 'Allowed' : 'Off')),
                  onPress: s == null || s.notifications ? null : () async { await Sms.instance.requestPermissions(); _refresh(); },
                ),
              ]),
            ),
            SizedBox(height: t.space(6)),
            GlacierScope(
              attrs: const {'hue': 'graphite'},
              child: PaneSection(
                title: 'About',
                footer: const Text('Your messages stay in Android\'s own message store, so they\'re all still there if you switch back to another app.'),
                children: [
                  SettingRow(icon: chip(Lucide.ghost), label: 'Ghost Messaging', value: const Text('0.2.2')),
                  SettingRow(icon: chip(Lucide.info), label: 'Texts and picture messages', hint: const Text('SMS and MMS through your carrier. RCS and iMessage aren\'t available to apps other than Google\'s and Apple\'s own.')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
