import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../gallery/kit_gallery.dart';
import 'preferences.dart';

/// Inter's other subsets, which the page reaches by unicode-range and Flutter by falling back (pubspec.yaml).
const interFallbacks = [
  'Inter Variable LatinExt',
  'Inter Variable Cyrillic',
  'Inter Variable CyrillicExt',
  'Inter Variable Greek',
  'Inter Variable GreekExt',
  'Inter Variable Vietnamese',
];

/// The app: the design tokens over everything, haptics for every press, and the page's own type
/// (app.css `html { font-feature-settings: 'cv11', 'ss01' }`, `html, body { font-family; color; background }`).
class GhostApp extends StatelessWidget {
  const GhostApp({super.key, required this.sheet});

  final TokenSheet sheet;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPreferences>(
      valueListenable: preferences,
      builder: (context, prefs, _) {
        return WidgetsApp(
          title: 'Ghost Flutter',
          color: const Color(0xFF0D0D0D),
          debugShowCheckedModeBanner: false,
          pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
          builder: (context, child) => GlacierTheme(
            sheet: sheet,
            attrs: prefs.attrs,
            child: HapticsProvider(enabled: prefs.haptics, child: _Page(child: child!)),
          ),
          home: const KitGallery(),
        );
      },
    );
  }
}

/// `html, body`: the paper, the ink, the sans face with its features, and the system bars' icons in the ink's shade.
class _Page extends StatelessWidget {
  const _Page({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = t.text('md').copyWith(
      fontFamilyFallback: interFallbacks,
      fontFeatures: const [FontFeature('cv11'), FontFeature('ss01')],
    );
    final dark = t.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: const Color(0x00000000),
        systemNavigationBarColor: const Color(0x00000000),
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: DefaultTextStyle(style: style, child: child),
      ),
    );
  }
}
