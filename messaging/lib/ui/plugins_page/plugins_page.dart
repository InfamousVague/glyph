/// The Plugins page (Matt, 2026-11-17: "redo how the plugins look with their own dedicated plugins page with a
/// marketplace like look how ghostmd has"): Ghost.md's Market (its lib/market/market_screen.dart) for Ghost
/// Messaging's plugins. A band in colour with the plugins' tiles on it, a search, a chip for each shelf, a few
/// featured plugins, and then every plugin on a card: those added, and those to discover. A plugin's own page says
/// what it does, what it reads and keeps, has Add or Remove, and once it is added its settings.
///
/// It is Settings › Plugins (lib/plugins/settings.dart), a screen of its own: on a phone a plugin's page opens over
/// it, and with room (a Fold open, a computer's window) it stands beside the shelves, whose cards go two to four
/// across. Adding a plugin is the registry's switch, as Settings' switches were.
library;

import '../split_handle.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app_state.dart';
import '../../art/app_icon.dart' show LucideIcon;
import '../../art/lucide.g.dart';
import '../../kit/settings_kit.dart';
import '../../kit/settings_type.dart';
import '../../plugins/plugin.dart';
import '../../plugins/registry.dart';
import '../../sms.dart';
import '../common.dart';
import '../dialup/bevel.dart';
import '../settings.dart' show SettingsSeek, settingsMatch;
import 'market_parts.dart';
import 'plugin_cards.dart';
import 'plugin_detail.dart';
import 'plugins_band.dart';

/// The plugins featured at the head of the page, in this order, those the app has.
const List<String> featuredPlugins = ['translate', 'codes', 'spam'];

/// From this wide, a plugin's page stands beside the shelves rather than over them.
const double pluginsWide = 720;

/// Where the plugins run, in a word.
String pluginsHere() => Sms.remote ? (Platform.isIOS ? 'iPhone' : 'computer') : 'phone';

/// What plugins are, in a line: the band's.
String pluginsLine() => 'Extras for your messages, each on this ${pluginsHere()} alone. Adding one is a switch.';

/// What a shelf chip stands for: every plugin (null), those added, or one shelf.
const String _added = 'added';

/// The chip for the plugins meant for circles.
const String _circles = 'circles';

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key, this.registry, this.open, this.settingsOf, this.summaryOf});

  /// The plugins: the app's own where not given.
  final PluginRegistry? registry;

  /// A plugin's id whose page is open from the start.
  final String? open;

  /// A plugin's own settings, as cards, for its page once it is added.
  final List<Widget> Function(BuildContext context, GhostPlugin plugin)? settingsOf;

  /// What a plugin's settings come to, in a line, for its page once it is added.
  final String? Function(BuildContext context, GhostPlugin plugin)? summaryOf;

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  String _query = '';

  /// The chip chosen: null for All, [_added], or a [PluginShelf]'s name.
  String? _shelf;

  /// The plugin whose page stands beside the shelves, with room.
  String? _open;

  /// The setting a search found, to light on its plugin's page.
  String? _seek;
  final _finder = SettingsFinder();
  bool _sought = false;

  PluginRegistry get _registry => widget.registry ?? PluginRegistry.instance;

  @override
  void initState() {
    super.initState();
    _open = widget.open;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sought) return;
    _sought = true;
    // A search's hit for a plugin (its name, or a setting of its own) opens its page, the setting lit on it.
    final seek = SettingsSeek.of(context);
    if (seek == null) return;
    final folded = seek.toLowerCase();
    final plugin = _registry.plugins.where((p) => p.name.toLowerCase() == folded || (p.settingsPage?.label ?? '').toLowerCase() == folded).firstOrNull ??
        _registry.plugins.where((p) => _registry.settingsOf(p).any((s) => s.label.toLowerCase() == folded)).firstOrNull;
    if (plugin == null) return;
    // Opened as [PluginsPage.open] is: beside the shelves with room, over them on a phone (the first layout).
    _open = plugin.id;
    if (plugin.name.toLowerCase() != folded) _seek = seek;
    if (_seek != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => WidgetsBinding.instance.addPostFrameCallback((_) => WidgetsBinding.instance.addPostFrameCallback((_) {
            final found = _finder.find(_seek!);
            if (found == null || !mounted) return;
            Scrollable.ensureVisible(found.context, alignment: 0.25, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
            found.light();
          })));
    }
  }

  bool _wide = false;

  /// The first layout has been: what was open from the start has been put where it goes.
  bool _placed = false;

  void _set(GhostPlugin plugin, bool on) => _registry.setOn(plugin, AppStore(AppState.of(context)), on);

  void _openPlugin(GhostPlugin plugin) {
    if (_wide) return setState(() => _open = _open == plugin.id ? null : plugin.id);
    _push(plugin);
  }

  void _push(GhostPlugin plugin) => push<void>(context, (context) => PluginDetailPage(title: plugin.name, body: (context) => _detail(context, plugin, close: false)));

  Widget _detail(BuildContext context, GhostPlugin plugin, {required bool close}) => pluginDetailOf(
        context,
        _registry,
        plugin,
        settingsOf: widget.settingsOf,
        summaryOf: widget.summaryOf,
        onClose: close ? () => setState(() => _open = null) : null,
        finder: _finder,
        seek: _seek,
      );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final store = AppStore(AppState.of(context));
    return GhostPage(
      title: 'Plugins',
      body: LayoutBuilder(
        builder: (context, box) {
          _wide = box.maxWidth >= pluginsWide;
          // A plugin open from the start (or found by a search) on a phone: its page over the shelves, once they are
          // drawn. Decided here, where the width is known.
          if (!_wide && !_placed && _open != null) {
            final plugin = _registry.plugins.where((p) => p.id == _open).firstOrNull;
            _open = null;
            if (plugin != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _push(plugin);
              });
            }
          }
          _placed = true;
          final open = _wide && _open != null ? _registry.plugins.where((p) => p.id == _open).firstOrNull : null;
          final foot = t.space(8) + MediaQuery.paddingOf(context).bottom;
          final shelves = ListView(
            key: const ValueKey('plugins-scroll'),
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), foot),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _page(context, t, store, wide: _wide, narrowed: open != null)),
                ),
              ),
            ],
          );
          if (open == null) return shelves;
          final bevel = isBevelChrome(t);
          // As made, or as dragged (lib/ui/split_handle.dart): from 300 to what leaves the shelves 360.
          _paneWidth ??= PaneWidth.of(AppState.of(context), 'plugins');
          double fit(double w) => w.clamp(300.0, (box.maxWidth - 360).clamp(300.0, double.infinity));
          final paneW = fit(_paneWidth ?? math.min(440.0, box.maxWidth * 0.42));
          final grip = SplitHandle.widthOf(context);
          return Stack(children: [
            Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: shelves),
              Container(
                key: const ValueKey('plugins-pane'),
                width: paneW,
                decoration: BoxDecoration(
                  color: bevel ? DialupColors.of(t).chrome : t.color('app-paper'),
                  border: Border(left: BorderSide(color: bevel ? DialupColors.of(t).dark : t.color('app-rule'), width: t.len('glacier-hairline'))),
                ),
                child: ListView(
                  key: ValueKey('plugins-pane-${open.id}'),
                  padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), foot),
                  children: [_detail(context, open, close: true)],
                ),
              ),
            ],
            ),
            Positioned(
              key: const ValueKey('plugins-split'),
              right: paneW - grip / 2,
              top: 0,
              bottom: 0,
              width: grip,
              child: SplitHandle(
                label: 'Resize the plugin\'s page',
                onDrag: (dx) => setState(() => _paneWidth = fit(fit(_paneWidth ?? paneW) - dx)),
                onDone: () => PaneWidth.keep(AppState.of(context), 'plugins', _paneWidth),
                onReset: () {
                  setState(() => _paneWidth = null);
                  PaneWidth.keep(AppState.of(context), 'plugins', null);
                },
              ),
            ),
          ]);
        },
      ),
    );
  }

  /// The plugin's page's width as dragged (PaneWidth 'plugins'); null for its width as made.
  double? _paneWidth;

  /// Everything on the shelves' side: the band, the search, the chips and what the chosen shelf holds.
  List<Widget> _page(BuildContext context, Tokens t, PluginStore store, {required bool wide, required bool narrowed}) {
    final all = _registry.plugins;
    final featured = [for (final id in featuredPlugins) ...all.where((p) => p.id == id)];
    final added = [for (final p in all) if (_registry.isOn(p, store)) p];
    final shelves = [for (final s in PluginShelf.values) if (all.any((p) => p.shelf == s)) s];
    final shelf = _shelf;
    final query = _query.trim();
    final searching = query.isNotEmpty;
    // Meant for circles (a circle's owner or admins turn them on for everyone in it) or for this device alone: shown
    // apart (Matt, 2026-11-19: "Label plugins meant for circles in a separate section from the ones that are global").
    bool forCircles(GhostPlugin p) => p.scopes.contains(PluginScope.circle);
    final circled = [for (final p in all) if (forCircles(p)) p];
    bool chosen(GhostPlugin p) => switch (shelf) {
          null => true,
          _added => _registry.isOn(p, store),
          _circles => forCircles(p),
          final name => p.shelf.name == name,
        };
    final found = [for (final p in all) if (chosen(p) && (!searching || _matches(p, query))) p];
    final gap = t.space(6);

    Widget cards(List<GhostPlugin> plugins) {
      PluginCard card(GhostPlugin p) => PluginCard(
            plugin: p,
            added: _registry.isOn(p, store),
            onAdd: () => _set(p, true),
            onOpen: () => _openPlugin(p),
            wide: wide,
            selected: _open == p.id && wide,
          );
      if (!wide) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < plugins.length; i++) ...[if (i > 0) SizedBox(height: t.space(2)), card(plugins[i])],
        ]);
      }
      return MarketGrid(minWidth: t.lenOf(isBevelChrome(t) ? '20rem' : '14rem'), most: narrowed ? 2 : 4, children: [for (final p in plugins) card(p)]);
    }

    Widget shelfOf(String title, List<GhostPlugin> plugins, {String? meta, LucideIcon? icon, Key? key}) => Padding(
          key: key,
          padding: EdgeInsets.only(top: gap),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [MarketHeading(title: title, meta: meta, icon: icon), cards(plugins)]),
        );

    // A circle's plugins under their own heading, with a line saying who turns them on.
    Widget circleShelf(List<GhostPlugin> plugins) => Padding(
          key: const ValueKey('plugins-shelf-circles'),
          padding: EdgeInsets.only(top: gap),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MarketHeading(title: 'For circles', meta: '${plugins.length}', icon: Lucide.circleDot),
            Padding(
              padding: EdgeInsets.only(bottom: t.space(3)),
              child: Text(
                'A circle\'s owner or admins turn these on for everyone in it, in the circle\'s settings. Added here, one works for you in your own spaces and calls too.',
                style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.4),
              ),
            ),
            cards(plugins),
          ]),
        );

    final parts = <Widget>[
      PluginsBand(plugins: [...featured, ...all.where((p) => !featured.contains(p))], added: added.length, line: pluginsLine(), wide: wide),
      SizedBox(height: t.space(4)),
      GlacierSearchField(key: const ValueKey('plugins-search'), value: _query, placeholder: 'Search plugins', size: GlacierFieldSize.md, onValueChange: (v) => setState(() => _query = v)),
      SizedBox(height: t.space(3)),
      _chips(t, [
        MarketChip(key: const ValueKey('plugins-chip-all'), label: 'All', chosen: shelf == null, onPress: () => setState(() => _shelf = null)),
        MarketChip(key: const ValueKey('plugins-chip-added'), label: 'Added', count: added.length, chosen: shelf == _added, onPress: () => setState(() => _shelf = _added)),
        if (circled.isNotEmpty) MarketChip(key: const ValueKey('plugins-chip-circles'), label: 'For circles', chosen: shelf == _circles, onPress: () => setState(() => _shelf = _circles)),
        for (final s in shelves) MarketChip(key: ValueKey('plugins-chip-${s.name}'), label: s.label, chosen: shelf == s.name, onPress: () => setState(() => _shelf = s.name)),
      ], wide: wide),
    ];

    if (found.isEmpty) {
      parts.add(Padding(
        key: const ValueKey('plugins-nothing'),
        padding: EdgeInsets.only(top: gap),
        child: Column(children: [
          Text(searching ? 'Nothing called “$query”.' : (shelf == _added ? 'No plugin is added yet.' : 'No plugin here yet.'), textAlign: TextAlign.center, style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'))),
          SizedBox(height: t.space(3)),
          MarketButton(
            label: 'Show every plugin',
            look: MarketButtonLook.ring,
            onPress: () => setState(() {
              _query = '';
              _shelf = null;
            }),
          ),
        ]),
      ));
      return parts;
    }

    if (searching) {
      parts.add(shelfOf('Found', found, meta: '${found.length}', icon: Lucide.search, key: const ValueKey('plugins-shelf-found')));
      return parts;
    }

    if (shelf == null) {
      if (featured.isNotEmpty) {
        final featuredCards = [
          for (final p in featured) FeaturedPluginCard(plugin: p, added: _registry.isOn(p, store), onAdd: () => _set(p, true), onOpen: () => _openPlugin(p)),
        ];
        // Tall enough for a pitch of three or four lines under the name, whole.
        final height = t.lenOf(isBevelChrome(t) ? '13rem' : '14.5rem');
        parts.add(Padding(
          key: const ValueKey('plugins-featured'),
          padding: EdgeInsets.only(top: gap),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const MarketHeading(title: 'Featured', icon: Lucide.sparkles),
            // Across wherever the three fit, a plugin's page beside the shelves or not; else in a row that scrolls, so
            // the third is not left alone on a row of its own. On a phone the next card peeks past the edge; beside a
            // plugin's page the row fades out before the divider rather than being cut off flat against it.
            LayoutBuilder(builder: (context, box) {
              final least = t.lenOf(narrowed ? '12rem' : '14rem');
              final gap = t.space(3);
              if (wide && box.maxWidth >= featuredCards.length * least + (featuredCards.length - 1) * gap) {
                return MarketGrid(minWidth: least, most: featuredCards.length, children: [for (final c in featuredCards) SizedBox(height: height, child: c)]);
              }
              return MarketRow(width: math.min(t.lenOf('17rem'), box.maxWidth * 0.8), height: height, fade: wide, children: featuredCards);
            }),
          ]),
        ));
      }
      final mine = [for (final p in added) if (!forCircles(p)) p];
      final global = [for (final p in all) if (!forCircles(p)) p];
      final discover = [for (final p in global) if (!_registry.isOn(p, store)) p];
      if (mine.isNotEmpty) parts.add(shelfOf('Added', mine, meta: '${mine.length} of ${global.length}', key: const ValueKey('plugins-shelf-added')));
      if (discover.isNotEmpty) parts.add(shelfOf('Discover', discover, meta: '${discover.length}', key: const ValueKey('plugins-shelf-discover')));
      if (circled.isNotEmpty) parts.add(circleShelf(circled));
      return parts;
    }

    if (shelf == _circles) {
      parts.add(circleShelf(found));
      return parts;
    }
    final title = shelf == _added ? 'Added' : PluginShelf.values.byName(shelf).label;
    parts.add(shelfOf(title, found, meta: '${found.length}', key: ValueKey('plugins-shelf-$shelf')));
    return parts;
  }

  /// The shelves' chips: on a phone a row that scrolls sideways, as a market's filter does (wrapped, "Messages" was
  /// left alone on a second row); with room, wrapped, where they fit on one line.
  Widget _chips(Tokens t, List<Widget> chips, {required bool wide}) {
    final gap = t.space(2);
    if (wide) return Wrap(key: const ValueKey('plugins-chips'), spacing: gap, runSpacing: gap, children: chips);
    return SingleChildScrollView(
      key: const ValueKey('plugins-chips'),
      scrollDirection: Axis.horizontal,
      // Past the page's gutter as it scrolls, to the screen's edge.
      clipBehavior: Clip.none,
      child: Row(children: [for (var i = 0; i < chips.length; i++) ...[if (i > 0) SizedBox(width: gap), chips[i]]]),
    );
  }

  /// Whether [plugin] answers the search: its name, its lines, its shelf or what it adds.
  bool _matches(GhostPlugin plugin, String query) => settingsMatch(query, [plugin.name, plugin.tagline, plugin.description, plugin.shelf.label, ...plugin.adds, plugin.settingsPage?.label ?? ''].join(' '));
}

/// A plugin's page as the Plugins page and a plugin's own screen draw it: Add or Remove, and once it is added its
/// settings and what they come to.
Widget pluginDetailOf(
  BuildContext context,
  PluginRegistry registry,
  GhostPlugin plugin, {
  List<Widget> Function(BuildContext context, GhostPlugin plugin)? settingsOf,
  String? Function(BuildContext context, GhostPlugin plugin)? summaryOf,
  VoidCallback? onClose,
  SettingsFinder? finder,
  String? seek,
}) {
  final store = AppStore(AppState.of(context));
  final added = registry.isOn(plugin, store);
  return PluginDetail(
    key: ValueKey('plugins-page-${plugin.id}'),
    plugin: plugin,
    added: added,
    here: pluginsHere(),
    onSwitch: (on) => registry.setOn(plugin, store, on),
    summary: added ? summaryOf?.call(context, plugin) : null,
    settings: added ? (settingsOf?.call(context, plugin) ?? const []) : const [],
    hasSettings: registry.settingsOf(plugin).isNotEmpty || plugin.settingsPage != null,
    onClose: onClose,
    finder: finder,
    seek: seek,
  );
}

/// A plugin's own section of Settings (`plugin-<id>`, opened by a link or a search): its page from the Plugins page,
/// on a screen of its own. It was a plain list of rows with the plugin's switch on a card at its top, then a second
/// switch for translating as texts come, which read as two switches saying different things; now it is the same page
/// as on the shelves, its colour across the head and Add or Remove under it.
class PluginScreen extends StatefulWidget {
  const PluginScreen({super.key, required this.registry, required this.plugin, this.settingsOf, this.summaryOf});

  final PluginRegistry registry;
  final GhostPlugin plugin;
  final List<Widget> Function(BuildContext context, GhostPlugin plugin)? settingsOf;
  final String? Function(BuildContext context, GhostPlugin plugin)? summaryOf;

  @override
  State<PluginScreen> createState() => _PluginScreenState();
}

class _PluginScreenState extends State<PluginScreen> {
  final _finder = SettingsFinder();
  String? _seek;
  bool _sought = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sought) return;
    _sought = true;
    // A search's hit for one of its settings: lit on the page, as the Plugins page lights it.
    final seek = SettingsSeek.of(context);
    if (seek == null || seek.toLowerCase() == widget.plugin.name.toLowerCase()) return;
    _seek = seek;
    WidgetsBinding.instance.addPostFrameCallback((_) => WidgetsBinding.instance.addPostFrameCallback((_) {
          final found = _finder.find(seek);
          if (found == null || !mounted) return;
          Scrollable.ensureVisible(found.context, alignment: 0.25, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
          found.light();
        }));
  }

  @override
  Widget build(BuildContext context) => PluginDetailPage(
        title: widget.plugin.name,
        body: (context) => pluginDetailOf(context, widget.registry, widget.plugin, settingsOf: widget.settingsOf, summaryOf: widget.summaryOf, finder: _finder, seek: _seek),
      );
}

/// Settings' way to the Plugins page, where its row was: the band, short, with a few of the plugins' tiles on it and
/// how many are added. Ringed in the ink while the page stands beside Settings' list.
class PluginsEntry extends StatelessWidget {
  const PluginsEntry({super.key, required this.registry, required this.onOpen, this.selected = false});

  final PluginRegistry registry;
  final VoidCallback onOpen;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final store = AppStore(AppState.of(context));
    final all = registry.plugins;
    final featured = [for (final id in featuredPlugins) ...all.where((p) => p.id == id)];
    final added = all.where((p) => registry.isOn(p, store)).length;
    final radius = isBevelChrome(t) ? 0.0 : t.radius('lg') * 1.2;
    return GlacierPressable(
      key: const ValueKey('plugins-entry'),
      onPressed: onOpen,
      semanticLabel: 'Plugins, $added of ${all.length} added',
      selected: selected,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: radius,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: state.pressed && !isBevelChrome(t) ? 0.985 : 1,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), border: selected ? Border.all(color: t.color('app-ink'), width: 2) : null),
            child: ExcludeSemantics(child: PluginsBand(plugins: [...featured, ...all.where((p) => !featured.contains(p))], added: added, line: pluginsLine(), wide: false, compact: true)),
          ),
        ),
      ),
    );
  }
}
