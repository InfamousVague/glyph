import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/icon_packs.dart' show IconInk, iconPreviewNames;
import 'package:ghost_md/core/back.dart' show BackScope;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_items.dart';
import 'package:ghost_md/market/market_listing.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/settings/theme_cards.dart' show themeOptions;
import 'package:ghost_md/share/app_links.dart';

import '../settings/panes/support.dart';

/// landing/market.json, the website's market page's listing (lib/market/market_listing.dart; Matt, 2026-10-26: "add
/// a browsable marketplace listed under the plugins section on the website that deeplinks to the app"), held to the
/// app's own lists: it is what the Market lists now, made again by
///
/// ```sh
/// flutter test --no-pub test/market/market_listing_test.dart --update-goldens
/// ```
///
/// and this fails while the file and the app part. With it, what the page leans on: every link opens what it names
/// in the app, every icon and mark it names it has, and every face it sets has its file on the site.
void main() {
  final listingFile = File('landing/market.json');

  /// The brands whose marks the site ships: landing/brands/*.svg, by name.
  Set<String> shippedMarks() => {
        for (final file in Directory('landing/brands').listSync().whereType<File>())
          if (file.path.endsWith('.svg')) file.uri.pathSegments.last.replaceAll('.svg', ''),
      };

  Future<String> made(WidgetTester tester) async {
    await pumpSettings(tester, const SizedBox.expand(), prefs: const Preferences(theme: 'light'));
    final t = tokensAt(tester, find.byType(BackScope));
    final json = marketListingJson(plugins: builtIn, themes: themeOptions(t), marks: shippedMarks());
    await endSettings(tester);
    return json;
  }

  testWidgets('landing/market.json is the Market as the app lists it now', (tester) async {
    final now = await made(tester);
    if (autoUpdateGoldenFiles) listingFile.writeAsStringSync(now);
    expect(listingFile.existsSync(), isTrue, reason: 'landing/market.json is made with --update-goldens');
    expect(
      listingFile.readAsStringSync(),
      now,
      reason: 'The app\'s plugins, themes or fonts changed and the website\'s listing did not: make it again with '
          '`flutter test --no-pub test/market/market_listing_test.dart --update-goldens`.',
    );
  });

  group('what the page leans on', () {
    late Map<String, Object?> listing;
    setUpAll(() => listing = jsonDecode(listingFile.readAsStringSync()) as Map<String, Object?>);

    List<Map<String, Object?>> each(String kind) => [for (final item in listing[kind]! as List) item as Map<String, Object?>];

    test('every plugin that ships is listed once, in the catalogue’s order, and only those', () {
      final ids = [for (final plugin in each('plugins')) plugin['id']];
      expect(ids.toSet().length, ids.length);
      expect(ids.toSet(), {for (final plugin in builtIn) plugin.manifest.id});
      // The newest plugins among them (lib/plugins/meetings, lib/plugins/discord).
      expect(ids, containsAll(['google-meet', 'zoom', 'discord', 'slack', 'github', 'lovart', 'claude']));
    });

    test('every theme, every face and every icon pack is listed', () {
      expect([for (final theme in each('themes')) theme['id']], themes);
      expect([for (final font in each('fonts')) font['id']], typefaces);
      expect([for (final pack in each('iconPacks')) pack['id']], iconPackChoices);
      expect([for (final shelf in listing['shelves']! as List) (shelf as Map)['id']], contains('icons'));
    });

    test('every icon pack carries its twelve in each style, drawn as the app draws them (Matt, 2026-10-27)', () {
      for (final pack in each('iconPacks')) {
        final preview = pack['preview']! as Map;
        expect(preview.keys, ['outline', 'solid', 'filled'], reason: '${pack['id']}');
        for (final style in preview.values) {
          final glyphs = (style as List).cast<Map>();
          expect([for (final glyph in glyphs) glyph['name']], iconPreviewNames, reason: '${pack['id']}');
          for (final glyph in glyphs) {
            expect(IconInk.values.map((ink) => ink.name), contains(glyph['ink']));
            expect(glyph['paths'] as List, isNotEmpty);
          }
        }
        final coverage = pack['coverage']! as Map;
        expect((coverage['own'] as int) + (coverage['lucide'] as List).length, coverage['of']);
      }
      // Lucide draws every glyph itself; Phosphor in its own three sets, the fill filled.
      final lucide = each('iconPacks').first;
      expect((lucide['coverage']! as Map)['lucide'], isEmpty);
      final phosphor = each('iconPacks').firstWhere((pack) => pack['id'] == 'phosphor');
      expect((((phosphor['preview']! as Map)['filled'] as List).first as Map)['ink'], 'shapes');
    });

    test('the page draws the icon packs, their shelf and their pages', () {
      final script = File('landing/market.js').readAsStringSync();
      expect(script, contains('iconPacks'));
      expect(script, contains('function packPage'));
      expect(script, contains("hash === 'icons'"));
    });

    test('every link opens, in the app, the thing it is listed with', () {
      for (final (kind, items) in [('plugin', each('plugins')), ('theme', each('themes')), ('font', each('fonts')), ('icons', each('iconPacks'))]) {
        for (final item in items) {
          final link = item['link']! as String;
          final place = readAppLink(link);
          expect(place, isA<PlaceAppLink>(), reason: link);
          final landing = marketLinkLanding((place! as PlaceAppLink).place as MarketPlace, plugins: builtIn);
          final id = item['id'];
          expect(landing.missing, isNull, reason: link);
          expect(switch (kind) { 'plugin' => landing.plugin, 'theme' => landing.theme, 'icons' => landing.icons, _ => landing.face }, id, reason: link);
        }
      }
    });

    test('every icon it names is in its icons, and every mark is one the site ships', () {
      final icons = (listing['icons']! as Map).keys.toSet();
      for (final plugin in each('plugins')) {
        expect(icons, contains(plugin['icon']), reason: '${plugin['id']}');
        for (final permission in plugin['permissions']! as List) {
          expect(icons, contains((permission as Map)['icon']));
        }
        final mark = plugin['mark'];
        if (mark != null) expect(File('landing/brands/$mark.svg').existsSync(), isTrue, reason: '$mark');
      }
      // Claude's, Notion's and Lovart's are the site's; GitHub's is not, so its tile wears its icon.
      final marks = {for (final plugin in each('plugins')) plugin['id']: plugin['mark']};
      expect((marks['claude'], marks['notion'], marks['lovart'], marks['github']), ('claude', 'notion', 'lovart', null));
    });

    test('every face it sets has a file on the site', () {
      final sheets = '${File('landing/site.css').readAsStringSync()}\n${File('landing/market.css').readAsStringSync()}';
      final faces = RegExp(r"@font-face\s*\{[^}]*font-family:\s*'([^']+)'[^}]*src:\s*url\('([^']+)'\)").allMatches(sheets);
      final files = {for (final face in faces) face.group(1)!: face.group(2)!};
      for (final font in each('fonts')) {
        final family = font['family']! as String;
        expect(files, contains(family), reason: '$family has no @font-face in landing/site.css or landing/market.css');
        expect(File('landing/${files[family]}').existsSync(), isTrue, reason: files[family]);
      }
    });

    test('the page reads the listing and is linked from the home page', () {
      final page = File('landing/market.html').readAsStringSync();
      expect(page, contains('market.js'));
      expect(File('landing/market.js').readAsStringSync(), contains("'market.json'"));
      final home = File('landing/index.html').readAsStringSync();
      expect(home, contains('href="market.html"'));
    });
  });
}
