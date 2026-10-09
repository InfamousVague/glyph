import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import '../gallery/kit_gallery.dart';
import '../settings/settings_css.dart';

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
///
/// It draws from the person's preferences (lib/core/preferences.dart), as `applyPreferences` dresses the page: their
/// attributes are the theme's, the interface size scales the window, the pace stretches the kit's durations, and
/// the haptics switch is the motor's. The preferences are read from storage before the first frame is shown: where
/// nobody has loaded them, it holds the first frame back and loads them itself. A test that pumps this itself says
/// `preferences.startWithoutStorage()` first, as test/support/render.dart does, since a storage plugin never
/// answers on a test's clock.
///
/// **A link that opens the app is not a route.** Android hands Flutter every `VIEW` intent's address as a route to
/// push (the embedding's deep linking, on unless the manifest says otherwise), and a `WidgetsApp` with a `home`
/// answers `ghostmd://notifications`, whose path is empty, by pushing a second copy of the whole app over the
/// first. The app follows its links itself (lib/core/phone_links.dart, lib/share/app_links.dart), so every pushed
/// route is taken here, before the navigator hears of it, and dropped; and the first route is always the home's,
/// whatever address the launch carried.
class GhostApp extends StatefulWidget {
  const GhostApp({super.key, required this.sheet, this.home = const KitGallery()});

  final TokenSheet sheet;

  /// The screen under the page's theme: the app's own, or one screen alone for a test's picture.
  final Widget home;

  @override
  State<GhostApp> createState() => _GhostAppState();
}

class _GhostAppState extends State<GhostApp> with WidgetsBindingObserver {
  static final Listenable _choices = Listenable.merge([preferences, hapticsPref]);

  /// Taken, and nothing pushed (see the class's comment). This observer is added before the `WidgetsApp`'s own, so
  /// it is asked first.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async => true;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dress(widget.sheet);
    // What was chosen is read before anything is shown: the launch screen stays up until it has been.
    if (!preferences.loaded) {
      final binding = WidgetsBinding.instance;
      binding.deferFirstFrame();
      // Storage that will not answer is not waited for: the defaults are drawn, and what was kept follows if it comes.
      preferences.load().timeout(const Duration(seconds: 2), onTimeout: () {}).whenComplete(binding.allowFirstFrame);
    }
  }

  @override
  void didUpdateWidget(GhostApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dress(widget.sheet);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _choices,
      builder: (context, _) {
        final prefs = preferences.value;
        return WidgetsApp(
          title: 'Ghost Flutter',
          color: const Color(0xFF0D0D0D),
          debugShowCheckedModeBanner: false,
          initialRoute: Navigator.defaultRouteName,
          pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
          builder: (context, child) => _RootFontSize(
            scale: prefs.uiScale,
            child: Builder(
              builder: (context) => GlacierTheme(
                sheet: widget.sheet,
                attrs: {
                  // The page's own attributes, which are not preferences: stamped by the shell on the web.
                  'platform': defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS ? 'mobile' : 'desktop',
                  'tabs': 'on',
                  ...prefs.attrs,
                  // The pace, which the page writes as inline durations; a device asking for less motion is left
                  // to the kit's own rule for it.
                  if (prefs.motionSpeed != Preferences.defaults.motionSpeed && !MediaQuery.disableAnimationsOf(context)) _paceAttr: prefs.motionSpeed,
                },
                typography: const GlacierTypography(
                  features: [FontFeature('cv11'), FontFeature('ss01')],
                  fallbacks: {'Inter Variable': interFallbacks},
                ),
                child: HapticsProvider(enabled: hapticsPref.value, child: _InkOverrides(child: _Page(child: GlacierToastProvider(child: child!)))),
              ),
            ),
          ),
          home: widget.home,
        );
      },
    );
  }
}

/// The attribute the pace is put on the theme by. Not one of the page's: there the pace is inline style on the
/// root, which the kit's theme cannot be given, so [_dress] lays a rule for each pace over the sheet instead.
const String _paceAttr = 'pace';

final Expando<bool> _dressed = Expando<bool>('the app\'s own rules');

/// Lays over [sheet] what the web app's page has beyond the three stylesheets the engine reads: the custom
/// properties of settings.css (lib/settings/settings_css.dart), and what `applyPreferences` writes as inline style
/// on the root for a pace other than normal, the kit's durations stretched or shortened and `--app-motion-scale`.
/// Inline style outranks every rule, so these sort after all of them. Once for a sheet.
void _dress(TokenSheet sheet) {
  if (_dressed[sheet] ?? false) return;
  _dressed[sheet] = true;
  installSettingsStyles(sheet);
  const inline = 1 << 20;
  appendTokenRules(sheet, [
    TokenRule(conditions: const [], declarations: {'--app-motion-scale': Preferences.defaults.rootStyle()['--app-motion-scale']!}, specificity: inline, order: 0),
    for (final speed in motionScales.keys)
      if (speed != Preferences.defaults.motionSpeed)
        TokenRule(
          conditions: [TokenCondition.attr(_paceAttr, speed)],
          declarations: {
            for (final entry in Preferences(motionSpeed: speed).rootStyle().entries)
              if (entry.key.startsWith('--')) entry.key: entry.value,
          },
          specificity: inline + 1,
          order: 0,
        ),
  ]);
}

/// The interface size (`uiScale`): on the page it is the root's font size, which every rem in the kit and the app
/// is measured from. The kit's theme measures a rem as 16 logical pixels and cannot be told otherwise, so the
/// whole window is laid out that much smaller and drawn that much larger instead.
///
/// Rems and the lengths built on them come out as on the page, and so do lengths in `vw` (the window is as many
/// pixels wide as before once drawn). What differs: a length written in pixels (a hairline, `--app-line`) scales
/// with the rest where the page kept it, and a breakpoint is asked of the smaller window, so the split view comes a
/// little later at 110% and a little sooner at 85%. It goes the day `GlacierTheme` takes a root font size.
class _RootFontSize extends StatelessWidget {
  const _RootFontSize({required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1 || !isUiScale(scale)) return child;
    final media = MediaQuery.of(context);
    final size = media.size / scale;
    return MediaQuery(
      data: media.copyWith(
        size: size,
        devicePixelRatio: media.devicePixelRatio * scale,
        padding: media.padding / scale,
        viewPadding: media.viewPadding / scale,
        viewInsets: media.viewInsets / scale,
        systemGestureInsets: media.systemGestureInsets / scale,
      ),
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
        child: Transform.scale(scale: scale, alignment: Alignment.topLeft, child: child),
      ),
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
    final style = t.text('md');
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

/// ink.css's rules that reach into the kit's parts, where no token does:
/// `[role='switch'] + span > span { background: var(--app-paper) }`,
/// `[role='radiogroup'] > label[data-selected] > span:last-child { color: var(--app-paper) }` and
/// `[role='radiogroup'] > label > span[aria-hidden='true'] { box-shadow: none }`.
class _InkOverrides extends StatelessWidget {
  const _InkOverrides({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlacierOverrides(
      switchThumbColor: _paper,
      segmentedSelectedLabelColor: _paper,
      segmentedThumbShadow: _none,
      child: child,
    );
  }

  static Color _paper(Tokens t) => t.color('app-paper');
  static List<BoxShadow> _none(Tokens t) => const [];
}
