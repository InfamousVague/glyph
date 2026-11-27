import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../l10n/words.dart';
import '../packs/resource_pack.dart';
import 'common.dart';

/// Choosing the resource pack the look Runestone draws with (lib/packs/resource_pack.dart; Matt, 2026-11-27: "see how
/// we can get the dark vanilla texture pack", then "let's try the duckscape theme instead and bring in the pixelated
/// looks"): the packs kept on this device, one of them in use or none, and the hub's list to fetch another from.

/// Settings › Appearance's section, shown while the look is Runestone on a device that can have packs.
PaneSection resourcePackSection(BuildContext context, AppState app) {
  final t = context.tokens;
  final packs = ResourcePacks.instance;
  final chosen = app.choice(ResourcePacks.pref, '');
  Widget tick(bool on) => on ? AppIcon(Lucide.check, size: 18, color: t.color('app-ink')) : const SizedBox.shrink();
  return PaneSection(
    title: 'Textures',
    footer: const Tr('Runestone can draw its windows, buttons and chat parchment from a resource pack: pixel art that players of the game it is modelled on have made for it. A pack is its artist\'s own work. It is fetched to this device from the packs\' own hub and is not part of this app.'),
    children: [
      SettingRow(
        key: const ValueKey('pack-none'),
        icon: AppIcon(Lucide.square, size: 18),
        label: 'Plain stone',
        hint: const Tr('No pack: flat colours'),
        value: tick(chosen.isEmpty),
        onPress: () => packs.use(app, ''),
      ),
      for (final e in packs.installed())
        SettingRow(
          key: ValueKey('pack-${e.id}'),
          icon: AppIcon(Lucide.image, size: 18),
          label: e.name,
          hint: Text(e.author.isEmpty ? 'A resource pack'.t : '${'By'.t} ${e.author}'),
          value: tick(chosen == e.id),
          onPress: () => chosen == e.id ? _packMenu(context, app, e) : packs.use(app, e.id),
        ),
      SettingRow(
        key: const ValueKey('pack-get'),
        icon: AppIcon(Lucide.download, size: 18),
        label: 'Get a resource pack',
        hint: const Tr('Choose one from the hub to fetch'),
        onPress: () => push<void>(context, (_) => ResourcePackHubScreen(app: app)),
      ),
    ],
  );
}

/// The pack in use, pressed: stop using it, or take it off this device.
void _packMenu(BuildContext context, AppState app, PackEntry e) {
  final packs = ResourcePacks.instance;
  showChoices(context, title: e.name, choices: [
    Choice('Use plain stone', Lucide.square, () => packs.use(app, '')),
    Choice('Remove from this device', Lucide.trash2, () => packs.remove(app, e.id)),
  ]);
}

/// The hub's packs, to fetch one from: each with who made it, a field to find one by name, and Get.
class ResourcePackHubScreen extends StatefulWidget {
  const ResourcePackHubScreen({super.key, required this.app, this.packs});
  final AppState app;

  /// The packs asked, [ResourcePacks.instance] where null.
  final ResourcePacks? packs;

  @override
  State<ResourcePackHubScreen> createState() => _ResourcePackHubScreenState();
}

class _ResourcePackHubScreenState extends State<ResourcePackHubScreen> {
  List<PackEntry>? _list;
  String? _problem;
  String _find = '';

  /// The pack being fetched, by its id.
  String? _getting;

  ResourcePacks get _packs => widget.packs ?? ResourcePacks.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _problem = null);
    try {
      final list = await _packs.hub();
      if (mounted) setState(() => _list = list);
    } catch (_) {
      if (mounted) setState(() => _problem = 'The list of packs couldn\'t be fetched. Check the connection and try again.'.t);
    }
  }

  Future<void> _get(PackEntry e) async {
    if (_getting != null) return;
    setState(() => _getting = e.id);
    try {
      await _packs.install(widget.app, e);
      if (!mounted) return;
      toast(context, '${e.name}: ${'in use'.t}');
      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) toast(context, '${e.name}: ${'couldn\'t be fetched'.t}', tone: GlacierToastTone.danger);
    } finally {
      if (mounted) setState(() => _getting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final find = _find.trim().toLowerCase();
    final shown = [
      for (final e in _list ?? const <PackEntry>[])
        if (find.isEmpty || e.name.toLowerCase().contains(find) || e.author.toLowerCase().contains(find) || e.tags.any((tag) => tag.toLowerCase().contains(find))) e,
    ];
    final have = {for (final e in _packs.installed()) e.id: e.commit};
    return GhostPage(
      title: 'Resource packs',
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8)),
          children: [
            PaneSection(
              description: const Tr('Each pack is its artist\'s own work, made for the game Runestone is modelled on and kept in the packs\' hub on GitHub. Get fetches one to this device; nothing of it is sent anywhere.'),
              children: [
                SettingRowBox(
                  child: GlacierInput(
                    key: const ValueKey('pack-find'),
                    placeholder: 'Find a pack',
                    ariaLabel: 'Find a pack',
                    onChange: (v) => setState(() => _find = v),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space(5)),
            if (_problem != null)
              PaneSection(children: [
                SettingRow(icon: AppIcon(Lucide.wifiOff, size: 18), label: 'Not fetched', hint: Text(_problem!), value: Text('Try again'.t), onPress: _load),
              ])
            else if (_list == null)
              PaneSection(children: [SettingRow(icon: AppIcon(Lucide.loaderCircle, size: 18), label: 'Fetching the list', hint: const Tr('From the packs\' hub'))])
            else
              PaneSection(
                title: 'Packs',
                children: [
                  for (final e in shown)
                    SettingRow(
                      key: ValueKey('hub-${e.id}'),
                      icon: AppIcon(Lucide.image, size: 18),
                      label: e.name,
                      hint: Text(e.author.isEmpty ? 'A resource pack'.t : '${'By'.t} ${e.author}'),
                      value: Text(_getting == e.id ? 'Fetching'.t : (have[e.id] == null ? 'Get'.t : (have[e.id] == e.commit ? 'Use'.t : 'Update'.t))),
                      disabled: _getting != null && _getting != e.id,
                      onPress: () => _get(e),
                    ),
                  if (shown.isEmpty) SettingRow(icon: AppIcon(Lucide.search, size: 18), label: 'No pack by that name'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
