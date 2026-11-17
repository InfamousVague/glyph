/// A plugin's own page on the Plugins page (Matt, 2026-11-17: "redo how the plugins look with their own dedicated
/// plugins page with a marketplace like look how ghostmd has"), after Ghost.md's PluginDetail: its colour across the
/// head with its icon, name and line; Add or Remove; what it does and what it adds; what it reads, keeps or sends;
/// and, once it is added, its own settings, the cards its section in Settings has always had.
///
/// Removing a plugin keeps its choices, as the registry always has: added again, it is as it was.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../kit/settings_kit.dart';
import '../../kit/settings_type.dart';
import '../../plugins/plugin.dart';
import '../common.dart';
import '../dialup/bevel.dart';
import '../dialup/title_bar.dart';
import '../translated_card.dart' show TranslatePreview;
import 'market_parts.dart';
import 'plugin_art.dart';

/// A picture of a plugin at work, for its page, where it has one: Translate's text with the words as they came dimmed
/// in the card and the translation in the bubble (Matt, 2026-11-17: "show the original text dimmed in a card with the
/// translated text for the actual message bubble"), as Market's pages show what a plugin does.
Widget? pluginPreview(GhostPlugin plugin) => switch (plugin.id) {
      'translate' => const TranslatePreview(),
      _ => null,
    };

class PluginDetail extends StatelessWidget {
  const PluginDetail({super.key, required this.plugin, required this.added, required this.onSwitch, required this.here, this.summary, this.settings = const [], this.hasSettings = false, this.onClose, this.finder, this.seek});

  final GhostPlugin plugin;
  final bool added;

  /// Adds it, or removes it.
  final ValueChanged<bool> onSwitch;

  /// Where it runs, in a word: phone, computer, iPhone.
  final String here;

  /// What its settings come to as they stand, under the buttons once it is added.
  final String? summary;

  /// Its own settings' cards, drawn once it is added.
  final List<Widget> settings;

  /// It has settings of its own, to say so while it is not added.
  final bool hasSettings;

  /// Shuts the page, where it stands beside the shelves; null where the page's bar does.
  final VoidCallback? onClose;

  /// Finds a setting on it by name, for a search's hit ([seek]).
  final SettingsFinder? finder;
  final String? seek;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bevel = isBevelChrome(t);
    final c = PluginHues.of(t, plugin.hue);
    final gap = t.space(4);
    final ink = t.color('app-ink');
    final body = pageText(t, t.fontSize('md'), height: 1.45, color: ink);
    final quiet = pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'));

    Widget section(String title, List<Widget> children, {Key? key}) => Padding(
          key: key,
          padding: EdgeInsets.only(top: gap * 1.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(title, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink))),
              SizedBox(height: t.space(1)),
              ...children,
            ],
          ),
        );

    Widget point(LucideIcon icon, String label, {String? hint}) => Padding(
          padding: EdgeInsets.only(top: t.space(2)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: t.lenOf('1.9rem'),
                height: t.lenOf('1.9rem'),
                decoration: BoxDecoration(color: bevel ? null : c.wash, borderRadius: BorderRadius.circular(pluginCorner(t, t.lenOf('0.55rem')))),
                alignment: Alignment.center,
                child: AppIcon(icon, size: 15, strokeWidth: 2.2, color: bevel ? ink : c.accent, wash: false),
              ),
              SizedBox(width: t.space(3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(padding: EdgeInsets.only(top: t.lenOf('0.2rem')), child: Text(label, style: pageText(t, t.fontSize('md'), weight: hint == null ? 'regular' : 'medium', height: 1.35, color: ink))),
                    if (hint != null) Padding(padding: EdgeInsets.only(top: t.lenOf('0.15rem')), child: Text(hint, style: quiet)),
                  ],
                ),
              ),
            ],
          ),
        );

    final status = added ? 'Added' : 'Not added';
    return Column(
      key: ValueKey('plugins-detail-${plugin.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bevel ? _window(t, status) : _hero(t, c, status),
        SizedBox(height: gap),
        Wrap(
          spacing: t.space(2),
          runSpacing: t.space(2),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Dial-Up's head has no tags: whether it is added stands by its button, not on the title bar.
            if (bevel && added) MarketAdded(key: const ValueKey('plugins-detail-status'), name: plugin.name),
            MarketButton(
              key: ValueKey(added ? 'plugins-remove-${plugin.id}' : 'plugins-add-${plugin.id}'),
              label: added ? 'Remove' : 'Add to Ghost Messaging',
              semantics: '${added ? 'Remove' : 'Add'} ${plugin.name}',
              icon: added ? Lucide.minus : Lucide.plus,
              look: added ? MarketButtonLook.ring : MarketButtonLook.filled,
              color: c.start,
              onColor: c.on,
              large: true,
              onPress: () => onSwitch(!added),
            ),
          ],
        ),
        SizedBox(height: t.space(2)),
        Text(
          added ? 'Added. Removed, it does nothing until it is added again, and keeps your choices for it.' : 'Built in: adding it is a switch, and removing it keeps your choices for it.',
          key: const ValueKey('plugins-detail-hint'),
          style: quiet,
        ),
        section('What it does', [Text(plugin.description, style: body)]),
        if (pluginPreview(plugin) case final preview?)
          section('How it looks', [
            SizedBox(height: t.space(1)),
            MarketCard(key: const ValueKey('plugins-detail-preview'), padding: EdgeInsets.all(t.space(3)), child: preview),
          ]),
        if (plugin.adds.isNotEmpty) section('What it adds', [for (final add in plugin.adds) point(Lucide.check, add)]),
        section('What it reads and keeps', [
          for (final r in plugin.reaches) point(r.icon, r.label, hint: r.hint),
          point(Lucide.shieldCheck, 'Runs on this $here', hint: plugin.reaches.isEmpty ? 'It works on what is on the screen, here, and sends nothing anywhere.' : 'Nothing else leaves it, and nothing is kept past the app being closed unless it says so above.'),
        ], key: const ValueKey('plugins-detail-privacy')),
        if (added && settings.isNotEmpty)
          Padding(
            key: const ValueKey('plugins-detail-settings'),
            padding: EdgeInsets.only(top: gap * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text('Its settings', style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink))),
                // What they come to now, named as such: under Remove with no word before it, "Balanced · muted" read
                // as nothing in particular.
                if (summary != null) Padding(padding: EdgeInsets.only(top: t.space(1)), child: Text('Set to: $summary', key: const ValueKey('plugins-detail-summary'), style: quiet)),
                SizedBox(height: t.space(2)),
                GlacierScope(
                  attrs: {'hue': plugin.hue},
                  child: SettingsPaneScope(
                    finder: finder ?? SettingsFinder(),
                    whole: seek != null,
                    seeking: seek,
                    child: PaneBody(children: settings),
                  ),
                ),
              ],
            ),
          )
        else if (!added && hasSettings)
          section('Its settings', [Text('Once it is added, its settings are here.', style: quiet)]),
        Padding(
          padding: EdgeInsets.only(top: gap * 1.5),
          child: Text('${plugin.shelf.label} · built in · on this $here alone', style: quiet),
        ),
      ],
    );
  }

  /// The head: the plugin's colour, its icon large and faint as its picture, and its name and line on it.
  Widget _hero(Tokens t, PluginHues c, String status) {
    final radius = pluginCorner(t, t.radius('lg') * 1.5);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: c.gradient),
        child: Stack(
          children: [
            Positioned.fill(child: hueGlow(c, radius: radius)),
            // Faint, low and mostly past the end, beyond the words' width: it ran under the line in every look.
            Positioned(right: -t.space(16), bottom: -t.space(12), child: AppIcon(plugin.icon, size: t.lenOf('12rem'), strokeWidth: 1.4, color: c.faint, wash: false)),
            Padding(
              padding: EdgeInsets.all(t.space(5)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GlassChip(plugin: plugin, size: t.lenOf('3.6rem')),
                      const Spacer(),
                      if (onClose != null)
                        GlacierPressable(
                          key: const ValueKey('plugins-detail-close'),
                          onPressed: onClose,
                          semanticLabel: 'Close ${plugin.name}',
                          builder: (context, state) => GlacierFocusRing(
                            visible: state.focused,
                            child: Container(
                              width: t.space(8),
                              height: t.space(8),
                              decoration: BoxDecoration(color: c.tag, borderRadius: BorderRadius.circular(pluginCorner(t, t.space(4)))),
                              alignment: Alignment.center,
                              child: AppIcon(Lucide.x, size: 16, strokeWidth: 2.4, color: c.on, wash: false),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: t.space(4)),
                  Semantics(header: true, child: Text(plugin.name, style: pageText(t, t.fontSize('2xl'), weight: 'bold', color: c.on))),
                  SizedBox(height: t.space(1)),
                  FractionallySizedBox(
                    widthFactor: 0.68,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(plugin.tagline, style: pageText(t, t.fontSize('md'), height: 1.35, color: c.on.withValues(alpha: 0.92))),
                  ),
                  SizedBox(height: t.space(3)),
                  Wrap(
                    spacing: t.space(2),
                    runSpacing: t.space(2),
                    children: [
                      MarketTag(key: const ValueKey('plugins-detail-status'), label: status, ground: c.tag, ink: c.on, ring: c.tagRing),
                      MarketTag(label: plugin.shelf.label, ground: c.tag, ink: c.on, ring: c.tagRing),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dial-Up's head: a window titled for the plugin's shelf (its X where the page stands beside the shelves), and on
  /// the silver its tile, its name and its line. The page's own bar names the plugin on a phone, so the window's title
  /// bar saying it again read as the title twice.
  Widget _window(Tokens t, String status) {
    final c = DialupColors.of(t);
    return Bevel(
      padding: const EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitleBar(title: '${plugin.shelf.label} plugin', onClose: onClose, closeLabel: 'Close ${plugin.name}', leading: AppIcon(plugin.icon, size: 16, strokeWidth: 2.2, color: c.titlebarInk, wash: false)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PluginTile(plugin: plugin, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Semantics(header: true, child: Text(plugin.name, style: pageText(t, 17, weight: 'bold', color: c.onChrome))),
                    const SizedBox(height: 2),
                    Text(plugin.tagline, style: pageText(t, 15, height: 1.35, color: c.onChrome)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A plugin's page on a phone: the page over the shelves, with its name on the bar and the way back.
class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key, required this.title, required this.body});

  final String title;

  /// The page's body, built afresh as the person's choices change (it is under the app's own scope, not the shelves').
  final Widget Function(BuildContext context) body;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GhostPage(
      title: title,
      body: ListView(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
        children: [Builder(builder: body)],
      ),
    );
  }
}
