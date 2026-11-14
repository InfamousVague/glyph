import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app_state.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_kit.dart';
import '../../ui/common.dart';
import '../../ui/computers.dart';
import '../../ui/settings.dart';
import '../../ui/settings_panes.dart' show aboutLicences;
import '../link/link.dart';
import '../remote.dart';
import '../updates.dart';
import 'update_bar.dart';
import 'wizard.dart';

/// What a computer adds to Settings. A computer has the phone's Settings and its pages (Matt, 2026-11-14: "desktop
/// and mobile should also share the same settings pages", and "a full features settings page like the ghost
/// markdown app ... instead of the one small settings panel we have now"); these are the sections that are the
/// computer's alone, which stand where the phone has its own (Computers, Updates, About): the phone it is paired
/// with and how the two connect, what is kept on this Mac, the Mac app's updates, and what it is.
///
/// The frame makes one while a phone is paired (lib/desktop/ui/shell.dart) and hands its sections to Settings
/// (SettingsSources), which is drawn again as the link, the updates or this change.
class DeskSettings extends ChangeNotifier {
  DeskSettings({required this.link, required this.calls, this.updates, this.envPeers = const []});

  final PhoneLink link;
  final LinkCalls calls;
  final MacUpdates? updates;
  final List<Peer> envPeers;

  /// How much of what was read is kept on this Mac (lib/desktop/cache.dart); null until it has been counted.
  ({int conversations, int bytes})? kept;
  DateTime _counted = DateTime.fromMillisecondsSinceEpoch(0);
  bool _gone = false;

  /// Counts what is kept. Asked each time its row or its page is drawn, so it is counted no oftener than every few
  /// seconds unless [now].
  void countKept({bool now = false}) {
    final at = DateTime.now();
    if (!now && at.difference(_counted) < const Duration(seconds: 3)) return;
    _counted = at;
    calls.cache.size().then((k) {
      if (_gone || k == kept) return;
      kept = k;
      notifyListeners();
    });
  }

  /// What Settings is drawn again for.
  List<Listenable> get watch => [this, link, ?updates];

  /// Before the app's own sections: the phone.
  List<SettingsSection> first() => [
        SettingsSection(
          id: 'phone',
          where: SettingsWhere.computer,
          label: 'Your phone',
          icon: const AppIcon(LucideMore.smartphone, size: 18),
          hue: 'blue',
          group: 'computer',
          summary: (m) => link.phone == null ? 'Not paired' : '${link.phone!.name} · ${_linkShort(link)}',
          page: (context, m) => _phonePage(context, this),
        ),
      ];

  /// After them: what is the Mac app's own.
  List<SettingsSection> after() => [
        SettingsSection(
          id: 'kept',
          where: SettingsWhere.computer,
          label: 'Kept on this Mac',
          icon: const AppIcon(Lucide.hardDrive, size: 18),
          hue: 'slate',
          group: 'app',
          summary: (m) {
            countKept();
            final k = kept;
            return k == null || k.bytes == 0 ? 'Nothing yet' : '${_conversations(k.conversations)} · ${keptSize(k.bytes)}';
          },
          page: (context, m) => _keptPage(context, this),
        ),
        SettingsSection(
          id: 'mac-updates',
          where: SettingsWhere.computer,
          label: 'Updates',
          icon: const AppIcon(Lucide.download, size: 18),
          hue: 'mint',
          group: 'app',
          // A copy that looks for none (a test, one run from the build folder) has nothing to say here.
          when: (m) => updates?.installed != null,
          summary: (m) => _updateShort(updates!),
          page: (context, m) => _updatesPage(context, this),
        ),
        SettingsSection(
          id: 'mac-about',
          where: SettingsWhere.computer,
          label: 'About',
          icon: const AppIcon(Lucide.info, size: 18),
          hue: 'graphite',
          group: 'app',
          summary: (m) => 'Ghost Messaging for the Mac ${link.app}',
          page: (context, m) => _aboutPage(context, this),
        ),
      ];

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}

Widget _icon(LucideIcon i) => AppIcon(i, size: 18);

String _conversations(int n) => '$n ${n == 1 ? 'conversation' : 'conversations'}';

/// A size on disk, as a person reads it.
String keptSize(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

/// How the phone is connected, in a word or two, for the row on Settings' list.
String _linkShort(PhoneLink link) {
  if (link.refused) return 'no longer paired';
  return switch (link.via) { 'local' => 'local network', 'relay' => 'through the relay', _ => 'not connected' };
}

/// Where the Mac app's update stands, short, for the row on Settings' list.
String _updateShort(MacUpdates u) {
  final version = u.release?.version ?? '';
  return switch (u.phase) {
    MacUpdatePhase.idle => u.checked == null ? 'Not looked for yet' : 'Up to date',
    MacUpdatePhase.checking => 'Looking…',
    MacUpdatePhase.downloading => 'Getting $version',
    MacUpdatePhase.ready => '$version is ready',
    MacUpdatePhase.restarting => 'Restarting…',
    MacUpdatePhase.manual => '$version is out',
    MacUpdatePhase.failed => 'Couldn\'t update',
  };
}

// --- Your phone -------------------------------------------------------------------------------------------------------

List<Widget> _phonePage(BuildContext context, DeskSettings d) {
  final link = d.link;
  final phone = link.phone;
  if (phone == null) return const [];
  return [
    PaneSection(title: 'Paired with', children: [
      SettingRow(
        icon: _icon(LucideMore.smartphone),
        label: phone.name,
        hint: Text('${linkLine(link)} · paired ${listWhen(phone.since)}'),
      ),
    ]),
    ConnectionChoice(value: phone.mode, relay: phone.relay, onChanged: (m) => link.setMode(m)),
    PaneSection(
      title: 'If the phone isn\'t found',
      footer: const Text('The phone announces itself on the network and this Mac looks for it. Where a network keeps the two from finding each other, give the phone\'s address: it is on the phone under Settings › Computers.'),
      children: [SettingRowBox(child: _AddressField(settings: d))],
    ),
    PaneSection(children: [
      SettingRow(
        icon: _icon(Lucide.unlink),
        label: 'Unpair this phone',
        hint: const Text('This Mac stops showing the phone\'s texts, and the key is deleted from both.'),
        onPress: () => showChoices(context, title: 'Unpair ${phone.name}? Its conversations leave this Mac, and the key the two share is deleted.', choices: [
          Choice('Unpair', Lucide.unlink, () async {
            d.calls.forget();
            await link.unpair();
          }, danger: true),
        ]),
      ),
    ]),
  ];
}

/// The phone's address, given by hand for a network where it is not found by itself.
class _AddressField extends StatefulWidget {
  const _AddressField({required this.settings});
  final DeskSettings settings;

  @override
  State<_AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<_AddressField> {
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

  void _save() {
    final d = widget.settings;
    final app = AppState.of(context);
    final text = _address.text.trim();
    // Left as it was (the field is left each time another row is pressed): nothing to say.
    if (text == app.choice('peer', '')) return;
    final peer = Peer.parse(text);
    if (text.isNotEmpty && peer == null) {
      toast(context, 'That isn\'t an address and a port, like 192.168.1.20:47811', tone: GlacierToastTone.danger);
      return;
    }
    app.set('peer', text);
    d.link.given = [...d.envPeers, ?peer];
    d.link.look();
    toast(context, text.isEmpty ? 'The phone is looked for by itself' : 'Saved. Trying it now.');
  }

  @override
  Widget build(BuildContext context) {
    return GlacierInput(
      controller: _address,
      placeholder: '192.168.1.20:47811',
      ariaLabel: 'The phone\'s address and port',
      autoCorrect: false,
      autoCapitalize: TextCapitalization.none,
      size: GlacierFieldSize.md,
      onSubmitted: (_) => _save(),
      onBlur: _save,
    );
  }
}

// --- Kept on this Mac -------------------------------------------------------------------------------------------------

/// What was read from the phone is kept here (Matt, 2026-11-14: "cache messages on the desktop app so that we don't
/// need to fetch them all from the phone every time"): how much, and a way to clear it.
List<Widget> _keptPage(BuildContext context, DeskSettings d) {
  d.countKept();
  final k = d.kept;
  final nothing = k == null || k.bytes == 0;
  return [
    PaneSection(
      title: 'Conversations and messages',
      description: const Text('The list and the conversations you open are kept on this Mac, sealed with your pairing\'s key, so they open at once and are there while your phone is away. Only what is new is fetched from your phone.'),
      children: [
        SettingRow(icon: _icon(Lucide.messageSquare), label: 'Conversations kept', value: Text(k == null ? '' : '${k.conversations}')),
        SettingRow(icon: _icon(Lucide.hardDrive), label: 'Space used', value: Text(k == null ? '' : (k.bytes == 0 ? 'None' : keptSize(k.bytes)))),
      ],
    ),
    PaneSection(
      footer: const Text('They are read from your phone again as you open them. Unpairing clears them too.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.trash2),
          label: 'Clear what is kept',
          disabled: nothing,
          onPress: nothing
              ? null
              : () => showChoices(context, title: 'Clear the conversations and messages kept on this Mac? They are read from your phone again as you open them.', choices: [
                    Choice('Clear what is kept', Lucide.trash2, () async {
                      await d.calls.clearKept();
                      d.countKept(now: true);
                      if (context.mounted) toast(context, 'Cleared');
                    }, danger: true),
                  ]),
        ),
      ],
    ),
  ];
}

// --- Updates ----------------------------------------------------------------------------------------------------------

/// The Mac app's own updates (lib/desktop/updates.dart): where they stand, and a look for one when asked.
List<Widget> _updatesPage(BuildContext context, DeskSettings d) {
  final u = d.updates;
  final here = u?.installed;
  if (u == null || here == null) return const [];
  final ready = u.phase == MacUpdatePhase.ready;
  final busy = u.phase == MacUpdatePhase.checking || u.phase == MacUpdatePhase.downloading || u.phase == MacUpdatePhase.restarting;
  return [
    PaneSection(
      title: 'Ghost Messaging for the Mac',
      footer: const Text('It updates itself from ghost-sms.com: a newer version is fetched behind the screens and put in place when you restart, or the next time you quit.'),
      children: [
        SettingRow(icon: _icon(Lucide.ghost), label: 'This version', value: Text('${here.version} (${here.build})')),
        SettingRow(
          icon: _icon(ready ? Lucide.rotateCcw : Lucide.download),
          label: ready ? 'Restart to update' : 'Look for an update',
          hint: Text(updateLine(u)),
          disabled: busy,
          onPress: busy ? null : (ready ? u.restart : u.check),
        ),
        if (u.phase == MacUpdatePhase.downloading) SettingRowBox(child: GlacierProgressBar(value: u.progress * 100, ariaLabel: 'Getting the update')),
      ],
    ),
  ];
}

// --- About ------------------------------------------------------------------------------------------------------------

List<Widget> _aboutPage(BuildContext context, DeskSettings d) {
  return [
    PaneSection(title: 'Ghost Messaging for the Mac', children: [
      SettingRow(icon: _icon(Lucide.ghost), label: 'Version', value: Text(d.link.app)),
      SettingRow(
        icon: _icon(LucideMore.smartphone),
        label: 'Your phone sends and receives',
        hint: const Text('This Mac shows what your phone has and sends through it, sealed between the two. A relay, where one is used, only ever carries sealed data.'),
      ),
      SettingRow(
        icon: _icon(Lucide.lock),
        label: 'What this Mac keeps',
        hint: const Text('The pairing, your choices here, and the conversations you have read, sealed with the pairing\'s key so nothing else on it can read them. Settings › Kept on this Mac clears them.'),
      ),
    ]),
    aboutLicences(),
  ];
}
