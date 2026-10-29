/// The Market (Matt, 2026-10-26: "Make the plugins a dedicated "Market" section in the app, include some more
/// themes, fonts an of course all our plugins with vivid iconography and imagery where possible include mobile and
/// desktop support and move the plugins section out of the settings (leaving plugin specific settings to own their
/// settings) add the plugins setting to the market page"): a place of its own (lib/shell/screen.dart
/// [ScreenMarket]) where every plugin, theme and font Ghost.md carries is laid out to browse and add.
///
/// It opens on what it is, a band in colour with the plugins' marks on it, then a search across everything and the
/// shelves to choose between: All, Plugins, Themes, Fonts. All leads with the featured plugins (those whose brand
/// Ghost.md draws), then the themes, the fonts and every plugin; each other shelf is its kind alone, the plugins with
/// their categories to filter by, the themes with the accents after them, the fonts as a note's and as the
/// interface's. What is typed in the search filters every shelf at once, and a search that leaves nothing says so,
/// with the way back to everything.
///
/// What was Settings › Plugins' own is here now: how many plugins are added of how many, the word that Local only is
/// on and holds the plugins that use the internet off (with its way to Account › Privacy), and the Added and Discover
/// shelves. A plugin's own page in Settings stays there (lib/settings/settings_sections.dart `pluginPageSections`);
/// a plugin's page here has the way to it ([onPluginSettings]).
///
/// **Setting one up** (Matt, 2026-10-28: "For each of the plugins add a small onboarding flow start with the lovart and
/// Claude plugins walk the user through setting up an account and getting their keys"): a plugin added here, from its
/// card, a featured card or its page, that has a setup ([GlyphPlugin.setup]) and still needs it (Lovart with no keys)
/// opens that setup at once over the Market (lib/plugins/onboarding/setup_sheet.dart): its account, its keys, a check
/// that they work. Skip puts it away; its page in Settings has Set up until the keys are kept.
///
/// On a phone the page is one column: the featured plugins, the themes and the fonts are rows that scroll sideways,
/// the plugins a card each down the page, and a plugin's page takes the screen, its way back the bar's arrow and the
/// back gesture. With room (a Fold open, a Mac), the cards stand two to four across, and a plugin's page opens beside
/// them, the shelves still there to press another.
///
/// A link opens it at one thing (`ghostmd://market/<kind>/<id>`, [MarketScreen.link]; Matt, 2026-10-26: "add a
/// browsable marketplace listed under the plugins section on the website that deeplinks to the app"): the website's
/// market page (landing/market.html) lists what this Market lists (landing/market.json, made from the same lists by
/// test/market/market_listing_test.dart), and each thing's Open in Ghost.md comes here. A plugin opens on its page
/// with Add; a theme or a face is held at the head of its shelf ([_Linked]), with the way to use it, since neither has
/// a page of its own; a link naming nothing this build has opens the front with a word saying so ([_LinkNote]).
///
/// Advanced mode's: simple mode hides every way in, as it hid Settings › Plugins, and a link that comes in Simple is
/// answered with a word instead (lib/root/ghost_root.dart `_marketInSimple`).
///
/// The icon packs have a shelf of their own, Icons (Matt, 2026-10-27: "add three icon styles (outline, solid and
/// filled) and add a few different icon packs for the app to choose from"; lib/market/market_icons.dart): a card for
/// each pack with twelve of the app's icons in all three styles, the style to draw them in under the cards, and a
/// page for each pack that opens as a plugin's does, with Use this pack (`ghostmd://market/icons/<id>` opens on it).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/back.dart';
import '../core/preferences.dart';
import '../plugins/catalogue.dart';
import '../plugins/onboarding/setup_flow.dart' show PluginSetup;
import '../plugins/onboarding/setup_sheet.dart';
import '../plugins/reach.dart';
import '../plugins/registry.dart';
import '../plugins/types.dart';
import '../settings/accent_swatch.dart';
import '../settings/kit/settings_type.dart';
import '../settings/theme_cards.dart';
import '../settings/words.dart' show faceWords;
import '../share/app_links.dart' show MarketPlace;
import '../shell/header_pane.dart';
import '../shell/page_dock.dart';
import 'market_cards.dart';
import 'market_items.dart';
import 'market_icons.dart';
import 'market_looks.dart';
import 'market_plugins.dart';

/// The width from which the Market lays its cards across and opens a plugin's page beside them.
const double marketWide = 720;

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key, required this.onBack, this.plugin, this.link, this.onPluginSettings, this.onLocalOnly, this.registry, this.prefs, this.dock, this.shelf, this.offerSetup = true});

  /// Home, from the bar's arrow.
  final VoidCallback onBack;

  /// The plugin whose page it opens on, from a link (an old Settings › Plugins › its name).
  final String? plugin;

  /// Where a `ghostmd://market` link said to open it (lib/share/app_links.dart [MarketPlace]): a plugin's page, a
  /// theme or a face at the head of its shelf, a shelf, or the front with a word for a link it cannot follow.
  final MarketPlace? link;

  /// Opens a plugin's own page in Settings, by the plugin's id.
  final ValueChanged<String>? onPluginSettings;

  /// Opens Account at its Privacy card, for "Local only".
  final VoidCallback? onLocalOnly;

  /// The plugins; the app's when null.
  final Registry? registry;

  /// The preferences a theme and a face are set in, and Local only read from; the app's when null.
  final PreferencesStore? prefs;

  /// The dock (docs/DOCK.md); none where it is left out.
  final PageDockSeam? dock;

  /// The shelf it opens on; All when null.
  final MarketShelf? shelf;

  /// Whether a plugin added here that still needs its keys opens its setup at once (lib/plugins/onboarding/; Matt,
  /// 2026-10-28: "For each of the plugins add a small onboarding flow"). A test of the shelves alone turns it off.
  final bool offerSetup;

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  /// Where [MarketScreen.link] lands, read once as the screen is made: a link is followed when it comes, and the
  /// Market is made anew for the next one (lib/shell/app_shell.dart keys it by the link).
  late final MarketLanding? _landing = widget.link == null ? null : marketLinkLanding(widget.link!, plugins: _registry.all());

  late MarketShelf _shelf = widget.shelf ?? _landing?.shelf ?? MarketShelf.all;
  String _query = '';

  /// The category chosen on the Plugins shelf; null is every one.
  PluginCategory? _category;

  /// The plugin whose page is open.
  late String? _open = widget.plugin ?? _landing?.plugin;

  /// The icon pack whose page is open, where no plugin's is.
  late String? _openPack = widget.plugin == null ? _landing?.icons : null;

  /// The theme or the face a link named, held at the head of its shelf until it is put away or the shelf is left.
  late String? _linkedTheme = _landing?.theme;
  late String? _linkedFace = _landing?.face;

  /// The word for a link the Market could not follow, until it is put away.
  late String? _missing = _landing?.missing;

  final ScrollController _scroll = ScrollController();

  /// The setup open over the Market, for the plugin just added; null when none is.
  PluginSetup? _setup;

  Registry get _registry => widget.registry ?? plugins;
  PreferencesStore get _prefs => widget.prefs ?? preferences;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openPlugin(String id) => setState(() {
        _open = id;
        _openPack = null;
      });

  /// Adds the plugin [id], then offers its setup where it has one and it is still needed: Lovart with no keys yet.
  void _add(String id) {
    final registry = _registry;
    registry.setEnabled(id, true);
    final make = registry.byId(id)?.setup;
    if (!widget.offerSetup || make == null || !registry.isEnabled(id)) return;
    final setup = make();
    final prepare = setup.prepare;
    void offer() {
      if (mounted && !setup.ready() && registry.isEnabled(id)) setState(() => _setup = setup);
    }

    if (prepare == null) {
      offer();
    } else {
      // The keys are read first, so a plugin whose keys arrived from another device is not set up twice.
      prepare().then((_) => offer(), onError: (Object _) => offer());
    }
  }

  void _openIcons(String id) => setState(() {
        _openPack = id;
        _open = null;
      });

  void _close() => setState(() {
        _open = null;
        _openPack = null;
      });

  void _toShelf(MarketShelf shelf) {
    setState(() {
      _shelf = shelf;
      // What a link held at the head of its shelf goes with the shelf.
      if (shelf != MarketShelf.themes) _linkedTheme = null;
      if (shelf != MarketShelf.fonts) _linkedFace = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: Listenable.merge([_registry, _prefs]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= marketWide;
          final plugin = _open == null ? null : _registry.byId(_open!);
          final pack = plugin == null && _openPack != null && isIconPack(_openPack) ? iconPackOf(_openPack) : null;
          // The page open, a plugin's or an icon pack's: its key, its name for the bar, and the page itself.
          final open = plugin == null ? (pack == null ? null : (id: 'icons-${pack.id}', name: pack.name)) : (id: plugin.manifest.id, name: plugin.manifest.name);
          Widget detail({required bool close}) => plugin != null ? _detail(plugin, close: close) : _packDetail(pack!, close: close);
          final safeTop = t.len('app-safe-top');
          final hairline = t.len('glacier-hairline');
          final bar = safeTop + t.space(2) * 2 + t.space(8) + hairline * 2;
          final top = bar.roundToDouble() + t.space(4);
          final dock = widget.dock;
          final foot = t.len('app-safe-bottom') + (dock == null ? t.space(10) : math.max(t.space(10), pageDockRoom(t, dock.rings)));
          final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');
          final pad = EdgeInsetsDirectional.fromSTEB(gutterStart, top, gutterEnd, foot);

          // A phone's plugin page takes the screen; with room it stands beside the shelves.
          final paneWidth = math.min(440.0, box.maxWidth * 0.42);
          final Widget body;
          if (open != null && !wide) {
            body = OnBack(
              key: const ValueKey('back:market-plugin'),
              onBack: _close,
              child: SingleChildScrollView(key: ValueKey('market-page-${open.id}'), padding: pad, child: detail(close: false)),
            );
          } else {
            final shelves = SingleChildScrollView(
              key: const ValueKey('market-scroll'),
              controller: _scroll,
              padding: pad,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _page(t, wide: wide, narrowed: open != null)),
                ),
              ),
            );
            body = open == null
                ? shelves
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: shelves),
                      OnBack(
                        key: const ValueKey('back:market-plugin'),
                        onBack: _close,
                        child: Container(
                          key: const ValueKey('market-pane'),
                          width: paneWidth,
                          decoration: BoxDecoration(color: t.color('app-paper'), border: Border(left: BorderSide(color: t.color('app-rule'), width: hairline))),
                          child: SingleChildScrollView(
                            key: ValueKey('market-page-${open.id}'),
                            padding: EdgeInsets.fromLTRB(t.space(4), top, t.space(4), foot),
                            child: detail(close: true),
                          ),
                        ),
                      ),
                    ],
                  );
          }

          final title = open != null && !wide ? open.name : 'Market';
          return ColoredBox(
            color: t.color('glacier-bg'),
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(child: dock == null ? body : PageDockFrame(seam: dock, child: body)),
                  // Drawn over the app, wherever it is built (lib/sheet/sheet.dart): it takes no room here.
                  if (_setup case final setup?) PluginSetupSheet(key: ValueKey('market-setup-${setup.id}'), setup: setup, prefs: _prefs, onClose: () => setState(() => _setup = null)),
                  HeaderPane(
                    child: Padding(
                      key: const ValueKey('market-bar'),
                      padding: EdgeInsetsDirectional.fromSTEB(gutterStart - t.space(2), t.space(2), gutterEnd, t.space(2)),
                      child: Row(
                        spacing: t.space(2),
                        children: [
                          GlacierPressable(
                            key: const ValueKey('market-back'),
                            onPressed: open != null && !wide ? _close : widget.onBack,
                            semanticLabel: open != null && !wide ? 'Back to the Market' : 'Back to home',
                            builder: (context, state) => GlacierFocusRing(
                              visible: state.focused,
                              child: SizedBox.square(dimension: t.space(8), child: Center(child: AppIcon(Lucide.arrowLeft, size: 20, color: t.color('app-ink')))),
                            ),
                          ),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// A plugin's page, switched through the registry.
  Widget _detail(GlyphPlugin plugin, {required bool close}) {
    final registry = _registry;
    final id = plugin.manifest.id;
    final held = _prefs.value.localOnly && usesNetwork(plugin.manifest);
    final settings = widget.onPluginSettings;
    return PluginDetail(
      plugin: plugin,
      added: registry.switchedOn(id),
      on: registry.isEnabled(id),
      held: held,
      onSwitch: (on) => on ? _add(id) : registry.setEnabled(id, false),
      onSettings: settings == null || plugin.settings == null ? null : () => settings(id),
      onLocalOnly: widget.onLocalOnly,
      onClose: close ? _close : null,
    );
  }

  /// An icon pack's page: Use this pack, and the style, each written to the preferences, which the app is drawn from.
  Widget _packDetail(IconPack pack, {required bool close}) {
    final prefs = _prefs.value;
    return IconPackDetail(
      pack: pack,
      inUse: iconPackOf(prefs.iconPack).id == pack.id,
      style: IconStyle.of(prefs.iconStyle),
      onUse: () => _prefs.update((now) => now.copyWith(iconPack: pack.id)),
      onStyle: (style) => _prefs.update((now) => now.copyWith(iconStyle: style.name)),
      onClose: close ? _close : null,
    );
  }

  /// Everything above the plugin's page: the band, the search, the shelves' control and what the shelf holds.
  List<Widget> _page(Tokens t, {required bool wide, required bool narrowed}) {
    final registry = _registry;
    final prefs = _prefs.value;
    final query = _query;
    final all = catalogueOrder(registry.all());
    final options = themeOptions(t);
    final shelf = _shelf;
    final searching = query.trim().isNotEmpty;
    final gap = t.space(6);

    // What each shelf would show, the search applied.
    final categories = categoriesOf(all);
    final category = categories.contains(_category) ? _category : null;
    final found = [
      for (final plugin in pluginsFound(all, query))
        if (shelf != MarketShelf.plugins || category == null || plugin.manifest.category == category) plugin,
    ];
    final themesFound = [for (final option in options) if (themeFound(option, query)) option];
    final noteFaces = [for (final face in typefaces) if (faceFound(face, query)) face];
    final uiFaces = [for (final face in interfaceFaces) if (faceFound(face, query)) face];
    final packsFound = [for (final pack in iconPacks) if (iconPackFound(pack, query)) pack];
    final showPlugins = shelf == MarketShelf.all || shelf == MarketShelf.plugins;
    final showThemes = shelf == MarketShelf.all || shelf == MarketShelf.themes;
    final showFonts = shelf == MarketShelf.all || shelf == MarketShelf.fonts;
    final showIcons = shelf == MarketShelf.all || shelf == MarketShelf.icons;
    final nothing = (!showPlugins || found.isEmpty) && (!showThemes || themesFound.isEmpty) && (!showFonts || (noteFaces.isEmpty && uiFaces.isEmpty)) && (!showIcons || packsFound.isEmpty);
    // A phone's All shows the themes and the fonts as rows that scroll sideways; everywhere else they stand across.
    final rows = !wide && shelf == MarketShelf.all;

    final linkedTheme = [for (final option in options) if (option.value == _linkedTheme) option].firstOrNull;
    final linkedFace = typefaces.contains(_linkedFace) ? _linkedFace : null;
    final parts = <Widget>[
      _Band(plugins: all, themes: options.length, faces: typefaces.length, packs: iconPacks.length, wide: wide),
      if (_missing case final missing?) ...[SizedBox(height: t.space(4)), _LinkNote(words: missing, onDismiss: () => setState(() => _missing = null))],
      if (linkedTheme != null) ...[
        SizedBox(height: t.space(4)),
        _Linked(
          key: ValueKey('market-linked-theme-${linkedTheme.value}'),
          kind: 'Theme',
          name: linkedTheme.label,
          line: linkedTheme.description,
          wide: wide,
          picture: MarketThemeCard(option: linkedTheme, selected: prefs.theme == linkedTheme.value, onPress: () => _prefs.update((now) => themeChoice(linkedTheme.value, now))),
          uses: [(label: 'Use this theme', inUse: prefs.theme == linkedTheme.value, use: () => _prefs.update((now) => themeChoice(linkedTheme.value, now)))],
          onDismiss: () => setState(() => _linkedTheme = null),
        ),
      ],
      if (linkedFace != null) ...[
        SizedBox(height: t.space(4)),
        _Linked(
          key: ValueKey('market-linked-face-$linkedFace'),
          kind: 'Font',
          name: faceWords[linkedFace] ?? linkedFace,
          line: faceRoles(linkedFace).join(' · '),
          wide: wide,
          picture: MarketFontCard(face: linkedFace, role: FaceRole.note, selected: prefs.faces.note == linkedFace, onPress: () => _prefs.update((now) => now.copyWith(noteFace: linkedFace))),
          uses: [
            (label: 'Use for notes', inUse: prefs.faces.note == linkedFace, use: () => _prefs.update((now) => now.copyWith(noteFace: linkedFace))),
            if (interfaceFaces.contains(linkedFace)) (label: 'Use for the interface', inUse: prefs.faces.ui == linkedFace, use: () => _prefs.update((now) => now.copyWith(typeface: linkedFace))),
          ],
          onDismiss: () => setState(() => _linkedFace = null),
        ),
      ],
      SizedBox(height: t.space(4)),
      GlacierSearchField(
        key: const ValueKey('market-find'),
        value: query,
        onValueChange: (value) => setState(() => _query = value),
        placeholder: 'Search plugins, themes, fonts and icons',
        ariaLabel: 'Search the Market',
      ),
      SizedBox(height: t.space(3)),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 520 : double.infinity),
          child: GlacierSegmentedControl(
            key: const ValueKey('market-shelves'),
            ariaLabel: 'Shelves',
            fullWidth: true,
            options: [for (final each in MarketShelf.values) GlacierSegmentedOption(value: each.name, label: Text(each.label))],
            value: shelf.name,
            onValueChange: (value) => _toShelf(MarketShelf.values.byName(value)),
          ),
        ),
      ),
    ];

    if (nothing) {
      return [
        ...parts,
        SizedBox(height: gap),
        _Nothing(
          query: query.trim(),
          onEverything: () => setState(() {
            _query = '';
            _category = null;
            _shelf = MarketShelf.all;
          }),
        ),
      ];
    }

    // The featured plugins, at the head of All before anything is typed.
    if (shelf == MarketShelf.all && !searching) {
      final featured = featuredPlugins(all);
      if (featured.isNotEmpty) {
        final cards = [for (final plugin in featured) _featured(plugin)];
        parts.addAll([
          SizedBox(height: gap),
          const MarketHeading(title: 'Featured', icon: Lucide.sparkles),
          if (!wide)
            MarketRow(width: t.lenOf('17rem'), height: t.lenOf('13rem'), children: cards)
          else
            MarketGrid(minWidth: t.lenOf('14rem'), most: narrowed ? 2 : 4, children: [for (final card in cards) SizedBox(height: t.lenOf('13rem'), child: card)]),
        ]);
      }
    }

    if (showThemes && themesFound.isNotEmpty) {
      final cards = [
        for (final option in themesFound) MarketThemeCard(option: option, selected: prefs.theme == option.value, onPress: () => _prefs.update((now) => themeChoice(option.value, now))),
      ];
      parts.addAll([
        SizedBox(height: gap),
        MarketHeading(
          title: 'Themes',
          icon: Lucide.swatchBook,
          meta: '${themesFound.length} to choose from',
          more: shelf == MarketShelf.all ? 'See all' : null,
          onMore: () => _toShelf(MarketShelf.themes),
        ),
        if (rows)
          MarketRow(width: t.lenOf('10.5rem'), height: t.lenOf('7rem') + t.lenOf('3.6rem'), children: cards)
        else
          MarketGrid(minWidth: t.lenOf('10rem'), most: 5, children: cards),
      ]);
      if (shelf == MarketShelf.themes) {
        parts.addAll([
          SizedBox(height: gap),
          MarketHeading(title: 'Accent', icon: Lucide.palette, meta: accentName(prefs.accent)),
          MarketCard(
            key: const ValueKey('market-accents'),
            padding: EdgeInsets.all(t.space(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccentSwatch(accent: prefs.accent, onAccent: (accent) => _prefs.update((now) => now.copyWith(accent: accent))),
                SizedBox(height: t.space(3)),
                Text('The one colour Ghost.md wears: the chosen tab, a link, a ticked box. Ink is no colour at all.', style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'))),
              ],
            ),
          ),
        ]);
      }
    }

    if (showFonts && (noteFaces.isNotEmpty || uiFaces.isNotEmpty)) {
      final faces = prefs.faces;
      Widget fonts(List<String> list, FaceRole role) {
        final cards = [
          for (final face in list)
            MarketFontCard(
              face: face,
              role: role,
              selected: role == FaceRole.note ? faces.note == face : faces.ui == face,
              onPress: () => _prefs.update((now) => role == FaceRole.note ? now.copyWith(noteFace: face) : now.copyWith(typeface: face)),
            ),
        ];
        return rows ? MarketRow(width: t.lenOf('14rem'), height: t.lenOf('6.2rem') + t.lenOf('3.6rem'), children: cards) : MarketGrid(minWidth: t.lenOf('13rem'), most: 4, children: cards);
      }

      if (noteFaces.isNotEmpty) {
        parts.addAll([
          SizedBox(height: gap),
          MarketHeading(title: shelf == MarketShelf.fonts ? 'Note font' : 'Fonts', icon: Lucide.type, meta: 'Your notes’ words and code', more: shelf == MarketShelf.all ? 'See all' : null, onMore: () => _toShelf(MarketShelf.fonts)),
          fonts(noteFaces, FaceRole.note),
        ]);
      }
      if (uiFaces.isNotEmpty && (shelf == MarketShelf.fonts || searching)) {
        parts.addAll([
          SizedBox(height: gap),
          const MarketHeading(title: 'Interface font', icon: Lucide.textCursorInput, meta: 'Menus, tabs and buttons'),
          fonts(uiFaces, FaceRole.interface),
        ]);
      }
    }

    if (showIcons && packsFound.isNotEmpty) {
      final using = iconPackOf(prefs.iconPack);
      final style = IconStyle.of(prefs.iconStyle);
      final cards = [
        for (final pack in packsFound) MarketIconPackCard(pack: pack, selected: using.id == pack.id, open: _openPack == pack.id, onPress: () => _openIcons(pack.id)),
      ];
      parts.addAll([
        SizedBox(height: gap),
        MarketHeading(
          title: 'Icons',
          icon: Lucide.shapes,
          meta: '${packsFound.length} packs, each outline, solid or filled',
          more: shelf == MarketShelf.all ? 'See all' : null,
          onMore: () => _toShelf(MarketShelf.icons),
        ),
        if (rows)
          MarketRow(width: t.lenOf('17rem'), height: t.lenOf('11.6rem'), children: cards)
        else
          MarketGrid(minWidth: t.lenOf('16rem'), most: narrowed ? 2 : 3, children: cards),
      ]);
      // The style under the packs on their own shelf, as the accent is under the themes.
      if (shelf == MarketShelf.icons) {
        parts.addAll([
          SizedBox(height: gap),
          MarketHeading(title: 'Style', icon: Lucide.sparkles, meta: '${style.label}, in ${using.name}'),
          MarketCard(
            key: const ValueKey('market-icon-style'),
            padding: EdgeInsets.all(t.space(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IconStyleChooser(pack: using, style: style, onStyle: (style) => _prefs.update((now) => now.copyWith(iconStyle: style.name))),
                SizedBox(height: t.space(3)),
                Text('Outline is the pack’s own line, Solid the same icons bolder, and Filled each one filled in. Every icon in Ghost.md changes at once.', style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'))),
              ],
            ),
          ),
        ]);
      }
    }

    if (showPlugins && (found.isNotEmpty || category != null)) parts.addAll([SizedBox(height: gap), ..._plugins(t, all: all, found: found, categories: categories, category: category, wide: wide)]);
    return parts;
  }

  Widget _featured(GlyphPlugin plugin) {
    final id = plugin.manifest.id;
    final held = _prefs.value.localOnly && usesNetwork(plugin.manifest);
    return FeaturedPluginCard(plugin: plugin, added: _registry.switchedOn(id), held: held, onAdd: held ? null : () => _add(id), onOpen: () => _openPlugin(id));
  }

  /// The plugins: how many are added, Local only's word, the categories on their own shelf, then Added and Discover.
  List<Widget> _plugins(Tokens t, {required List<GlyphPlugin> all, required List<GlyphPlugin> found, required List<PluginCategory> categories, required PluginCategory? category, required bool wide}) {
    final registry = _registry;
    final localOnly = _prefs.value.localOnly;
    final count = all.where((p) => registry.switchedOn(p.manifest.id)).length;
    final added = [for (final plugin in found) if (registry.switchedOn(plugin.manifest.id)) plugin];
    final discover = [for (final plugin in found) if (!registry.switchedOn(plugin.manifest.id)) plugin];

    Widget card(GlyphPlugin plugin) {
      final id = plugin.manifest.id;
      final held = localOnly && usesNetwork(plugin.manifest);
      return MarketPluginCard(
        plugin: plugin,
        added: registry.switchedOn(id),
        held: held,
        wide: wide,
        selected: _open == id,
        onAdd: held ? null : () => _add(id),
        onOpen: () => _openPlugin(id),
      );
    }

    Widget shelf(String title, List<GlyphPlugin> list) {
      final size = t.lenOf('0.72rem');
      return Column(
        key: ValueKey('shelf ${title.toLowerCase()}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(top: t.space(4), bottom: t.space(2)),
            child: Semantics(
              header: true,
              label: title,
              child: ExcludeSemantics(child: Text(title.toUpperCase(), style: pageText(t, size, weight: 'semibold', color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps', em: size)))),
            ),
          ),
          if (wide)
            MarketGrid(minWidth: t.lenOf('14rem'), most: 4, children: [for (final plugin in list) card(plugin)])
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < list.length; i++) ...[if (i > 0) SizedBox(height: t.space(2)), card(list[i])],
              ],
            ),
        ],
      );
    }

    return [
      MarketHeading(
        title: 'Plugins',
        icon: Lucide.puzzle,
        meta: '$count of ${all.length} added',
        more: _shelf == MarketShelf.all && _query.trim().isEmpty ? 'See all' : null,
        onMore: () => _toShelf(MarketShelf.plugins),
      ),
      Text(
        'Every one is built in: adding one is a switch, and removing one keeps what it kept. None reaches anywhere its page does not say.',
        style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3')),
      ),
      if (localOnly) ...[
        SizedBox(height: t.space(3)),
        _LocalOnly(onPress: widget.onLocalOnly),
      ],
      if (_shelf == MarketShelf.plugins && categories.length > 1) ...[
        SizedBox(height: t.space(3)),
        Semantics(
          container: true,
          label: 'Categories',
          child: Wrap(
            spacing: t.space(2),
            runSpacing: t.space(2),
            children: [
              MarketChip(label: 'All', chosen: category == null, onPress: () => setState(() => _category = null)),
              for (final each in categories) MarketChip(label: each.label, chosen: category == each, onPress: () => setState(() => _category = each)),
            ],
          ),
        ),
      ],
      if (added.isNotEmpty) shelf('Added', added),
      if (discover.isNotEmpty) shelf('Discover', discover),
      if (found.isEmpty)
        Padding(
          padding: EdgeInsets.only(top: t.space(4)),
          child: Text('There is no plugin in ${category?.label ?? 'this build'} that matches.', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
        ),
    ];
  }
}

/// The Market's head: a band in colour, its name and what it is, how much is on its shelves, and the plugins' tiles
/// scattered at its end, the brands' marks first.
class _Band extends StatelessWidget {
  const _Band({required this.plugins, required this.themes, required this.faces, required this.packs, required this.wide});

  final List<GlyphPlugin> plugins;
  final int themes;
  final int faces;
  final int packs;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = t.radius('lg') * 1.6;
    final height = wide ? t.lenOf('12rem') : t.lenOf('11rem');
    final tiles = [...plugins.where(featuresFirst), ...plugins.where((p) => !featuresFirst(p))].take(wide ? 7 : 4).toList();
    // Where each tile sits, from the band's end: its offset across and down, its size and its turn.
    const spots = [(0.06, 0.12, 3.6, -0.10), (0.30, 0.46, 3.0, 0.08), (0.03, 0.62, 2.6, 0.14), (0.24, 0.02, 2.4, 0.06), (0.52, 0.10, 2.2, -0.12), (0.47, 0.58, 2.6, -0.04), (0.70, 0.40, 2.0, 0.10)];
    final lineStyle = pageText(t, t.fontSize(wide ? 'md' : 'sm'), height: 1.35, color: const Color(0xEBFFFFFF));
    return ClipRRect(
      key: const ValueKey('market-band'),
      borderRadius: BorderRadius.circular(radius),
      child: ConstrainedBox(
        // At least this tall, and taller where its words need it.
        constraints: BoxConstraints(minHeight: height),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4F5BD5), Color(0xFF9A45C9), Color(0xFFD6336C), Color(0xFFD9600D)], stops: [0, 0.38, 0.72, 1]),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final across = wide ? math.min(box.maxWidth * 0.4, 420.0) : box.maxWidth * 0.42;
              return Stack(
                children: [
                  Positioned.fill(child: tileLight(radius: radius)),
                  for (var i = 0; i < tiles.length; i++)
                    Positioned(
                      right: spots[i].$1 * across,
                      top: spots[i].$2 * height,
                      child: Transform.rotate(
                        angle: spots[i].$4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(t.lenOf('${spots[i].$3 * 0.28}rem')),
                            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6))],
                          ),
                          child: PluginTile(plugin: tiles[i], size: t.lenOf('${spots[i].$3}rem')),
                        ),
                      ),
                    ),
                  Container(
                    width: box.maxWidth,
                    alignment: AlignmentDirectional.bottomStart,
                    padding: EdgeInsets.all(t.space(wide ? 6 : 5)),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: height - t.space(wide ? 6 : 5) * 2, maxWidth: box.maxWidth - across - t.space(wide ? 6 : 5)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Market', style: pageText(t, t.fontSize(wide ? '3xl' : '2xl'), weight: 'bold', color: const Color(0xFFFFFFFF))),
                          SizedBox(height: t.space(1)),
                          Text('Plugins, themes, fonts and icons, all built in. Adding one is a switch.', maxLines: 3, overflow: TextOverflow.ellipsis, style: lineStyle),
                          SizedBox(height: t.space(3)),
                          Text(
                            '${plugins.length} plugins · $themes themes · $faces fonts · $packs icon packs',
                            key: const ValueKey('market-band-count'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: const Color(0xCCFFFFFF)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One way to use what a link held ([_Linked]): its word, whether it is what is in use already, and the doing of it.
typedef _Use = ({String label, bool inUse, VoidCallback use});

/// A theme or a face a link named (`ghostmd://market/theme/<id>`, `…/font/<id>`), at the head of its shelf: its card
/// as the shelf draws it, its name and line, and the way to use it, which is the Market's Add for a thing that is
/// built in and only chosen. Once in use the button says so, ticked. Put away with its cross, or by leaving the shelf.
class _Linked extends StatelessWidget {
  const _Linked({super.key, required this.kind, required this.name, required this.line, required this.picture, required this.uses, required this.onDismiss, required this.wide});

  /// "Theme" or "Font": the word over its name.
  final String kind;
  final String name;
  final String line;
  final Widget picture;
  final List<_Use> uses;
  final VoidCallback onDismiss;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.lenOf('0.72rem');
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(kind.toUpperCase(), style: pageText(t, size, weight: 'semibold', color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps', em: size))),
        SizedBox(height: t.space(1)),
        Semantics(header: true, child: Text(name, style: pageText(t, t.fontSize('xl'), weight: 'bold', color: t.color('app-ink')))),
        SizedBox(height: t.space(1)),
        Text(line, style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'))),
        SizedBox(height: t.space(3)),
        Wrap(
          spacing: t.space(2),
          runSpacing: t.space(2),
          children: [
            for (final each in uses)
              MarketButton(
                key: ValueKey('market-use ${each.label}'),
                label: each.inUse ? 'In use' : each.label,
                semantics: each.inUse ? '$name, in use' : '${each.label}: $name',
                icon: each.inUse ? Lucide.check : Lucide.plus,
                look: each.inUse ? MarketButtonLook.ring : MarketButtonLook.ink,
                large: true,
                onPress: each.inUse ? null : each.use,
              ),
          ],
        ),
      ],
    );
    // The card at the size its shelf's row gives it (the phone's MarketRow for themes and fonts), and a breath taller,
    // since using a face for the interface sets the card's own words in it, and a taller face would not fit the row's.
    final theme = kind == 'Theme';
    final cardWidth = t.lenOf(theme ? '10.5rem' : '14rem');
    final cardHeight = (theme ? t.lenOf('7rem') + t.lenOf('3.6rem') : t.lenOf('6.2rem') + t.lenOf('3.6rem')) + t.space(1);
    final card = SizedBox(width: cardWidth, height: cardHeight, child: picture);
    return MarketCard(
      key: const ValueKey('market-linked'),
      padding: EdgeInsets.all(t.space(4)),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(end: t.space(8)),
            child: wide
                ? Row(children: [card, SizedBox(width: t.space(5)), Expanded(child: words)])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [card, SizedBox(height: t.space(4)), words]),
          ),
          PositionedDirectional(top: 0, end: 0, child: _Dismiss(label: 'Put $name away', onPress: onDismiss)),
        ],
      ),
    );
  }
}

/// The word over the front for a link the Market could not follow ([MarketLanding.missing]): a link from a newer
/// website to an older Ghost.md, most likely. Put away with its cross.
class _LinkNote extends StatelessWidget {
  const _LinkNote({required this.words, required this.onDismiss});

  final String words;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      key: const ValueKey('market-link-note'),
      padding: EdgeInsets.all(t.space(3)),
      decoration: BoxDecoration(
        color: t.color('app-paper-2'),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline')),
      ),
      child: Row(
        children: [
          AppIcon(Lucide.info, size: 18, strokeWidth: 2.1, color: t.color('app-ink-2')),
          SizedBox(width: t.space(3)),
          Expanded(child: Text(words, style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-2')))),
          SizedBox(width: t.space(2)),
          _Dismiss(label: 'Put the note away', onPress: onDismiss),
        ],
      ),
    );
  }
}

/// A small cross that puts a word or a linked card away.
class _Dismiss extends StatelessWidget {
  const _Dismiss({required this.label, required this.onPress});

  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      key: const ValueKey('market-link-dismiss'),
      onPressed: onPress,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: SizedBox.square(dimension: t.space(8), child: Center(child: AppIcon(Lucide.x, size: 16, strokeWidth: 2.2, color: t.color('app-ink-3')))),
      ),
    );
  }
}

/// Local only's word over the plugins: on, it holds every plugin that uses the internet off.
class _LocalOnly extends StatelessWidget {
  const _LocalOnly({this.onPress});
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      key: const ValueKey('market-local-only'),
      padding: EdgeInsets.all(t.space(3)),
      decoration: BoxDecoration(
        color: t.color('app-paper-2'),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline')),
      ),
      child: Row(
        children: [
          AppIcon(Lucide.wifiOff, size: 18, strokeWidth: 2.1, color: t.color('app-ink-2')),
          SizedBox(width: t.space(3)),
          Expanded(child: Text('Local only is on, so plugins that use the internet are held off until it is off.', style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-2')))),
          if (onPress != null) ...[SizedBox(width: t.space(2)), MarketWord(word: 'Local only', onPress: onPress!)],
        ],
      ),
    );
  }
}

/// A search that left nothing: the ghost finding nothing, and the way back to everything.
class _Nothing extends StatelessWidget {
  const _Nothing({required this.query, required this.onEverything});

  final String query;
  final VoidCallback onEverything;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: const ValueKey('market-nothing'),
      children: [
        const Ghost(scene: GhostScene.searchNothing, size: GhostSize.small, align: GhostAlign.center, maxWidth: 200),
        SizedBox(height: t.space(3)),
        Text(query.isEmpty ? 'Nothing here yet' : 'Nothing matches “$query”', textAlign: TextAlign.center, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
        SizedBox(height: t.space(1)),
        Text('Try a plugin’s name, a theme, a font or an icon pack.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
        SizedBox(height: t.space(4)),
        MarketButton(key: const ValueKey('market-everything'), label: 'Show everything', look: MarketButtonLook.ring, onPress: onEverything),
      ],
    );
  }
}
