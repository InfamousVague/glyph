import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../emoji_sets.dart';
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
  UpdateState _update = const UpdateState();
  StreamSubscription<UpdateState>? _updates;
  final _number = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _updates = Sms.instance.updates.stream.listen((u) { if (mounted) setState(() => _update = u); });
    Sms.instance.update().then((u) { if (mounted) setState(() => _update = u); }).catchError((_) {});
  }

  /// Where the update stands, in a sentence.
  String _updateLine(UpdateState u) => switch (u.phase) {
        'checking' => 'Checking ${_host(u)}…',
        'upToDate' => 'Up to date.',
        'available' => '${u.available} is available.',
        'downloading' => 'Downloading ${u.available}${u.progress == null ? '' : ' · ${(u.progress! * 100).round()}%'}',
        'ready' => u.error == 'needsPermission' || !u.canInstall
            ? '${u.available} is downloaded. Allow Ghost Messaging to install its own updates, then tap Update now.'
            : '${u.available} is downloaded and ready.',
        'installing' => 'Installing ${u.available}…',
        'failed' => u.error != null && u.error!.contains('not signed by this app')
            ? 'This copy is a test build, signed differently from the release. Install the release from ${_host(u)} once, and it updates itself from then on.'
            : 'Couldn\'t update: ${u.error ?? 'something went wrong'}',
        'disabled' => 'Updates are off in debug builds.',
        _ => 'Looks for a new version when the app opens, at most twice a day.',
      };

  static String _host(UpdateState u) => u.source.replaceFirst('https://', '');

  @override
  void dispose() {
    _updates?.cancel();
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
                SettingRow(
                  icon: chip(Lucide.sparkles),
                  label: 'Message effects',
                  hint: const Text('Confetti for "Congratulations", balloons for "Happy birthday", and more, as a message arrives or is sent.'),
                  control: GlacierSwitch(checked: app.effects, onCheckedChange: app.setEffects, ariaLabel: 'Message effects'),
                ),
              ]),
            ),
            SizedBox(height: t.space(6)),
            GlacierScope(
              attrs: const {'hue': 'amber'},
              child: PaneSection(
                title: 'Emoji',
                footer: const Text('How emoji are drawn in this app. What the other person sees is drawn by their own phone.'),
                children: [
                  for (final set in emojiSets)
                    SettingRow(
                      label: set.name,
                      hint: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(set.about),
                        SizedBox(height: t.space(1)),
                        // Each row in its own set, whichever is chosen: no fallback but the set's (or the phone's).
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          for (final e in emojiSample)
                            Padding(
                              padding: EdgeInsets.only(right: t.space(2)),
                              child: Text(e, style: TextStyle(inherit: false, fontFamily: set.family, fontFamilyFallback: const [], fontSize: t.lenOf('1.35rem'), height: 1.3, color: t.color('app-ink'))),
                            ),
                        ]),
                      ]),
                      control: Pick(checked: app.emoji == set.id, label: 'Use ${set.name} emoji', onPress: () => app.setEmoji(set.id)),
                    ),
                ],
              ),
            ),
            SizedBox(height: t.space(6)),
            GlacierScope(
              attrs: const {'hue': 'cyan'},
              child: PaneSection(
                title: 'Receipts',
                footer: const Text('One tick is sent, two is delivered, two in colour is read. Delivered needs your carrier to send delivery reports. Read exists only for picture and group messages, and only from phones that send read reports; a plain text can\'t say it was read.'),
                children: [
                  SettingRow(
                    icon: chip(Lucide.checkCheck),
                    label: 'Ask for read receipts',
                    hint: const Text('On picture and group messages.'),
                    control: GlacierSwitch(checked: app.readReports, onCheckedChange: app.setReadReports, ariaLabel: 'Ask for read receipts'),
                  ),
                ],
              ),
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
              attrs: const {'hue': 'mint'},
              child: PaneSection(
                title: 'Updates',
                footer: Text(_updateLine(_update)),
                children: [
                  SettingRow(
                    icon: chip(Lucide.download),
                    label: 'Automatic updates',
                    hint: Text('New versions from ${_update.source.isEmpty ? 'ghost-sms.com' : _host(_update)}, downloaded and installed by the app.'),
                    control: GlacierSwitch(
                      checked: _update.auto,
                      ariaLabel: 'Automatic updates',
                      onCheckedChange: (on) async {
                        await Sms.instance.setAutoUpdate(on);
                        final u = await Sms.instance.update();
                        if (mounted) setState(() => _update = u);
                      },
                    ),
                  ),
                  if (_update.phase == 'downloading')
                    SettingRowBox(child: GlacierProgressBar(value: (_update.progress ?? 0) * 100, ariaLabel: 'Downloading the update')),
                  if (_update.phase == 'ready' && (!_update.canInstall || _update.error == 'needsPermission'))
                    SettingRow(icon: chip(Lucide.settings), label: 'Allow installing updates', onPress: () => Sms.instance.allowInstalls()),
                  if (const {'available', 'ready', 'failed'}.contains(_update.phase) && _update.available != null)
                    SettingRow(icon: chip(Lucide.rotateCcw), label: 'Update now', value: Text(_update.available!), onPress: () => Sms.instance.updateInstall())
                  else if (!const {'checking', 'downloading', 'installing', 'disabled'}.contains(_update.phase))
                    SettingRow(icon: chip(Lucide.refreshCw), label: 'Check for updates', onPress: () => Sms.instance.updateCheck()),
                ],
              ),
            ),
            SizedBox(height: t.space(6)),
            GlacierScope(
              attrs: const {'hue': 'graphite'},
              child: PaneSection(
                title: 'About',
                footer: const Text('Your messages stay in Android\'s own message store, so they\'re all still there if you switch back to another app.'),
                children: [
                  SettingRow(icon: chip(Lucide.ghost), label: 'Ghost Messaging', value: Text(_update.current.isEmpty ? '0.3.0' : _update.current)),
                  SettingRow(icon: chip(Lucide.info), label: 'Texts and picture messages', hint: const Text('SMS and MMS through your carrier. RCS and iMessage aren\'t available to apps other than Google\'s and Apple\'s own.')),
                  SettingRow(icon: chip(Lucide.info), label: 'Emoji sets', hint: const Text('Noto Color Emoji and Noto Emoji © Google (SIL OFL 1.1). Twemoji © Twitter and contributors (CC-BY 4.0). All emojis designed by OpenMoji, the open-source emoji and icon project (CC BY-SA 4.0).')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
